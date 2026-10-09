#!/usr/bin/env python3
"""Ask the chipdb where its HCLK switch-matrix tiles actually are.

    tools/chipdb-hclk-tiles.py <GW5AST-138C.msgpack.xz> [row]

The PLL that feeds the TMDS bit clock sits at X1Y81 and the CLKDIV that divides
it sits at X181Y81, so a dedicated route between them needs switch-matrix tiles
across 180 columns of row 81.  nextpnr reports failing that dedicated route and
falling back to fabric, and the database only carries 171 HCLK tiles in total.
If they do not form an unbroken chain along that row, there is no dedicated path
to find, which would be the missing route rather than a naming or modelling gap.

SPDX-License-Identifier: MIT
"""
import sys
import collections

sys.path.insert(0, "/run/media/vash/GIT/apicula-mathieufro")
from apycula import chipdb  # noqa: E402

db = chipdb.load_chipdb(sys.argv[1])
row = int(sys.argv[2]) if len(sys.argv) > 2 else 81

print(f"chipdb {sys.argv[1]}")
pips = db.hclk_pips
print(f"db.hclk_pips: {len(pips)} tiles")
print()

by_row = collections.defaultdict(list)
for (y, x) in pips:
    by_row[y].append(x)

rows = sorted(by_row)
print(f"rows carrying HCLK tiles: {len(rows)}")
print(f"  {rows[:20]}{' ...' if len(rows) > 20 else ''}")
print()

for y in rows[:4] + [row] if row in by_row else rows[:4]:
    xs = sorted(by_row[y])
    gaps = [(a, b) for a, b in zip(xs, xs[1:]) if b != a + 1]
    print(f"row {y}: {len(xs)} tiles, x {xs[0]}..{xs[-1]}, gaps: "
          f"{gaps if gaps else 'none (contiguous)'}")
print()

if row in by_row:
    xs = sorted(by_row[row])
    print(f"row {row}: x from {xs[0]} to {xs[-1]}")
    print(f"  the failing route needs x=1 to x=181 along this row")
    missing = [x for x in range(1, 182) if x not in set(xs)]
    print(f"  columns 1..181 with no HCLK tile: {len(missing)} "
          f"{missing[:20]}{' ...' if len(missing) > 20 else ''}")
else:
    print(f"row {row} carries no HCLK tiles at all")
