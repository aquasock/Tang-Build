#!/usr/bin/env python3
"""Decode a clock-smoke capture and measure the clocks it reports.

    tools/decode-clock-smoke.py CAPTURE --seconds 25.0

The design (`fpga/clock-smoke/clock_smoke.v`) sends one fixed 40-byte line:

    clock-smoke s=A c=B h=C lock=DE n=XXXX\\r\\n

once every 2^18 `sys_clk` cycles, where A/B/C are cnt_sys[24], cnt_27[23] and
cnt_hclk[24], D/E are the two PLL LOCK bits, and XXXX is a counter of lines
sent, so the design states its own time base rather than leaving it inferred.

Three things are checked here, in order, and each one licenses the next:

1. Faithfulness.  `n=` must advance by exactly one per line.  A repeat is a
   duplicated read; a jump is a dropped one.  Both are reported and the
   capture is rejected as a measurement if they are common.

2. The line period.  `--seconds` is the wall-clock duration of the capture, so
   the line period is (seconds / lines) with the line count taken from the
   design's own counter, not from how much the host managed to read.  Host
   buffering moves the endpoints by at most a line, not the rate.

3. The cadence, which is the check that makes the rest absolute.  The line is
   sent every 2^18 sys_clk cycles, so `s` -- cnt_sys[24], which toggles every
   2^25 cycles -- must toggle every 2^25 / 2^18 = exactly 128 lines.  If it
   measures 128 the cadence is confirmed, and then

       f_sys = 2^18 / line_period

   with no assumption about the crystal at all.  clk27 and hclk follow from
   their own bit periods: c is bit 23 of a 24-bit counter, so it toggles every
   2^24 cycles, and h is bit 24 of a 25-bit counter, every 2^25.

If `s` does *not* measure 128 lines the cadence is not what the RTL says and
this tool refuses to print absolute frequencies, because at that point the
design and its own description disagree and neither can be trusted.

SPDX-License-Identifier: MIT
"""

import argparse
import re
import sys
from collections import Counter

CAD_BITS = 18            # the line cadence, from the RTL
TARGET_S_PERIOD = (1 << 7)   # 2^25 / 2^18 = 128 lines, the cadence check

#: field -> (label, counter bit index; its toggle period is 2^(n+1) cycles)
FIELDS = (("s", "sys_clk", 24), ("c", "clk27", 23), ("h", "hclk (CLKDIV output)", 24))

LINE_RE = re.compile(
    rb"clock-smoke s=([01]) c=([01]) h=([01]) lock=([01])([01]) n=([0-9a-f]{4})\r\n")


def periods(vals):
    """interval in lines between successive transitions of a bit"""
    edges = [i for i in range(1, len(vals)) if vals[i] != vals[i - 1]]
    return [b - a for a, b in zip(edges, edges[1:])], len(edges)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture")
    ap.add_argument("--seconds", type=float, required=True,
                    help="wall-clock duration of the capture")
    args = ap.parse_args()

    raw = open(args.capture, "rb").read()
    hits = [(m.start(), m.groups()) for m in LINE_RE.finditer(raw)]
    print("capture : %s" % args.capture)
    print("           %d bytes, %.3f s" % (len(raw), args.seconds))
    if len(hits) < 20:
        print("\nonly %d well-formed lines -- not enough to measure" % len(hits))
        return 1

    counts = [int(h[5], 16) for _, h in hits]
    deltas = [(b - a) % 65536 for a, b in zip(counts, counts[1:])]
    d = Counter(deltas)
    print("lines   : %d well-formed; bytes accounted for %d/%d"
          % (len(hits), len(hits) * 40, len(raw)))
    print("          n= deltas: %s" % dict(sorted(d.items())[:6]))
    good = d.get(1, 0)
    if good < 0.95 * len(deltas):
        print("          capture is NOT faithful (not 95%% of steps are +1);"
              " refusing to measure")
        return 1
    # The span comes from the steps that are exactly +1.  Summing the raw
    # deltas would fold in any single corrupt step as a five-thousand-line
    # jump, which is silent nonsense; counting the good steps is not.
    lines_span = good
    if good != len(deltas):
        odd = {k: v for k, v in d.items() if k != 1}
        print("          %d step(s) are not +1 and are excluded: %s"
              % (len(deltas) - good, odd))
    line_period = args.seconds / lines_span
    print("          %d lines between the first and last counter reading" % lines_span)
    print("          line period  %.6f ms  (%.2f lines/s)"
          % (line_period * 1e3, 1.0 / line_period))

    locks = Counter((h[3].decode() + h[4].decode()) for _, h in hits)
    print("\nPLL lock bits (pll_27, pll_hdmi): %s"
          % ", ".join("%s x%d" % (k, v) for k, v in locks.most_common()))

    print("\nbit periods, in lines:")
    measured = {}
    for key, label, n in FIELDS:
        vals = [int(h[{"s": 0, "c": 1, "h": 2}[key]]) for _, h in hits]
        runs, edges = periods(vals)
        if not runs:
            print("  %-24s no transitions -- bit constant at %s all capture"
                  % (label, vals[0]))
            measured[key] = None
            continue
        runs.sort()
        med = runs[len(runs) // 2]
        mean = sum(runs) / len(runs)
        measured[key] = mean
        print("  %-24s %d transitions, median %d, mean %.3f lines"
              % (label, edges, med, mean))

    s_period = measured.get("s")
    print("\ncadence check: `s` should toggle every %d lines" % TARGET_S_PERIOD)
    if s_period is None:
        print("  `s` never toggled -- the 50 MHz input is not running")
        return 1
    err = 100.0 * (s_period - TARGET_S_PERIOD) / TARGET_S_PERIOD
    print("  measured %.3f lines, error %+.3f%%" % (s_period, err))
    if abs(err) > 2.0:
        print("  cadence does NOT match the RTL -- absolute frequencies withheld")
        return 1
    print("  confirmed; the design's own cadence is 2^%d sys_clk cycles" % CAD_BITS)

    print("\nmeasured frequencies (absolute, from the line period alone):")
    f_sys = (1 << CAD_BITS) / line_period
    print("  %-24s %9.4f MHz" % ("sys_clk", f_sys / 1e6))
    for key, label, n in FIELDS:
        if key == "s" or measured[key] is None:
            continue
        f = (1 << (n + 1)) / (measured[key] * line_period)
        print("  %-24s %9.4f MHz   (= %d x sys_clk, %.6f)"
              % (label, f / 1e6, 0, f / f_sys))
    if measured.get("h"):
        f_h = (1 << 25) / (measured["h"] * line_period)
        print("\n  hclk5 = 5 x hclk = %.4f MHz" % (5 * f_h / 1e6))
        print("  (hclk5 carries no flop -- a 371.25 MHz fabric path fails timing"
              "\n   on this design -- so it is established through the CLKDIV.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
