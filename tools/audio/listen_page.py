# -*- coding: utf-8 -*-
# LISTENING page for the owner: one player per sound, with the gate's measurement.
#   python tools/audio/listen_page.py FOLDER [--out FOLDER/listen.html] [--title "Series 2"]
# Agents NEVER listen (no agent ever plays a sound). The supervisor opens this page,
# the owner listens, and the answer ("keep 2 and 5, redo 3 drier") becomes a
# decision. Static page, relative paths: open it in a browser.
import argparse
import html
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))


def main():
    ap = argparse.ArgumentParser(description="Write a static HTML page to let the owner listen to a folder of sounds.")
    ap.add_argument("folder")
    ap.add_argument("--out", default=None)
    ap.add_argument("--title", default="Sounds to listen to")
    a = ap.parse_args()
    d = pathlib.Path(a.folder)
    if not d.is_dir():
        print("LISTEN PAGE: no folder %s" % d)
        return 1
    out = pathlib.Path(a.out) if a.out else d / "listen.html"
    sounds = sorted(p for p in d.iterdir() if p.suffix.lower() in (".mp3", ".wav", ".ogg"))
    try:
        import gate
    except Exception:   # the gate needs numpy + soundfile: the page still works without measurements
        gate = None
    items = []
    for i, s in enumerate(sounds, 1):
        meas = ""
        if gate:
            try:
                au, peak, share, ok = gate.measure(str(s))
                meas = "%s - audible %.1f dB, peak line %.0f Hz %.1f %%" % ("OK" if ok else "REJECTED", au, peak, share)
            except Exception as e:
                meas = "measurement failed (%s)" % e
        try:
            rel = os.path.relpath(s.resolve(), out.parent.resolve())
        except ValueError:   # other drive: absolute URI
            rel = s.resolve().as_uri()
        items.append('<li><b>%d. %s</b> <small>%s</small><br><audio controls preload="none" src="%s"></audio></li>'
                     % (i, html.escape(s.name), html.escape(meas), html.escape(str(rel).replace("\\", "/"))))
    page = """<!doctype html><html lang="en"><meta charset="utf-8"><title>%s</title>
<style>body{font:16px system-ui;max-width:760px;margin:2em auto;padding:0 16px}li{margin:1em 0}audio{width:100%%}</style>
<h1>%s</h1><p>Listen on headphones AND on speakers. Answer by number: keep / redo (how).</p>
<ol style="list-style:none;padding:0">%s</ol></html>""" % (html.escape(a.title), html.escape(a.title), "\n".join(items))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    print("LISTEN PAGE %d sound(s) -> %s" % (len(sounds), out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
