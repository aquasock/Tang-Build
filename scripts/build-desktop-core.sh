#!/usr/bin/env bash
#
# Build TinyTang's desktop core end to end with the open flow.
#
#   scripts/build-desktop-core.sh <reconstructed-design-tree> [out-dir]
#
#   NEXTPNR_BUILD   directory holding nextpnr-himbaechel
#                   (default /home/vash/tools/nextpnr-mathieufro)
#   APICULA_FORK    the fork's apycula (default /run/media/vash/GIT/apicula-mathieufro)
#
# This is the three steps the project has been running by hand: synthesis
# (`synth-desktop.sh`), place and route (`pnr-desktop.sh`), and packing with the
# fork's `gowin_pack`.  It exists because running them by hand cost real time:
#
#  * `pnr-desktop.sh` passes nextpnr NO `*_as_gpio` options, so the packer has to
#    be run without them too.  Passing the vendor's six (mspi, ready, done, i2c,
#    cpu, sspi) makes `gowin_pack` refuse with "i2c_as_gpio has conflicting
#    settings in nexpnr and gowin_pack", which is the packer working correctly.
#    Matching the vendor's pinout would mean passing the options to both tools,
#    and this flow does not do that today.
#  * The packer needs the fork's apycula, whose `get_pll_attrvals` handles the
#    string parameters the slang front end leaves in place; the suite's would
#    reject them.
#  * Nothing here defaults into /tmp.  A build that lives in a temporary
#    directory has cost this project a bitstream before.
#
# The tree is left as it was apart from the build artefacts the two scripts
# write into it (`.open-shim/`, `.open-pnr/`, `nestang-top-open.json`).
#
# SPDX-License-Identifier: MIT
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)

tree=${1:-}
if [[ -z $tree || ! -d $tree ]]; then
    echo "usage: $0 <reconstructed-design-tree> [out-dir]" >&2
    exit 2
fi
tree=$(cd "$tree" && pwd)
out=${2:-$tree/.open-fs}

A=${APICULA_FORK:-/run/media/vash/GIT/apicula-mathieufro}
NPNR=${NEXTPNR_BUILD:-/home/vash/tools/nextpnr-mathieufro}
# The placement seed.  Placement decides how much clock skew this design's main
# clock accumulates: `clk` cannot reach the dedicated network from any PLL site,
# because the HCLK interconnect is not modelled, so it rides general fabric and
# the skew depends on where its segments land.  Seed 23, with pll_nes pinned to
# PLL_R[0], is the placement that measures violation-free -- and the gate below
# refuses to publish one that does not.
SEED=${NEXTPNR_SEED:-23}
export NEXTPNR_SEED=$SEED
PY=${PY:-/home/vash/oss-cad-suite/py3bin/python3}
PYDEPS=${PYDEPS:-/home/vash/tools/pydeps}
DEVICE_PART="GW5AST-LV138PG484AC1/I0"
DEVICE_FAMILY="GW5AST-138C"

log() { printf '%s\n' "$*" >&2; }

if [[ -z ${OSS_CAD_SUITE_SOURCED:-} ]]; then
    for env in "$HOME/oss-cad-suite/environment" /opt/oss-cad-suite/environment; do
        # shellcheck disable=SC1090
        [[ -f $env ]] && { source "$env"; SUITE=$(cd "$(dirname "$env")" && pwd); break; }
    done
fi
[[ -n ${SUITE:-} ]] && export PYTHONHOME="$SUITE"
export PYTHONPATH="$A:$PYDEPS:${PYTHONPATH:-}"
[[ -d $A/apycula ]] || { log "no fork apycula at $A"; exit 2; }
mkdir -p "$out"

# --------------------------------------------------------------- 1. synthesis
log "=== 1. synthesis ==="
bash "$here/synth-desktop.sh" "$tree" "$tree/nestang-top-open.json"
[[ -f $tree/nestang-top-open.json ]] || { log "no netlist produced"; exit 1; }

# ---------------------------------------------------------- 2. place and route
log "=== 2. place and route ==="
bash "$here/pnr-desktop.sh" "$tree" "$tree/nestang-top-open.json"
[[ -f $tree/.open-pnr/pnr.json ]] || { log "no routed netlist produced"; exit 1; }

# A routed netlist is not a working bitstream.  `pnr-desktop.sh` passes nextpnr
# `--timing-allow-fail`, so a violated path is reported and the flow carries on
# and packs it -- and a build with a hold violation is a build that runs by
# luck, whatever the screen happens to do.  TinyTang's Gowin recipe sets the
# same bar for its own binary ("zero setup/hold violations"), so require it here
# and refuse to pack.  tools/pnr-timing.py explains why this reads the log:
# hold violations appear in no structured field of nextpnr's report.
log "=== 2b. timing gate (seed $SEED) ==="
if ! "$PY" "$root/tools/pnr-timing.py" "$tree/.open-pnr/nextpnr.log" \
    --require-dedicated-clock clk \
    --require-clock keyboard_link.clk=50 \
    --require-clock desktop_sockets.pixel_clk=74.25 \
    --require-clock clk=21.49; then
    log ""
    log "REFUSING TO PACK: the place-and-route has timing violations."
    log "A bitstream from this netlist is not one to put on the board."
    log "The paths and their slack are above; what causes the skew, and the"
    log "PLL site that decides it, are recorded in"
    log "$tree/src/desktop/desktop.cst and evidence/hclk-route-gap.txt."
    exit 1
fi

# ----------------------------------------------------------------- 3. packing
# No *_as_gpio options: see the note at the top of this script.
log "=== 3. pack (gowin_pack, the fork's apycula) ==="
"$PY" -m apycula.gowin_pack -d "$DEVICE_FAMILY" \
    -o "$out/desktop.fs" "$tree/.open-pnr/pnr.json" 2>&1 \
    | grep -vE "warnings.warn|UserWarning|DeprecationWarning" | sed 's/^/   /' || true

log ""
if [[ -f $out/desktop.fs ]]; then
    ls -l "$out/desktop.fs" | sed 's/^/   /'
    sha256sum "$out/desktop.fs" | sed 's/^/   /'
    log "   packed ok"
else
    log "   NO BITSTREAM"
    exit 1
fi
