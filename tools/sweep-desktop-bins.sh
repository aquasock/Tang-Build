#!/usr/bin/env bash
#
# Build a batch of desktop-core candidates, stamp each, and list the loads.
#
#   tools/sweep-desktop-bins.sh <tree> <outdir> [seed ...]
#
# Why this exists next to tools/sweep-timing-parallel.sh.  That one routes a
# batch of seeds and prints which pass timing; it stops at the routed netlist.
# What a placement sweep on hardware needs instead is *loadable artefacts*: the
# route packed to a bitstream, converted to the vendor binary, and named by its
# own content hash, so a candidate the user has actually put on the screen can
# be identified afterwards.  A sweep whose results cannot be named is a sweep
# whose results are lost -- this session already paid for that once, with
# `fadd00ba`, a build that renders perfectly and whose provenance nobody kept.
#
# Placement is the only variable that has changed the outcome so far: three
# placements have given a clean picture, a lined one, and a dead screen.  The
# timing model is itself suspect -- it scores hold violations at the site
# Gowin's own flow ships -- so this sweep deliberately does NOT filter on timing.
# It builds everything asked for and reports the violations it saw, leaving the
# CRT to decide what the model cannot.
#
# Default seeds: 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67
# Concurrency is every seed at once; set JOBS=n to narrow it.
#
# SPDX-License-Identifier: MIT
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)

tree=${1:-}; outdir=${2:-}
shift 2 2>/dev/null || true
if [[ -z $tree || ! -d $tree || -z $outdir ]]; then
    echo "usage: $0 <tree> <outdir> [seed ...]" >&2
    exit 2
fi
tree=$(cd "$tree" && pwd)
mkdir -p "$outdir"; outdir=$(cd "$outdir" && pwd)
seeds=("$@")
[[ ${#seeds[@]} -eq 0 ]] && seeds=(7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67)

netlist=$tree/nestang-top-open.json
[[ -f $netlist ]] || { echo "no synthesised netlist at $netlist -- run synth first" >&2; exit 2; }

PY=${PY:-/home/vash/oss-cad-suite/py3bin/python3}
export PYTHONHOME=${PYTHONHOME:-/home/vash/oss-cad-suite}
export PYTHONPATH=/run/media/vash/GIT/apicula-mathieufro:/home/vash/tools/pydeps${PYTHONPATH:+:$PYTHONPATH}

build_one() {
    local seed=$1 w=$2
    mkdir -p "$w"
    PNR_WORK=$w NEXTPNR_SEED=$seed \
        bash "$root/scripts/pnr-desktop.sh" "$tree" "$netlist" > "$w/run.log" 2>&1
    echo $? > "$w/exit"
    [[ $(cat "$w/exit") == 0 ]] || return 0
    "$PY" -m apycula.gowin_pack -d GW5AST-138C -o "$w/desktop.fs" "$w/pnr.json" \
        > "$w/pack.log" 2>&1 || return 0
    "$PY" "$root/tools/fs-to-bin.py" "$w/desktop.fs" -o "$w/desktop.bin" \
        > /dev/null 2>&1 || return 0
    ( cd "$w" && sha256sum desktop.bin desktop.fs | awk '{print substr($1,1,12), $2}' \
        > stamps.txt )
    cp -f "$w/desktop.bin" "$outdir/desktop.seed-$seed.$(cut -d' ' -f1 "$w/stamps.txt" | head -1).bin"
}

echo "building ${#seeds[@]} candidates in parallel -> $outdir" >&2
pids=()
for seed in "${seeds[@]}"; do
    build_one "$seed" "$outdir/seed-$seed" &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done

printf '%-6s %-6s %-5s %-6s %-9s %-9s %s\n' seed finish setup hold worst-slack bin-stamp >&2
for seed in "${seeds[@]}"; do
    w=$outdir/seed-$seed
    fin=FAILED; [[ -f $w/exit && $(cat $w/exit) == 0 ]] && fin=ok
    line=$("$PY" "$root/tools/pnr-timing.py" "$w/nextpnr.log" 2>/dev/null | tail -1)
    setup=$(sed -n 's/.*setup=\([0-9]*\).*/\1/p' <<<"$line")
    hold=$(sed -n 's/.*hold=\([0-9]*\).*/\1/p' <<<"$line")
    slack=$(sed -n 's/.*worst_slack=\([-0-9.]*\).*/\1/p' <<<"$line")
    stamp=-
    [[ -f $w/stamps.txt ]] && stamp=$(awk '$2=="desktop.bin"{print $1}' "$w/stamps.txt")
    printf '%-6s %-6s %-5s %-6s %-9s %-9s %s\n' "$seed" "$fin" "${setup:--}" "${hold:--}" \
        "${slack:--}" "${stamp:--}" "$( [[ -f $w/desktop.fs ]] && echo packed || echo -)" >&2
done

echo >&2
echo "loadable candidates are in $outdir as desktop.seed-<seed>.<stamp>.bin" >&2
ls -1 "$outdir"/desktop.seed-*.bin 2>/dev/null >&2 || echo "  (none)" >&2
