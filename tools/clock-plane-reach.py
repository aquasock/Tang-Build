#!/usr/bin/env python3
"""How far does each clock gate reach across the plane?

    tools/clock-plane-reach.py <GW5AST-138C.msgpack.xz> [--load-tile R,C ...]

`nextpnr/himbaechel/uarch/gowin/globals.cc` says the thing that decides whether
a clock can be routed at all: "A buffer sits on one logic-to-clock gate, and a
gate reaches only part of the clock plane... move the buffer to a gate that does
reach both its source and its loads." When no gate does, nextpnr prints

    no clock gate reaches both its source and its loads.

The gate sites are the clock-buffer (BUFG) bels, which the chipdb records in
`dev.extra_func[(row, col)]['buf']`. This tool enumerates them and, for each,
computes the set of tiles its wire can actually reach, using the database's own
two connectivity mechanisms:

  * pips, `rc.clock_pips[dest] = {srcs}`, which connect wires **inside** one tile;
  * nodes, `dev.nodes[name] = (type, {(row, col, wire), ...})`, which group the
    same wire across tiles -- a node with members in many tiles is exactly the
    cross-tile link a clock needs.

Reachability is a BFS over (row, col, wire) states that may follow a pip within
a tile or step to any other member of the same node. Bounding boxes make the
answer readable: a gate that only covers its own edge cannot carry a clock whose
source and loads are somewhere else.

This is a model of the model, not of the silicon: it says what nextpnr could
route, and its edges come from the chipdb alone.

**Its reach numbers are known to be wrong and must not be used as they stand.**
It treats a wire *name* as one net and lets the BFS step between every tile that
mentions it, but the routed design shows `CLK1`/`CLK2` are **per-tile wires with
a shared name** -- `clk` alone holds 432 of them at 432 different tiles. That
made 16 gate sites appear to reach the whole die, which contradicts the router.
`evidence/clock-wire-dump.txt` records the refutation; the tool is kept for the
record and for rework, not for its numbers.

SPDX-License-Identifier: MIT
"""

import argparse
import sys
from collections import deque, defaultdict

sys.path.insert(0, "/run/media/vash/GIT/apicula-mathieufro")
from apycula import chipdb  # noqa: E402

DEFAULT = "/run/media/vash/GIT/apicula-mathieufro/apycula/GW5AST-138C.msgpack.xz"


def load(path):
    db = chipdb.load_chipdb(path)
    # (row, col, wire) -> node name, and node name -> members
    where = {}
    members = {}
    for name, (kind, wires) in db.nodes.items():
        members[name] = list(wires)
        for (r, c, w) in wires:
            where[(r, c, str(w))] = name
    # pips per tile: dest -> set(src)
    pips = defaultdict(lambda: defaultdict(set))
    for r in range(db.rows):
        for c in range(db.cols):
            for dest, srcs in (getattr(db[r, c], 'clock_pips', {}) or {}).items():
                for s in srcs:
                    pips[(r, c)][str(dest)].add(str(s))
    return db, where, members, pips


def reach(start, where, members, pips, limit=400000):
    seen = {start}
    q = deque([start])
    tiles = set()
    while q:
        state = q.popleft()
        if len(seen) > limit:
            break
        r, c, w = state
        tiles.add((r, c))
        for dest, srcs in pips.get((r, c), {}).items():
            nxt = None
            if dest == w:                      # we drive this destination
                nxt = (r, c, dest)
            elif w in srcs:                     # this pip is driven by our wire
                nxt = (r, c, dest)
            if nxt and nxt not in seen:
                seen.add(nxt); q.append(nxt)
        # the same wire at other tiles (a node is one net)
        node = where.get((r, c, w))
        if node:
            for (rr, cc, ww) in members.get(node, ()):
                s2 = (rr, cc, str(ww))
                if s2 not in seen:
                    seen.add(s2); q.append(s2)
    return tiles, len(seen)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("chipdb", nargs="?", default=DEFAULT)
    ap.add_argument("--load-tile", action="append", default=[],
                    metavar="R,C", help="a tile the clock must reach, repeatable")
    ap.add_argument("--source-tile", metavar="R,C",
                    help="the tile the clock comes from, e.g. the PLL site")
    args = ap.parse_args(argv[1:])

    db, where, members, pips = load(args.chipdb)
    gates = []
    for (r, c), ef in (db.extra_func or {}).items():
        for btype, wires in (ef.get('buf') or {}).items():
            for w in wires:
                gates.append((r, c, btype, str(w)))
    gates.sort()

    src = tuple(int(x) for x in args.source_tile.split(",")) if args.source_tile else None
    loads = [tuple(int(x) for x in t.split(",")) for t in args.load_tile]

    print("chipdb %s" % args.chipdb)
    print("clock-gate (BUFG) sites: %d" % len(gates))
    print("source tile: %s   load tiles: %s" % (src, loads or "none given"))
    print()

    covering = []
    for (r, c, btype, w) in gates:
        tiles, states = reach((r, c, w), where, members, pips)
        xs = [x for _, x in tiles]; ys = [y for y, _ in tiles]
        covers_src = src in tiles if src else None
        covers_loads = all(t in tiles for t in loads) if loads else None
        print("  gate (row=%3d col=%3d) %-5s wire=%-6s reach: %6d tiles  X %3d..%3d  Y %3d..%3d"
              % (r, c, btype, w, len(tiles), min(xs), max(xs), min(ys), max(ys)))
        if covers_src is not None or covers_loads is not None:
            tag = []
            if covers_src is not None:
                tag.append("source=%s" % ("YES" if covers_src else "no"))
            if covers_loads is not None:
                tag.append("loads=%s" % ("YES" if covers_loads else "no"))
            print("        %s" % "  ".join(tag))
            if covers_src and covers_loads:
                covering.append((r, c, w))
    print()
    if src or loads:
        print("gates reaching BOTH source and loads: %d %s"
              % (len(covering), covering[:6]))
        if not covering:
            print("  -> matches nextpnr's own report: no clock gate reaches both")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
