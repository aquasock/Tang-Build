#!/usr/bin/env python3
"""How complete is the chipdb's HCLK network?  A wire-level inventory.

    tools/chipdb-hclk-gaps.py <GW5AST-138C.msgpack.xz> [wire-number ...]

`tools/chipdb-hclk-tiles.py` shows the HCLK switch-matrix tiles sit at x=0,
x=181 and along row 108 -- the die's left, right and bottom sides -- 171 tiles
in all.  nextpnr still reports `Failed to route net 'clk'` 943 times and
`Failed to route net 'hclk5'` for the TMDS bit clock, so the question is what
the *pips* are missing, not where the tiles are.

For every wire name in `db.hclk_pips` this tool reports where it is driven
(sources) and where it is consumed (destinations), and separates the three
cases that matter:

  * spanning       -- driven in one tile and consumed in another, so the name
                      carries a signal between tiles at all;
  * consumed but never driven -- a destination with no source anywhere: a
                      signal cannot be placed on it.  The vendor's own build
                      uses at least one of these (HCLK_UNK581, the input-mux
                      feed recorded in evidence/hclk-route-gap.txt);
  * driven but never consumed -- a source nothing reads.

Then the tile graph those spanning wires imply.  Read its result carefully:
sharing a wire *name* between two tiles is necessary but not sufficient for a
routable path, so a single connected component does NOT mean the network works.
It means the model is not grossly disjoint, which is itself worth knowing -- it
rules out the simplest explanation for the failed routes.

SPDX-License-Identifier: MIT
"""

import sys
import collections

sys.path.insert(0, "/run/media/vash/GIT/apicula-mathieufro")
from apycula import chipdb  # noqa: E402

DEFAULT = "/run/media/vash/GIT/apicula-mathieufro/apycula/GW5AST-138C.msgpack.xz"


def classify(wire, src_tiles, dst_tiles):
    st, dt = src_tiles.get(wire), dst_tiles.get(wire)
    if not st and not dt:
        return "absent from hclk_pips"
    if dt and not st:
        return "UNDRIVEN (consumed, never sourced)"
    if st and not dt:
        return "dead-end (sourced, never consumed)"
    if st != dt:
        return "spanning (sourced and consumed in different tiles)"
    return "intra-tile only (sourced and consumed in the same tile)"


def main(argv):
    path = argv[1] if len(argv) > 1 else DEFAULT
    extra = [int(a) for a in argv[2:]]
    db = chipdb.load_chipdb(path)
    pips = db.hclk_pips

    tiles = sorted(pips)
    src_tiles = collections.defaultdict(set)
    dst_tiles = collections.defaultdict(set)
    for tile, matrix in pips.items():
        for dst, srcs in matrix.items():
            dst_tiles[str(dst)].add(tile)
            for s in srcs:
                src_tiles[str(s)].add(tile)

    wires = set(src_tiles) | set(dst_tiles)
    spanning = sorted(w for w in wires if src_tiles.get(w) and dst_tiles.get(w)
                      and src_tiles[w] != dst_tiles[w])
    undriven = sorted(w for w in wires if dst_tiles.get(w) and not src_tiles.get(w))

    print("chipdb %s" % path)
    print("  HCLK tiles: %d across rows %d..%d"
          % (len(tiles), tiles[0][0] if tiles else -1,
             tiles[-1][0] if tiles else -1))
    cols = collections.Counter(x for _, x in tiles)
    edges = sum(n for x, n in cols.items() if x in (0, 181))
    print("  at the die edges (x=0, x=181): %d; interior (row 108): %d"
          % (edges, len(tiles) - edges))
    print()

    print("HCLK wire names seen: %d" % len(wires))
    print("  spanning (carry between tiles) : %d" % len(spanning))
    print("  UNDRIVEN (consumed, no source) : %d" % len(undriven))
    print("  dead-end (source, no consumer): %d"
          % sum(1 for w in wires if src_tiles.get(w) and not dst_tiles.get(w)))
    print()

    named = extra or [561, 563, 571, 581, 585]
    print("specific wires the prior evidence names (see hclk-route-gap.txt):")
    for n in named:
        w = "HCLK_UNK%d" % n if str(n).isdigit() else str(n)
        print("  %-16s %s" % (w, classify(w, src_tiles, dst_tiles)))
        print("      src=%s dst=%s"
              % (sorted(src_tiles.get(w, []))[:4], sorted(dst_tiles.get(w, []))[:4]))
    print()

    print("first %d undriven wires:" % min(15, len(undriven)))
    for w in undriven[:15]:
        print("  %-16s consumed in %s" % (w, sorted(dst_tiles[w])[:3]))
    print()

    parent = {t: t for t in tiles}

    def find(t):
        while parent[t] != t:
            parent[t] = parent[parent[t]]
            t = parent[t]
        return t

    for w in spanning:
        srcs, dsts = sorted(src_tiles[w]), sorted(dst_tiles[w])
        for a in srcs:
            for b in dsts:
                if a != b:
                    ra, rb = find(a), find(b)
                    if ra != rb:
                        parent[ra] = rb

    comps = collections.Counter(find(t) for t in tiles)
    sizes = sorted(comps.values(), reverse=True)
    print("tile graph over shared wire names: %d component(s), sizes %s"
          % (len(sizes), sizes[:12]))
    print("  (necessary-but-not-sufficient for a route; a single component says")
    print("  only that the model is not grossly disjoint.  What nextpnr could not")
    print("  route is a specific path, which the log, not this graph, identifies.)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
