#!/usr/bin/env bash
#
# Build the clock-smoke design: the desktop core's clock chain, isolated.
#
#   scripts/build-clock-smoke.sh [out-dir]        (default /home/vash/tools/clock-smoke)
#
#   NEXTPNR_BUILD   directory holding nextpnr-himbaechel
#                   (default /home/vash/tools/nextpnr-mathieufro)
#
# Nothing here defaults into /tmp.  It used to, and that cost this project a
# bitstream to a reboot: `/tmp/tb/clock-smoke` was where the only build of this
# design lived when `/tmp` was cleared.  `scripts/pnr-desktop.sh` was repaired
# for the same reason; this is its counterpart.
#
# This uses the *fork* toolchain deliberately, not the suite's.  The chipdb
# that carries this device's clock structures is generated locally by the
# apycula fork from the vendor install, and the suite's published database has
# none of them for GW5AST-138C (see TOOLCHAIN.md, "The device database").
#
# Nothing here is specific to the smoke design except the file names: the same
# three steps are the project's general recipe.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/fpga/clock-smoke"
out="${1:-/home/vash/tools/clock-smoke}"

A=${APICULA_FORK:-/run/media/vash/GIT/apicula-mathieufro}
NPNR=${NEXTPNR_BUILD:-/home/vash/tools/nextpnr-mathieufro}/nextpnr-himbaechel
PY=${PY:-/home/vash/oss-cad-suite/py3bin/python3}
PYDEPS=${PYDEPS:-/home/vash/tools/pydeps}
DEVICE_PART="GW5AST-LV138PG484AC1/I0"
DEVICE_FAMILY="GW5AST-138C"

log() { printf '%s\n' "$*" >&2; }

# ------------------------------------------------------------------ environment
if [[ -z ${OSS_CAD_SUITE_SOURCED:-} ]]; then
    for env in "$HOME/oss-cad-suite/environment" /opt/oss-cad-suite/environment; do
        # shellcheck disable=SC1090
        [[ -f $env ]] && { source "$env"; SUITE=$(cd "$(dirname "$env")" && pwd); break; }
    done
fi
command -v yosys >/dev/null || { log "yosys not on PATH"; exit 2; }
[[ -x $NPNR ]] || { log "no fork-built nextpnr at $NPNR (set NEXTPNR_BUILD)"; exit 2; }
case $NPNR in
    */oss-cad-suite/*)
        log "NEXTPNR_BUILD points at oss-cad-suite's nextpnr; that build carries the"
        log "published GW5AST-138C database, which has no clock structures for this"
        log "device.  Point it at the fork's -- TOOLCHAIN.md, 'Building nextpnr against"
        log "the database'."
        exit 2
        ;;
esac
[[ -f $A/apycula/$DEVICE_FAMILY.msgpack.xz ]] || { log "no local chipdb in $A/apycula"; exit 2; }
# `msgspec` is needed by gowin_pack and by chipdb_builder and the bundle does not
# ship it; it is kept out of the toolchain install on purpose.
[[ -d $PYDEPS ]] || { log "no Python dependency dir at $PYDEPS (set PYDEPS)"; exit 2; }

# nextpnr's embedded Python interpreter is linked against the suite's prefix
# and aborts with "failed to get the Python codec of the filesystem encoding"
# unless PYTHONHOME names the bundle.  Measured, and recorded in TOOLCHAIN.md.
if [[ -n ${SUITE:-} ]]; then
    export PYTHONHOME="$SUITE"
    log "PYTHONHOME=$PYTHONHOME"
fi

export PYTHONPATH="$A:$PYDEPS:${PYTHONPATH:-}"

mkdir -p "$out"
cd "$src"
log "design: $src"
log "output: $out"
log "nextpnr: $NPNR"
log "apycula: $A"

# --------------------------------------------------------------- 1. synthesis
log ""
log "=== 1. synthesis (yosys, synth_gowin) ==="
yosys -q -l "$out/synth.log" -p "
    read_verilog -sv clock_smoke.v
    synth_gowin -top clock_smoke -family gw5a
    write_json $out/clock-smoke.json
"
log "   $out/clock-smoke.json"
yosys -q -p "read_json $out/clock-smoke.json; stat" 2>/dev/null | sed 's/^/   /' | tail -20 || true

# ---------------------------------------------------------- 2. place and route
log ""
log "=== 2. place and route (nextpnr-himbaechel) ==="
"$NPNR" \
    --json "$out/clock-smoke.json" \
    --write "$out/clock-smoke-pnr.json" \
    --device "$DEVICE_PART" \
    --vopt cst="$src/clock_smoke.cst" \
    --sdc "$src/clock_smoke.sdc" \
    --timing-allow-fail \
    --report "$out/report.json" \
    2>&1 | tee "$out/nextpnr.log" | grep -E "Max frequency|Info: Device utilisation|ERROR|Warning" | sed 's/^/   /' || true

# ----------------------------------------------------------------- 3. packing
log ""
log "=== 3. pack (gowin_pack, the fork's apycula) ==="
"$PY" -m apycula.gowin_pack -d "$DEVICE_FAMILY" \
    -o "$out/clock-smoke.fs" "$out/clock-smoke-pnr.json" \
    2>&1 | grep -vE "warnings.warn|UserWarning|DeprecationWarning" | sed 's/^/   /' || true

log ""
if [[ -f $out/clock-smoke.fs ]]; then
    ls -l "$out/clock-smoke.fs" | sed 's/^/   /'
    log "   packed ok"
else
    log "   NO BITSTREAM"
    exit 1
fi
