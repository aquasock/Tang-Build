#!/usr/bin/env bash
#
# Sweep placement seeds for the desktop core, in parallel, accepting on TIMING.
#
#   tools/sweep-timing-parallel.sh <tree> [seed ...]
#
#   default seeds:  7 11 13 17 19 23 29 31
#
# Why this exists next to tools/sweep-hclk5-parallel.sh.  That one accepts on
# zero `Failed to route net 'hclk5'` warnings, which is the right test for
# whether the TMDS bit clock reached the dedicated network.  It is not the test
# for whether the bitstream runs: the same run that gets hclk5 down to three
# fabric segments still leaves `clk` -- the 21.477 MHz main clock -- failing
# dedicated routing 943 times, and a clock on general fabric arrives at
# different registers at different times.  On the build this was written for
# that skew reached -2.09 ns and produced ten hold violations, and a build that
# ships with a hold violation is a build that runs by luck.
#
# So the criterion here is tools/pnr-timing.py's exit code: every clock passed
# and no setup or hold path violated.  That is the same bar TinyTang's Gowin
# recipe sets for its own binary ("zero setup/hold violations"), which is why
# the vendor's build has none and ours has ten.
#
# Timing is placement-dependent -- skew comes from where the clock's fabric
# segments land -- so this sweeps seeds rather than trying to fix one.  Each
# seed gets its own work directory because the place-and-route step writes its
# netlist and log there, and parallel runs in one directory would overwrite each
# other.  A run is only counted if nextpnr finished: an interrupted run has no
# violations in its log because it never reached the timing report.
#
# SPDX-License-Identifier: MIT
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)

tree=${1:-}
shift || true
if [[ -z $tree || ! -d $tree ]]; then
    echo "usage: $0 <tree> [seed ...]" >&2
    exit 2
fi
tree=$(cd "$tree" && pwd)
seeds=("$@")
[[ ${#seeds[@]} -eq 0 ]] && seeds=(7 11 13 17 19 23 29 31)

netlist=$tree/nestang-top-open.json
[[ -f $netlist ]] || { echo "no synthesised netlist at $netlist" >&2; exit 2; }

sweep=$tree/.open-timing
mkdir -p "$sweep"

echo "sweeping ${#seeds[@]} seeds in parallel, accepting on zero timing violations: ${seeds[*]}" >&2
echo >&2

pids=()
for seed in "${seeds[@]}"; do
    w=$sweep/seed-$seed
    mkdir -p "$w"
    (
        PNR_WORK=$w NEXTPNR_SEED=$seed \
            bash "$root/scripts/pnr-desktop.sh" "$tree" "$netlist" \
            > "$w/run.log" 2>&1
        echo "$?" > "$w/exit"
    ) &
    pids+=($!)
    echo "  launched seed $seed -> $w" >&2
done

echo >&2
echo "waiting for ${#pids[@]} runs..." >&2
for p in "${pids[@]}"; do wait "$p" || true; done
echo >&2

# ------------------------------------------------------------------ results --
printf '%-8s %-10s %-7s %-7s %-13s %s\n' seed finish setup hold worst-slack worst-skew >&2
winner=""
for seed in "${seeds[@]}"; do
    w=$sweep/seed-$seed
    log=$w/nextpnr.log
    rc=$(cat "$w/exit" 2>/dev/null || echo "?")
    if [[ ! -f $log ]] || ! grep -q 'Program finished normally' "$log"; then
        printf '%-8s %-10s %s\n' "$seed" "no($rc)" "NOT FINISHED -- not counted" >&2
        continue
    fi
    line=$(python3 "$root/tools/pnr-timing.py" "$log" 2>/dev/null | grep -m1 'summary:')
    setup=$(sed -n 's/.*setup=\([0-9]*\).*/\1/p' <<<"$line")
    hold=$(sed -n 's/.*hold=\([0-9]*\).*/\1/p' <<<"$line")
    slack=$(sed -n 's/.*worst_slack=\([-0-9.]*\).*/\1/p' <<<"$line")
    skew=$(sed -n 's/.*worst_skew=\([-0-9.]*\).*/\1/p' <<<"$line")
    printf '%-8s %-10s %-7s %-7s %-13s %s\n' "$seed" ok "${setup:-?}" "${hold:-?}" "${slack:-?}" "${skew:-?}" >&2
    if [[ $setup == 0 && $hold == 0 ]]; then
        winner=$seed
    fi
done

echo >&2
if [[ -n $winner ]]; then
    echo "WINNER: seed $winner has no setup or hold violation." >&2
    echo "its routed netlist is $sweep/seed-$winner/pnr.json" >&2
    echo "pack it with the fork's apicula (no *_as_gpio options):" >&2
    echo "  PYTHONHOME=/home/vash/oss-cad-suite \\" >&2
    echo "  PYTHONPATH=/run/media/vash/GIT/apicula-mathieufro:/home/vash/tools/pydeps \\" >&2
    echo "  /home/vash/oss-cad-suite/py3bin/python3 -m apicula.gowin_pack \\" >&2
    echo "      -d GW5AST-138C -o desktop-seed-$winner.fs $sweep/seed-$winner/pnr.json" >&2
    exit 0
fi
echo "no seed produced a violation-free build" >&2
exit 1
