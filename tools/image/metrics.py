# -*- coding: utf-8 -*-
# Measures on a capture: luminance, text contrast, palette, colour of an area, clipping, coverage.
#   python tools/image/metrics.py lum IMAGE                     -> max and mean luminance
#   python tools/image/metrics.py contrast IMAGE x y w h        -> background, letter, ratio, letter height
#   python tools/image/metrics.py palette IMAGE [--top 8] [--crop 0.7]
#   python tools/image/metrics.py zone IMAGE x y w h [--name wall]
#   python tools/image/metrics.py clipped IMAGE                 -> % of clipped pixels (pure black, or a channel at 255)
#   python tools/image/metrics.py coverage IMAGE                -> % of pixels different from the background
#                                                                  (top-left pixel)
# A MEASURE IS NEVER AN ACCEPTANCE. It says we did not go the wrong way; the image next to the
# reference says whether it is good. (Merged from four older PowerShell tools; same thresholds, same lessons.)
import argparse
import sys

import numpy as np
from PIL import Image

# Absolute luminance floor of a letter (0-255). Readings that set it: unreadable ~19, clear 90-106,
# dark but readable 53. Under 40, no contrast ratio redeems the letter.
LUM_FLOOR = 40.0
# Minimum letter height in pixels: under 9 px, a good contrast redeems nothing.
PX_FLOOR = 9


def load(f):
    return np.asarray(Image.open(f).convert("RGB")).astype(np.float64)


def lum709(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def cmd_lum(a):
    px = load(a.image)
    y = 0.299 * px[..., 0] + 0.587 * px[..., 1] + 0.114 * px[..., 2]
    y = y[a.skip_top:]   # below the title bar of a window capture
    print("%s  max=%d  mean=%.1f" % (a.image, int(y.max()), y.mean()))


def cmd_contrast(a):
    # CONTRAST, NOT AMPLITUDE: what makes a text readable is the ratio between the LETTER and what is
    # IMMEDIATELY behind it. But on pure black the ratio is infinite whatever the letter: so we also
    # print the ABSOLUTE luminance of the letter, and the letter HEIGHT (a 4 px text is unreadable).
    z = lum709(load(a.image))[a.y:a.y + a.h, a.x:a.x + a.w]
    low, high = np.percentile(z, 10), np.percentile(z, 90)
    ratio = high / low if low > 0.5 else float("inf")
    print("%s : background(10th pct) %.1f | letter(90th) %.1f | ratio %.2f" % (a.image, low, high, ratio))
    if high < LUM_FLOOR:
        print("   UNREADABLE : letter at %.1f, under the absolute floor of %.0f." % (high, LUM_FLOOR))
    # Letter height BY ROWS: a row carries ink if 2 % of its pixels pass the threshold; consecutive inked
    # rows form a band = one line of text. (Counting by columns measured the width of a stroke: wrong both
    # ways.) A single band as tall as the area = text seen at an angle.
    threshold = (low + high) / 2.0
    ink = (z >= threshold).sum(axis=1) >= max(1, int(a.w * 0.02))
    bands, c = [], 0
    for e in ink:
        if e:
            c += 1
        elif c:
            bands.append(c)
            c = 0
    if c:
        bands.append(c)
    if not bands:
        print("   NO INK : the area holds no text.")
        return
    med = sorted(bands)[len(bands) // 2]
    print("   letter height ~%d px (%d band(s) in an area of %d px)" % (med, len(bands), a.h))
    if len(bands) == 1 and med >= a.h * 0.9:
        print("   DOUBTFUL MEASURE : one band filling the area (slanted text or area too tight). Look at the image.")
    elif med < PX_FLOOR:
        print("   TOO SMALL : %d px, under the floor of %d px." % (med, PX_FLOOR))


def cmd_palette(a):
    # --crop 0.7 keeps the central 70 %: a flat board background would otherwise crush the ranking.
    px = load(a.image)
    h, w = px.shape[:2]
    x0, y0 = int(w * (1 - a.crop) / 2), int(h * (1 - a.crop) / 2)
    z = px[y0:h - y0:3, x0:w - x0:3].reshape(-1, 3)
    m = z.mean(axis=0)
    print("image      : %s (%dx%d, %d pixels read)" % (a.image, w, h, len(z)))
    print("mean       : R %.0f G %.0f B %.0f   #%02X%02X%02X" % (m[0], m[1], m[2], int(m[0]), int(m[1]), int(m[2])))
    lum = 0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]
    print("luminance  : %.1f / 255 (%.0f %%)" % (lum, 100 * lum / 255))
    print("warmth     : %.1f  (R - B ; positive = amber, negative = blue)" % (m[0] - m[2]))
    # Steps of 32: coarse enough to group, fine enough to separate two hues.
    # WARNING: quantisation MIXES neighbouring hues; for a precise colour role (the wall, the floor),
    # measure the ZONE.
    q = (z // 32 * 32).astype(int)
    keys, n = np.unique(q, axis=0, return_counts=True)
    print("dominant   :")
    for i in np.argsort(-n)[:a.top]:
        r, g, b = keys[i]
        print("   #%02X%02X%02X  %5.1f %%" % (r, g, b, 100.0 * n[i] / len(z)))


def cmd_zone(a):
    z = load(a.image)[a.y:a.y + a.h, a.x:a.x + a.w].reshape(-1, 3)
    if not len(z):
        print("empty zone")
        return
    r, g, b = z.mean(axis=0)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn) / mx if mx > 0 else 0
    print("%-12s #%02X%02X%02X  lum %5.1f (%2.0f %%)  sat %4.2f  warmth %5.1f"
          % (a.name, int(r), int(g), int(b), lum, 100 * lum / 255, sat, r - b))


def cmd_clipped(a):
    z = load(a.image).reshape(-1, 3)
    black = (z <= 0).all(axis=1)
    white = (z >= 255).any(axis=1)
    n = len(z)
    print("clipped %.2f %%  (black %.2f %%, a channel at 255 %.2f %%)"
          % (100.0 * (black | white).sum() / n, 100.0 * black.sum() / n, 100.0 * white.sum() / n))


def cmd_coverage(a):
    img = load(a.image)
    bg = img[0, 0]
    other = (np.abs(img - bg).max(axis=2) > a.tolerance)
    print("coverage %.1f %%  (background #%02X%02X%02X, tolerance %d)"
          % (100.0 * other.mean(), int(bg[0]), int(bg[1]), int(bg[2]), a.tolerance))


def main():
    ap = argparse.ArgumentParser(description="measures on a capture")
    s = ap.add_subparsers(dest="cmd", required=True)
    p = s.add_parser("lum"); p.add_argument("image")
    p.add_argument("--skip-top", type=int, default=45); p.set_defaults(f=cmd_lum)
    p = s.add_parser("contrast"); p.add_argument("image")
    for k in "xywh":
        p.add_argument(k, type=int)
    p.set_defaults(f=cmd_contrast)
    p = s.add_parser("palette"); p.add_argument("image"); p.add_argument("--top", type=int, default=8)
    p.add_argument("--crop", type=float, default=1.0); p.set_defaults(f=cmd_palette)
    p = s.add_parser("zone"); p.add_argument("image")
    for k in "xywh":
        p.add_argument(k, type=int)
    p.add_argument("--name", default="zone"); p.set_defaults(f=cmd_zone)
    p = s.add_parser("clipped"); p.add_argument("image"); p.set_defaults(f=cmd_clipped)
    p = s.add_parser("coverage"); p.add_argument("image")
    p.add_argument("--tolerance", type=int, default=2); p.set_defaults(f=cmd_coverage)
    a = ap.parse_args()
    a.f(a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
