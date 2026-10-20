# The harness — how the duos run

> WRITTEN BY: the Duo-dev-process template. BUDGET: 170 lines. Changing `bin/harness/` is an owner decision.

## The pieces

```
 owner ──talks──> SUPERVISOR (interactive Claude session)
                    │ writes pipeline/owner.md, ADRs, PLAN      ▲ supervisor/watch.sh (no model)
                    │ launches                                   │ tails logs/harness-*.log
                    ▼                                            │
 ORCHESTRATOR (bin/harness/orchestrator.ps1, no model, a round every 5 min)
   │ reads config/duos.txt, creates worktrees, gives each duo a LANE (tools/lanes.py)
   │ relaunches a dead duo, watches journals and disk, calls the MEDIATOR on an incident
   ├──> DUO A  (repo folder)         bin/harness/duo.ps1 : reviewer -> coder -> reviewer -> ...
   └──> DUO B  (../<project>-b)      same loop, its own worktree, branch, build folder, lane
          │
          ├─ run-reviewer.ps1 : judgment packet -> claude -p (reviewer prompt) -> review.md + task.md
          │      blind judge (lib/judge.ps1): separate call, sees only capture + reference
          │      ACCEPT -> merge task/<nnn> into main (lib/branches.ps1) ; new branch for the next task
          ├─ run-coder.ps1    : claude -p (coder prompt + task) -> commits + report.md
          │      self-judge.ps1 (the coder's own blind check, 2 tries max)
          └─ gate (lib/gate.ps1): GATE_CMDS + fixed checks -> pipeline/gate.md (read by the next reviewer)
```

Everything without a model (orchestrator rounds, duo loop, idle sleep, watcher, gate) costs nothing. Models
are called only for: a reviewer pass, a coder session, a blind judgment, a mediation.

## One task, end to end

1. **Reviewer pass** (`run-reviewer.ps1`). Builds the packet (see `docs/TOKEN-ECONOMY.md`), runs the blind
   judge if the task has `- art-judge:` lines, calls the reviewer. It writes `pipeline/review.md` (verdict)
   and `pipeline/task.md` (next task). The harness then: archives everything in `pipeline/history/`, merges
   the judged branch on `ACCEPT` (with `--no-ff`, under the shared `merge` lock, after syncing `origin/main`),
   counts rejections (circuit breaker), creates `task/<nnn>-<entry>` for the new task, records fingerprints.
2. **Coder session** (`run-coder.ps1`). Takes the coder lock (and refuses if another coder acted < 20 min ago:
   heartbeat hook), writes `.in_progress`, picks the model from the `MODEL` line and the rejection count,
   writes the MCP subset for the task's `DOMAINS`, calls the coder. Then: waits for live benches, one nudge
   at most if no report, runs the **gate**, cleans up processes, starts background bench/load if configured.
3. **Gate** (`lib/gate.ps1`): every `GATE_CMDS` command (heavy ones wait for the other duo's build and take
   the shared `suite` lock), the harness lint, visual tests, then fixed checks: commit message format, no file
   > 10 MB entering git (LFS pointers pass), protected docs untouched, generated ADR index not edited, report
   size. It lists TOUCHED TESTS (modified/removed tests, removed assertions, added skips) for the reviewer to
   justify. At an `[End of Mn` task it also runs the milestone benches and load test.

## The duo loop (`duo.ps1`)

Reviewer then coder, forever, until a `STOP` file. A task written but never tried goes straight to the coder.
Exit codes drive it: `10` (TASK: NONE) -> **idle sleep** without a model until PLAN, owner's box, lane or HEAD
change; `5` (quota) -> sleep until the remembered reopening; `4` (another coder alive) -> wait 5 min; `3`
(FATAL) -> stop and notify; `2` -> exponential backoff. One notification when it pauses, one when it resumes.

## Models (config `config/project.env`)

| Role | Default | Escalation |
|---|---|---|
| Reviewer | `REVIEWER_MODEL`, effort `REVIEWER_EFFORT` | `REVIEWER_ESCALATION` / `REVIEWER_EFFORT_VISUAL` only to judge images |
| Coder | the task's `MODEL` tier: `top`=`MODEL_TOP`, `default`=`CODER_MODEL`, `mid`=`MODEL_MID`, `small`=`MODEL_SMALL` | 1 rejection: mid/small -> default, default -> `CODER_EFFORT_REJECTED`; 2 rejections: top |
| Blind judge / self-judge | `REVIEWER_ESCALATION` then `REVIEWER_MODEL`, effort `REVIEWER_EFFORT_VISUAL` | — |
| Mediator | operations: `MODEL_MID` medium (ESCALATE -> `CODER_MODEL` high); doc conflict: `CODER_MODEL` high; code conflict: `MODEL_TOP` high | — |

A credit or usage limit on one model: the call falls back to the next model of the role's chain
(`--fallback-model`), and the closed model is remembered until its announced reset (`.state/quota.txt`).

## Several duos

- `config/duos.txt`: one line per duo: `<name> <folder> <build-folder|-> <background-load yes|no>` (folders
  relative to the parent of the repo; `.` = the repo itself). The orchestrator creates missing worktrees
  (detached on `main`).
- **Lanes**: each backlog entry carries `**Lane**: <name>. **Zones**: <paths>.`. `tools/lanes.py` checks that
  two lanes share no zone and says which lanes are ready. The orchestrator writes each duo's
  `pipeline/lane.txt`; a duo without a ready lane sleeps for free. Special lanes: `single` (backlog not split
  yet: one duo, which splits it), `end` (the End-of-milestone task: first duo only, the other sleeps), `*`
  (invalid backlog: first duo fixes it). `PARALLEL_MILESTONE: Mn` in PLAN lets a duo start the next
  milestone's lanes early.
- Shared state lives in the git common dir (`<git-common-dir>/harness/`): locks (`merge`, `suite`,
  `counters`, `mediator`) and counters (task and ADR numbers). Per-worktree state is in `.state/`.
- Per-duo files: `docs/STATE-<duo>.md`, `docs/OWNER-<duo>.md`. ADRs: one file each, index generated on `main`
  after each merge. Mechanical conflicts (that index; pure concurrent appends in a backlog file) are solved by
  the harness.
- Each duo builds into its own folder (`HARNESS_BUILD_DIR`, and `BUILD_DIR_ENV` such as `CARGO_TARGET_DIR`):
  a binary from a shared folder may be the other duo's.

## The mediator (`mediator.ps1`)

Called by the orchestrator on: a blocked merge, a FATAL error, a task set aside, a duo dying 3 times in an
hour. It solves (resolves conflicts keeping BOTH sides; fixes a mechanical blocker) or asks the owner
(`docs/QUESTIONS.md` + notification). Guards: forbidden paths (`bin/harness/`, protected docs, secrets) cancel
everything; a code conflict resolution must pass the full gate before being committed; its resolution diff is
shown to the next reviewer of the duo (`pipeline/mediation.md`).

## Circuit breaker

`REJECT_MAX` rejections in a row on one branch: the reviewer is told to judge normally but, if it rejects
again, to ask the owner and choose another task; the harness then **sets the branch aside** (kept, not merged)
and goes back to `main`. The duo never loops forever on one task.

## Notifications (optional)

`NTFY_TOPIC` in the owner's User environment (never in a file) -> pushes to the phone via ntfy.sh: duo asleep
waiting for an answer, quota pause/resume, merge blocked, task set aside, milestone finished, mediator
question. Absent: nothing is sent. `FILE:<path>` writes them to a file (harness tests).

## Stack adapters (optional)

Most stacks need nothing: the coder builds and runs things itself, the gate runs `GATE_CMDS`. A stack with a
long-lived editor or emulator (Unreal/Godot editor bridge, Android emulator, a dev server) gets an adapter
`bin/harness/lib/stacks/<STACK>.ps1` (interface: `bin/harness/lib/stacks/README.md`): start it before the
coder, report its health to the doctor, give its MCP server to every coder call, kill it on `stop-all`.

## Testing the harness without spending

`bin/harness/test/` runs the whole loop with a **fake claude** (`fake-claude.ps1`) that plays scripted roles:
`powershell -File bin/harness/test/test-loop.ps1` (and test-two-duos, test-orchestrator, test-mediator,
test-judge, test-self-judge, test-models, test-shared, test-gate-size). Run them after any change to
`bin/harness/`. `bash bin/benches/harness_lint.sh` parses every script.

## Files and exit codes

State files and log names: `pipeline/README.md`. Exit codes: `0` ok, `2` infrastructure (retried), `3` FATAL
(login, merge blocked), `4` another session alive, `5` quota closed on every model, `10` TASK: NONE. Stop
files: `STOP` (one duo), `STOP-ALL` (orchestrator: STOP everywhere, then exit); delete them before relaunching.

## Requirements

Windows 10/11 with Windows PowerShell 5.1 (the harness is PowerShell), Git for Windows (Git Bash) + git-lfs,
Python 3.11+, the Claude Code CLI logged in. The PRODUCT can target any platform; only the harness is Windows.
