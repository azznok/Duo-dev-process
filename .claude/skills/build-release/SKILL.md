---
name: build-release
description: Build and deliver - release build, the playable/usable package with its README-to-play, CI on the supported platforms, end-of-milestone replay of the acceptance criteria from the package, and the periodic process review (costs, doc budgets, skills, loop dashboard). Use for every task with DOMAINS build, every End of milestone task, every intermediate build (~3 days of work), and every process review. Do NOT use for an ordinary development build (skill stack).
---

# Build and release

## Cadence

- A **playable/usable build at the end of each milestone**, and every **~3 days of work** as soon as
  there is something to see (`docs/PLAN.md` § Cadence of builds). An imperfect build beats an absent build.
- **Tags** (`m<n>-build<k>`, one per day at most) are set by the OWNER, never by an agent.

## The gesture

1. **Release build first, in the background, waited for inside the turn** (often the longest step),
   log in `proofs/<nnn>/`.
2. **Package** into `build/<name>/` (git-ignored, replaced at each call) with one script: the binaries,
   the data, the scenes and scenarios used by proofs, one reference golden, a one-click launcher and
   `README-to-play` (< 60 lines). The script fails (code 1) if an expected file is missing; a file added
   to the package = one line of its expected list.
3. **README-to-play is stale by default**: every sentence is re-checked against the current code at
   EVERY build, not just the first: how to start, the controls and HUD as they ARE (re-read the data
   files), "what to try" = the milestone's done criteria in <= 6 numbered lines, "what is not there"
   checked against `docs/STATE.md`, "if it crashes".
4. **From the package folder**: run a scripted capture and a headless server/back-end run; launch the
   launcher ONCE as a real window, capture it after a few seconds, stop it (and its parent shell); no
   app process left before the end of the turn.
5. **End of milestone**: replay FROM THE PACKAGE every acceptance criterion of the milestone
   (`docs/ROADMAP.md`): captures compared to goldens (0 px expected), all scenarios, data validation,
   the load test (skill `load-test`); images next to the proofs of the original tasks.
6. Update `docs/STATE.md` ("Last playable build": path, date, what to try) and `docs/OWNER.md`.
   Then the process review (below).

**Intermediate build**: steps 1-4 only (no acceptance replay, no process review).

## CI

One job per platform, steps in the order of the gate. Expensive platforms (macOS minutes cost more)
run nightly or on demand, not on every push. Cache restore and save as separate steps, save even when
a later step fails. Check every CI action's licence from its repository. "CI green" is observed by the
owner or supervisor; an agent never claims it without seeing it.

## Process review (end of milestone or every ~15 tasks)

1. **Costs**: `python tools/costs/agg_logs.py > proofs/<nnn>/costs.log` (all), then from the first coder
   log after the previous review. Cost of task n = its coder logs + the reviewer pass that judges it
   (pass n+1). A log without its final JSON (stopped turn) is "unknown": count it apart.
2. **Doc budgets**: `python tools/costs/budgets.py` (code 1 = over). Over budget outside the core: split,
   the old text goes VERBATIM to `docs/journal/`, one pointer line stays. Core and harness: propose
   (`docs/QUESTIONS.md`).
3. **Skills**: each <= 150 lines; descriptions say when to use AND when not; usage = the `DOMAINS`
   lines of the harness log; a duplicate of an always-loaded doc becomes a pointer.
4. **Loop dashboard**: `python tools/costs/loop.py` - first-pass acceptance, median time and cost per
   task, bugs found later, per domain. Paste the output in the journal.
5. **Repository**: size, LFS files, binaries outside LFS.
6. **Art calibration**: skill `art-judge` § Calibration.
7. Write `docs/journal/<date>.md` § Process review <nnn> (outputs, tables, proposals); generic lessons
   to `docs/UPSTREAM.md`.

## Pitfalls already paid

- A proposal open for two reviews in a row without being wired becomes a mandatory harness backlog
  entry at the next review, not a line copied again.
- Re-read the verification SCRIPT itself before writing a coverage claim: a review once repeated a
  claim the script had already outgrown.
- A metrics tool that classifies "rejection" and "fix" from task TITLES is wrong repeatedly: read the
  real `VERDICT:` lines and the "fixes NNN" in task and report text; keep a test on synthetic logs.
- With several duos each has its own logs folder: run the review once per folder; a gate refusal caused
  by a locked binary is not a code fault - count it apart.
- Proof mode (fixed step) freezes FPS counters: budgets are measured by a real-time bench on the
  release package. The first measurement after a build runs under load: re-run before concluding.
- A golden copied from LFS without `git lfs pull` is a ~130-byte pointer: the package script refuses
  goldens under 1 KB.
- A `build/` ignore rule also ignored `bin/build/` templates: anchor it (`/build/`).
- On Windows an agent shell may not search the current folder for executables: launchers call
  `"%~dp0app.exe"`, PowerShell calls `.\app.exe`.
- A bench whose header changes (call, default) regenerates `docs/BENCHES.md`
  (`python bin/benches/benches.py`) in the same commit.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
