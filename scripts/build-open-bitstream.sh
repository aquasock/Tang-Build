#!/usr/bin/env bash
# Build an Apicula example for the Sipeed Tang Console 138K with the open
# toolchain, and optionally load it onto the board.
#
#   scripts/build-open-bitstream.sh                    # the UART demo for this board
#   scripts/build-open-bitstream.sh attosoc            # a picorv32 RISC-V SoC
#   scripts/build-open-bitstream.sh uart-message --load
#
# Everything comes from oss-cad-suite (yosys, nextpnr-himbaechel, gowin_pack,
# openFPGALoader) plus upstream Apicula's examples. No Gowin EDA is involved,
# and no root is needed.
#
# --load requires the board's MCU USB-C port (the FT2232 bridge, 0403:6010) and
# writes the FPGA's SRAM, which is volatile: a power cycle or the reconfig
# button erases it. TinyTang does not run in that arrangement.
set -euo pipefail

SUITE="${OSS_CAD_SUITE:-$HOME/oss-cad-suite}"
APICULA="${APICULA_DIR:-$HOME/apicula}"
OUT_DIR="${OUT_DIR:-$PWD/build}"

DESIGN="${1:-uart-message}"
LOAD="${2:-}"

DEVICE_PART="GW5AST-LV138PG484AC1/I0"
DEVICE_FAMILY="GW5AST-138C"
BOARD="tangconsole"

log() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- environment

[[ -f "$SUITE/environment" ]] || die "no oss-cad-suite at $SUITE (set OSS_CAD_SUITE)"
# shellcheck disable=SC1090
source "$SUITE/environment"

for tool in yosys nextpnr-himbaechel gowin_pack openFPGALoader; do
    command -v "$tool" >/dev/null || die "$tool is not on PATH after sourcing $SUITE/environment"
done

log "toolchain:"
log "  yosys               $(yosys -V 2>/dev/null | head -1)"
log "  nextpnr-himbaechel  $(nextpnr-himbaechel --version 2>/dev/null | head -1)"
log "  openFPGALoader      $(openFPGALoader --Version 2>/dev/null | head -1)"
log "  device database     $(python3 -c 'import apycula, os; print(os.path.join(os.path.dirname(apycula.__file__), "GW5AST-138C.msgpack.xz"))')"

# ------------------------------------------------------------------- examples

if [[ ! -d "$APICULA/examples/gw5a" ]]; then
    log "cloning upstream apicula into $APICULA"
    git clone --depth 1 https://github.com/YosysHQ/apicula.git "$APICULA"
fi

cd "$APICULA/examples/gw5a"

case "$DESIGN" in
    uart-message) TARGET=tangconsole138k ;;   # uses tangconsole138k.cst
    attosoc|big-shift) TARGET=tangmega138k ;;
    *) die "unknown design '$DESIGN' (uart-message | attosoc | big-shift)" ;;
esac

log "building $DESIGN ($TARGET) for $DEVICE_PART"
make "$TARGET"

mkdir -p "$OUT_DIR"

# The Makefile names everything after the Mega 138K; for the Console the only
# difference is which .cst nextpnr was given.
produced=()
for f in *-"$DESIGN"-tangmega138k.fs; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$OUT_DIR/"
    produced+=("$OUT_DIR/$(basename "$f")")
done
[[ ${#produced[@]} -gt 0 ]] || die "no .fs produced — did the build fail?"

# A compressed copy: the raw .fs is ~35 MB because Gowin's .fs is text, and
# gowin_pack -c brings it down to roughly a fifth of that.
for f in "${produced[@]}"; do
    # Re-pack compressed from a fresh nextpnr run, keeping the intermediate.
    base="$(basename "$f" .fs)"
    if [[ -f "$base.json" ]]; then
        gowin_pack -c --cpu_as_gpio -d "$DEVICE_FAMILY" -o "$OUT_DIR/$base-compressed.fs" "$base.json" 2>/dev/null || true
    fi
done

log "built:"
for f in "$OUT_DIR"/*.fs; do
    [[ -f "$f" ]] || continue
    log "  $(stat -c '%10s  %n' "$f")"
done

# ----------------------------------------------------------------------- load

if [[ "$LOAD" == "--load" ]]; then
    fs="${produced[0]}"
    log "loading $(basename "$fs") — needs the board on the MCU port"
    openFPGALoader -b "$BOARD" "$fs"
    log "loaded. SRAM only: a power cycle or the reconfig button erases it."
else
    log "not loading (pass --load). Loading needs the MCU USB-C port:"
    log "  openFPGALoader -b $BOARD ${produced[0]}"
fi
