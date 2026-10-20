---
name: stack
description: Write or change the project's code with its pinned language, framework and toolchain - build, test and lint commands, fast iteration, error handling, file size, dependency policy, and the stack's paid-for pitfalls. Use for every task with DOMAINS code, ui, visual, feel, network or data. Do NOT use to choose a new architecture (write an ADR first), to upgrade the framework outside a dedicated task, or for proofs (skill proofs).
---

# Stack: <language> + <framework> (pinned)

> TEMPLATE. The supervisor fills every `<...>` at onboarding (`supervisor/ONBOARDING.md`) with the
> owner, then deletes this note. Until then the coder treats any `<...>` as "ask, do not guess":
> `STATUS: IMPOSSIBLE` + `PROPOSED QUESTION:` in the report.

Rules this file does not repeat: `CLAUDE.md` (code style, forbidden things), `docs/PROJECT-RULES.md`.

## The pins

| What | Value |
|---|---|
| Language and version | `<e.g. Rust 1.xx / TypeScript 5.x / C# 12 / Python 3.12>` |
| Framework / engine and version | `<name x.y.z>`, pinned in `<manifest file>` |
| Package manager / lock file | `<tool>`, `<lock file>` (committed) |
| Local API docs of THIS version | `<path or command that builds them>` |
| Build folder (outside the repo if heavy) | `<path>`; per duo: env var `<BUILD_DIR_ENV>` |
| Supported platforms | `<Windows / macOS / Linux / web / mobile>` |

An unknown API: read the docs of the PINNED version (local copy or the tag's sources), never memory and
never the online docs of another version. The framework is upgraded only by a dedicated task.

## The commands (the gate runs the same ones: `GATE_CMDS` in `config/project.env`)

| Step | Command | Expected time |
|---|---|---|
| Build | `<cmd>` | `<cold / incremental>` |
| Tests | `<cmd>` | `<...>` |
| Lint (warnings are errors) | `<cmd>` | `<...>` |
| Format check | `<cmd>` | `<...>` |
| Run the app | `<cmd>` | `<...>` |
| One test / one module | `<cmd>` | `<...>` |
| Screenshot of a scene (skill proofs) | `<cmd --scene <file> --out proofs/<nnn>/<x>.png>` | `<...>` |
| Logic scenario (commands + assertions) | `<cmd scenarios/<x>.<ext>>` | `<...>` |
| Raw input script then capture | `<cmd --inputs scenarios/inputs/<x>.<ext> --out ...>` | `<...>` |
| Compare two images (0 = same) | `<cmd a.png b.png>` | `<...>` |

Long commands (cold build, full suite): ONE blocking call with a timeout, waited for inside the turn
(`docs/RULES.md` § 5 Long jobs). Ending the turn kills the job and loses the report.

## Fast iteration

- `<incremental build settings: debug optimisation level, fast linker, hot reload, watch mode>`
- Pure logic lives in modules/packages that do NOT depend on the framework: they build fast and test
  without a window. List them here: `<...>`.
- Measure the incremental build once (one-line change, relink): write the figure here, re-measure
  when it doubles.

## Code rules

- Errors are typed (`<error library or pattern>`); no `<unwrap / force-cast / bare except>` outside
  tests and startup.
- Files under 400 lines; split into modules beyond.
- No `<unsafe / eval / reflection hacks>` without an ADR.
- Each module/package has a short `README.md`: role, public API, invariants, what it must NOT do;
  updated in the same commit as the code.
- Game/app values (balance, timings, colours, texts) live in data files `<format, folder>`, never in code.

## Dependencies

- A new dependency is justified in the report: why, licence (`<MIT / Apache-2.0 / compatible>` only),
  compatibility with the pinned framework version, size of what it pulls in.
- Check the licence from the source repository, not from memory.

## Pitfalls already paid (generic; the stack's own go below)

- A script that rewrites source files on Windows writes CRLF and the formatter refuses the file:
  write with explicit `\n` line endings and UTF-8 (read with UTF-8 too, or a pattern with a non-ASCII
  character silently matches nothing).
- `checkout`, `stash` or `switch` on a dirty tree erases uncommitted work: commit BEFORE any check that
  touches the tree; read an old file with `git show <rev>:<path>`.
- Two duos on one machine: each calls its tools through ITS build folder env var, never a hard-coded
  path; a binary built by the other duo produces a "proof" of the wrong code.
- Temporary folders of tests: a FIXED name under the build folder plus a guard that removes it at
  creation and at exit. A name with the process id, removed only before the run, piles up (tens of GB).
  The system temp folder is shared by every duo: never a bare fixed name there.
- A process that launches a child which outlives it: on Windows the child inherits the parent's
  handles, and anything reading the parent's stdout waits for the child's death. Redirect to a file.
- An automatic shell variable used as an ordinary one (PowerShell `$args`) is silently empty: the tool
  prints its help and returns 0, a "successful" build that compiled nothing.
- A path with spaces passed through a joined argument list is cut in two: quote it, or call the exe
  directly.

## Stack pitfalls (filled by the duo: one line per pitfall paid, in the task's commit)

<!-- `- <symptom> : <cause> : <fix> (TASK nnn)`. Over 150 lines: move the oldest to pitfalls.md beside this file, verbatim. -->
