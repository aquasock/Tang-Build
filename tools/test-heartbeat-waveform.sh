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
# The figures asserted are the shape the design targets: a fast attack and a
# deliberately slow decay.  S1 snaps to full in 43 ms and fades over 255, so the
# sound lasts ~298 ms from the beat; S2 is the quieter one, rising to 120 of 255
# in 24 ms and fading over 120, beginning at 402 ms.  About 450 ms of the second
# is dark.  The decay is the long part on purpose -- it is what makes the
# brightness legible -- so a shorter one is a regression, not a tightening.
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

    // A second instance for the delay and single-sound parameters the lock
    // lanes use: ONE sound, no S2, and the whole beat shifted by DELAY_MS.
    wire led2;
    heartbeat #(.TICK_DIV(1000), .TICKS(1000), .DELAY_MS(700), .S2_EN(0), .FALL(8'd4), .DUTY_SHIFT(4))
              dut2 (.clk(clk), .led(led2));

    integer t, duty;
    integer s1_on = -1, s1_off = -1, s2_on = -1, s2_off = -1;
    integer s1_peak = 0, s2_peak = 0;
    integer d2_on = -1, d2_off = -1, d2b_on = -1;

    initial begin
        // Every register the design relies on powering up at zero has to be
        // named here.  Miss one and it sits at x, which is how the brightness
        // accumulator first went missing: `if (led)` was false for x on every
        // sample.  This list has to move with the design.
        dut.phase = 0; dut.tick = 0; dut.env = 0; dut.pwm = 0; dut.st = 0; dut.cdiv = 0;
        dut2.phase = 0; dut2.tick = 0; dut2.env = 0; dut2.pwm = 0; dut2.st = 0; dut2.cdiv = 0;
        for (t = 0; t < 2100; t = t + 1) begin
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
            if (dut2.env > 0 && d2_on < 0) d2_on = t;
            if (dut2.env == 0 && d2_on >= 0 && d2_off < 0) d2_off = t;
            // and again on the NEXT beat: a lane whose second sound is switched
            // off must still return to the start, or it blinks once and dies.
            if (dut2.env > 0 && d2_off >= 0 && d2b_on < 0) d2b_on = t;
            // The duty itself is no longer the thing to measure per tick: a
            // sixteen-bit carrier is longer than a whole test tick, so what a
            // tick contains is a fragment of one carrier period.  What matters
            // is the threshold the comparison uses, which is the envelope
            // shifted up by DUTY_SHIFT, and that is an identity to check.
            if (t % 20 == 0)
                $display("THRESH %0d %0d %0d %0d", dut.env, dut.thresh, dut2.env, dut2.thresh);
        end
        $display("S1 %0d %0d %0d %0d", s1_on, s1_off, s1_off - s1_on, s1_peak);
        $display("S2 %0d %0d %0d %0d", s2_on, s2_off, s2_off - s2_on, s2_peak);
        $display("BEAT %0d", 1000);
        $display("DELAY %0d %0d %0d", d2_on, d2_off - d2_on, d2b_on);
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
check "S1 width, ms"                298 "$s1_w"
check "S1 peak brightness of 255"   255 "$s1_p"
check "S2 onset, ms"                402 "$s2_on"
check "S2 width, ms"                144 "$s2_w"
check "S2 peak brightness of 255"   120 "$s2_p"
check "S1 onset to S2 onset, ms"    400 "$((s2_on - s1_on))"
check "diastole after S2, ms"       454 "$((1000 - s2_off))"

# The lock lanes: one sound, no S2, and the beat shifted by DELAY_MS.  The two
# ticks the onset lags by are the FSM's own, the same as `dut`'s.
D=$(grep '^DELAY ' "$work/out.txt"); read -r _ d2_on d2_w d2b_on <<<"$D"
echo
echo "the delayed single-sound lane the lock lanes use:"
check "onset, ms (DELAY_MS + 2)"     702 "$d2_on"
check "width, ms (rise 43, FALL 4)"  107 "$d2_w"
check "onset on the next beat, ms" 1702 "$d2b_on"

# The duty is thresh/65536 and thresh is the envelope shifted up by DUTY_SHIFT,
# so brightness tracks the envelope by construction.  Both shifts are checked:
# the default instance at 8, the delayed one at 4.
bad=0
while read -r _ env th env2 th2; do
    [[ $env == +([0-9]) ]] || continue
    if (( th != env * 256 )); then
        echo "  FAIL threshold not env<<8 at env=$env (got $th)"; bad=1
    fi
    if (( th2 != env2 * 16 )); then
        echo "  FAIL shifted threshold not env<<4 at env=$env2 (got $th2)"; bad=1
    fi
done < <(grep '^THRESH' "$work/out.txt")
(( bad )) && fail=1
echo "  ok   duty threshold is the envelope shifted up, for both shifts"

echo
if (( fail )); then echo "HEARTBEAT WAVEFORM: FAIL"; exit 1; fi
echo "HEARTBEAT WAVEFORM: PASS -- 60 bpm, S1 298 ms, S2 144 ms at 402 ms"
