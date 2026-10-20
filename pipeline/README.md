# The duo's pipeline

> WRITTEN BY: the Duo-dev-process template. BUDGET: 60 lines. This folder is the thread between the two
> agents.

Two models, two roles, never at the same time in one duo (a single driver of the working copy at a time):

- **The reviewer** (`bin/harness/run-reviewer.ps1`) = architect + reviewer. Judges the previous task on its
  PROOFS and writes the next one from `docs/PLAN.md` and the current milestone's backlog. No MCP, no skill,
  read-only tools except its few files.
- **The coder** (`bin/harness/run-coder.ps1`) = implementer + QA. Does THE task, tests first, proves it,
  commits it, writes its report and stops. A fresh session for each task.

## The files

| File | Written by | Tracked by git |
|---|---|---|
| `task.md` | reviewer (format: `task-template.md`) | no (state) |
| `report.md` | coder (format: `report-template.md`) | no (state) |
| `review.md` | reviewer (verdict, 1st line `VERDICT: ACCEPT`/`REJECT`) | no |
| `gate.md` | harness (checks run after the coder) | no |
| `owner.md` | supervisor (owner's answers, dated) | **yes** |
| `lane.txt` | orchestrator (multi-duo: this duo's lane) | no |
| `bench.md`, `load.md`, `mediation.md`, `blind-judge.md` | harness | no |
| `task-template.md`, `report-template.md` | template | yes |
| `base.txt`, `.n`, `.hashes`, `.in_progress`, `.snapshots/` | harness | no |
| `history/` | harness (everything, numbered) | no |

No `task.md` at the start: the reviewer's first pass chooses the first task (usually: write the M0 backlog).

## The cycle

1. The reviewer reads the judgment packet (built by `run-reviewer.ps1`: task, report, commits, bounded diff,
   gate, thumbnails, blind judge, PLAN, STATE, QUESTIONS, TASTE, the milestone's ROADMAP section and backlog,
   diffs of PLAN and of the owner's box), writes `review.md` then `task.md`. Nothing can move without the
   owner: `TASK: NONE` and a question in `docs/QUESTIONS.md`; the harness sleeps.
2. The harness merges an accepted branch, creates the next `task/<nnn>-<entry>` branch.
3. The coder takes the lock, writes `.in_progress`, does the task, writes `report.md`.
4. The harness runs the gate (`gate.md`) and the background benches/load, then back to 1. A task never tried
   (no `.in_progress`) goes straight back to the coder.

## Waking up after `TASK: NONE`

The duo loop compares every `POLL_IDLE_S` seconds the fingerprints of `docs/PLAN.md`, `pipeline/owner.md`,
`pipeline/lane.txt` and HEAD with those of the last pass (`.hashes`). A change relaunches the reviewer, who
receives the full DIFF: an owner's answer is never "already read".

## Answering as the owner

Talk to the supervisor, or write yourself a dated line at the end of `pipeline/owner.md`.

## Exit codes

`0` ok · `2` infrastructure (retried) · `3` FATAL, login lost (`claude /login`) or merge blocked · `4` another
coder session is alive (the task waits) · `5` quota closed on every model (sleep until the remembered
reopening) · `10` `TASK: NONE`.
