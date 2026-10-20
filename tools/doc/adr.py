#!/usr/bin/env python3
"""One ADR = one file: docs/adr/NNNN-<slug>.md, and docs/DECISIONS.md is a GENERATED index.

Usage:
  python tools/doc/adr.py index            rewrite docs/DECISIONS.md from docs/adr/*.md
  python tools/doc/adr.py index --check    exit 1 if the index is stale (nothing written)
  python tools/doc/adr.py split SRC        one-shot: cut SRC (an old single-file decision log) into docs/adr/
  python tools/doc/adr.py headers          print every ADR header line (for other tools)

Why one file per ADR: with several duos, a single decisions file is the place every task appends to,
so every merge conflicts there. The harness runs `index` on main after each merge
(bin/harness/lib/branches.ps1, Merge-Task); duos never edit docs/DECISIONS.md (the gate refuses it).
"""
import argparse
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADR_DIR = ROOT / "docs" / "adr"
INDEX = ROOT / "docs" / "DECISIONS.md"
HEADER_RE = re.compile(r"^## ADR-(\d{4}[a-z]?)\b")
FILE_RE = re.compile(r"^(\d{4}[a-z]?)-.+\.md$")

INDEX_HEAD = """# Decisions (ADR): GENERATED INDEX
> WRITTEN BY: `python tools/doc/adr.py index` (the harness, after each merge into `main`). BUDGET: none.

DO NOT EDIT: the gate refuses a task that changes this file (one line per ADR, regenerated).

One ADR = one file `docs/adr/NNNN-<slug>.md`. Number: `powershell -File bin/harness/next-adr.ps1`
(shared by all duos, so two duos never take the same number). The file starts with
`## ADR-NNNN — <title> — *<status>* (TASK <nnn>)`; then context, decision, consequences. An "open"
decision must be settled by the milestone it names. Never rewrite an existing ADR: write a new one and
mark the old one "replaced by ADR-XXXX".

---

"""


def slug(title, limit=60):
    t = unicodedata.normalize("NFKD", title)
    t = "".join(c for c in t if not unicodedata.combining(c)).lower()
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return (t[:limit].rstrip("-")) or "adr"


def title_of(header):
    """`## ADR-0001 — Language choice — *Accepted*` -> `Language choice`."""
    rest = HEADER_RE.sub("", header, count=1).lstrip(" —-:")
    return rest.split(" — *", 1)[0].split(" *", 1)[0].strip()


def split_blocks(text):
    """[(number, header, block)] for each `## ADR-` header of an old single-file log."""
    blocks, cur = [], None
    for line in text.splitlines():
        m = HEADER_RE.match(line)
        if m:
            cur = [m.group(1), line, [line]]
            blocks.append(cur)
        elif cur is not None:
            cur[2].append(line)
    out = []
    for num, header, lines in blocks:
        while lines and lines[-1].strip() in ("", "---"):
            lines.pop()
        out.append((num, header, "\n".join(lines) + "\n"))
    return out


def split(src, dest=None):
    """Every block goes VERBATIM to its own file (a knowledge is never rewritten while moved)."""
    dest = dest or ADR_DIR
    dest.mkdir(parents=True, exist_ok=True)
    used = {p.name for p in dest.glob("*.md")}
    written = []
    for num, header, block in split_blocks(Path(src).read_text(encoding="utf-8")):
        name = f"{num}-{slug(title_of(header))}.md"
        k = 2
        while name in used:
            name = f"{num}-{slug(title_of(header))}-{k}.md"
            k += 1
        used.add(name)
        (dest / name).write_text(block, encoding="utf-8", newline="\n")
        written.append(name)
    return written


def adr_files(adr_dir=None):
    adr_dir = adr_dir or ADR_DIR
    files = [p for p in adr_dir.glob("*.md") if FILE_RE.match(p.name)]
    return sorted(files, key=lambda p: (p.name[:4], p.name))


def first_header(path):
    for line in path.read_text(encoding="utf-8").splitlines():
        if HEADER_RE.match(line):
            return line
    return ""


def headers(adr_dir=None):
    adr_dir = adr_dir or ADR_DIR
    return [h for h in (first_header(p) for p in adr_files(adr_dir)) if h]


def render_index(adr_dir=None):
    adr_dir = adr_dir or ADR_DIR
    lines = []
    for p in adr_files(adr_dir):
        h = first_header(p)
        num = FILE_RE.match(p.name).group(1)
        rest = HEADER_RE.sub("", h, count=1).lstrip(" —-:") if h else "(header missing)"
        lines.append(f"- [ADR-{num}](adr/{p.name}) — {rest}")
    return INDEX_HEAD + "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("index")
    i.add_argument("--check", action="store_true")
    s = sub.add_parser("split")
    s.add_argument("src")
    sub.add_parser("headers")
    a = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if a.cmd == "split":
        print(f"{len(split(a.src))} ADR written to {ADR_DIR}")
        return 0
    if a.cmd == "headers":
        print("\n".join(headers()))
        return 0
    new = render_index()
    old = INDEX.read_text(encoding="utf-8") if INDEX.exists() else ""
    if old.replace("\r\n", "\n") == new:
        print("ADR index up to date")
        return 0
    if a.check:
        print("ADR index STALE: python tools/doc/adr.py index")
        return 1
    INDEX.write_text(new, encoding="utf-8", newline="\n")
    print(f"ADR index rewritten ({len(adr_files())} ADR)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
