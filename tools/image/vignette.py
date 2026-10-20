# -*- coding: utf-8 -*-
# Shrinks images (<= 1280 px, JPEG) BEFORE an agent reads them: a full-size PNG costs a lot of context,
# and it is read again at every later call of the session.
#   python tools/image/vignette.py --out .state/thumbs a.png b.png ...   -> "THUMB a.png -> .state/thumbs/a.jpg"
#   python tools/image/vignette.py --max 800 --out D x.png              (smaller still)
# Rule: an agent reads the THUMBNAIL; the original only for a detail, through tools/image/loupe.ps1
# (zoomed area, pixel exact). Already small: copied as is, as JPEG.
import argparse
import pathlib
import sys

from PIL import Image


def thumbnail(src, folder, max_side=1280, quality=82):
    src = pathlib.Path(src)
    folder.mkdir(parents=True, exist_ok=True)
    dst = folder / (src.stem + ".jpg")
    with Image.open(src) as im:
        im = im.convert("RGB")
        w, h = im.size
        k = min(1.0, float(max_side) / max(w, h))
        if k < 1.0:
            im = im.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
        im.save(dst, "JPEG", quality=quality, optimize=True)
    return dst


def main():
    ap = argparse.ArgumentParser(description="JPEG thumbnails for an agent to read")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--max", type=int, default=1280)
    ap.add_argument("--quality", type=int, default=82)
    a = ap.parse_args()
    code = 0
    for f in a.images:
        try:
            d = thumbnail(f, pathlib.Path(a.out), a.max, a.quality)
            print("THUMB %s -> %s" % (f, d))
        except Exception as e:   # one unreadable image does not block the others
            print("UNREADABLE %s : %s" % (f, e))
            code = 1
    return code


if __name__ == "__main__":
    sys.exit(main())
