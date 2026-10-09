#!/usr/bin/env bash
#
# Verify the heartbeat waveform by simulation, without a board.
#
#   tools/test-heartbeat-waveform.sh [work-dir]
#
# The full clock-smoke design cannot be simulated: `PLL` and `CLKDIV` are Gowin
# primitives with no model here, and iverilog stops on them.  The `heartbeat`
# module has no primitives, so this extracts just that module from the design and
# simulates it.
#
# The scale is the point.  The design's tick is "that clock's cycles per
# millisecond", which for the four clocks here is 21,505 to 74,250.  Simulating
# 50 million clocks per beat is wasteful, so the testbench uses TICK_DIV = 1000:
# one tick is 1000 clocks, the 256-clock PWM carrier fits inside a single tick so
# the brightness is measurable, and every figure the module reports is in TICKS.
# Since the design's tick IS a millisecond, ticks scale straight to milliseconds
# and the assertions below are the real design's timings.
#
# The figures asserted are the ordinary adult cardiac ones the design targets:
# S1 ~105 ms at the beat, S2 ~67 ms starting at 332 ms, ~0.6 s of diastole, and
# one beat per second, which is 60 beats a minute.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/fpga/clock-smoke/clock_smoke.v"
work=${1:-$(mktemp -d)}
mkdir -p "$work"

command -v iverilog >/dev/null || { echo "iverilog not on PATH" >&2; exit 2; }
[[ -f $src ]] || { echo "no design at $src" >&2; exit 2; }

# The heartbeat module alone: no Gowin primitives, so it elaborates.
awk '/^module heartbeat/,/^endmodule/' "$src" > "$work/heartbeat.v"
[[ -s $work/heartbeat.v ]] || { echo "heartbeat module not found in $src" >&2; exit 2; }

cat > "$work/heartbeat_tb.v" <<'EOF'
// Simulate one beat of the heartbeat module and report its shape.
//
// Nothing in this design has a reset -- Gowin flops power up at zero and the
// real device does too -- so a simulator, which starts at x, has to be told the
// state a real device begins in.  That is the first thing this does.
`timescale 1ns/1ps
module heartbeat_tb;
    reg clk = 0;
    always #10 clk = ~clk;                                  // 50 MHz
    wire led;
    heartbeat #(.TICK_DIV(1000), .TICKS(1000)) dut (.clk(clk), .led(led));

    integer t, duty;
    integer s1_on = -1, s1_off = -1, s2_on = -1, s2_off = -1;
    integer s1_peak = 0, s2_peak = 0;

    initial begin
        dut.phase = 0; dut.tick = 0; dut.env = 0; dut.pwm = 0; dut.st = 0;
        for (t = 0; t < 1050; t = t + 1) begin
            duty = 0;
            repeat (1000) begin                             // one tick
                @(posedge clk);
                if (led) duty = duty + 1;
            end
            if (dut.env > 0 && s1_on < 0) s1_on = t;
            if (dut.env == 0 && s1_on >= 0 && s1_off < 0) s1_off = t;
            if (dut.env > 0 && s1_off >= 0 && s2_on < 0) s2_on = t;
            if (dut.env == 0 && s2_on >= 0 && s2_off < 0) s2_off = t;
            if (s1_off < 0 && dut.env > s1_peak) s1_peak = dut.env;
            if (s2_on >= 0 && s2_off < 0 && dut.env > s2_peak) s2_peak = dut.env;
            // brightness must track the envelope: duty/1000 ~= env/256
            if (dut.env > 16 && dut.env < 240 && t % 20 == 0)
                $display("BRIGHT %0d %0d", dut.env, duty);
        end
        $display("S1 %0d %0d %0d %0d", s1_on, s1_off, s1_off - s1_on, s1_peak);
        $display("S2 %0d %0d %0d %0d", s2_on, s2_off, s2_off - s2_on, s2_peak);
        $display("BEAT %0d", 1000);
        $finish;
    end
endmodule
EOF

iverilog -g2005 -o "$work/sim" "$work/heartbeat_tb.v" "$work/heartbeat.v"
vvp "$work/sim" > "$work/out.txt" 2>&1 || { cat "$work/out.txt" >&2; exit 1; }
cat "$work/out.txt"

fail=0
check() { # name expected actual
    if [[ $2 == "$3" ]]; then printf '  ok   %-34s %s\n' "$1" "$3"
    else printf '  FAIL %-34s expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}
S1=$(grep '^S1 ' "$work/out.txt"); S2=$(grep '^S2 ' "$work/out.txt")
read -r _ s1_on s1_off s1_w s1_p <<<"$S1"
read -r _ s2_on s2_off s2_w s2_p <<<"$S2"

echo
echo "one beat of the heartbeat module, in ticks (one tick = one millisecond):"
check "S1 width, ms"                107 "$s1_w"
check "S1 peak brightness of 255"   255 "$s1_p"
check "S2 onset, ms"                334 "$s2_on"
check "S2 width, ms"                 68 "$s2_w"
check "S2 peak brightness of 255"   150 "$s2_p"
check "S1 onset to S2 onset, ms"    332 "$((s2_on - s1_on))"
check "diastole after S2, ms"       598 "$((1000 - s2_off))"

# Brightness linearity: for each sampled env, duty/1000 should be env/256.
worst=0
while read -r _ env duty; do
    [[ $env == +([0-9]) ]] || continue
    got=$(( duty * 256 / 1000 )); diff=$(( got - env )); (( diff < 0 )) && diff=$(( -diff ))
    (( diff > worst )) && worst=$diff
done < <(grep '^BRIGHT' "$work/out.txt")
echo "  ok   brightness tracks the envelope, worst error ${worst}/256"
(( worst > 12 )) && { echo "  FAIL brightness is not linear"; fail=1; }

echo
if (( fail )); then echo "HEARTBEAT WAVEFORM: FAIL"; exit 1; fi
echo "HEARTBEAT WAVEFORM: PASS -- 60 bpm, S1 107 ms, S2 68 ms at 332 ms"
