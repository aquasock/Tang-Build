#!/usr/bin/env bash
#
# Sweep placement seeds for the desktop core IN PARALLEL, one run per seed.
#
#   tools/sweep-hclk5-parallel.sh <tree> [seed ...]
#
#   default seeds:  7 11 13 17 23 29
#
# Each seed gets its own work directory under <tree>/.open-sweep/, because
# everything the place-and-route step writes lives there and parallel runs in
# one directory would overwrite each other's netlist and log.  Six at a time is
# comfortable: this machine has 28 cores and nextpnr's placer is single
# threaded.
#
# Acceptance is a number, not a board test: zero
#
#   Failed to route net 'hclk5' ... using dedicated routing
#
# warnings.  That warning means nextpnr fell back to general fabric for the
# 371.25 MHz TMDS bit clock, which is what puts jitter on it and what the
# vendor's build does not do.  A placement that reaches zero has taken the
# dedicated route.
#
# A run is only counted if it FINISHED.  An interrupted run's log has no route
# failures in it because it never reached the router, which reads as a perfect
# score and is not one -- that happened once already.  So the log must contain
# nextpnr's own completion line, and the routed netlist must exist and be
# newer than the netlist it came from, before a zero is believed.
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
[[ ${#seeds[@]} -eq 0 ]] && seeds=(7 11 13 17 23 29)

netlist=$tree/nestang-top-open.json
[[ -f $netlist ]] || { echo "no synthesised netlist at $netlist" >&2; exit 2; }

sweep=$tree/.open-sweep
mkdir -p "$sweep"

echo "sweeping ${#seeds[@]} seeds in parallel: ${seeds[*]}" >&2
echo "baseline: 3 failing 'hclk5' segments of 947" >&2
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
best=999
winner=""
printf '%-8s %-10s %-10s %-8s %s\n' seed hclk5 all-nets finished verdict >&2
for seed in "${seeds[@]}"; do
    w=$sweep/seed-$seed
    log=$w/nextpnr.log
    rc=$(cat "$w/exit" 2>/dev/null || echo "?")
    finished=no
    if [[ -f $log ]] && grep -q 'Program finished normally' "$log"; then
        finished=yes
    fi
    if [[ $finished == yes && -f $w/pnr.json && $w/pnr.json -nt $netlist ]]; then
        n=$(grep -c "Failed to route net 'hclk5'" "$log")
        total=$(grep -c 'Failed to route net' "$log")
    else
        n="-"; total="-"
    fi
    verdict=""
    if [[ $finished == no ]]; then
        verdict="NOT FINISHED (exit $rc) -- not counted"
    elif [[ $n == 0 ]]; then
        verdict="ZERO hclk5 failures -- dedicated route taken"
        winner=$seed
    fi
    printf '%-8s %-10s %-10s %-8s %s\n' "$seed" "$n" "$total" "$finished" "$verdict" >&2
    if [[ $n =~ ^[0-9]+$ ]] && (( n < best )); then best=$n; fi
done

echo >&2
if [[ -n $winner ]]; then
    echo "WINNER: seed $winner routed with no hclk5 fabric fallback." >&2
    echo "its routed netlist is $sweep/seed-$winner/pnr.json" >&2
    echo "pack it with the fork's apycula (no *_as_gpio options):" >&2
    echo "  PYTHONHOME=/home/vash/oss-cad-suite \\" >&2
    echo "  PYTHONPATH=/run/media/vash/GIT/apicula-mathieufro:/home/vash/tools/pydeps \\" >&2
    echo "  /home/vash/oss-cad-suite/py3bin/python3 -m apycula.gowin_pack \\" >&2
    echo "      -d GW5AST-138C -o desktop-seed-$winner.fs $sweep/seed-$winner/pnr.json" >&2
    exit 0
fi
echo "no seed reached zero; best was $best hclk5 failures" >&2
exit 1
