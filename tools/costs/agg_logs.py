# -*- coding: utf-8 -*-
# Cost and tokens of the duo's `claude -p` calls, read from the logs (read only, no model call).
#   python tools/costs/agg_logs.py                    -> summary per role, per day, most expensive calls
#   python tools/costs/agg_logs.py --since 261001     -> only the logs from that date (yyMMdd)
#   python tools/costs/agg_logs.py --since 261001-065247 -> from that time (yyMMdd-HHmmss)
#   python tools/costs/agg_logs.py --logs ../game-b/logs [--logs logs] -> read these log folders (repeatable);
#     default: the logs/ folder of every duo in config/duos.txt, else logs/ of this repo
#   python tools/costs/agg_logs.py --loop [--since yyMMdd] [--tasks a-b] -> the loop dashboard (loop.py)
# Reads the logs written by bin/harness (logs/<yyMMdd-HHmmss>-coder.log, -reviewer-NNN.log, -judge-NNN.log,
# -mediator-<duo>.log): each holds the final JSON of the CLI (cumulative session cost, tokens).
# The cost of a call = delta of the cumulative cost within the same session (resume), or the cost alone.
# Serves the "process review": where the money goes, who grows the context.
import collections
import json
import pathlib
import re
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from project import ROOT  # noqa: E402

NAME = re.compile(r"^(\d{6})-(\d{6})-(coder|reviewer|judge|mediator)(?:-([\w.-]+))?\.log$")
ROLES = ("reviewer", "coder", "judge", "mediator")


def load(p):
    raw = p.read_bytes()
    s = raw.decode("utf-16", "replace") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8-sig", "replace")
    s = s.replace("\x00", "")
    # stream-json: the result is the line type=result; plain json (older runs): the only object.
    for line in reversed(s.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                j = json.loads(line)
            except ValueError:
                continue
            if j.get("type") == "result" or ("type" not in j and "session_id" in j):
                return j
    return None


SKILL = re.compile(r'"name":"Skill","input":\{"skill":"([^"]+)"')
READ_SKILL = re.compile(r'"file_path":"[^"]*?skills[\\/]+([a-z0-9-]+)[\\/]+([^"]+?\.md)"')


def skills(p):
    """Skills loaded (Skill tool) and skill files read (Read) in a stream-json log."""
    s = p.read_bytes().decode("utf-8", "replace")
    return SKILL.findall(s), ["%s/%s" % (a, b.replace("\\\\", "/")) for a, b in READ_SKILL.findall(s)]


def end_context(u):
    it = (u or {}).get("iterations") or []
    if not it:
        return None
    x = it[-1]
    return x.get("input_tokens", 0) + x.get("cache_read_input_tokens", 0) + x.get("cache_creation_input_tokens", 0)


def calls(folders, since="000000"):
    """Reads the claude logs of `folders` (one Path or a list): (rows, skills loaded, skill files read)."""
    if isinstance(folders, pathlib.Path):
        folders = [folders]
    rows, cumul = [], {}
    used_skills, reads = collections.Counter(), collections.Counter()
    for folder in folders:
        for p in sorted(folder.glob("*.log")):
            m = NAME.match(p.name)
            if not m or "%s-%s" % (m.group(1), m.group(2)) < since:
                continue
            sk, rd = skills(p)
            used_skills.update((m.group(3), x) for x in sk)
            reads.update(rd)
            j = load(p)
            base = dict(f=p.name, dir=str(folder), day=m.group(1), role=m.group(3), tag=m.group(4))
            if not j:
                rows.append(dict(base, err=True, cost=0.0))
                continue
            u = j.get("usage") or {}
            sid, c = j.get("session_id"), j.get("total_cost_usd") or 0.0
            prev = cumul.get(sid)
            cost = c - prev if (prev is not None and c >= prev) else c
            cumul[sid] = c
            rows.append(dict(base, err=bool(j.get("is_error")), cost=cost,
                             turns=j.get("num_turns") or 0, cr=u.get("cache_read_input_tokens", 0),
                             cc=u.get("cache_creation_input_tokens", 0), out=u.get("output_tokens", 0),
                             ctx=end_context(u), models=sorted((j.get("modelUsage") or {}).keys()),
                             dur=j.get("duration_ms"), res=(j.get("result") or "")[:80].replace("\n", " ")))
    return rows, used_skills, reads


def duo_log_folders(root=None):
    """logs/ of every duo of config/duos.txt (`<name> <folder> <build> <load>`, folders relative to the
    PARENT of the main repo, `.` = the main repo); none listed -> logs/ of this repo."""
    root = root or ROOT
    f = root / "config" / "duos.txt"
    out = []
    if f.exists():
        for line in f.read_text(encoding="utf-8-sig").splitlines():
            parts = line.split("#", 1)[0].split()
            if len(parts) >= 2:
                d = root if parts[1] == "." else root.parent / parts[1]
                out.append(d / "logs")
    return out or [root / "logs"]


def log_folders(argv):
    """Every `--logs <folder>` (relative to the current folder), else the duos' log folders."""
    out = [pathlib.Path(argv[i + 1]) for i, a in enumerate(argv[:-1]) if a == "--logs"]
    return out or duo_log_folders()


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    argv = sys.argv[1:] if argv is None else argv
    folders = log_folders(argv)
    if "--loop" in argv:
        import loop
        return loop.main(argv, folders)
    since = argv[argv.index("--since") + 1] if "--since" in argv else "000000"
    rows, used_skills, reads = calls(folders, since)
    if not rows:
        print("COSTS : no claude log in %s" % ", ".join(str(f) for f in folders))
        return 0
    for role in ROLES:
        L = [r for r in rows if r["role"] == role and not r.get("err")]
        if not L:
            continue
        cs = [r["cost"] for r in L]
        ctx = [r["ctx"] for r in L if r.get("ctx")]
        print("=== %s : %d calls, %.2f $ (median %.2f, max %.2f) ; turns med %d ; end context med %s"
              % (role.upper(), len(L), sum(cs), statistics.median(cs), max(cs),
                 statistics.median(r["turns"] for r in L), "{:,}".format(int(statistics.median(ctx))) if ctx else "?"))
        print("    cache read %s, cache created %s, output %s tokens ; models %s" % (
            "{:,}".format(sum(r["cr"] for r in L)), "{:,}".format(sum(r["cc"] for r in L)),
            "{:,}".format(sum(r["out"] for r in L)),
            collections.Counter(m for r in L for m in r["models"]).most_common(3)))
    print("\nPer day (yyMMdd): calls, cost")
    per_day = collections.defaultdict(list)
    for r in rows:
        per_day[r["day"]].append(r)
    for d in sorted(per_day):
        L = per_day[d]
        print("  %s  reviewer %3d / coder %3d / judge %3d / mediator %3d  %8.2f $  errors %d" % (
            d, *(sum(r["role"] == x for r in L) for x in ROLES),
            sum(r["cost"] for r in L), sum(r.get("err", False) for r in L)))
    print("\nThe 10 most expensive calls")
    for r in sorted(rows, key=lambda r: -r["cost"])[:10]:
        print("  %-38s %6.2f $  turns %-4s ctx %s  %s" % (r["f"], r["cost"], r.get("turns"), r.get("ctx"), r.get("res", "")))
    cut = [r for r in rows if r.get("err") and "turns" not in r]
    if cut:
        # A killed call leaves no final JSON: its cost is unknown, never guessed.
        print("\nInterrupted calls, no final JSON (cost unknown, not counted): %d" % len(cut))
        for r in cut:
            print("  %s" % r["f"])
    if used_skills or reads:
        print("\nSkills loaded (role, skill): %s" % ", ".join("%s %s x%d" % (k[0], k[1], v) for k, v in used_skills.most_common()))
        print("Skill files read: %s" % ", ".join("%s x%d" % kv for kv in reads.most_common(12)))
    idle = [r for r in rows if r["role"] == "reviewer" and "TASK: NONE" in r.get("res", "")]
    if idle:
        print("\nReviewer passes ending on TASK: NONE: %d, %.2f $" % (len(idle), sum(r["cost"] for r in idle)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
