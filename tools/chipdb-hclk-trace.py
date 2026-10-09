#!/usr/bin/env python3
"""Where does an HCLK wire sit, and what does the database model as spine?

    tools/chipdb-hclk-trace.py <GW5AST-138C.msgpack.xz> [wire ...]

The vendor's CLKDIV selects an HCLK-network wire (`HCLK_UNK581`) while ours
selects a fabric entry, and the failing route runs from the PLL at X1Y81 to the
CLKDIV at X181Y81.  This prints, for each wire asked about, every HCLK tile that
mentions it and whether it is a source or a destination there, plus the whole
switch matrix of the tiles on that row.  It also lists the database's own field
names, since the spine model -- whatever nextpnr has to route across sections --
lives in one of them.

SPDX-License-Identifier: MIT
"""
import sys
import dataclasses

sys.path.insert(0, "/run/media/vash/GIT/apicula-mathieufro")
from apycula import chipdb  # noqa: E402

db = chipdb.load_chipdb(sys.argv[1])
want = [int(a) for a in sys.argv[2:]] or [581]

print("database fields:")
for f in dataclasses.fields(db):
    try:
        n = len(getattr(db, f.name))
    except TypeError:
        n = "-"
    print(f"  {f.name}: {n}")
print()

pips = db.hclk_pips
for w in want:
    name = f"HCLK_UNK{w}"
    print(f"wire {w} ({name}):")
    hits = 0
    for (y, x), matrix in sorted(pips.items()):
        for dst, srcs in matrix.items():
            as_src = any(str(s) == name or s == name for s in srcs.keys())
            if dst == name or str(dst) == name:
                print(f"  tile (y={y}, x={x}): DESTINATION of "
                      f"{len(srcs)} source(s)")
                hits += 1
            elif as_src:
                print(f"  tile (y={y}, x={x}): source into {dst}")
                hits += 1
    if not hits:
        print("  appears in no hclk_pips matrix")
    print()

print("the two tiles on row 81, in full:")
for (y, x), matrix in sorted(pips.items()):
    if y == 81:
        print(f"  tile (y=81, x={x}): {len(matrix)} destination wire(s)")
        for dst, srcs in list(matrix.items())[:8]:
            print(f"    {dst} <- {list(srcs.keys())[:6]}")
print()

# What feeds the wire the vendor selects, and where the spine model lives.
for (y, x), matrix in sorted(pips.items()):
    for dst, srcs in matrix.items():
        if str(dst) == 'HCLK_MUX_GAMMA30':
            print(f"HCLK_MUX_GAMMA30 is fed by {[str(s) for s in srcs.keys()]} "
                  f"at tile (y={y}, x={x})")
            for src in srcs.keys():
                back = sorted(
                    (yy, xx, str(d))
                    for (yy, xx), m2 in pips.items()
                    for d, s2 in m2.items()
                    if str(d) == str(src)
                )
                print(f"  and {src} is a destination in tiles: {back[:8]}")
print()
print(f"spine_select_wires: {getattr(db, 'spine_select_wires', None)}")
