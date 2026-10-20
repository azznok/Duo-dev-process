# -*- coding: utf-8 -*-
# Size budgets of the process documents (docs/RULES.md, memory and documents), read only.
#   python tools/costs/budgets.py   -> one line per document: actual / budget, OVER if above
# Exit 0 if everything fits, 1 if a document is over (the core CLAUDE.md / RULES included: report it, do
# not fix it here). The budget is READ from each document's header, second line:
#     > WRITTEN BY: <who>. BUDGET: <n> lines.        (also `<n> bytes.` or `<n> questions.`)
# Why read it instead of keeping a list here: a hand-kept list drifts from the documents by the third
# new one, and a list that lies costs more than no list. A skill (`.claude/skills/*/SKILL.md`) without a
# header gets the skill limit (150 lines). `BUDGET: none` (generated files) is skipped.
# Serves the end-of-milestone process review: every line of a document loaded at each call costs everywhere.
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from project import ROOT  # noqa: E402

DECLARED = re.compile(r"BUDGET\s*:\s*(\d+)\s*(lines?|bytes?|questions?)\b", re.I)
SKILL_LINES = 150
HEAD_LINES = 5
# Where process documents live; docs/journal/ is the archive (never loaded, no budget).
GLOBS = ("CLAUDE.md", "*.md", "docs/*.md", "docs/**/*.md", "supervisor/*.md", "pipeline/*.md",
         ".claude/skills/*/*.md", ".claude/skills/*/*/*.md", "bin/harness/prompts/*.md")
SKIP = ("docs/journal/", "docs/adr/")


def measure(p, unit):
    b = p.read_bytes()
    if unit == "bytes":
        return len(b)
    s = b.decode("utf-8", "replace")
    if unit == "questions":
        return len(re.findall(r"(?m)^(?:#+\s*)?Q\d+\b", s))
    return len(s.splitlines())


def declared(p):
    """(n, unit) from 'BUDGET: N lines.' in the first lines of the document, or None."""
    head = "\n".join(p.read_bytes().decode("utf-8", "replace").splitlines()[:HEAD_LINES])
    m = DECLARED.search(head)
    if not m:
        return None
    unit = m.group(2).lower()
    return int(m.group(1)), unit if unit.endswith("s") else unit + "s"


def documents(root=None):
    root = root or ROOT
    seen, out = set(), []
    for g in GLOBS:
        for p in sorted(root.glob(g)):
            rel = str(p.relative_to(root)).replace("\\", "/")
            if rel in seen or not p.is_file() or rel.startswith(SKIP):
                continue
            seen.add(rel)
            d = declared(p)
            if d is None and rel.startswith(".claude/skills/") and p.name == "SKILL.md":
                d = (SKILL_LINES, "lines")
            if d is not None:
                out.append((rel, p, d[0], d[1]))
    return out


def main(root=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    over = 0
    docs = documents(root)
    for rel, p, budget, unit in docs:
        n = measure(p, unit)
        state = "OVER" if n > budget else ("full" if n == budget else "ok")
        over += n > budget
        print("%-52s %5d / %-5d %-9s %s" % (rel, n, budget, unit, state))
    print("budgets : %s (%d document(s), %d over)" % ("OK" if not over else "OVER", len(docs), over))
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())
