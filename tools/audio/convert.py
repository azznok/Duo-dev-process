# -*- coding: utf-8 -*-
# Converts a raw sound (mp3/wav) into a shipping sound: 44.1 kHz, MONO; WAV PCM 16-bit, or OGG Vorbis when
# the OUTPUT ends in .ogg. Every decision is a MEASUREMENT, printed for the report.
#   python tools/audio/convert.py INPUT OUTPUT.wav --mode hit    [--highpass 40] [--peak -1]
#   python tools/audio/convert.py INPUT OUTPUT.wav --mode loop   [--fade-ms 150] [--active -27]
#   python tools/audio/convert.py INPUT OUTPUT.wav --mode split  (-> OUTPUT_01.wav, OUTPUT_02.wav ...)
#   python tools/audio/convert.py INPUT OUTPUT.ogg --mode hit    (same, as OGG Vorbis)
# Modes:
#  - hit   : silence trimmed at both ends (threshold -55 dBFS, 20 ms before, 100 ms after),
#            fades 5 / 80 ms. A sound replayed by the app on a timer is NOT a loop.
#  - loop  : cuts [a, b) where the envelope at b best matches the one at a; the last L
#            samples are crossfaded with the L samples that PRECEDE a: when it wraps, the
#            end flows into what naturally followed. The seam is measured and printed.
#  - split : an attack = 10 ms envelope > -20 dBFS and +18 dB over the previous 50 ms,
#            0.20 s apart at least; every piece brought to the SAME active level (a raw series
#            of footsteps had 9 dB between steps; the app varies them by +-3 dB afterwards).
# High-pass 40 Hz by default (Butterworth order 2, forward-backward, zero phase): a generated mp3
# can carry 70-80 % of its energy below 50 Hz, inaudible on laptop speakers, and rejected as "broken".
# Level: peak at -1 dBFS by default, or --active (RMS of the 50 ms windows above -50 dBFS).
# Mono = mean of the channels: phase cancellation can lose level, so the result is re-measured.
# We do not LISTEN: we measure. The owner listens (tools/audio/listen_page.py).
import argparse
import os
import sys

import numpy as np
import soundfile as sf

SR = 44100


def db(v):
    return 20.0 * np.log10(max(float(v), 1e-9))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0


def active(x, threshold=-50.0):
    w = int(0.05 * SR)
    r = np.array([rms(x[i:i + w]) for i in range(0, max(1, len(x) - w + 1), w)])
    a = r[r > 10 ** (threshold / 20)]
    return db(rms(a)) if len(a) else -99.0


def env10(x):
    w = int(0.01 * SR)
    return np.array([db(rms(x[i:i + w])) for i in range(0, max(1, len(x) - w + 1), w)])


def below50(x):
    X = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return 100.0 * X[f < 50.0].sum() / max(X.sum(), 1e-20)


def highpass(x, fc):
    # Butterworth biquad (RBJ, Q = 0.707) run twice, the second time reversed; 0.5 s of
    # mirror at each end so that the filter transient falls outside the sound.
    w0 = 2 * np.pi * fc / SR
    al = np.sin(w0) / (2 * 0.7071)
    c = np.cos(w0)
    b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2]) / (1 + al)
    a = np.array([1.0, -2 * c / (1 + al), (1 - al) / (1 + al)])
    p = min(int(0.5 * SR), len(x) - 2)
    y = np.concatenate([x[p:0:-1], x, x[-2:-p - 2:-1]])
    for _ in range(2):
        z = np.zeros_like(y)
        x1 = x2 = y1 = y2 = 0.0
        for i, v in enumerate(y):
            o = b[0] * v + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            x2, x1, y2, y1 = x1, v, y1, o
            z[i] = o
        y = z[::-1]
    return y[p:p + len(x)]


def fades(y, in_ms, out_ms):
    fi, fo = int(in_ms / 1000 * SR), int(out_ms / 1000 * SR)
    if fi:
        y[:fi] *= np.sin(np.linspace(0, np.pi / 2, fi))
    if fo:
        y[-fo:] *= np.cos(np.linspace(0, np.pi / 2, fo))
    return y


def hit(x):
    e = env10(x)
    loud = np.where(e > -55.0)[0]
    if not len(loud):
        raise ValueError("no sound above -55 dBFS")
    w = int(0.01 * SR)
    a, b = max(0, loud[0] - 2) * w, min(len(x), (loud[-1] + 10) * w)
    return fades(x[a:b].copy(), 5, 80), "hit [%.2f s ; %.2f s)" % (a / SR, b / SR)


def loop(x, fade_ms):
    e = np.convolve(env10(x), np.ones(5) / 5, mode="same")
    w, L = int(0.01 * SR), int(fade_ms / 1000 * SR)
    ia = max(30, L // w + 1)
    cand = range(max(ia + 50, len(e) - 150), len(e) - 3)
    if not len(cand):
        raise ValueError("sound too short for a loop")
    ib = min(cand, key=lambda i: abs(e[i] - e[ia]))
    a, b = ia * w, ib * w
    y = x[a:b].copy()
    t = np.linspace(0.0, np.pi / 2, L)
    y[-L:] = y[-L:] * np.cos(t) + x[a - L:a] * np.sin(t)
    n = int(0.05 * SR)
    seam = "jump %.4f ; RMS end %.1f dB / start %.1f dB" % (abs(y[-1] - y[0]), db(rms(y[-n:])), db(rms(y[:n])))
    return y, "loop [%.2f s ; %.2f s), fade %d ms, seam: %s" % (a / SR, b / SR, fade_ms, seam)


def split(x):
    e = env10(x)
    w = int(0.01 * SR)
    att = []
    for i in range(5, len(e)):
        if e[i] > -20.0 and e[i] - e[i - 5:i].min() > 18.0 and (not att or i - att[-1] >= 20):
            att.append(i)
    pieces = []
    for k, i in enumerate(att):
        a = (i - 1) * w
        end = (att[k + 1] - 1) * w if k + 1 < len(att) else len(x)
        pieces.append(fades(x[a:min(end, a + int(0.40 * SR))].copy(), 2, 30))
    return pieces


def load(f, hp):
    d, sr = sf.read(f, always_2d=True)
    m = d.mean(axis=1)
    if sr != SR:   # linear resampling: good enough for short effects
        m = np.interp(np.linspace(0, len(m) - 1, int(len(m) * SR / sr)), np.arange(len(m)), m)
    note = "source %.2f s, %d Hz, %d channel(s), below 50 Hz %.0f %%" % (len(d) / sr, sr, d.shape[1], below50(m))
    if hp:
        m = highpass(m, hp)
        note += " -> high-pass %.0f Hz: %.0f %%" % (hp, below50(m))
    return m, note


def level(y, peak, target_active):
    g = (target_active - active(y)) if target_active is not None else (peak - db(np.abs(y).max()))
    y = y * 10 ** (g / 20)
    if np.abs(y).max() >= 1.0:   # never clip, even with --active
        y = y / np.abs(y).max() * 10 ** (-0.5 / 20)
    return y, g


def write(y, f):
    d = os.path.dirname(os.path.abspath(f))
    os.makedirs(d, exist_ok=True)   # libsndfile only says "System error" on a missing folder
    if f.lower().endswith(".ogg"):
        # Vorbis is lossy: the re-measured peak can move by a few tenths of a dB.
        sf.write(f, y, SR, format="OGG", subtype="VORBIS")
    else:
        sf.write(f, y, SR, subtype="PCM_16")
    return "%s : %.2f s, peak %.1f dBFS, active %.1f dBFS" % (f, len(y) / SR, db(np.abs(y).max()), active(y))


def main():
    ap = argparse.ArgumentParser(description="Convert a raw sound into a measured mono 44.1 kHz WAV or OGG.")
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--mode", choices=("hit", "loop", "split"), required=True)
    ap.add_argument("--highpass", type=float, default=40.0, help="Hz, 0 = off")
    ap.add_argument("--peak", type=float, default=-1.0, help="dBFS")
    ap.add_argument("--active", type=float, default=None, help="target active level in dBFS (instead of --peak)")
    ap.add_argument("--fade-ms", type=int, default=150)
    a = ap.parse_args()
    m, note = load(a.input, a.highpass)
    print("CONVERT " + note)
    if a.mode == "split":
        pieces = split(m)
        target = a.active if a.active is not None else min(active(y) for y in pieces) if pieces else -20
        ext = ".ogg" if a.output.lower().endswith(".ogg") else ".wav"
        base = a.output[:-4] if a.output.lower().endswith((".wav", ".ogg")) else a.output
        for k, y in enumerate(pieces):
            y, _ = level(y, a.peak, target)
            print("  " + write(y, "%s_%02d%s" % (base, k + 1, ext)))
        print("SPLIT %d piece(s)" % len(pieces))
        return 0 if pieces else 1
    y, what = hit(m) if a.mode == "hit" else loop(m, a.fade_ms)
    y, g = level(y, a.peak, a.active)
    print("  %s ; gain %+.1f dB" % (what, g))
    print("  " + write(y, a.output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
