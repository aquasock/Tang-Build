#!/usr/bin/env bash
#
# Capture raw frames from the HDMI capture card watching the Tang's output.
#
#   tools/capture-hdmi.sh <out.yuv> [frames] [device] [WxH]
#
# A capture card is a TMDS RECEIVER.  It reports what it can lock to and, unlike
# a monitor, it will happily hand over the pixels, which makes it the only
# instrument this project has that can say what the HDMI output actually is
# rather than whether a screen lit up.
#
# Raw YUYV, not MJPEG: the point is to read the levels, and a compressed frame
# would not have them.  The card exposes YUYV, MJPEG, BGR24 and NV12; YUYV is
# the one this uses.  `/dev/video0` is the capture node and `/dev/video1` is its
# metadata node, which answers nothing but ioctls of its own.
#
# Note the two meanings a frame can have, which cost this project a wrong
# conclusion once: a frame at luma 16 throughout is the Tang sending legal
# digital black, while a frame with a background of luma 0 and bright text on it
# is the CARD's own logo, drawn when its link is buggy or not synced.  Legal
# video never has 0 in the active pixels.  Check which one you have before
# concluding anything: tools/hdmi-frames.py does that check.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

out=${1:-}
frames=${2:-60}
dev=${3:-/dev/video0}
size=${4:-1280x720}

if [[ -z $out ]]; then
    echo "usage: $0 <out.yuv> [frames] [device] [WxH]" >&2
    exit 2
fi
command -v ffmpeg >/dev/null || { echo "ffmpeg not on PATH" >&2; exit 2; }
[[ -c $dev ]] || { echo "no video device at $dev" >&2; exit 2; }

echo "capturing $frames frames of $size YUYV from $dev into $out" >&2
ffmpeg -y -hide_banner -loglevel error \
    -f v4l2 -input_format yuyv422 -video_size "$size" -i "$dev" \
    -frames:v "$frames" -pix_fmt yuyv422 -f rawvideo "$out"

w=$(cut -dx -f1 <<<"$size"); h=$(cut -dx -f2 <<<"$size")
echo "$(stat -c%s "$out") bytes" >&2
echo "now:  python3 tools/hdmi-frames.py $out $w $h" >&2
