#!/usr/bin/env python3
"""Ask the local chipdb what HCLK resources it knows, by number and by name.

    tools/chipdb-hclk-probe.py <GW5AST-138C.msgpack.xz> [wire-number ...]

The vendor's bitstream configures its HCLK section with `HCLK_MUX_GAMMA30`, and
apicula's 5A name table puts that at wire 585 -- but decoding their bitstream
yields wire 581, which the table leaves unnamed.  The question is whether the
database knows 581 at all: if the pips covering it are absent or unnamed then
nextpnr cannot route a clock through it, which is a candidate for the missing
TMDS bit-clock route.

SPDX-License-Identifier: MIT
"""
import sys
import collections

sys.path.insert(0, "/run/media/vash/GIT/apicula-mathieufro")
from apycula import chipdb  # noqa: E402

path = sys.argv[1]
want = [int(a) for a in sys.argv[2:]] or [581, 585]

db = chipdb.load_chipdb(path)
print(f"chipdb: {path}")
print(f"device db: {db.width}x{db.height}")
print()

pips = db.hclk_pips
print(f"db.hclk_pips: {len(pips)} entries keyed by (y, x)")

kinds = collections.Counter()
names = set()
for key, val in pips.items():
    for name in (val.keys() if hasattr(val, "keys") else []):
        names.add(name)
    kinds[type(val).__name__] += 1
print(f"  value types: {dict(kinds)}")

# Collect every wire name or number mentioned anywhere in the HCLK pip data.
seen = set()


def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            walk(k)
            walk(v)
    elif isinstance(obj, (set, list, tuple)):
        for v in obj:
            walk(v)
    elif isinstance(obj, str):
        seen.add(obj)
    else:
        seen.add(obj)


walk(pips)

print(f"  distinct items across the pip data: {len(seen)}")
for n in want:
    hits = sorted(x for x in seen if (isinstance(x, int) and x == n)
                  or (isinstance(x, str) and (f"UNK{n}" in x or x == str(n))))
    print(f"  wire {n}: {'FOUND ' + str(hits) if hits else 'NOT PRESENT in hclk_pips'}")

gam = sorted(x for x in seen if isinstance(x, str) and "GAMMA" in x)
print(f"  GAMMA names present: {gam[:12]}{' ...' if len(gam) > 12 else ''}")
unk = sorted(x for x in seen if isinstance(x, str) and "UNK" in x)
print(f"  UNK names present: {len(unk)}  e.g. {unk[:8]}")
