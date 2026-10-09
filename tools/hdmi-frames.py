#!/usr/bin/env python3
"""Characterise a raw YUYV capture from the HDMI capture card.

    tools/hdmi-frames.py <raw.yuv> [width] [height]

Answers the questions a picture cannot:

  * how many DISTINCT frames there are, and in what pattern over time -- which
    is how a link that comes up and then dies looks from the receiving end;
  * whether a frame is the Tang's video or the CARD's own logo.  Legal video
    black is luma 16 and the active pixels are never 0; the card's logo is
    bright text on a background of luma 0.  This tool is what says which;
  * where the differing frames differ, and by how much.

Written after a 15-second capture came back as 863 frames of the card's logo and
36 of the Tang's legal black, reproducibly, which is what turned "the HDMI
produces no signal" into "it produces a signal for about 0.6 s and then the link
drops".

SPDX-License-Identifier: MIT
"""
import sys
import hashlib
import collections

path = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
H = int(sys.argv[3]) if len(sys.argv) > 3 else 720
FRAME = W * H * 2

data = open(path, 'rb').read()
n = len(data) // FRAME
print(f"{path}: {n} frames of {W}x{H} YUYV, {FRAME} bytes each")
if n == 0:
    sys.exit("no whole frames in that file")
print()

frames = [data[i * FRAME:(i + 1) * FRAME] for i in range(n)]
digests = [hashlib.md5(f).hexdigest()[:12] for f in frames]

groups = collections.OrderedDict()
for i, d in enumerate(digests):
    groups.setdefault(d, []).append(i)

print(f"{len(groups)} distinct frame(s) over {n}:")
for d, idx in groups.items():
    print(f"  {d}: {len(idx):5d} frames, first at {idx[0]:5d} "
          f"({100.0*len(idx)/n:5.1f} per cent)")
print()

runs = []
for d in digests:
    if runs and runs[-1][0] == d:
        runs[-1][1] += 1
    else:
        runs.append([d, 1])
print("pattern over time (digest x repeat, first 40 runs):")
print("  " + " ".join(f"{d}x{c}" for d, c in runs[:40]))
print()

for d, idx in groups.items():
    fr = frames[idx[0]]
    ys = fr[0::2]
    cs = fr[1::2]
    cy = collections.Counter(ys)
    kind = "?"
    if max(ys) <= 16 and min(ys) >= 16:
        kind = "LEGAL BLACK (the source's own video black, luma 16 throughout)"
    elif min(ys) == 0 and max(ys) > 96:
        kind = "CARD LOGO (bright text on background 0 -- not legal video)"
    print(f"{d}: luma distinct={len(cy)} min={min(ys)} max={max(ys)} "
          f"mean={sum(ys)/len(ys):.1f} | chroma distinct={len(set(cs))} "
          f"min={min(cs)} max={max(cs)}")
    print(f"    -> {kind}")
    if len(cy) > 6:
        print(f"    luma top: {cy.most_common(8)}")
print()

common = sorted(groups.items(), key=lambda kv: -len(kv[1]))
if len(common) >= 2:
    a = frames[common[0][1][0]]
    b = frames[common[1][1][0]]
    diff = [i for i in range(FRAME) if a[i] != b[i]]
    print(f"between {common[0][0]} and {common[1][0]}: {len(diff)} of {FRAME} "
          f"bytes differ ({100.0*len(diff)/FRAME:.3f} per cent)")
    if diff:
        px = sorted({i // 2 for i in diff})
        print(f"  affected pixels x {px[0]%W}..{px[-1]%W}, "
              f"y {px[0]//W}..{px[-1]//W} (of {W}x{H})")
        vals = collections.Counter((a[i], b[i]) for i in diff)
        print(f"  most common (a,b) byte pairs: {vals.most_common(6)}")
