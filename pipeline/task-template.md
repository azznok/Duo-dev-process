TASK: <nnn> — [M0-01] <short title>
DOMAINS: code
MODEL: default
PROCESS: none
LOAD: none
WALKTHROUGH: none
BACKLOG: docs/backlog/M0-foundations.md § M0-01 (criteria covered: all | 1, 3, 4)

## Context
Why this task, links to the docs (e.g. docs/ROADMAP.md § M0). Previous verdict to fix, if any ("fixes NNN").

## Goal
What must exist at the end, in one or two sentences.

## What is (checked by the reviewer at HEAD <short sha>, do not re-check)
- Established facts useful to the task: existing APIs, files to touch, known traps (<= 8 lines).

## Do not
- What is out of the task or already decided otherwise (ADR), in 1 to 4 lines.

## Acceptance criteria (checkable)
- [ ] <command / test / scenario> gives <expected output>.
- [ ] ... (taken from the backlog entry, or this task's part of it)

## Modules touched
<main module>, ...

## Out of scope
What the task does NOT do (and which entry will).

## Docs to update
README.md of the touched modules; a file docs/adr/NNNN-<slug>.md if a decision is taken.

TIMEBOX: 2 h (at most; bigger = cut in advance)
FALLBACK: what we deliver if the box expires (always a state that builds and whose tests pass).

PROOFS:
- checks: the gate commands (result lines in the report).
- images: `<screenshot command> --out proofs/<nnn>/<x>.png`, next to `tests/golden/<x>.png` | none
- art-judge: proofs/<nnn>/<x>.png | docs/art/refs/<...>.png   (one line per element that has a reference)
- scenario: `<scenario command> scenarios/<x>` -> exit 0 (drives the product through its commands).

<!--
First line starts with "TASK:" (read by the harness); "TASK: NONE" = nothing to do.
DOMAINS: one or more of code | ui | visual | feel | gameplay | data | network | build | 3d | audio | docs.
  Skills: table in CLAUDE.md. MCP: none, except 3d = Blender + Meshy.
MODEL: default (new production code) | mid (docs, data, tooling, build, renaming, goldens, process review)
  | small (one line, one value) | top (identified hard trap). Escalation after a rejection: docs/HARNESS.md.
PROCESS: none | skill <name> to create | skill <name> to update.
LOAD: none | add <action or system> to the milestone load profile and its invariant (if the project has one).
WALKTHROUGH: none | add <step> to the automatic walkthrough (as soon as something playable/usable and visible).
DUO: <name> — only with several duos, under DOMAINS.
PROOFS stays LAST: the harness looks for "images:" to give the next reviewer the visual model.
Size: <= 4 KB. The coder reads a task, not a novel.
-->
