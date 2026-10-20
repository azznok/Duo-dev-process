"""Lanes of a milestone: what can move forward in parallel without two duos getting in each other's way.

    python tools/lanes.py --milestone M5 [--json] [--ref main]

Reads docs/backlog/<milestone>-*.md. Each entry `## Mn-xx — <title>` carries, on its metadata lines:
    **Lane**: <name>. **Zones**: <path>, <path>.
(zones are repository paths: `src/sim`, `assets/data/looks`, `docs/GAMEPLAY.md`; a folder covers its
sub-folders). An entry is DONE if its title carries ✅ or if all its checkboxes are ticked.

Checks (exit 1 otherwise): every open entry has a lane and zones; two different lanes share no zone (two
duos editing the same files = merge conflicts every round); no `## Mn-xx` title appears twice in a file.
A backlog without any label = one lane `single` (not split yet: one duo only).
A prerequisite saying "owner decision" or "pause" blocks the entry (only the owner unblocks it).
For each lane: ready (an open entry whose prerequisites outside the lane are done), waiting (open
entries, all blocked by another lane), done (every entry done). The `## End of Mn` entry is the lane
`end`, ready only when every other lane is done. (The orchestrator gives the lane `*` to the first duo
when this script reports errors: that duo fixes the backlog; see docs/HARNESS.md § Lanes.)
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ID = r"M\d+[a-z]?-\d+"
PAUSE = "PAUSE"
SINGLE = "single"
END = "end"
END_ID = "END"
DONE_MARK = "✅"
BLOCKERS = re.compile(r"owner(?:.s)? decision|decision of the owner|\bpause\b", re.I)


def label(name):
    """`**Lane**: x` or `**Lane:** x` -> regex for the value after the label."""
    return r"\*\*" + name + r"(?:\*\*\s*:|:\*\*)\s*"


def prerequisites_of(text):
    """Cited ids; "owner decision" or "pause" blocks the entry (never done outside the lane)."""
    ids = ids_of(text)
    if BLOCKERS.search(text):
        ids.append(PAUSE)
    return ids


def ids_of(text):
    """Cited ids, ranges `M4-15 to M4-18` included."""
    out = []
    for m in re.finditer(rf"({ID})(?:\s*(?:\bto\b|\.\.)\s*({ID}))?", text):
        a, b = m.group(1), m.group(2)
        out.append(a)
        if b:
            pa, na = a.rsplit("-", 1)
            pb, nb = b.rsplit("-", 1)
            if pa == pb:
                out += [f"{pa}-{n:02d}" for n in range(int(na) + 1, int(nb) + 1)]
    return out


def texts(milestone, ref=None):
    """(name, text) of the milestone's backlog files: working copy, or branch `ref` (git show).
    `--ref main` matters: the MERGED backlog counts, not the working copy of a coder mid-task."""
    if not ref:
        fs = [f for f in (ROOT / "docs" / "backlog").glob("*.md") if re.match(rf"{milestone}[a-z]?-", f.name)]
        return [(f.name, f.read_text(encoding="utf-8")) for f in sorted(fs)]
    names = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "--name-only", ref, "docs/backlog/"],
                           capture_output=True, text=True, encoding="utf-8").stdout.split()
    out = []
    for n in sorted(names):
        name = n.rsplit("/", 1)[-1]
        if re.match(rf"{milestone}[a-z]?-", name):
            out.append((name, subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:{n}"],
                                             capture_output=True, text=True, encoding="utf-8").stdout))
    return out


def read(milestone, ref=None):
    entries = []
    for name, text in texts(milestone, ref):
        for b in re.split(r"(?m)^(?=## )", text):
            t = b.splitlines()[0] if b.strip() else ""
            m = re.match(rf"## ({ID})\b", t)
            end = re.match(r"## End of (M\d+|milestone)\b", t, re.I)
            if not (m or end):
                continue
            boxes = re.findall(r"(?m)^\s*- \[( |x)\]", b)
            done = DONE_MARK in t or (bool(boxes) and all(c == "x" for c in boxes))
            c = re.search(label("Lane") + r"`?([\w-]+)", b)
            z = re.search(label("Zones") + r"([^*\n]+)", b)
            p = re.search(label("Prerequisites") + r"([^*]+)", b)
            zones = [s.strip().strip("`").rstrip(".").strip().strip("`").rstrip("/")
                     for s in (z.group(1).split(",") if z else []) if s.strip()]
            entries.append({
                "id": m.group(1) if m else END_ID,
                "file": name,
                "done": done,
                "lane": END if end else (c.group(1) if c else None),
                "zones": [x for x in zones if x],
                "prerequisites": prerequisites_of(p.group(1)) if p else [],
            })
    return entries


def overlaps(a, b):
    a, b = a.lower(), b.lower()
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def analyse(entries, done_elsewhere=frozenset()):
    """`done_elsewhere`: done entries of OTHER milestones (a prerequisite M4-28 of an M5 entry)."""
    errors = []
    seen = set()
    for e in entries:
        key = (e.get("file"), e["id"])
        if e["id"] != END_ID and key in seen:
            errors.append(f"{e['id']} : duplicate title")
        seen.add(key)
    open_ = [e for e in entries if not e["done"] and e["id"] != END_ID]
    labelled = [e for e in entries if e["lane"] not in (None, END)]
    if not labelled:
        for e in open_:
            e["lane"] = SINGLE
    for e in open_:
        if not e["lane"]:
            errors.append(f"{e['id']} : no lane")
        elif e["lane"] != SINGLE and not e["zones"]:
            errors.append(f"{e['id']} : no zones")
    done = {e["id"] for e in entries if e["done"]} | set(done_elsewhere)
    lanes = {}
    for e in open_:
        if e["lane"]:
            lanes.setdefault(e["lane"], []).append(e)
    for x, ex in lanes.items():
        for y, ey in lanes.items():
            if x >= y:
                continue
            for zx in {z for e in ex for z in e["zones"]}:
                for zy in {z for e in ey for z in e["zones"]}:
                    if overlaps(zx, zy):
                        errors.append(f"lanes {x} and {y} share the zone {zx} / {zy}")
    report = {}
    for x, ex in lanes.items():
        ids = {e["id"] for e in ex}
        ready = [e["id"] for e in ex if all(p in done or (p in ids and p != PAUSE) for p in e["prerequisites"])]
        report[x] = {"state": "ready" if ready else "waiting", "entries": [e["id"] for e in ex],
                     "ready": ready, "zones": sorted({z for e in ex for z in e["zones"]})}
    # A labelled lane whose entries are all done is reported "done" (the orchestrator frees its duo).
    for e in entries:
        x = e["lane"]
        if e["done"] and x not in (None, END, SINGLE) and x not in lanes:
            r = report.setdefault(x, {"state": "done", "entries": [], "ready": [], "zones": []})
            r["entries"].append(e["id"])
            r["zones"] = sorted(set(r["zones"]) | set(e["zones"]))
    for e in entries:
        if e["id"] == END_ID:
            if e["done"]:
                report[END] = {"state": "done", "entries": [END_ID], "ready": [], "zones": []}
            else:
                report[END] = {"state": "waiting" if lanes else "ready", "entries": [END_ID],
                               "ready": [] if lanes else [END_ID], "zones": []}
            break
    return report, errors


def main():
    ap = argparse.ArgumentParser(description="lanes of a milestone")
    ap.add_argument("--milestone", required=True)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--ref", help="read the backlog of this branch (e.g. main) instead of the working copy")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    # A prerequisite from another milestone (M5-06 after M4-28) is read in ALL backlogs, not only this one.
    done_elsewhere = {e["id"] for e in read(r"M\d+", a.ref) if e["done"]}
    report, errors = analyse(read(a.milestone, a.ref), done_elsewhere)
    if a.json:
        print(json.dumps({"lanes": report, "errors": errors}, ensure_ascii=False))
    else:
        for x, r in report.items():
            print(f"{x} : {r['state']} ; entries {', '.join(r['entries'])} ; ready {', '.join(r['ready']) or '-'} ; "
                  f"zones {', '.join(r['zones']) or '-'}")
        for e in errors:
            print(f"ERROR {e}")
        n = sum(1 for r in report.values() if r["state"] == "ready")
        print(f"LANES {a.milestone} : {n} ready, {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
