#!/usr/bin/env python3
"""Capture the FPGA's UART off the board and look at what came back.

    tools/capture-uart.py --seconds 100 --out evidence/uart-live-capture.bin

The demo design transmits the Apicula README continuously at 115200 on the
FPGA's UART_TX (ball U15), which the board's MCU-port bridge presents as a
USB-serial port. This reads it, then answers the two questions worth asking of
a capture: is the payload in there, and is the capture faithful?

Caveat it reports honestly: a USB-serial read can drop bytes, and a dropped
chunk is indistinguishable from a wrong payload unless you check. The check
here is the constant-offset test — if the source appears at a *constant* offset
over a long run, the payload is faithful and the capture merely skipped ahead.

Needs pyserial. SPDX-License-Identifier: MIT
"""

import argparse
import os
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is required: pip install pyserial")

MARKER = b"Project Apicula\r\n\r\nOpen"


def capture(port, baud, seconds):
    """Read for a fixed wall-clock window.

    A hard deadline, deliberately: the demo transmits continuously, so an
    "extend while data keeps arriving" rule would never end."""
    with serial.Serial(port, baud, timeout=0.5) as p:
        data, end = b"", time.time() + seconds
        while time.time() < end:
            data += p.read(4096)
        return data


def find_all(haystack, needle):
    at, out = haystack.find(needle), []
    while at >= 0:
        out.append(at)
        at = haystack.find(needle, at + 1)
    return out


def load_source(path):
    """The payload as the hardware sends it: the design's array is 8-bit, so a
    4-digit token (the README's unicode arrow, 21a9) goes out as its low byte."""
    with open(path) as fh:
        return bytes(int(t, 16) & 0xFF for t in fh.read().split() if t)


def hexdump(data, offset=0):
    for i in range(0, len(data), 16):
        ch = data[i:i + 16]
        hexpart = " ".join(ch[j:j + 2].hex() for j in range(0, len(ch), 2))
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in ch)
        print(f"{offset + i:08x}: {hexpart:<39} {asc}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--seconds", type=float, default=100.0)
    ap.add_argument("--out", default="evidence/uart-live-capture.bin")
    ap.add_argument("--source", default=os.path.expanduser(
        "~/apicula/examples/gw5a/message.hex"),
        help="apicula's message.hex, for the fidelity check")
    ap.add_argument("--hexdump", type=int, default=176,
                    help="bytes to dump from the first marker (0 = none)")
    args = ap.parse_args()

    print(f"reading {args.port} at {args.baud} for {args.seconds:.0f}s")
    data = capture(args.port, args.baud, args.seconds)
    print(f"captured {len(data)} bytes")

    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "wb") as fh:
            fh.write(data)
        print(f"wrote {args.out}")

    starts = find_all(data, MARKER)
    print(f"loop-start marker found {len(starts)} time(s) at {starts}")
    if len(starts) > 1:
        gaps = [b - a for a, b in zip(starts, starts[1:])]
        print(f"gaps between them: {gaps}")
        print("  (a fixed 8,192-byte loop would show equal gaps; unequal gaps mean"
              " the capture dropped bytes)")

    if os.path.exists(args.source):
        src = load_source(args.source)
        print(f"\nfidelity check against {args.source} ({len(src)} bytes):")
        for probe in (0x100, 0x800, 0x1000, 0x1a00):
            if probe + 64 > len(src):
                continue
            at = data.find(src[probe:probe + 64])
            print(f"  src[0x{probe:04x}..+64] in capture at "
                  f"{hex(at) if at >= 0 else 'NOT FOUND'}"
                  f"{'  (delta ' + hex(at - probe) + ')' if at >= 0 else ''}")
        print("  equal deltas over a long run = faithful payload, lossy capture")

    if args.hexdump and starts:
        s = starts[0]
        print(f"\n(first {args.hexdump} bytes from the marker at {s})")
        hexdump(data[s:s + args.hexdump])


if __name__ == "__main__":
    main()
