# -*- coding: utf-8 -*-
"""Project configuration for the Python tools (mirror of Import-Config in bin/harness/lib/common.ps1).

    import sys, pathlib; sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
    from project import ROOT, cfg, path, secret

ROOT: repository root (derived from this file). cfg("KEY", default): config/project.env, or the whole
example file when project.env is absent (same rule as the PowerShell side, so both read the same value);
override HARNESS_<KEY> in the environment; the value `empty` clears a key (a duo can switch a command off
for itself without touching the shared config file). secret("NAME"): process environment, then the
Windows User registry; NEVER printed or logged by this module.
"""
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
EMPTY = "empty"


def _read():
    f = ROOT / "config" / "project.env"
    if not f.exists():
        f = ROOT / "config" / "project.env.example"
    d = {}
    if f.exists():
        for line in f.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


_CFG = _read()


def cfg(key, default=""):
    """Config value: HARNESS_<KEY> env override, then the config file, then `default`; `empty` -> ""."""
    env = os.environ.get("HARNESS_" + key)
    if env:
        v = env
    else:
        v = _CFG.get(key, default)
    return "" if v == EMPTY else v


def path(key, default=""):
    """A config value that is a path: relative -> under ROOT."""
    v = cfg(key, default)
    p = pathlib.Path(v.replace("\\", "/"))
    return p if p.is_absolute() else ROOT / p


def secret(name):
    """A secret from the environment, then the Windows User registry (keys live there, never in a file)."""
    v = os.environ.get(name, "")
    if not v and os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
                v = winreg.QueryValueEx(k, name)[0]
        except OSError:
            v = ""
    return (v or "").strip()
