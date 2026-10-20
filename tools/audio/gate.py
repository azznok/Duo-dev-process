# -*- coding: utf-8 -*-
# The GATE of a generated sound: audible above 200 Hz, and not a hum.
#   python tools/audio/gate.py file.mp3 [...]   -> "GATE OK|REJECTED name : audible -23.1 dB, peak line 60 Hz 3.2 %"
# Criteria (measured on sounds an owner rejected):
#  - AUDIBLE: RMS of the content above 200 Hz > -40 dB. Below that, the sound is a
#    hiss or a low rumble that laptop speakers do not reproduce;
#  - NO LINE: the dominant spectral line (+-3 Hz) carries less than 15 % of the energy.
#    Above that, it is a hum (mains, drone), which the owner rejected.
# A gate is not a listen: it rejects the obvious, the owner judges the rest.
# Exit code 1 if any file is REJECTED or unreadable.
import sys

import numpy as np
import soundfile as sf

AUDIBLE_MIN_DB = -40.0
CUTOFF_HZ = 200.0
LINE_MAX_PCT = 15.0


def measure(path):
    x, sr = sf.read(path)
    x = x.mean(axis=1) if x.ndim > 1 else x
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1.0 / sr)
    S = np.abs(X) ** 2
    Y = X.copy()
    Y[fr < CUTOFF_HZ] = 0
    y = np.fft.irfft(Y, len(x))
    audible = 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)
    peak = fr[np.argmax(S)]
    share = S[(fr > peak - 3) & (fr < peak + 3)].sum() / max(S.sum(), 1e-20) * 100
    ok = audible > AUDIBLE_MIN_DB and share < LINE_MAX_PCT
    return audible, peak, share, ok


def line(path):
    a, p, s, ok = measure(path)
    return "GATE %s %s : audible %.1f dB, peak line %.0f Hz %.1f %%" % ("OK" if ok else "REJECTED", path, a, p, s)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print("usage: python tools/audio/gate.py file.mp3 [...]  (exit 1 if a file is REJECTED or unreadable)")
        return 0 if argv else 2
    code = 0
    for f in argv:
        try:
            out = line(f)
        except Exception as e:
            out = "GATE UNREADABLE %s : %s" % (f, e)
        print(out)
        if not out.startswith("GATE OK"):
            code = 1
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
