# Rules for the agents

> WRITTEN BY: the owner (project section, rules: validated) and the Duo-dev-process template (process). The
> duo proposes, it does not modify. BUDGET: 130 lines. Loaded at EVERY call with `docs/RULES.md`: every line
> here costs, everywhere.

This file applies to **every agent** working on this repo. If a task conflicts with this file, this file
wins; tell the human about the conflict.

@docs/RULES.md

## Who are you?

- Launched by the harness (`claude -p`, your prompt starts with "YOU ARE THE ..."): you are the reviewer, the
  coder, the mediator or the blind judge. Follow that prompt.
- An **interactive session with a human**: you are the **supervisor**. Read `supervisor/SUPERVISOR.md` first.
  If `config/project.env` is missing or does not say `ONBOARDED=1`, run `supervisor/ONBOARDING.md` before
  anything else.

## Project

> Filled at onboarding (`supervisor/ONBOARDING.md` phase 2). Until then: `<not onboarded>`.

- **Product**: `<one-sentence pitch>` (vision: `docs/VISION.md`, owner-only).
- **Stack**: `<language, framework, pinned version>` (skill `stack`).
- **Layout**: `<modules/folders and what they do; what must never depend on what>`.
- **Run it**: `<command>`. **Proof of what the user sees**: `<screenshot command>` (skill `proofs`).

## Language

- Documentation and talk with the owner: **`<owner's language>`**.
- Code, identifiers, comments, commit messages, code file names: **English**.

## Non-negotiable rules (summary of `docs/PROJECT-RULES.md`, owner-only)

1. **Everything is data.** Content and tuning values live in data files, never hard-coded.
2. **Headless first.** Every logic feature is testable without a window.
3. **Tested or nonexistent.** No feature without a test. Visible feature: a reference capture.
4. **Performance budgets.** Respect the budgets of `docs/PROJECT-RULES.md`; a regression > 10 % blocks.
5. **Platforms.** Nothing may break a target platform; OS-specific code only in modules made for it.
6. `<project rules added at onboarding: determinism, client/server split, accessibility...>`

## Code style

- The gate commands (`GATE_CMDS` in `config/project.env`) must pass: format, lint with warnings as errors,
  tests.
- Files under **400 lines**; beyond, split into modules.
- Pure logic modules do not depend on the UI/engine framework unless an ADR says why: they build fast and
  test easily.
- Typed errors; no panic/crash paths outside tests and initialisation.
- Every module has a short `README.md`: role, public API, invariants, what it must NOT do.

## Working method

1. Read the task, the docs it cites and the `README.md` of the modules you touch.
2. Ambiguous task or contradicting the docs: **stop and ask**, do not guess.
3. Write first the tests or the scenario that define success.
4. Implement the minimum that makes them pass.
5. Check: the gate commands, the touched benches, the captures.
6. Update the docs you touched. Every new architecture decision = one file `docs/adr/NNNN-<slug>.md`
   (`docs/DECISIONS.md` is the generated index, never edited).
7. One change = one branch = one small diff (ideally under 500 lines).

## Forbidden

- Modifying `docs/VISION.md` or `docs/PROJECT-RULES.md` without the owner's explicit validation.
- Adding a dependency without justifying it in the report (licence compatible with the project's).
- Disabling, skipping or weakening a test to make the gate pass.
- Upgrading the pinned framework version outside a dedicated task.
- Committing generated files (temporary captures, builds, test saves).

## Visual checks

For any visible change, produce a capture with the project's screenshot command (skill `proofs`), look at
its thumbnail, and cite it in the report next to its reference.

## The duo (roles of `docs/WORKFLOW.md`)

- **The reviewer** (architect + reviewer) chooses and cuts the task, writes `pipeline/task.md`, judges the
  delivered task on its proofs. It does not code.
- **The coder** (implementer + QA) does ONE task, tests first, proves it, commits it, writes
  `pipeline/report.md` and stops.
- **The supervisor** (interactive session) relays the owner: `supervisor/SUPERVISOR.md`.
- **The owner** (director, tester) decides; their answers arrive in `pipeline/owner.md`, their decisions
  become ADRs.
- Branches: one task = one branch `task/<nnn>-<entry>`, merged into `main` by the harness after
  `VERDICT: ACCEPT`. "Stop and ask" = coder: `STATUS: IMPOSSIBLE` + proposed question in the report;
  reviewer: `docs/QUESTIONS.md`. Nobody answers during a turn.

## Reading order (only what the task needs)

1. The task and the verdict (already in your prompt).
2. The domain skill (`.claude/skills/<name>/`, table below), before acting.
3. The cited backlog entry, then the doc sections it cites — not whole docs.
4. `docs/STATE.md` (+ your duo's part `docs/STATE-<duo>.md`): milestone status and open problems.
5. The code: module READMEs, `grep`, `git log -- <path>`. The whole repo stays readable.

## Where things are

| What | Where |
|---|---|
| Vision, pillars (owner only) | `docs/VISION.md` ; the product in 3 pages: `docs/BRIEF.md` |
| Non-negotiable rules (owner only) | `docs/PROJECT-RULES.md` |
| Process: roles, task format, done, checklist | `docs/WORKFLOW.md` ; harness: `docs/HARNESS.md` |
| Milestones and their acceptance | `docs/ROADMAP.md` |
| Current milestone, scope, cadence | `docs/PLAN.md` (short, authoritative on "now") |
| Milestone tasks | `docs/backlog/Mn-*.md` |
| Decisions (one file each; generated index) | `docs/adr/` ; `docs/DECISIONS.md` |
| Open questions to the owner | `docs/QUESTIONS.md` |
| Current state; owner's page (+ per duo `-A`, `-B`) | `docs/STATE.md` ; `docs/OWNER.md` |
| Owner's taste; art direction | `docs/TASTE.md` ; `docs/ART-DIRECTION.md` |
| Project words | `docs/GLOSSARY.md` |
| Ideas and proposals waiting | `docs/parking/` |
| Harness, tools; config | `bin/harness/`, `bin/benches/` (`docs/BENCHES.md`), `tools/` ; `config/project.env` |
| Journal (never loaded); lessons for the template | `docs/journal/` ; `docs/UPSTREAM.md` |

## Domain skills (line `DOMAINS` of the task)

| Domain | Skills to load |
|---|---|
| `code` | `stack` (+ `determinism` if simulation, generation or protocol) |
| `feel` (controls, camera, movement) | `stack`, `game-feel`, `proofs` |
| `ui` / `visual` | `stack`, `proofs`, + `ui-ux` / `art-judge` |
| `gameplay` (systems, values) | + `systems-design` (the reviewer reads it to write the task) |
| `data` / `docs` | `stack`, `systems-design` / none |
| `network` / `build` | `networking`, `determinism` / `build-release` |
| `3d` / `audio` | `pipeline-3d` / `pipeline-audio` (proposal until validated: see the skill) |
| load test | `load-test` |

Any visual proof: `proofs`. Skills start thin and grow with the project (`docs/RULES.md` §8).
