#!/usr/bin/env python3
"""Decode a clock-smoke capture and measure the clocks it reports.

    tools/decode-clock-smoke.py CAPTURE --seconds 25.0

The design (`fpga/clock-smoke/clock_smoke.v`) sends one fixed 49-byte line:

    clock-smoke s=A lock=DE c27=XXXX hk=XXXX n=XXXX\\r\\n

once every 2^25 `sys_clk` cycles (671.08864 ms at 50 MHz).  `D`/`E` are the pll_27 and pll_hdmi LOCK
bits and `XXXX` values are hex.  `n` counts lines sent, so the design states
its own time base; `c27` and `hk` are COUNTS of bit-8 edges of `cnt_27` and
`cnt_hclk`, and that is the whole reason this version exists.

A counter bit n toggles once every 2^(n+1) cycles, so bit 12 toggles every 8192
cycles and a count of its edges is a count of 8192-cycle units.  That means the
readout yields

    f = (cycles added per line) / (line period) = (delta x 256) / line period

without the reader having to know which bit was read.  The two earlier versions
of this readout reported bits, and a bit's position cannot be recovered from a
flop count -- which is exactly how a real doubling of a PLL and a reporting
error became indistinguishable.

The line period comes from `n` and `--seconds`, and `sys_clk` is checked two
independent ways, neither of which uses the counters under test:

  * from the cadence, f_sys = 2^25 / line_period; and
  * from the UART, f_sys ~= 434 x baud, which is meaningful only while the
    stream decodes, because the design's own baud is derived from sys_clk.

If the two disagree the capture is not to be trusted about anything.

SPDX-License-Identifier: MIT
"""

import argparse
import re
import sys
from collections import Counter

CAD_BITS = 25        # the line cadence, from the RTL
BAUD_DIV = 434       # sys_clk cycles per UART bit, from the RTL
BIT = 12             # the counter bit whose edges are counted

LINE_RE = re.compile(
    rb"clock-smoke s=([01]) lock=([01])([01]) c27=([0-9a-f]{4})"
    rb" hk=([0-9a-f]{4}) n=([0-9a-f]{4})\r\n")


def unwrapped(values):
    """successive differences, with the 16-bit wraps taken out"""
    out, prev = [], values[0]
    for v in values[1:]:
        d = (v - prev) % 65536
        while d > 32768:          # a wrap forward, not a big backward step
            d -= 65536
        out.append(d)
        prev = v
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture")
    ap.add_argument("--seconds", type=float, required=True,
                    help="wall-clock duration of the capture")
    ap.add_argument("--baud", type=int, default=115200,
                    help="baud the capture was taken at (default 115200)")
    args = ap.parse_args()

    raw = open(args.capture, "rb").read()
    hits = [m.groups() for m in LINE_RE.finditer(raw)]
    print("capture : %s" % args.capture)
    print("           %d bytes, %.3f s" % (len(raw), args.seconds))
    if len(hits) < 30:
        print("\nonly %d well-formed lines -- not enough to measure" % len(hits))
        return 1

    counts = [int(h[5], 16) for h in hits]
    deltas = [(b - a) % 65536 for a, b in zip(counts, counts[1:])]
    d = Counter(deltas)
    good = d.get(1, 0)
    print("lines   : %d well-formed" % len(hits))
    print("          n= deltas: %s" % dict(sorted(d.items())[:5]))
    if good < 0.95 * len(deltas):
        print("          capture is NOT faithful (fewer than 95%% of steps are +1)")
        return 1
    if good != len(deltas):
        print("          %d step(s) not +1, excluded" % (len(deltas) - good))

    lines = good
    line_period = args.seconds / lines
    f_cadence = (1 << CAD_BITS) / line_period
    f_uart = BAUD_DIV * args.baud
    print("          line period %.6f ms  (%.2f lines/s)" % (line_period * 1e3, 1 / line_period))

    print("\nsys_clk, two independent checks:")
    print("  cadence (2^%d / line period)      %9.4f MHz" % (CAD_BITS, f_cadence / 1e6))
    print("  UART    (%d x %d baud)          %9.4f MHz" % (BAUD_DIV, args.baud, f_uart / 1e6))
    skew = abs(f_cadence - f_uart) / f_uart
    print("  agreement                         %9.3f %%" % (skew * 100))
    if skew > 0.05:
        print("  DISAGREE by more than 5%% -- one of the two references is not")
        print("  what it is assumed to be; refusing to report clock rates")
        return 1

    locks = Counter(h[1].decode() + h[2].decode() for h in hits)
    print("\nPLL lock bits (pll_27, pll_hdmi): %s"
          % ", ".join("%s x%d" % (k, v) for k, v in locks.most_common()))

    print("\nclocks, from counted bit-%d edges (8192 cycles each):" % BIT)
    for name, idx, expect in (("clk27", 3, 27.00), ("hclk (CLKDIV output)", 4, 74.25)):
        vals = [int(h[idx], 16) for h in hits]
        steps = unwrapped(vals)
        if max(abs(s) for s in steps) < 2:
            print("  %-24s no edges -- clock not running" % name)
            continue
        per_line = sum(steps) / len(steps)
        f = per_line * (1 << (BIT + 1)) / line_period
        print("  %-24s %8.4f MHz  (%.2f bit-%d edges/line, %.4f x sys_clk)"
              % (name, f / 1e6, per_line, BIT, f / f_cadence))
        print("  %-24s   designed %8.4f MHz;  doubled would be %8.4f MHz"
              % ("", expect, 2 * expect))
    print("\n  hclk5 = 5 x hclk, and carries no flop of its own (a 371.25 MHz")
    print("  fabric path fails timing here), so hclk is what establishes it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
