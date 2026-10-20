# -*- coding: utf-8 -*-
# WHO grows the context: attributes the token growth to tool results, per category.
#   python tools/costs/transcripts.py                 -> every session of this repository
#   python tools/costs/transcripts.py --n 30          -> the 30 most recent transcripts
#   python tools/costs/transcripts.py --dir <folder>  -> another transcripts folder (e.g. a second duo's worktree)
# Reads the CLI transcripts (~/.claude/projects/<repo-path-as-slug>/*.jsonl), read only.
# For each model call the context grows by delta; the delta is shared between the tool results that
# arrived since the previous call, in proportion to their characters.
# "reread" = what a result costs afterwards, read again at every later call of the session.
# This is what showed: full-size images, big plan files read again and again, bench logs dumped whole.
import collections
import json
import os
import pathlib
import re
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from project import ROOT  # noqa: E402

FOLDER = pathlib.Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(ROOT))
CODE_EXT = (".py", ".rs", ".cpp", ".c", ".h", ".hpp", ".cs", ".js", ".ts", ".tsx", ".go", ".java", ".kt",
            ".swift", ".gd", ".lua", ".ps1", ".sh")


def program(cmd):
    """The program a shell command runs: skips `cd x &&`, `VAR=value` and `export` (noise, not a cost)."""
    for seg in re.split(r"&&|\|\||;|\|", cmd):
        words = [w for w in seg.strip().split() if not re.match(r"^[A-Za-z_]\w*=", w)]
        if not words or words[0] in ("cd", "export", "set", "Set-Location"):
            continue
        return os.path.basename(words[0].strip("\"'").replace("\\", "/")) or "?"
    return "?"


def category(name, inp):
    if name == "Read":
        p = (inp.get("file_path") or "").replace("\\", "/").lower()
        if p.endswith((".png", ".jpg", ".jpeg", ".webp")):
            return "Read image"
        for k in ("plan.md", "state.md", "decisions.md", "questions.md", "claude.md"):
            if p.endswith(k):
                return "Read " + k
        if "/pipeline/" in p:
            return "Read pipeline"
        if p.endswith(".log"):
            return "Read log"
        if "/.claude/skills/" in p:
            return "Read skill"
        if p.endswith(CODE_EXT):
            return "Read code"
        return "Read other"
    if name in ("Bash", "PowerShell"):
        c = (inp.get("command") or "").strip()
        if c.startswith("git"):
            return "git " + (c.split() + ["?"])[1]
        if "bin/benches" in c or "bin\\benches" in c:
            return "shell -> bench"
        return "shell -> " + program(c)
    if name.startswith("mcp__"):
        return "MCP " + name.split("__")[1]
    return name


def analyse(path):
    calls, seen, tools, pending, events = [], {}, {}, [], []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            j = json.loads(line)
        except ValueError:
            continue
        m, t = j.get("message") or {}, j.get("type")
        if t == "assistant":
            for c in m.get("content") or []:
                if c.get("type") == "tool_use":
                    tools[c["id"]] = (c["name"], c.get("input") or {})
            mid, u = m.get("id"), m.get("usage") or {}
            if mid and mid not in seen:
                seen[mid] = len(calls)
                calls.append([u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                              + u.get("cache_creation_input_tokens", 0), u.get("output_tokens", 0)])
                events += [(len(calls) - 1, c, n) for c, n in pending]
                pending = []
        elif t == "user":
            cont = m.get("content")
            if isinstance(cont, str):
                pending.append(("prompt", len(cont)))
                continue
            for c in cont or []:
                if c.get("type") == "tool_result":
                    name, inp = tools.get(c.get("tool_use_id"), ("?", {}))
                    cc = c.get("content")
                    n = len(cc) if isinstance(cc, str) else sum(
                        len(x.get("text", "")) if x.get("type") == "text" else 5000 for x in (cc or []))
                    pending.append((category(name, inp), n))
    if not calls:
        return None
    N, new, reread = len(calls), collections.Counter(), collections.Counter()
    new["(system + tools + 1st prompt)"] += calls[0][0]
    reread["(system + tools + 1st prompt)"] += calls[0][0] * (N - 1)
    park = collections.defaultdict(list)
    for k, c, n in events:
        park[k].append((c, n))
    for k in range(1, N):
        delta = calls[k][0] - calls[k - 1][0] - calls[k - 1][1]
        if delta < 0:
            continue   # compaction
        ev = park.get(k) or [("(output / thinking)", 1)]
        tot = sum(n for _, n in ev) or 1
        for c, n in ev:
            new[c] += delta * n / tot
            reread[c] += delta * n / tot * (N - 1 - k)
    return N, calls[0][0], new, reread


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    folder = pathlib.Path(sys.argv[sys.argv.index("--dir") + 1]) if "--dir" in sys.argv else FOLDER
    if not folder.is_dir():
        print("TRANSCRIPTS : no folder %s" % folder)
        return 0
    files = sorted(folder.glob("*.jsonl"), key=os.path.getmtime)
    if "--n" in sys.argv:
        files = files[-int(sys.argv[sys.argv.index("--n") + 1]):]
    TN, TR, firsts, ns = collections.Counter(), collections.Counter(), [], []
    for f in files:
        a = analyse(f)
        if a:
            ns.append(a[0])
            firsts.append(a[1])
            TN.update(a[2])
            TR.update(a[3])
    if not ns:
        print("TRANSCRIPTS : nothing to analyse")
        return 0
    sn, sr = sum(TN.values()) or 1, sum(TR.values()) or 1
    print("%d session(s) ; calls med %d ; context at 1st call med %s tokens" % (
        len(ns), statistics.median(ns), "{:,}".format(int(statistics.median(firsts)))))
    print("%-34s %14s %6s %16s %7s" % ("category", "new tokens", "%", "reread tokens", "%"))
    for c, v in TN.most_common(25):
        print("%-34s %14s %5.1f%% %16s %6.1f%%" % (c, "{:,}".format(int(v)), 100 * v / sn,
                                                  "{:,}".format(int(TR[c])), 100 * TR[c] / sr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
