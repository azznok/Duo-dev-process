# Glossary

> WRITTEN BY: everyone (a word that comes up three times enters here). BUDGET: 80 lines.
One word, one line, and where it is defined. No redefinition: point to the doc.

## The product

- <word> : <definition> (<doc § section>)

## The process

- **Owner**: the human; product director and tester; decides (`docs/VISION.md`, ADRs).
- **Supervisor**: the interactive Claude session that talks to the owner and relays their words (`supervisor/SUPERVISOR.md`).
- **Duo**: a reviewer and a coder taking turns on one branch at a time; several duos can run in parallel (`docs/WORKFLOW.md`).
- **Reviewer**: architect + reviewer; picks and splits the task, writes `pipeline/task.md`, judges the delivered task on its proofs; never codes.
- **Coder**: implementer + QA; does ONE task, tests first, proves it, commits it, writes `pipeline/report.md`, stops.
- **Orchestrator**: the script that launches, watches and relaunches the duos (`bin/harness/orchestrator.ps1`).
- **Mediator**: a short call that solves a stuck merge or a blocked duo, or escalates (`bin/harness/mediator.ps1`).
- **Milestone (M0, M1...)**: a playable/usable step of the roadmap with acceptance criteria (`docs/ROADMAP.md`).
- **Backlog entry**: a numbered piece of a milestone (`## M1-03 — <title>`) with acceptance boxes (`docs/backlog/README.md`).
- **Task**: one unit of a few hours taken from a backlog entry, with timebox and fallback (`pipeline/task.md`).
- **Timebox / fallback**: the time a task may take / what is delivered when the time is out.
- **Lane**: a chain of backlog entries one duo can advance without touching another lane's files.
- **Zone**: a path (file or folder) a lane owns; two lanes never share a zone.
- **Gate**: the harness checks run before a verdict (build, tests, lint, size, visual...) -> `pipeline/gate.md`.
- **Proof**: what shows a task is done: an image next to its reference, a scenario, an input script, a measure (`docs/RULES.md` § 1, The proof).
- **Golden**: a reference image in `tests/golden/`, compared at the pixel; changed only explicitly.
- **Proof mode**: fixed time step, lockstep server, input script as the only input: same script = same image.
- **Scenario**: a headless run that drives the logic by `Command`s, with assertions.
- **Input script**: raw keys and mouse events played into the real client, ending in a capture.
- **Blind judge**: a separate call that sees only a capture and its reference and lists the gaps (`bin/harness/prompts/blind-judge.md`).
- **Self-judge**: the coder running the same blind judge on its captures before reporting; never a verdict (`bin/harness/self-judge.ps1`).
- **Polish**: a gap found by the art judge, kept in `docs/STATE.md` § Polish, chosen by the owner after playing.
- **Walkthrough**: a scripted tour of the whole product, one capture per step, all green, run from the build.
- **Load test**: many seeded simulated users playing everything at once, invariants checked every tick (skill `load-test`).
- **Bench**: a script that proves one gesture and prints ONE verdict line (`docs/BENCHES.md`).
- **ADR**: one decision, one file `docs/adr/NNNN-<slug>.md`; index generated in `docs/DECISIONS.md`.
- **TASK: NONE**: the reviewer has nothing to do without the owner; the duo sleeps without spending.
- **Set aside**: a task branch kept but not merged after repeated rejections.
- **Owner box**: `pipeline/owner.md`, the owner's dated answers.
- **Default if silence**: what is done if a question stays unanswered (`docs/QUESTIONS.md`).
- **Handoff**: the note a supervisor session leaves to the next one (`supervisor/HANDOFF.md`).
- **Dry run**: a paid tool saying what it would do, without spending.
- **Thumbnail**: an image reduced to <= 1280 px, the only kind an agent reads (`tools/image/vignette.py`).
- **Process review**: the periodic task that measures costs and prunes docs and skills (skill `build-release`).
- **Upstream lesson**: a generic lesson for the template (`docs/UPSTREAM.md`).
