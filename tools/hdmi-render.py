#!/usr/bin/env python3
"""Render one frame from a raw YUYV capture as text.

    tools/hdmi-render.py <raw.yuv> <frame> [W] [H] [ramp cols rows | zoom x0 y0 x1 y1 [step]]

Why this exists: the agent working on this project cannot view images on its
model route, and a capture card hands back pictures.  Rendering a frame as
characters turns it into something readable, and it was this that found the
card's logo sitting in a stream everyone had assumed was empty video.

    ramp (default)   the whole frame as a COLS x ROWS brightness map, each cell
                     showing its peak luma so thin bright strokes survive
                     downsampling -- this is for FINDING content
    zoom             a region at STEP pixels per character, '#' bright, '.'
                     above black, ' ' black -- this is for READING it

SPDX-License-Identifier: MIT
"""
import sys

path = sys.argv[1]
idx = int(sys.argv[2])
W = int(sys.argv[3]) if len(sys.argv) > 3 else 1280
H = int(sys.argv[4]) if len(sys.argv) > 4 else 720
mode = sys.argv[5] if len(sys.argv) > 5 else "ramp"

FRAME = W * H * 2
fr = open(path, 'rb').read()[idx * FRAME:(idx + 1) * FRAME]
if len(fr) < FRAME:
    sys.exit(f"no frame {idx} in {path}")
luma = fr[0::2]

RAMP = " .:-=+*#%@"


def peak(x0, y0, x1, y1):
    p = 0
    for y in range(y0, y1):
        base = y * W
        for x in range(x0, x1):
            v = luma[base + x]
            if v > p:
                p = v
    return p


if mode == "zoom":
    x0, y0, x1, y1 = (int(v) for v in sys.argv[6:10])
    step = int(sys.argv[10]) if len(sys.argv) > 10 else 2
    print(f"frame {idx}, region x {x0}..{x1} y {y0}..{y1}, {step}px per character")
    print("+" + "-" * ((x1 - x0) // step) + "+")
    for y in range(y0, y1, step):
        row = []
        for x in range(x0, x1, step):
            p = peak(x, y, min(x + step, x1), min(y + step, y1))
            row.append("#" if p > 96 else ("." if p > 20 else " "))
        print("|" + "".join(row) + "|")
    print("+" + "-" * ((x1 - x0) // step) + "+")
else:
    cols = int(sys.argv[6]) if len(sys.argv) > 6 else 128
    rows = int(sys.argv[7]) if len(sys.argv) > 7 else 40
    cw, ch = W / cols, H / rows
    print(f"frame {idx}, {W}x{H} -> {cols}x{rows}, brightness ramp (peak luma per cell)")
    print("+" + "-" * cols + "+")
    for r in range(rows):
        line = []
        for c in range(cols):
            p = peak(int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch))
            line.append(RAMP[min(len(RAMP) - 1, p * len(RAMP) // 256)])
        print("|" + "".join(line) + "|")
    print("+" + "-" * cols + "+")
