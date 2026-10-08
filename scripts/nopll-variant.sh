#!/usr/bin/env bash
#
# Make a no-PLL bring-up variant of the desktop core.
#
#   scripts/nopll-variant.sh <prepared-tree> <variant-tree>
#
# This is an EXPERIMENT, not the recipe.  It exists because the open database
# cannot place a PLL for GW5AST-138C, and the question "can we get something
# running without one" deserves a measured answer rather than an opinion.
#
# What it does, and why each part is legitimate rather than an HDL hack:
#
#  * Every clock domain is driven from the 50 MHz system input instead of from
#    the three PLLs and the CLKDIV.  The design's own clock-frequency
#    parameters then have to be told the truth: iosys_bl616 is instantiated
#    with FREQ(21_492_000) and divides its UART baud from that, so it becomes
#    FREQ(50_000_000).  The keyboard link already names CLK_HZ(50_000_000).
#    Without that change the BL616 link would run 2.33x fast and not talk.
#
#  * The timing constraints drop to a single clock.  desktop.sdc names
#    sys_clk, clk and hclk5; in this variant they are one net, and telling
#    nextpnr that one net is both 50 MHz and 21.49 MHz makes its clock
#    handling fail (measured: `Failed to route net 'clk' ... dedicated
#    routing`).
#
# What this variant costs: HDMI cannot work, because TMDS needs 371.25 MHz
# exactly, and the NES core runs 2.33x fast.  What it keeps: the desktop, its
# register interface, and the OLED terminal -- none of which care what the
# clock is.
#
# Measured outcome (2026-10-08): synthesises to 8,732 cells and *places
# completely*, then fails to route the clock net.  See
# ../evidence/desktop-core-nopll.txt and ../OPEN-FLOW-DESKTOP.md.
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

src=${1:-}
dst=${2:-}
if [[ -z $src || ! -d $src || -z $dst ]]; then
    echo "usage: $0 <prepared-tree> <variant-tree>" >&2
    echo "  <prepared-tree>: a tree with patches/0001 applied" >&2
    exit 2
fi
src=$(cd "$src" && pwd)

rsync -a --exclude .git --exclude .open-shim --exclude .open-pnr \
      --exclude .open-nopll "$src/" "$dst/"
echo "variant tree: $dst"

python3 - "$dst/src/nestang_top.sv" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

start = "`ifdef PLL_R\n// Nano uses rPLL"
end = "`else   // verilator"
old = s[s.index(start):s.index(end)]
new = """// Open-toolchain bring-up variant: no PLLs.
//
// GW5AST-138C has no placeable PLL in the open database, so every clock domain
// is driven straight from the 50 MHz system input.  The host interface is told
// the new frequency (see the iosys instantiation) so the BL616 link keeps its
// baud.  What this costs: HDMI cannot work, because TMDS needs 371.25 MHz
// exactly, and the NES core runs 2.33x fast.  What it keeps: the desktop, its
// register interface, and the OLED terminal.
assign clk27 = sys_clk;
assign clk   = sys_clk;
assign fclk  = sys_clk;
assign hclk5 = sys_clk;
assign hclk  = sys_clk;

"""
s = s.replace(old, new)
n = s.count(".FREQ(21_492_000)")
s = s.replace(".FREQ(21_492_000)", ".FREQ(50_000_000)")
open(p, "w").write(s)
print("clock block replaced; %d FREQ parameter(s) retargeted" % n)
PY

cat > "$dst/src/desktop/desktop.sdc" <<'EOF'
// Bring-up variant: one clock.  Every domain runs from the 50 MHz input.
// desktop.sdc's clk and hclk5 names are the same net here, and telling
// nextpnr otherwise makes its clock routing fail.
create_clock -name sys_clk -period 20 [get_nets {sys_clk}]
EOF
echo "constraints reduced to a single 50 MHz clock"
echo
echo "now:  scripts/synth-desktop.sh $dst"
echo "      scripts/pnr-desktop.sh  $dst"
