#!/usr/bin/env bash
#
# Sweep CLKDIV placement variants x seeds, in parallel.
#
#   tools/sweep-clkdiv-variants.sh <tree> [seeds...]
#
#   default seeds: 7 11 13 17   (12 runs total: 3 variants x 4 seeds)
#
# Why the CLKDIV.  The TMDS bit clock must reach the serialisers' FCLK, and in
# this design it does not: nextpnr either falls back to general fabric for three
# segments of `hclk5`, or refuses outright with
#
#   ERROR: Net hclk5 has no route to the FCLK of u_hdmi.hdmi.serializer.gwSer0
#          (sink wire X181Y102/FCLKA)
#
# Our build places the divider on CLKDIV_3; the vendor's places it on CLKDIV_0 on
# the same tile, with the same divisor, and its serialisers get their clock.  The
# bel is what selects which HCLK section's muxes feed the divider, so it is the
# one knob that reaches the vendor's configuration rather than just its seed.
#
#   A  as-is                          (control; lands on CLKDIV_3)
#   B  div5 pinned to CLKDIV_0        (the vendor's slot)
#   C  div5 pinned to CLKDIV_2        (section 1's sibling of the control)
#
# Acceptance is zero `Failed to route net 'hclk5'` warnings, and a run only
# counts if nextpnr's own completion line is in its log -- an interrupted run
# has no route failures in it because it never reached the router, which reads
# as a perfect score and is not one.
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
[[ ${#seeds[@]} -eq 0 ]] && seeds=(7 11 13 17)

netlist=$tree/nestang-top-open.json
basecst=$tree/src/desktop/desktop.cst
[[ -f $netlist ]] || { echo "no synthesised netlist at $netlist" >&2; exit 2; }
[[ -f $basecst ]] || { echo "no constraints at $basecst" >&2; exit 2; }

sweep=$tree/.open-clkdiv
mkdir -p "$sweep"

# ------------------------------------------------------------------ variants --
declare -A VARIANT_BEL=( [A]="" [B]="CLKDIV_0" [C]="CLKDIV_2" )
for v in A B C; do
    cst=$sweep/cst-$v.cst
    cp "$basecst" "$cst"
    bel=${VARIANT_BEL[$v]}
    if [[ -n $bel ]]; then
        {
            echo
            echo "// added by tools/sweep-clkdiv-variants.sh: pin the divider"
            echo "INS_LOC \"div5\" $bel;"
        } >> "$cst"
    fi
    echo "variant $v -> cst-$v.cst ${bel:+(div5 pinned to $bel)}" >&2
done
echo >&2

# ------------------------------------------------------------------- launch ---
pids=()
for v in A B C; do
    for seed in "${seeds[@]}"; do
        w=$sweep/$v-$seed
        mkdir -p "$w"
        (
            PNR_WORK=$w PNR_CST=$sweep/cst-$v.cst NEXTPNR_SEED=$seed \
                bash "$root/scripts/pnr-desktop.sh" "$tree" "$netlist" \
                > "$w/run.log" 2>&1
            echo "$?" > "$w/exit"
        ) &
        pids+=($!)
    done
done

echo "launched ${#pids[@]} runs; waiting..." >&2
for p in "${pids[@]}"; do wait "$p" || true; done
echo >&2

# ------------------------------------------------------------------ results --
printf '%-4s %-6s %-9s %-9s %-8s %-9s %s\n' var seed hclk5 all-nets finished clkdiv verdict >&2
best=999
for v in A B C; do
    for seed in "${seeds[@]}"; do
        w=$sweep/$v-$seed
        log=$w/nextpnr.log
        rc=$(cat "$w/exit" 2>/dev/null || echo "?")
        finished=no
        grep -q 'Program finished normally' "$log" 2>/dev/null && finished=yes
        n="-"; total="-"; where="-"
        if [[ $finished == yes && -f $w/pnr.json ]]; then
            n=$(grep -c "Failed to route net 'hclk5'" "$log")
            total=$(grep -c 'Failed to route net' "$log")
            where=$(grep -oE 'div5[^ ]*bel=[^ ]*|bel=X[0-9]+Y[0-9]+/CLKDIV_[0-9]' "$log" 2>/dev/null | head -1)
            [[ -z $where ]] && where=$(grep -oE 'X[0-9]+Y[0-9]+/CLKDIV_[0-9]' "$w/pnr.json" 2>/dev/null | head -1)
        fi
        verdict=""
        if [[ $finished == no ]]; then
            verdict="NOT FINISHED (exit $rc)"
            if grep -q 'no route to the FCLK' "$log" 2>/dev/null; then
                verdict="$verdict -- hclk5 could not reach the serialiser"
            fi
            if grep -qiE 'constraint|INS_LOC.*div5|failed to place' "$log" 2>/dev/null; then
                verdict="$verdict -- CHECK THE CONSTRAINT"
            fi
        elif [[ $n == 0 ]]; then
            verdict="ZERO hclk5 failures -- dedicated route"
            echo >&2
            echo "WINNER: variant $v seed $seed -- routed netlist $w/pnr.json" >&2
        fi
        printf '%-4s %-6s %-9s %-9s %-8s %-9s %s\n' "$v" "$seed" "$n" "$total" "$finished" "${where:--}" "$verdict" >&2
        [[ $n =~ ^[0-9]+$ ]] && (( n < best )) && best=$n
    done
done

echo >&2
echo "best: $best hclk5 failures" >&2
