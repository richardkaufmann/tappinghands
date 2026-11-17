#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
"""Cleans the giraffe photo cut-out (Assets/source/giraffe-cutout.png) into Assets/giraffe.png.

The source has hard on/off alpha with stair-stepped edges, a ragged tongue and a flat cut where the neck
leaves the frame. Steps:
  1. Tongue: close notches/holes, drop slivers, round it off (mask morphology + blur), refill colours.
  2. Flip horizontally so the tongue tip points up-left like a cursor and the neck trails down-right.
  3. Scale to a working size, smooth every edge (blur + threshold), trim 1 px of photo fringe, anti-alias.
  4. Re-colour the edge band from the interior (removes the photo background's colour fringe).
  5. Fade the neck to transparent toward its cut end.

Usage: python3 tools/make_giraffe.py [preview_dir]
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets/source/giraffe-cutout.png"
OUT = ROOT / "Assets/giraffe.png"
TONGUE = (1815, 325, 1965, 485)      # source coords (before flip): tongue + lips
WIDTH = 1000                          # working/output width (px)


def threshold(m, t):
    return m.point(lambda v: 255 if v >= t else 0)


def refill_colors(rgba, keep_mask, radius):
    """Colours of pixels outside `keep_mask` = normalized blur of the colours inside it."""
    r, g, b, _ = rgba.split()
    k = keep_mask
    kb = k.filter(ImageFilter.GaussianBlur(radius))
    chans = [ImageChops.multiply(c, k).filter(ImageFilter.GaussianBlur(radius)) for c in (r, g, b)]
    out = rgba.copy()
    op, kp, cp = out.load(), kb.load(), [c.load() for c in chans]
    kin = k.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            if kin[x, y] == 0 and kp[x, y] > 2:
                s = kp[x, y]
                op[x, y] = (min(255, cp[0][x, y] * 255 // s), min(255, cp[1][x, y] * 255 // s),
                            min(255, cp[2][x, y] * 255 // s), op[x, y][3])
    return out


def clean_tongue(im):
    box = im.crop(TONGUE)
    a = box.split()[3]
    m = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))      # close notches + the gap
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))      # drop slivers
    m = threshold(m.filter(ImageFilter.GaussianBlur(4)), 120)                    # round the outline
    box = refill_colors(box, threshold(a, 128), 4)                               # colour new pixels
    box.putalpha(m)
    im.paste(box, TONGUE[:2])
    return im


def main(preview=None):
    im = Image.open(SRC).convert("RGBA")
    im = clean_tongue(im)
    im = im.crop(im.getbbox()).transpose(Image.FLIP_LEFT_RIGHT)
    pad = 12
    canvas = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad))
    canvas.paste(im, (pad, pad))
    s = WIDTH / canvas.width
    im = canvas.resize((WIDTH, round(canvas.height * s)), Image.LANCZOS)

    # Smooth edges: blur the mask, threshold slightly high (trims ~1 px of fringe), then anti-alias.
    a = im.split()[3]
    hard = threshold(a.filter(ImageFilter.GaussianBlur(1.6)), 150)
    inner = hard.filter(ImageFilter.MinFilter(5))
    im = refill_colors(im, inner, 3)
    alpha = hard.filter(ImageFilter.GaussianBlur(0.7))

    # Neck fade: along the line from the tongue tip to the neck's cut end.
    w, h = im.size
    ap = alpha.load()
    pts = [(x, y) for y in range(h) for x in range(w) if ap[x, y] > 128]
    tip = min(pts, key=lambda p: p[0] + p[1])
    far = max(pts, key=lambda p: p[0] + p[1])
    dx, dy = far[0] - tip[0], far[1] - tip[1]
    L2 = dx * dx + dy * dy
    for y in range(h):
        for x in range(w):
            if ap[x, y]:
                t = ((x - tip[0]) * dx + (y - tip[1]) * dy) / L2
                u = min(1.0, max(0.0, (t - 0.45) / (0.9 - 0.45)))
                f = 1 - u * u * (3 - 2 * u)
                ap[x, y] = round(ap[x, y] * f)
    im.putalpha(alpha)
    im.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} {im.size}, tongue tip ~{tip}")

    if preview:
        d = Path(preview)
        d.mkdir(parents=True, exist_ok=True)
        for name, bg in (("white", (255, 255, 255)), ("black", (0, 0, 0))):
            sheet = Image.new("RGBA", im.size, bg + (255,))
            sheet.alpha_composite(im)
            sheet.save(d / f"giraffe-on-{name}.png")
        # Zoom on the tongue/head.
        z = Image.new("RGBA", im.size, (255, 255, 255, 255)); z.alpha_composite(im)
        z.crop((0, 0, 260, 200)).resize((780, 600), Image.LANCZOS).save(d / "giraffe-tongue-zoom.png")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
