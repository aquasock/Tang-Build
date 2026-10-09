#!/usr/bin/env python3
"""Decode a clock-smoke capture and measure the clocks it reports.

    tools/decode-clock-smoke.py CAPTURE --seconds 30.0 [--baud 115200]

The design (`fpga/clock-smoke/clock_smoke.v`) sends one fixed 49-byte line:

    clock-smoke s=A lock=DEF c27=XXXX hk=XXXX ns=XXXX n=XXXX\\r\\n

once every 2^25 `sys_clk` cycles.  `D`/`E` are the pll_27 and pll_hdmi LOCK
bits; `XXXX` values are hex.  `c27` and `hk` are COUNTS of bit-12 edges of
`cnt_27` and `cnt_hclk`, which is what makes this measurable at all: bit n has a
PERIOD of 2^(n+1) cycles, so bit 12 has a period of 8192 cycles and yields TWO
edges per period -- 4096 cycles of its clock per edge.  A count of its edges is
therefore a count of HALF-cycles, and the reader never has to know which bit
was read.  Two earlier versions of this readout reported bits, and a bit's
position cannot be recovered from a flop count.

An earlier version of this script multiplied by 8192, on the reading that an
edge count is a cycle count.  It is not: that factor reported every clock at
exactly twice its frequency, and it is why the committed design's `clk27` was
recorded as doubled for several cycles.  The hardware was right; this script was
not.  See `evidence/clock-smoke-panel.txt` and the `hclk` heartbeat that caught
it -- a decoder-free instrument that blinks at 1 Hz, which is impossible if the
clocks were doubled.

THE RATIO IS THE MEASUREMENT.  For consecutive lines separated by exactly one
`n`, the ratio

    f / f_sys  =  d(edges) x 4096 / 2^25

needs no timing at all: the design's own line counter says how many line
periods elapsed, and the line period is 2^25 sys_clk cycles by construction.
`--seconds` is still required and the ratio is cross-checked against the
cadence, because a capture whose line rate does not match 2^25 cycles per
period is telling us the design is not doing what its RTL says -- which has
happened, so it is checked rather than assumed.

Samples with d(n) other than 1 are excluded: there, d(edges) spans more than one
line period and the division is an assumption rather than a measurement.  The
control run that produced "min 2211, max 4440" was exactly this artefact -- the
4440 samples were two-line gaps, not a doubled clock.

SPDX-License-Identifier: MIT
"""

import argparse
import re
import statistics
import sys
from collections import Counter

CAD_BITS = 25        # the line cadence, from the RTL
BAUD_DIV = 434       # sys_clk cycles per UART bit, from the RTL
BIT = 12             # the counter bit whose edges are counted

LINE_RE = re.compile(
    rb"clock-smoke s=([01]) lock=([01])([01])([01]) c27=([0-9a-f]{4})"
    rb" hk=([0-9a-f]{4}) ns=([0-9a-f]{4}) n=([0-9a-f]{4})\r\n")


def per_line_edges(vals, ns):
    """edges per line, from the d(n)=1 samples only

    Returns (edges_per_line, used, skipped).  A d(n) of 2 would double the
    edge delta without the clock changing at all, so those are counted and
    dropped rather than averaged in."""
    num = den = used = skipped = 0
    for i in range(1, len(vals)):
        dn = (ns[i] - ns[i - 1]) % 65536
        dv = (vals[i] - vals[i - 1]) % 65536
        if dv > 32768:
            dv -= 65536
        if dn == 1 and 0 <= dv:
            num += dv
            den += 1
            used += 1
        else:
            skipped += 1
    return (num / den if den else None), used, skipped


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture")
    ap.add_argument("--seconds", type=float, required=True,
                    help="wall-clock duration of the capture")
    ap.add_argument("--baud", type=int, default=115200)
    args = ap.parse_args()

    raw = open(args.capture, "rb").read()
    hits = [m.groups() for m in LINE_RE.finditer(raw)]
    print("capture : %s" % args.capture)
    print("           %d bytes, %.3f s" % (len(raw), args.seconds))
    if len(hits) < 8:
        print("\nonly %d well-formed lines -- not enough to measure" % len(hits))
        return 1

    ns = [int(h[7], 16) for h in hits]
    deltas = Counter((b - a) % 65536 for a, b in zip(ns, ns[1:]))
    print("lines   : %d;  d(n) values %s" % (len(hits), dict(sorted(deltas.items())[:5])))
    good = deltas.get(1, 0)
    if good < 0.5 * (len(ns) - 1):
        print("          fewer than half the steps are d(n)=1; capture is not")
        print("          usable for a ratio measurement")
        return 1

    line_period = args.seconds / good
    f_cadence = (1 << CAD_BITS) / line_period
    f_uart = BAUD_DIV * args.baud

    print("\nsys_clk reference:")
    print("  UART anchor (%d x %d baud)        %9.4f MHz" % (BAUD_DIV, args.baud, f_uart / 1e6))
    print("  cadence     (2^%d / line period)   %9.4f MHz" % (CAD_BITS, f_cadence / 1e6))
    agree = abs(f_cadence - f_uart) / f_uart
    print("  agreement                          %9.3f %%" % (agree * 100))
    if agree > 0.05:
        print("  NOTE: the line rate and the UART disagree by more than 5%%.")
        print("  That is a real discrepancy in the design, not in this script -- it")
        print("  has been seen before.  The clock RATIOS below are unaffected.")

    locks = Counter(h[1].decode() + h[2].decode() + h[3].decode() for h in hits)
    print("\nPLL lock bits (pll_27, pll_hdmi, pll_nes): %s"
          % ", ".join("%s x%d" % (k, v) for k, v in locks.most_common()))

    print("\nclocks, from counted bit-%d edges (4096 cycles each):" % BIT)
    for name, idx, expect in (("clk27", 4, 27.00), ("hclk (CLKDIV output)", 5, 74.25),
                              ("clk_nes", 6, 21.50)):
        vals = [int(h[idx], 16) for h in hits]
        epl, used, skipped = per_line_edges(vals, ns)
        if epl is None:
            print("  %-24s no usabled samples -- clock not running?" % name)
            continue
        ratio = epl * (1 << BIT) / (1 << CAD_BITS)
        print("  %-24s %8.4f x sys_clk   (= %8.4f MHz at the anchor)"
              % (name, ratio, ratio * f_uart / 1e6))
        print("  %-24s %8.1f bit-%d edges per line, %d samples used, %d skipped"
              % ("", epl, BIT, used, skipped))
        print("  %-24s designed %.4f x sys_clk;  doubled would be %.4f"
              % ("", expect * 1e6 / f_uart, 2 * expect * 1e6 / f_uart))
    print("\n  hclk5 = 5 x hclk and carries no flop of its own (a 371.25 MHz fabric")
    print("  path fails timing here), so hclk is what establishes it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
