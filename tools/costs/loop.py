# -*- coding: utf-8 -*-
# Loop dashboard: first-pass acceptance, median cost and time per task, bugs found later, per domain.
#   python tools/costs/agg_logs.py --loop [--since yyMMdd] [--tasks a-b] [--logs <folder> ...]
# METHOD (no other heuristic; each log folder = one duo, task numbers are shared between duos):
#  - task n = line `reviewer : TASK: n — <title>` of logs/harness-<yyMMdd>.log; domain = 1st of
#    `coder : domains a,b`; coder logs = lines `coder : ... -> <log>-coder.log` until the next task line.
#  - the pass that JUDGES n = the first reviewer log of the SAME folder whose number is > n (the reviewer
#    numbers a pass with the task it is about to write; with two duos, n+1 may belong to the other duo);
#    no reviewer log: the next task of the folder, else n+1.
#  - cost/time of n = its coder logs + the reviewer logs of its judging pass; a log without final JSON
#    counts the task but makes its cost "unknown" (excluded from medians and totals, reported).
#  - correction = title containing the WORD correction, `fixes NNN` or BENCH KO / LOAD KO (a plain "fix" in a
#    title is a feature, not a correction). Its targets = the 3-digit numbers (< n) after `fixes` in
#    pipeline/history/<n>-task.md or in the report of n (<judging pass>-judged-report.md), else in the title;
#    no number: the previous task of the same folder; MANUAL_CITATIONS wins.
#  - first-pass rejection = verdict REJECT of n: journal line `reviewer : verdict REJECT on task/<n>-...`,
#    else first line of pipeline/history/<judging pass>-review.md; with neither: a task cited by
#    "correction [of] N" in a title. Bug cited = task cited by a correction (a target that is itself a
#    correction is brought back to the task it fixes); a bug not rejected was found AFTER acceptance.
#  - accepted on first pass = not a correction and not rejected.
# NOT MEASURABLE: the gate's share of rejections; the reviewer's real effort (logged on escalation only);
# a bug that neither a title nor MANUAL_CITATIONS names.
import collections
import pathlib
import re
import statistics
import sys

import agg_logs

# {task: (cited tasks,)} when a correction's title and report do not name what it fixes. Empty in a new
# project; filled at the process review, never guessed.
MANUAL_CITATIONS = {}

TASK = re.compile(r"reviewer : TASK: (\d+) — (.*)")
CORRECTION = re.compile(r"\bcorrection\b|\bfixes\s+\d{3}\b|BENCH KO|LOAD KO", re.I)
FIXES = re.compile(r"\bfixes\s+((?:\d{3}\b(?:\s*(?:,|and)\s*)?)+)", re.I)
REJECTED_TITLE = re.compile(r"correction (?:of )?(\d{3})\b", re.I)
CODER_LOG = re.compile(r"-> (\d{6}-\d{6}-coder\S*\.log)")
VERDICT_LINE = re.compile(r"reviewer : verdict (\w+) on task/(\d+)")


def read_tasks(folder):
    """Tasks of one log folder: {n: dict(n, title, day, dom, coders, dir, verdict)}."""
    tasks, cur = {}, None
    for f in sorted(folder.glob("harness-*.log")):
        day = f.stem.split("-")[1]
        for line in f.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            v = VERDICT_LINE.search(line)
            if v and int(v.group(2)) in tasks:
                tasks[int(v.group(2))]["verdict"] = v.group(1).upper()
            m = TASK.search(line)
            if m:
                n = int(m.group(1))
                cur = tasks.setdefault(n, dict(n=n, title=m.group(2).strip(), day=day, dom=None, coders=[],
                                               dir=str(folder), verdict=None))
                continue
            if "reviewer : TASK:" in line:
                cur = None
            elif cur is not None and "coder : domains " in line:
                d = line.split("coder : domains ", 1)[1].split(" ->")[0].strip()
                cur["dom"] = cur["dom"] or re.split(r"[ ,]+", d)[0]
            elif cur is not None:
                j = CODER_LOG.search(line)
                if j and j.group(1) not in cur["coders"]:
                    cur["coders"].append(j.group(1))
    return tasks


def read_all(folders):
    tasks = {}
    for f in folders:
        tasks.update(read_tasks(f))
    return tasks


def history_of(t):
    return pathlib.Path(t["dir"]).parent / "pipeline" / "history"


def read(history, name):
    f = history / name if history else None
    return f.read_text(encoding="utf-8-sig", errors="replace") if f and f.exists() else ""


def verdict(t, history):
    if t.get("verdict"):
        return t["verdict"]
    if t.get("judge") is None:
        return None
    m = re.match(r"VERDICT:\s*(\w+)", read(history, "%03d-review.md" % t["judge"]))
    return m.group(1).upper() if m else None


def targets(t, history, previous):
    n = t["n"]
    if n in MANUAL_CITATIONS:
        return MANUAL_CITATIONS[n]
    report = read(history, "%03d-judged-report.md" % t["judge"]) if t.get("judge") is not None else ""
    text = "\n".join([t["title"], read(history, "%03d-task.md" % n), report])
    found = sorted({int(x) for m in FIXES.finditer(text) for x in re.findall(r"\d{3}", m.group(1)) if int(x) < n})
    if found:
        return tuple(found)
    m = CORRECTION.search(t["title"])
    for x in re.finditer(r"\b(\d{3})\b", t["title"][m.start():]):
        if int(x.group(1)) < n:
            return (int(x.group(1)),)
    return (previous,) if previous is not None else (n - 1,)


def analyse(tasks, rows, history=None):
    """-> (rejected on first pass, bugs cited). `history`: force one history folder (tests); default:
    pipeline/history next to each task's log folder."""
    by_file = {(r["dir"], r["f"]): r for r in rows}
    passes = collections.defaultdict(lambda: collections.defaultdict(list))  # dir -> tag -> [file]
    for r in rows:
        if r["role"] == "reviewer" and r.get("tag") and r["tag"].isdigit():
            passes[r["dir"]][int(r["tag"])].append(r["f"])
    per_dir = collections.defaultdict(list)
    for n in sorted(tasks):
        per_dir[tasks[n]["dir"]].append(n)
    for t in tasks.values():
        later = sorted(k for k in passes[t["dir"]] if k > t["n"])
        nexts = [k for k in per_dir[t["dir"]] if k > t["n"]]
        t["judge"] = later[0] if later else (nexts[0] if nexts else t["n"] + 1)  # n+1: not run yet / single duo
        h = history or history_of(t)
        t["correction"] = bool(CORRECTION.search(t["title"]))
        earlier = [k for k in per_dir[t["dir"]] if k < t["n"]]
        t["targets"] = targets(t, h, earlier[-1] if earlier else None) if t["correction"] else ()
        files = t["coders"] + (passes[t["dir"]].get(t["judge"], []) if t["judge"] is not None else [])
        rs = [by_file.get((t["dir"], f)) for f in files]
        ok = [r for r in rs if r and not r.get("err")]
        t["unknown"] = len(ok) < len(rs) or not rs
        t["cost"] = sum(r["cost"] for r in ok)
        t["dur"] = sum(r["dur"] or 0 for r in ok) / 60000.0
        t["known"] = bool(ok) and not t["unknown"] and all(r.get("dur") is not None for r in ok)

    def root_of(n, seen=()):
        c = tasks.get(n)
        while c and c["correction"] and c["targets"] and c["n"] not in seen:
            seen += (c["n"],)
            c = tasks.get(c["targets"][0])
        return c["n"] if c else n

    rejected, bugs = set(), set()
    verdicts = {n: verdict(t, history or history_of(t)) for n, t in tasks.items()}
    for t in tasks.values():
        if not t["correction"]:
            continue
        for c in t["targets"]:
            r = root_of(c)
            bugs.add(r)
            m = REJECTED_TITLE.search(t["title"])
            if verdicts.get(c) is None and m and t["n"] not in MANUAL_CITATIONS and int(m.group(1)) == c:
                rejected.add(r)
    rejected |= {n for n, v in verdicts.items() if v == "REJECT"}
    return rejected, bugs


def med(v):
    return statistics.median(v) if v else None


def fmt(x, u):
    return "?" if x is None else ("%.2f $" % x if u == "$" else "%d min" % round(x))


def table(tasks, rejected, bugs):
    dom = collections.defaultdict(list)
    for t in tasks:
        dom[t["dom"] or "?"].append(t)
    out = ["| Domain | Tasks | Not corrections | Rejected 1st pass | Accepted 1st pass | Bugs cited | Median cost "
           "| Median time | Total | Corrections |", "|" + "---|" * 10]

    def line(name, L):
        nc = [t for t in L if not t["correction"]]
        rj = sum(t["n"] in rejected for t in nc)
        bg = sum(t["n"] in bugs for t in nc)
        cs = [t["cost"] for t in L if t["known"]]
        ds = [t["dur"] for t in L if t["known"]]
        unk = sum(not t["known"] for t in L)
        tot = "%s%s" % (fmt(sum(cs), "$"), " (+%d unknown)" % unk if unk else "")
        return "| %s | %d | %d | %d | %d/%d | %d | %s | %s | %s | %d |" % (
            name, len(L), len(nc), rj, len(nc) - rj, len(nc), bg, fmt(med(cs), "$"), fmt(med(ds), "min"), tot,
            len(L) - len(nc))

    for d in sorted(dom, key=lambda d: -len(dom[d])):
        out.append(line(d, dom[d]))
    out.append(line("**Total**", tasks))
    return out


def main(argv, folders):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if isinstance(folders, pathlib.Path):
        folders = [folders]
    since = argv[argv.index("--since") + 1] if "--since" in argv else "000000"
    a, b = 0, 10 ** 9
    if "--tasks" in argv:
        a, b = (int(x) for x in argv[argv.index("--tasks") + 1].split("-"))
    tasks = read_all(folders)
    rows, _, _ = agg_logs.calls(folders)
    rejected, bugs = analyse(tasks, rows)
    sel = [t for _, t in sorted(tasks.items()) if a <= t["n"] <= b and t["day"] >= since]
    if not sel:
        print("LOOP : no task in the selection")
        return 0
    print("\n".join(table(sel, rejected, bugs)))
    nc = [t for t in sel if not t["correction"]]
    rj = sum(t["n"] in rejected for t in nc)
    after = sum(t["n"] in bugs and t["n"] not in rejected for t in nc)
    cs = [t["cost"] for t in sel if t["known"]]
    ds = [t["dur"] for t in sel if t["known"]]
    cor = [t for t in sel if t["correction"]]
    cc = sum(t["cost"] for t in cor if t["known"])
    tot = sum(cs)
    print("\nTasks %d-%d : %d, of which %d corrections ; bugs cited : %s"
          % (sel[0]["n"], sel[-1]["n"], len(sel), len(cor), ", ".join(str(n) for n in sorted(bugs) if a <= n <= b) or "none"))
    if nc:
        print("Three key numbers: %d %% accepted on first pass (%d/%d ; %d %%, %d/%d, counting the %d bugs found "
              "after acceptance) ; median cost %s and median time %s per task ; %d corrections, %s (%d %% of the total)."
              % (round(100 * (len(nc) - rj) / len(nc)), len(nc) - rj, len(nc),
                 round(100 * (len(nc) - rj - after) / len(nc)), len(nc) - rj - after, len(nc), after,
                 fmt(med(cs), "$"), fmt(med(ds), "min"), len(cor), fmt(cc, "$"), round(100 * cc / tot) if tot else 0))
    unk = [t["n"] for t in sel if not t["known"]]
    if unk:
        print("Cost or time unknown (log missing, no final JSON, or judging pass not written yet): %s"
              % ", ".join(str(n) for n in unk))
    return 0


if __name__ == "__main__":
    sys.exit(agg_logs.main(sys.argv[1:] + ["--loop"]))
