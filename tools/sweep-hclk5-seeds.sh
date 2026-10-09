#!/usr/bin/env bash
#
# Sweep placement seeds for the desktop core, looking for a placement where the
# TMDS bit clock gets a dedicated route.
#
#   tools/sweep-hclk5-seeds.sh <tree> [max-seed] [out-dir]
#
# Acceptance is a number, not a board test: zero
#
#   Failed to route net 'hclk5' ... using dedicated routing
#
# warnings, out of the 947 this design normally produces.  That warning means
# nextpnr fell back to general fabric for this 371.25 MHz net, which is what
# puts jitter on the TMDS bit clock and what the vendor's build does not do --
# theirs selects the HCLK network's input at the divider instead.  A placement
# that reaches zero has taken the dedicated route.
#
# Synthesis does not depend on the seed, so this only re-places and re-routes,
# which is about a minute per seed.  The first seed that reaches zero has its
# routed netlist COPIED OUT before the next seed overwrites it, and the sweep
# stops there.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)

tree=${1:-}
max=${2:-20}
if [[ -z $tree || ! -d $tree ]]; then
    echo "usage: $0 <tree> [max-seed] [out-dir]" >&2
    exit 2
fi
tree=$(cd "$tree" && pwd)
out=${3:-$tree/.open-sweep}
mkdir -p "$out"

netlist=$tree/nestang-top-open.json
[[ -f $netlist ]] || { echo "no synthesised netlist at $netlist" >&2; exit 2; }

echo "sweeping seeds 1..$max on $tree" >&2
echo "baseline is 3 failing 'hclk5' segments out of 947" >&2
echo >&2

best=999
for seed in $(seq 1 "$max"); do
    NEXTPNR_SEED=$seed bash "$root/scripts/pnr-desktop.sh" "$tree" "$netlist" \
        > "$out/seed-$seed.log" 2>&1 || true
    log=$tree/.open-pnr/nextpnr.log
    n=$(grep -c "Failed to route net 'hclk5'" "$log" 2>/dev/null || echo "?")
    total=$(grep -c "Failed to route net" "$log" 2>/dev/null || echo "?")
    printf 'seed %-3s hclk5 failures: %-4s (all nets: %s)\n' "$seed" "$n" "$total" >&2

    if [[ $n == 0 ]]; then
        cp "$tree/.open-pnr/pnr.json" "$out/pnr-seed-$seed.json"
        cp "$log" "$out/nextpnr-seed-$seed.log"
        echo >&2
        echo "seed $seed reaches ZERO hclk5 failures -- routed netlist kept at" >&2
        echo "  $out/pnr-seed-$seed.json" >&2
        echo "pack it with:" >&2
        echo "  PYTHONHOME=/home/vash/oss-cad-suite \\" >&2
        echo "  PYTHONPATH=\$APICULA_FORK:/home/vash/tools/pydeps \\" >&2
        echo "  /home/vash/oss-cad-suite/py3bin/python3 -m apycula.gowin_pack \\" >&2
        echo "      -d GW5AST-138C -o desktop-seed-$seed.fs $out/pnr-seed-$seed.json" >&2
        exit 0
    fi
    [[ $n =~ ^[0-9]+$ ]] && (( n < best )) && best=$n
done

echo >&2
echo "no seed in 1..$max reached zero; best was $best failures" >&2
exit 1
