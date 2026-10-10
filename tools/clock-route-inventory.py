#!/usr/bin/env python3
"""How was every clock net in this nextpnr log actually routed?

    tools/clock-route-inventory.py [--json] <log> [more.log ...]

`tools/pnr-timing.py` answers "did anything violate a constraint?".  This tool
answers the other half: "did each clock reach its sinks over the dedicated
clock network, or was it quietly put somewhere else?"  On the GW5AST-138C the
second question is the one that matters, because the chipdb's HCLK interconnect
is incomplete, so nextpnr can complete a build whose clocks are on general
fabric or "global resources only" and report no violation at all.

A nextpnr log describes each clock net's routing in one of four ways, and the
distinction is everything:

    Info:     'NAME' net was routed.
        routed on the dedicated clock network -- the good case.

    Info:     'NAME' net was routed using global resources only.
        completed, but on the global-resource fabric, not the clock spine.
        There is NO warning for this.  A gate that only reads warnings misses it.

    Info:     'NAME' net was routed but not connected end to end; leaving it to
              the router.
        partially routed; a later "was routed." line may still appear, so a
        check that only looks for the good line is fooled.

    Warning: Failed to route net 'NAME' from A to B using dedicated routing.
        one line PER SINK.  The sink falls back to general fabric.  This is what
        produced the "943 missing wires" on the desktop core: 943 sinks of the
        single net `clk`, not 943 nets.

Exit code is 0 when every clock net seen in the log is fully dedicated, 1 when
any is not, and 2 when a log cannot be read or carries no clock information.
That exit code is the topology gate: there is no separate "report-only" mode,
so a caller cannot mistake "printed a table" for "passed".

SPDX-License-Identifier: MIT
"""

import argparse
import json
import re
import sys
from collections import OrderedDict

ROUTED = re.compile(r"^Info:\s+'([^']+)' net was routed\.$")
GLOBAL = re.compile(r"^Info:\s+'([^']+)' net was routed using global resources only\.$")
PARTIAL = re.compile(
    r"^Info:\s+'([^']+)' net was routed but not connected end to end; leaving it to the router\.$")
FALLBACK = re.compile(
    r"^Warning: Failed to route net '([^']+)' from .* using dedicated routing\.$")
FMAX = re.compile(
    r"^Info: Max frequency for clock\s+'([^']+)':\s+([\d.]+) MHz \((PASS|FAIL) at ([\d.]+) MHz\)$")

# The order of these lines in the log runs: final net routes, then the timing
# summary.  Both are read; neither is assumed to come first.


def inventory(path):
    """Return {net: record} for one log, plus the log's total line count."""
    nets = OrderedDict()

    def rec(name):
        return nets.setdefault(name, {
            "routed": False, "global_only": False, "partial": False,
            "fallbacks": 0, "fmax": None, "constraint": None, "verdict": None})

    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    for line in lines:
        m = FALLBACK.match(line)
        if m:
            rec(m.group(1))["fallbacks"] += 1
            continue
        m = PARTIAL.match(line)
        if m:
            rec(m.group(1))["partial"] = True
            continue
        m = GLOBAL.match(line)
        if m:
            rec(m.group(1))["global_only"] = True
            continue
        m = ROUTED.match(line)
        if m:
            rec(m.group(1))["routed"] = True
            continue
        m = FMAX.match(line)
        if m:
            # Placement prints an estimate and routing prints the final value;
            # the last one seen is the post-route number, which is what counts.
            r = rec(m.group(1))
            r["fmax"], r["constraint"] = float(m.group(2)), float(m.group(4))
            continue

    for r in nets.values():
        r["dedicated"] = r["routed"] and not r["global_only"] \
            and not r["partial"] and r["fallbacks"] == 0

    return nets, len(lines)


def verdict(record):
    if record["fallbacks"]:
        return "fabric (%d sink%s)" % (record["fallbacks"],
                                       "" if record["fallbacks"] == 1 else "s")
    if record["partial"]:
        return "partial (not connected end to end)"
    if record["global_only"]:
        return "global-resources-only"
    if record["routed"]:
        return "dedicated"
    return "not routed"


def report(path, nets, lines, as_json):
    bad = sorted(n for n, r in nets.items() if not r["dedicated"])
    if as_json:
        print(json.dumps({
            "log": path, "log_lines": lines,
            "nets": {n: {**r, "verdict": verdict(r)} for n, r in nets.items()},
            "non_dedicated": bad, "ok": not bad,
        }, indent=2))
        return
    print("=== %s ===" % path)
    if not nets:
        print("  no clock-net routing lines found -- wrong log?")
        return
    width = max(len(n) for n in nets) if nets else 4
    print("  %-*s  %-9s  %8s  %11s  %s"
          % (width, "net", "binding", "fallbacks", "final MHz", "constraint MHz"))
    for name, r in nets.items():
        fmax = "%8.2f" % r["fmax"] if r["fmax"] is not None else "%8s" % "-"
        cons = "%11.2f" % r["constraint"] if r["constraint"] is not None \
            else "%11s" % "-"
        print("  %-*s  %-9s  %8d  %s  %s"
              % (width, name, "yes" if r["dedicated"] else "NO",
                 r["fallbacks"], fmax, cons))
    print()
    for name in nets:
        print("  %-*s  %s" % (width, name, verdict(nets[name])))
    print()
    if bad:
        print("  CLOCK TOPOLOGY UNVERIFIED: %d of %d clock net(s) do not ride the"
              % (len(bad), len(nets)))
        print("  dedicated network: %s" % ", ".join(bad))
        print("  A pass here would be a pass over a partially-modelled clock")
        print("  network.  See evidence/hclk-route-gap.txt.")
    else:
        print("  all %d clock net(s) dedicated" % len(nets))


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("logs", nargs="+")
    p.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    args = p.parse_args(argv[1:])

    failed = False
    for path in args.logs:
        try:
            nets, lines = inventory(path)
        except OSError as e:
            print("%s: %s" % (path, e), file=sys.stderr)
            return 2
        if not nets:
            print("=== %s ===" % path)
            print("  no clock-net routing lines found -- wrong log?")
            return 2
        report(path, nets, lines, args.json)
        if any(not r["dedicated"] for r in nets.values()):
            failed = True

    # The exit code is the topology gate and nothing else: a non-dedicated
    # clock is never reported as a pass.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
