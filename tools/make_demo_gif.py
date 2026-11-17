#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
"""Builds docs/taphand-demo.gif: every built-in theme clicking in turn, laid out as a justified mosaic.

Each theme is cropped to its footprint (pointer + everything its click effect touches, over all frames) and padded
to a common height; the cards are then packed, in menu order, into rows that span the full width with one constant
gap between cards and around the edge. Each row is scaled to fit exactly, so the canvas is used edge to edge.

Usage: python3 tools/make_demo_gif.py
"""
import json
import subprocess
import tempfile
from itertools import combinations
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/taphand-demo.gif"
W = 960                          # GIF width (px)
GAP = 10                         # the one constant gutter and border (px)
PAD = 16                         # breathing room around each footprint (source px, 2x renders)
LABEL = 20                       # label strip inside the bottom of each card (px)
RADIUS = 10
CARD, PAGE, INK = (0xFB, 0xF8, 0xF2), (0xE4, 0xDC, 0xCC), (92, 80, 64)
TARGET_H = 540                   # preferred GIF height (px)


def footprint(frames):
    """Union bbox of everything that ever differs from the empty card, over all frames."""
    blank = Image.new("RGB", frames[0].size, CARD)
    box = None
    for f in frames[::2]:
        b = ImageChops.difference(f, blank).convert("L").point(lambda v: 255 if v > 12 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def layout(aspects):
    """Rows (contiguous, menu order) whose total height is near TARGET_H with similar per-row scale."""
    n, inner = len(aspects), W - 2 * GAP
    best = None
    for k in range(1, 5):                                   # 2..5 rows
        for cut in combinations(range(1, n), k):
            bounds = [0, *cut, n]
            rows = [list(range(bounds[i], bounds[i + 1])) for i in range(len(bounds) - 1)]
            hs = [(inner - GAP * (len(r) - 1)) / sum(aspects[j] for j in r) for r in rows]
            total = sum(h + LABEL for h in hs) + GAP * (len(rows) + 1)
            score = abs(total - TARGET_H) + 3 * (max(hs) - min(hs))
            if best is None or score < best[0]:
                best = (score, rows, hs, round(total))
    return best[1], best[2], best[3]


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=r, fill=255)
    return m


subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT, check=True, capture_output=True)
with tempfile.TemporaryDirectory() as d:
    subprocess.run([str(ROOT / ".build/release/TapHand"), "--render-demo", d], check=True)
    meta = json.loads((Path(d) / "manifest.json").read_text())
    labels, n_frames = meta["labels"], meta["frames"]
    tiles = [[Image.open(Path(d) / f"p{i:02d}_{k:03d}.png").convert("RGB") for k in range(n_frames)]
             for i in range(len(labels))]

# 1. Crop each theme to its footprint; 2. pad all to a common height so pointer scale stays consistent.
crops = []
for frames in tiles:
    x0, y0, x1, y1 = footprint(frames)
    box = (max(0, x0 - PAD), max(0, y0 - PAD), min(frames[0].width, x1 + PAD), min(frames[0].height, y1 + PAD))
    crops.append([f.crop(box) for f in frames])
common_h = max(c[0].height for c in crops)
for i, c in enumerate(crops):
    if c[0].height < common_h:
        top = (common_h - c[0].height) // 2
        out = []
        for f in c:
            g = Image.new("RGB", (f.width, common_h), CARD)
            g.paste(f, (0, top))
            out.append(g)
        crops[i] = out

rows, heights, H = layout([c[0].width / c[0].height for c in crops])
_fonts = {}


def fit_font(text, max_w):
    """Largest size <= 14 pt that fits the card width."""
    for size in range(14, 8, -1):
        f = _fonts.setdefault(size, ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size))
        if f.getlength(text) <= max_w:
            return f
    return _fonts[9]

# Card positions (fixed for every frame).
places = []                       # (theme index, x, y, w, h)
y = GAP
for r, h in zip(rows, heights):
    x = GAP
    widths = [crops[j][0].width / crops[j][0].height * h for j in r]
    # absorb rounding so every row ends exactly at W - GAP
    ws = [round(w) for w in widths]
    ws[-1] += (W - 2 * GAP - GAP * (len(r) - 1)) - sum(ws)
    for j, w in zip(r, ws):
        places.append((j, x, round(y), w, round(h)))
        x += w + GAP
    y += h + LABEL + GAP
H = round(y)

frames_out = []
for k in range(n_frames):
    page = Image.new("RGB", (W, H), PAGE)
    draw = ImageDraw.Draw(page)
    for j, x, yy, w, h in places:
        card = Image.new("RGB", (w, h + LABEL), CARD)
        card.paste(crops[j][k].resize((w, h), Image.LANCZOS), (0, 0))
        cd = ImageDraw.Draw(card)
        f = fit_font(labels[j], w - 10)
        lw = cd.textlength(labels[j], font=f)
        cd.text(((w - lw) / 2, h + 2 + (14 - f.size) / 2), labels[j], fill=INK, font=f)
        page.paste(card, (x, yy), rounded_mask(card.size, RADIUS))
    frames_out.append(page)

picks = [round(i * (len(frames_out) - 1) / 9) for i in range(10)]
sample = Image.new("RGB", (W, H * len(picks)))
for s, k in enumerate(picks):
    sample.paste(frames_out[k], (0, H * s))
pal = sample.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
# No dithering: static cards then stay pixel-identical between frames, which keeps the GIF small.
frames_out = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames_out]
frames_out[0].save(OUT, save_all=True, append_images=frames_out[1:], duration=50, loop=0, optimize=True, disposal=1)
print(f"wrote {OUT.relative_to(ROOT)}: {len(frames_out)} frames ({len(frames_out) / 20:.1f}s), {W}x{H}, "
      f"{OUT.stat().st_size // 1024} KB; rows: {[[labels[j] for j in r] for r in rows]}")
