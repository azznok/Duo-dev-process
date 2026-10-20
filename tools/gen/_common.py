# -*- coding: utf-8 -*-
"""Shared base of the PAID generators (meshy.py, elevenlabs.py).

Rules enforced here, for all of them:
- DRY RUN by default: without --pay, print what would be done and what it would cost.
- Output already present -> skip (never buy the same thing twice).
- Cache keyed by a hash of the prompt and parameters (.state/gen_cache.json).
- Cap per command (GEN_CAP_<SERVICE> in config/project.env): refused above it.
- In-flight file written BEFORE waiting (.state/gen_in_flight.json): a paid job is not lost
  if the process dies; `resume` harvests it.
- Every paid call appends a line to docs/CREDITS.md (what was spent, on what, for which file).
- Keys are read from the environment (or the Windows User registry), never printed.
"""
import datetime
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from project import ROOT, cfg, secret  # noqa: E402,F401

STATE = ROOT / ".state"
CACHE = STATE / "gen_cache.json"
IN_FLIGHT = STATE / "gen_in_flight.json"
CREDITS = ROOT / "docs" / "CREDITS.md"


def _read_json(f, default):
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _write_json(f, d):
    STATE.mkdir(exist_ok=True)
    f.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")


def fingerprint(service, params):
    raw = service + json.dumps(params, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def already_done(out, h):
    """Path of an existing result (the output itself, or the cache); None otherwise."""
    s = pathlib.Path(out)
    if s.exists():
        return s
    c = _read_json(CACHE, {}).get(h)
    if c and pathlib.Path(c["out"]).exists():
        return pathlib.Path(c["out"])
    return None


def remember(h, out):
    c = _read_json(CACHE, {})
    c[h] = {"out": str(out), "date": datetime.datetime.now().isoformat(timespec="seconds")}
    _write_json(CACHE, c)


def in_flight_add(key, info):
    d = _read_json(IN_FLIGHT, {})
    d[key] = info
    _write_json(IN_FLIGHT, d)


def in_flight_remove(key):
    d = _read_json(IN_FLIGHT, {})
    d.pop(key, None)
    _write_json(IN_FLIGHT, d)


def in_flight():
    return _read_json(IN_FLIGHT, {})


def check_cap(key, estimate):
    """Refuse (exit 2) when the estimate is above GEN_CAP_<KEY>. 0 or empty = no cap (dry run still guards)."""
    try:
        cap = float(cfg("GEN_CAP_" + key.upper(), "0") or 0)
    except ValueError:
        cap = 0.0
    if not cap:
        print("NOTE: no GEN_CAP_%s in config/project.env, nothing caps this command" % key.upper())
    elif estimate > cap:
        print("REFUSED: %s estimates %.0f credits, cap %.0f per command (GEN_CAP_%s)"
              % (key, estimate, cap, key.upper()))
        sys.exit(2)


def _rel(p):
    try:
        return os.path.relpath(os.path.abspath(str(p)), str(ROOT)).replace("\\", "/")
    except ValueError:   # other drive: keep it absolute
        return str(p).replace("\\", "/")


def log_credits(service, operation, credits, out, note=""):
    """One line per paid call in docs/CREDITS.md (the table is created if needed)."""
    if not CREDITS.exists():
        CREDITS.parent.mkdir(parents=True, exist_ok=True)
        CREDITS.write_text("# Credits spent and asset licences\n\n"
                           "| date | service | operation | credits | output | note |\n"
                           "|---|---|---|---|---|---|\n", encoding="utf-8")
    line = "| %s | %s | %s | %s | `%s` | %s |\n" % (
        datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), service, operation, credits,
        _rel(out), note.replace("|", "/"))
    with open(CREDITS, "a", encoding="utf-8") as f:
        f.write(line)


def http(method, url, headers, body=None, timeout=120, raw=False):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    h = dict(headers)
    if data is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            b = r.read()
    except urllib.error.HTTPError as e:
        # The query string may carry tokens: never print it.
        raise RuntimeError("HTTP %d on %s : %s" % (e.code, url.split("?")[0], e.read()[:300]))
    return b if raw else json.loads(b.decode("utf-8"))


def download(url, dst):
    dst = pathlib.Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as r:
        dst.write_bytes(r.read())
    return dst


def required_key(name):
    k = secret(name)
    if not k:
        print("MISSING KEY: %s (User environment variable). Nothing was spent." % name)
        sys.exit(3)
    return k


def read_batch(path):
    """A batch: JSON list of jobs [{"type": ..., "prompt": ..., "out": ...}, ...] or {"jobs": [...]}."""
    d = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    return d if isinstance(d, list) else d.get("jobs", [])
