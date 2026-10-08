#!/usr/bin/env python3
"""Decode the demo's UART payload out of Apicula's message.hex.

    tools/decode-message.py --text
    tools/decode-message.py --hexdump 176
    tools/decode-message.py --regenerate evidence/

message.hex is `$readmemh` input for an 8-bit memory array: one hex token per
byte, and the design reads it back the way the hardware does — so a
four-digit token (the README's unicode arrow, U+21A9) is transmitted as its
low byte. This decodes accordingly, which is why the bytes here match the wire
rather than the source text.

Deterministic: the same message.hex always produces the same files, so
`--regenerate` is how the evidence/ copies are made.
SPDX-License-Identifier: MIT
"""

import argparse
import os
import sys

DEFAULT_SOURCE = os.path.expanduser("~/apicula/examples/gw5a/message.hex")


def wire_bytes(path):
    """The bytes the FPGA puts on the wire, token by token."""
    with open(path) as fh:
        return bytes(int(t, 16) & 0xFF for t in fh.read().split() if t), fh


def as_text(data):
    return data.decode("utf-8", "replace").replace("\r", "")


def hexdump(data, offset=0, length=176):
    lines = []
    for i in range(0, min(length, len(data)), 16):
        ch = data[i:i + 16]
        hexpart = " ".join(ch[j:j + 2].hex() for j in range(0, len(ch), 2))
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in ch)
        lines.append(f"{offset + i:08x}: {hexpart:<39} {asc}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SOURCE)
    ap.add_argument("--text", action="store_true", help="print the payload as text")
    ap.add_argument("--hexdump", type=int, metavar="N",
                    help="hexdump the first N bytes")
    ap.add_argument("--regenerate", metavar="DIR",
                    help="write the evidence copies (text + hexdump) into DIR")
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"no message.hex at {args.source} (pass --source)")

    data, _ = wire_bytes(args.source)
    text = as_text(data)

    if args.text or not (args.hexdump or args.regenerate):
        print(text)

    if args.hexdump:
        print(hexdump(data, 0, args.hexdump))

    if args.regenerate:
        os.makedirs(args.regenerate, exist_ok=True)
        with open(os.path.join(args.regenerate, "apicula-message.txt"), "w") as fh:
            fh.write(text)
        with open(os.path.join(args.regenerate, "hexdump-welcome.txt"), "w") as fh:
            fh.write("# first 176 bytes of the UART payload, as the FPGA sends them\n")
            fh.write(hexdump(data, 0, 176) + "\n")
        print(f"wrote {args.regenerate}/apicula-message.txt and hexdump-welcome.txt",
              file=sys.stderr)
        print(f"payload: {len(data)} bytes", file=sys.stderr)


if __name__ == "__main__":
    main()
