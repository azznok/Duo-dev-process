# Token economy — why the harness is built this way

> WRITTEN BY: the Duo-dev-process template (then the process reviews). BUDGET: 150 lines.

This template comes from two real projects run by agent duos (an Unreal game, then a custom-engine game run
by two duos for ~650 tasks). Every rule below answers a **measured** cost or a real incident. Figures are
API-equivalent dollars from the projects' logs (`tools/costs/agg_logs.py`, `tools/costs/loop.py`).

## Orders of magnitude (first project)

297 reviewer passes ≈ $1,126; 2,230 coder calls ≈ $6,517. In the second project, at one point the reviewer
cost as much as the coder ($1,487 vs $1,612) and the cost per task rose from ~$9 to ~$15 before the fixes
of the "reviewer" and "task size" sections. The lesson: **the expensive part is re-reading context**, not
writing code. Every rule here removes re-reading.

## The coder

| Measured | Rule |
|---|---|
| Resuming the same session forever: **237k tokens of context per call** on average; a cold start ≈ **66k**. | A FRESH session per task. `--resume` only for the SAME task (API error, quota, relaunch), and only within `RESUME_MAX_H`. |
| **245 nudges out of 259** only got "DONE" back, each re-reading ~300k tokens. | No nudge if `report.md` exists; `MAX_NUDGES=1`. |
| A 12-min bench killed at 2 min 20: the agent ended its turn "waiting" for a background job. | Rule in the prompt and RULES §5; the harness reads the live benches registry and says "wait for X" instead of killing. |
| The coder ran the full test suite several times per task while the other duo compiled. | The coder runs only the tests touched by its diff; the **gate** runs the full suite ONCE after it, under a shared lock. |
| MCP servers (editor bridge, Blender, Meshy) loaded on every call, even for pure code. Their tool definitions are re-read at EVERY call. | **MCP à la carte**: the task's `DOMAINS` line picks the servers (`MCP_BY_DOMAIN`), `--strict-mcp-config`. |
| 21 generic "course" skills: their list alone ≈ 6,000 tokens per call. | Thin project skills only (<= 150 lines, clear "when / when not"), grown by the duo when a procedure repeats. |
| A model too big for doc/data tasks (the cheaper line had been used 10 times in 117 tasks). | `MODEL` line per task: `mid` for docs, data, tooling, goldens; `small` for one value; `default` for new production code; `top` for identified hard traps. Escalation is automatic after a rejection, never "to be safe". |

## The reviewer

| Measured | Rule |
|---|---|
| The reviewer re-read task, report, git, plan by itself: 34 turns median; and kept an owner's answer "already read" **for 4 hours**. | `run-reviewer.ps1` builds a **judgment packet** in the prompt: task, report, commits, bounded diff (`DIFF_MAX_LINES`), gate, thumbnails, PLAN, STATE, QUESTIONS, TASTE, the milestone's roadmap section and backlog, and the **DIFF** of PLAN and of the owner's box as soon as their fingerprint changes. |
| Reviewer on the most expensive model, high effort, for everything: **54 % of the total cost** without coding. | Default model, medium effort; the escalation model ONLY to judge an image. Planning and post-rejection passes stay on the default. |
| A too-broad regex escalated 19 passes out of 21 (it matched "images: none"). | Escalation reads the `- images:` line exactly; a process proposal left unwired two reviews in a row becomes a mandatory harness task. |
| **105 refused tool turns** (git, ls); skills and plugins loaded for nothing. | No MCP (`--strict-mcp-config`), no skill (`--disable-slash-commands`), project settings only, reduced tools, a wide read-only git allowlist, one git command per call. |
| The reviewer judged tests on the report's word (it has no build tools). | The **gate** is run by the harness after the coder (`pipeline/gate.md`); a KO there is a rejection. |
| Median task 9.7 min for a 2 h timebox, while a reviewer pass costs ~4 min and ~$2.6 fixed. | Tasks of **30-60 min** (2-3 related entries grouped), **2 h at most** (agent reliability drops beyond). |
| Task files grew to novels; the coder re-read them on every call. | `task.md` <= 4 KB with "What is" (facts already checked) and "Do not"; `report.md` <= 3 KB. |
| The reviewer SAW the visual gaps but forgave them (it had read the coder's excuses first). | The **blind judge**: a separate call that sees only capture + reference (no task, no report, no code), runs in a temp folder with Read only. Then "make it exist first": its gaps are an opinion that feeds a polish list, not a veto. |

## Sleeping and waiting

| Measured | Rule |
|---|---|
| **26 "TASK: NONE" passes = $63** to repeat that there was nothing to do. | Idle loop without a model: fingerprints of HEAD, PLAN, owner's box and lane every `POLL_IDLE_S`; the reviewer runs again only on a change. And "nothing to do" is almost always false: a question blocks ONE task, its default is never "do nothing". |
| A usage limit closed a model "5 h from discovery" instead of from the real reset: up to ~4 h lost. | Quota memory per model (`.state/quota.txt`) set to the announced reset (+ margin), else a probe every `QUOTA_PROBE_MIN`; every role switches to the next model of its chain. |
| "Not logged in" retried 19 times x 90 s. | One central failure classifier: `auth` -> FATAL (exit 3) at once; `quota` -> switch/sleep; `api` -> exponential backoff 60 -> 900 s. |
| The supervisor session, long and compacted, lost context and re-read everything. | `supervisor/HANDOFF.md`: a fresh supervisor session regularly, starting from that file. The watcher (`watch.sh`) follows the logs **without any model call**. |

## Benchmarks and long checks

| Measured | Rule |
|---|---|
| Benchmarks at each task: a gate of 18 to 60 min, and two false KOs (measured while the other duo compiled). | No benchmark per task. At the **end of a milestone**, machine at rest: all benches against the previous milestone end, then the load test. |
| A load test with seeded actions found on its FIRST run a bug that 37 hand-written scenarios never touched. | One seeded load test as soon as there are several systems; its failures replay by seed; an invariant is never weakened to make it green. |

## Two duos

| Measured | Rule |
|---|---|
| ~8 blocked merges in 3 days on the same shared files; 9 more caused by shared state/owner pages. | Lanes and zones (disjoint by construction, checked by `tools/lanes.py`); one ADR = one file with a generated index; state and owner pages split per duo; mechanical conflicts (generated index, pure concurrent appends) solved by the harness alone. |
| A merge blocked = a stopped duo until a human came. | The orchestrator calls a **mediator** (model chosen by incident type: cheap for operations, strong for code conflicts) under strict guards (forbidden paths, full gate before committing a code resolution). |
| Two duos compiling at once doubled task time (~2 h 30 vs ~1 h 15). | The gate's heavy commands wait for the other duo's build (`HEAVY_PROCESS_REGEX`) and run under a shared `suite` lock. |

## Documents

| Measured | Rule |
|---|---|
| Lessons piled up in script comments and an 800 KB journal; prompts and plans grew without limit. | Every process doc has a WRITER and a BUDGET; over budget -> split, verbatim archive; `docs/journal/` never loaded; `STATE` and `QUESTIONS` keep only what is open. |
| Full-size PNGs read and re-read on every following call. | Thumbnails <= 1280 px (`tools/image/vignette.py`); the reviewer gets thumbnail paths. |
| Chatty benches on stdout (re-read by the agent). | One verdict line on stdout; details in `logs/benches/`. |

## Measuring it on your project

At each milestone end or ~15 tasks, the process review (skill `build-release`): `python tools/costs/agg_logs.py`
(cost per role, biggest consumers), `python tools/costs/loop.py` (first-pass acceptance, median duration and
cost per task, bugs found later, per domain), `python tools/costs/budgets.py` (docs over budget). Write 3-5
lines in `docs/STATE.md`, and generic lessons in `docs/UPSTREAM.md` for this template.
