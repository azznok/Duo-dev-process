# Workflow of the agents

> WRITTEN BY: the Duo-dev-process template (the owner may adapt it). BUDGET: 130 lines.

## Roles

| Role | Responsibility | Held by |
|---|---|---|
| **Owner** (director) | vision, priorities, playtests, milestone validation, answers to questions | the human |
| **Supervisor** | relays the owner, writes their decisions, watches the duos | interactive Claude session |
| **Architect** | cuts a milestone into tasks, keeps `docs/` and the ADRs, defines interfaces before they are filled | the reviewer |
| **Reviewer** | judges each task on its proofs with the checklist below; never reviews its own code | the reviewer |
| **Implementer** | does **one** task on its branch, tests included | the coder |
| **Tester / QA** | writes scenarios, input scripts and reference images; hunts regressions | the coder |

One agent never holds two roles of the same task. A duo = one reviewer + one coder, one task at a time.

## Parallelism without conflicts

- One task = one branch = one duo. Two duos at most, each in its own git worktree, on **disjoint lanes**:
  every backlog entry declares `**Lane**` and `**Zones**` (modules, data folders, docs it writes); two lanes
  never share a zone (`python tools/lanes.py --milestone Mn` checks it). The orchestrator gives each duo a
  ready lane.
- Interfaces between modules (types, traits, APIs) are defined by the architect **before** parallel work.
- Shared counters (task numbers, ADR numbers) live in the git common dir: duos never collide.
- Files two duos would both write are split per duo: `docs/STATE-<duo>.md`, `docs/OWNER-<duo>.md`; ADRs are
  one file each; the ADR index is generated.

## Task format

See `pipeline/task-template.md`. In short: first line `TASK: <nnn> — [M1-03] <title>`, then `DOMAINS`,
`MODEL`, `PROCESS`, `LOAD`, `WALKTHROUGH`, `BACKLOG`; sections Context, Goal, What is (facts checked by the
reviewer), Do not, Acceptance criteria (checkable), Modules touched, Out of scope, Docs to update;
`TIMEBOX` (2 h at most), `FALLBACK`; `PROOFS` last. 4 KB at most.

## Definition of done

- [ ] All acceptance criteria checked, with proofs (test output, captures, scenarios, measures).
- [ ] The gate is green (run by the harness, not declared by the coder).
- [ ] Performance budgets respected.
- [ ] A capture next to its reference if anything visible changed.
- [ ] Docs and module READMEs up to date; an ADR if an architecture decision was taken.
- [ ] No tuning value hard-coded; no user action outside the product's command path.
- [ ] Load profile / walkthrough step added if the task added a feature (when the project has them).

## Reviewer checklist

1. Does the task do **one thing**? Reasonable size?
2. `docs/PROJECT-RULES.md` respected?
3. Do the tests really check the behaviour (not only that it compiles)? Was a test weakened?
4. Is the dependency graph between modules respected?
5. Are errors handled?
6. Do the attached captures show the expected result, next to their reference?
7. **Deep review whatever the diff size** as soon as the task touches: a reference hash or a golden image,
   the order of the simulation steps, state hashing, a new module or a new edge between modules, a
   dependency. A check that could not run is written "not run: <reason>", never "passed".
8. **Protected files**: `tests/golden/`, reference hashes, an existing ADR change in a SEPARATE commit whose
   report says why the old value was wrong or which behaviour changed (with an ADR). A reference changed
   without that line: rejection.
9. **Recurring defects** of previous passes (the reviewer appends one real case or ADR per line and re-reads
   this list each pass):
   - a green test or a measure presented as a visual proof (`docs/RULES.md` §1);
   - a teleport or a console command instead of the gesture to prove;
   - a reference constant "repaired" to make a test pass instead of an ADR;
   - a declared build target/bench without its file, breaking every build of the module.

## Escalation to the owner

An agent stops and asks when:
- the task contradicts the docs or a project rule;
- a choice changes the feel of the product (speed, difficulty, look, wording);
- a major dependency must be added or upgraded;
- a performance budget looks impossible to hold;
- two valid approaches exist with lasting consequences.
Every question has options, a proposed one, and a **default if silence** that does not stop the duo.

## Milestone end

1. The architect checks every acceptance criterion of the milestone.
2. A playable/usable build is produced for the owner (skill `build-release`).
3. The owner plays/uses it -> feedback becomes priority tasks. The next milestone starts without waiting
   for this playtest (continuous development).
4. `docs/ROADMAP.md` status and ADRs updated.
5. End-of-milestone gate, run by the harness with the machine at rest, in this order: **benchmarks** (all,
   against the previous milestone end), then the **load test** (if the project has one: every feature of the
   milestone covered, budgets held, no invariant broken), then the **automatic walkthrough** (if any). All
   green: next milestone. A KO: priority fixes, then an "End of Mn (re-test)" task, and only then the next
   milestone. No benchmark at each task.

## Pipeline (how the duo talks)

The thread between the two agents is `pipeline/` (`pipeline/README.md`). The harness that runs them:
`docs/HARNESS.md`. What it costs and why it is built this way: `docs/TOKEN-ECONOMY.md`.
