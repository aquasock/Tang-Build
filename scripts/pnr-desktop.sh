#!/usr/bin/env bash
#
# Take the synthesised desktop core into place-and-route with nextpnr-himbaechel.
#
#   scripts/pnr-desktop.sh <reconstructed-design-tree> [netlist.json]
#
# Expect to be stopped at the PLL.  As of 2026-10-08 the GW5AST-138C
# architecture has no placeable PLL bel -- see ../OPEN-FLOW-DESKTOP.md, section
# "Where the open flow stops" -- so this gets as far as placing the first PLL
# and reports what it found.  Everything before that point (packing, BSRAM,
# the IOLOGIC/OSER10 path, IO) is placed successfully.
#
# Two pieces of design-to-toolchain translation are needed first, and both are
# done here rather than by editing the design:
#
#  * nextpnr's SDC reader does not accept `//` comments, and desktop.sdc opens
#    with one.  Converted to `#`.
#  * nextpnr requires every IO to have a location.  `reset2` is declared in
#    nestang_top.sv ("button S1 and pin 48 are both resets") and used nowhere,
#    and the vendor build has no pin for it either, so it cannot be placed.
#    It is dropped -- but only after checking it really is unused, because
#    silently deleting a port that something reads would be worse than the
#    error it avoids.
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tree=${1:-}
if [[ -z $tree || ! -d $tree ]]; then
    echo "usage: $0 <reconstructed-design-tree> [netlist.json]" >&2
    exit 2
fi
tree=$(cd "$tree" && pwd)
netlist=${2:-$tree/nestang-top-open.json}
[[ -f $netlist ]] || { echo "no netlist at $netlist (run synth-desktop.sh first)" >&2; exit 2; }

if [[ -z ${SYNTH_DESKTOP_NO_ENV:-} ]]; then
    for env in "$HOME/oss-cad-suite/environment" /opt/oss-cad-suite/environment; do
        [[ -f $env ]] && { source "$env"; break; }
    done
fi
command -v nextpnr-himbaechel >/dev/null || { echo "nextpnr-himbaechel not found" >&2; exit 2; }

cst=$tree/src/desktop/desktop.cst
sdc=$tree/src/desktop/desktop.sdc
work=$tree/.open-pnr
mkdir -p "$work"
[[ -f $cst ]] || { echo "no constraints at $cst" >&2; exit 2; }

# ------------------------------------------------------------- constraints --
# `//` -> `#`; nextpnr's SDC parser rejects the C++-style comment.
sed 's|^\([[:space:]]*\)//|\1#|' "$sdc" > "$work/desktop.sdc"
echo "timing constraints:"
sed 's/^/    /' "$work/desktop.sdc"

# ------------------------------------------------ unconstrained, unused IOs --
# Decide what has to be dropped, and refuse if anything has to be dropped that
# is actually in use.
python3 - "$netlist" "$cst" "$work" <<'PY'
import json, re, sys
netlist, cst_path, work = sys.argv[1], sys.argv[2], sys.argv[3]

doc = json.load(open(netlist))
top = doc["modules"]["nestang_top"]

# ports the constraint file gives a location to ("tmds_d_p[0]" -> "tmds_d_p")
constrained = set()
for line in open(cst_path):
    m = re.match(r'\s*IO_LOC\s+"([^"]+)"', line)
    if m:
        constrained.add(re.sub(r"\[.*\]$", "", m.group(1)))

unconstrained = [p for p in top["ports"] if p not in constrained]
if not unconstrained:
    print("every top-level port has a pin constraint")
    open(work + "/drop.ys", "w").write(
        "read_json %s\nwrite_json %s/pnr-input.json\n" % (netlist, work))
    sys.exit(0)

def consumers(bit):
    out = []
    for name, cell in top["cells"].items():
        for pin, bits in cell.get("connections", {}).items():
            if bit in bits:
                out.append((name, cell["type"], pin))
    return out

drop_ports, drop_cells, used = [], [], []
for port in unconstrained:
    bits = set(top["ports"][port]["bits"])
    bufs = [(n, c) for n, c in top["cells"].items()
            if c["type"] in ("IBUF", "IOBUF", "OBUF", "TBUF")
            and any(b in bits for b in
                    (c.get("connections", {}).get("I") or [])
                    + (c.get("connections", {}).get("O") or []))]
    if not bufs:
        drop_ports.append(port)
        continue
    in_use = False
    for bname, bcell in bufs:
        outs = set(bcell.get("connections", {}).get("O", []))
        for other, otype, opin in consumers(next(iter(outs), None)):
            if other != bname and not otype.startswith("$"):
                in_use = True
    if in_use:
        used.append(port)
    else:
        drop_ports.append(port)
        drop_cells.extend(n for n, _ in bufs)

if used:
    sys.stderr.write(
        "\nERROR: these top-level ports have no pin in %s and ARE used:\n" % cst_path)
    for p in used:
        sys.stderr.write("    %s\n" % p)
    sys.stderr.write("Add an IO_LOC for them (from the board's pinout) rather than\n"
                     "letting them be dropped.\n")
    sys.exit(1)

print("ports with no pin constraint: %s" % (", ".join(unconstrained) or "none"))
if drop_ports:
    print("unused, so dropped: %s%s"
          % (", ".join(drop_ports),
             "  (+ buffers: %s)" % ", ".join(drop_cells) if drop_cells else ""))

lines = ["read_json %s" % netlist, "select -module nestang_top"]
for n in drop_ports + drop_cells:
    lines.append("delete %s" % n)
lines += ["select -clear", "opt_clean -purge",
          "write_json %s/pnr-input.json" % work]
open(work + "/drop.ys", "w").write("\n".join(lines) + "\n")
PY

yosys -q -s "$work/drop.ys" > "$work/drop.log" 2>&1 || {
    echo "failed to prepare the netlist for place and route:" >&2
    tail -20 "$work/drop.log" >&2
    exit 1
}

# ------------------------------------------------------------------ nextpnr --
echo
echo "placing and routing (expect the PLL to be the thing that stops it)"
set +e
nextpnr-himbaechel \
    --json "$work/pnr-input.json" \
    --write "$work/pnr.json" \
    --device GW5AST-LV138PG484AC1/I0 \
    --vopt cst="$cst" \
    --sdc "$work/desktop.sdc" \
    --timing-allow-fail \
    --report "$work/report.json" 2>&1 | tee "$work/nextpnr.log"
rc=${PIPESTATUS[0]}
set -e

echo
if (( rc == 0 )); then
    echo "nextpnr finished; packed output in $work/pnr.json"
else
    echo "nextpnr stopped (exit $rc).  Log: $work/nextpnr.log"
    if grep -q "no BELs remaining to implement cell type 'PLL'" "$work/nextpnr.log"; then
        cat <<'EOF'

That is the known wall, not a mistake in the netlist:

  the design instantiates 3 PLL / 1 CLKDIV / 3 OSER10, exactly as the vendor
  build does, and the netlist is checked for them.  The GW5AST-138C
  architecture in this nextpnr build has no placeable PLL bel.  apicula grants
  its 5A clock flag (HAS_5A_HCLK) to GW5A-25A only, and nextpnr's GW5A PLL
  work covers the 25A's PLLA type.  Nothing newer is available: nextpnr
  master HEAD is 861c57be (2026-10-07), which is the revision this binary is
  built from, and apicula main is b4e70dc (2026-10-02).

See ../OPEN-FLOW-DESKTOP.md.
EOF
    fi
fi
exit $rc
