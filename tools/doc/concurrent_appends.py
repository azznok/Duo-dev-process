"""Resolve a merge conflict made only of concurrent additions.

Two duos append backlog entries at the same spot (just before "## End of M5"), so git sees a
conflict although nothing was overwritten. Without this, the harness set the task aside and a human
had to paste two blocks one after the other. Given a file in diff3 conflict style
(`git checkout --conflict=diff3 -- <file>`), this keeps OUR lines then THEIR lines in every hunk,
separated by a blank line, but only if every hunk has an EMPTY base (pure additions on both sides).
Otherwise the file is left untouched and the exit code is 1 (a human or the mediator decides).

    python tools/doc/concurrent_appends.py <file>    # 0 = resolved and rewritten, 1 = left as is
"""

import sys
from pathlib import Path


def resolve(text: str):
    """Return the resolved text, or None if a hunk is not a pure concurrent addition."""
    out, ours, base, theirs = [], [], [], []
    state = None  # None, "ours", "base", "theirs"
    hunks = 0
    for line in text.splitlines(keepends=True):
        bare = line.rstrip("\r\n")
        if state is None and bare.startswith("<<<<<<< "):
            state, ours, base, theirs = "ours", [], [], []
        elif state == "ours" and bare.startswith("||||||| "):
            state = "base"
        elif state in ("ours", "base") and bare == "=======":
            if state == "ours":
                return None  # no base section: not diff3 style, cannot tell an addition from an edit
            state = "theirs"
        elif state == "theirs" and bare.startswith(">>>>>>> "):
            if any(b.strip() for b in base):
                return None  # both sides changed existing lines: a real conflict
            out.extend(ours)
            if ours and theirs and ours[-1].strip() and theirs[0].strip():
                out.append("\r\n" if ours[-1].endswith("\r\n") else "\n")
            out.extend(theirs)
            hunks += 1
            state = None
        elif state == "ours":
            ours.append(line)
        elif state == "base":
            base.append(line)
        elif state == "theirs":
            theirs.append(line)
        else:
            out.append(line)
    if state is not None or hunks == 0:
        return None
    return "".join(out)


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path = Path(argv[1])
    raw = path.read_bytes().decode("utf-8")
    resolved = resolve(raw)
    if resolved is None:
        return 1
    path.write_bytes(resolved.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
