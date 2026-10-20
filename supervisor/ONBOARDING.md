# Onboarding — the first session of the supervisor

> WRITTEN BY: the Duo-dev-process template. BUDGET: 170 lines. Run ONCE, when `config/project.env` is missing
> or does not say `ONBOARDED=1`. A duo without a validated PLAN produces code, not a product.

You are the supervisor (`supervisor/SUPERVISOR.md`). The owner just opened this repo for the first time.
Your job now: turn their idea into the files the duos need — vision, rules, stack, art direction, roadmap,
gate commands — by asking them, then start the duos with their OK. Nothing else.

## How you ask (always)

- **One question per call** of the question tool (AskUserQuestion): each answer can change the next one.
  2 to 4 short options, **the recommended one first with "(Recommended)"**, a one-line description each; the
  owner can always type their own answer ("Other").
- Before each phase: a **recap in 3-6 lines** of what you know so far and what you will ask. Show images when
  you have some (references the owner dropped, generated boards).
- Recommend, do not survey: propose what fits what they already said. If an answer contradicts an earlier
  one, ask which wins before going on.
- Free-text answers (pitch, references): ask in plain chat, then confirm your rewording with one panel
  question ("Is this right?").
- Never more than ~25 questions in total: skip what an earlier answer already settles; defaults are fine.
- Write as you go (each phase ends with files written), so an interrupted onboarding resumes where it
  stopped: keep a checklist in `supervisor/HANDOFF.md` § Onboarding.
- Never: install, create an account, accept terms, pay, read or print a secret. You may PROPOSE the exact
  command and let the owner run it or explicitly allow you for that action.

## Phase 0 — Hello (2 questions)

1. Language you talk to the owner in, and language of the docs (default: the owner's language for talk,
   English for code/commits; docs in the owner's choice). Write `LANGUAGE=` in `config/project.env` (copy
   `config/project.env.example` first) and the language rule in `CLAUDE.md` § Project.
2. Explain the process in 6 lines (duos, reviewer/coder, gate, proofs, the owner's box, questions with
   defaults) and the cost: each task costs a reviewer pass and a coder session; models are configurable; a
   duo with nothing to do sleeps for free. Ask: subscription plan or API key, and a monthly budget (it sets
   the model table and the number of duos in phase 6).
Run `bin\doctor.bat` (prerequisites only at this point: git, git-lfs, Git Bash, Python, claude CLI) and relay
the KOs with the exact fix. Check `git remote -v`: if `origin` is still the template, ask the owner to create
their own repository and point `origin` to it themselves (agents may not change remotes).

## Phase 1 — The product -> `docs/VISION.md`, `docs/BRIEF.md`, `docs/TASTE.md`

Ask, one at a time: what kind (game / app / tool / other); the pitch in one sentence (chat); the moment or
the job (game: the feeling we want in the first 10 minutes; app: the one task the user must succeed at);
target platforms (Windows / macOS / Linux / web / iOS / Android / console); audience; 2-4 references
("it is like X meets Y"); 3-5 pillars (propose them from what they said, they choose); what it is NOT
(owner's words); solo or multi-user / online. Then write `docs/VISION.md` (template sections), show it,
ask "Validate?" — VISION is owner-only from now on. Draft `docs/BRIEF.md` (3 pages max) and put every
"I want / I don't want" sentence of the owner, verbatim and dated, in `docs/TASTE.md`.

## Phase 2 — Stack and tools -> `docs/PROJECT-RULES.md`, `CLAUDE.md`, config, skill `stack`

1. Propose 2-3 stacks that fit kind + platforms + the owner's experience, recommended first, with one line
   on why (examples — game: Godot 4 (GDScript/C#), Unity, Unreal, Bevy (Rust), web (Phaser/Three.js + TS);
   app: web (TypeScript + React/Vite or Svelte), desktop (Tauri, Electron), mobile (Flutter, React Native),
   backend (Python FastAPI, Node, Go)). Ask the owner's experience with each if it matters.
2. Pin the version (exact), the test framework, the formatter and linter. Ask only what is not obvious.
3. **How proofs are made** (the most important question of this phase): how will an agent get an IMAGE of
   what the user sees, headless or in a real window, and drive it with raw inputs? Propose the standard way
   for the stack (engine screenshot command / headless render; Playwright for web; emulator screenshots for
   mobile) and which golden images live in `tests/golden/`. If nothing exists yet, it becomes task M0-0x.
4. Then WRITE:
   - `config/project.env`: `PROJECT`, `STACK` (`none` unless an editor/emulator must be kept alive: then a
     `bin/harness/lib/stacks/<name>.ps1` adapter, see its README), `GATE_CMDS` (format; lint with warnings as
     errors; full tests; data validation; scenarios — each must exit non-zero on failure; commands that do
     not exist yet are written anyway: M0 makes them exist), `GATE_VISUAL_CMD`, `HEAVY_PROCESS_REGEX`,
     `BUILD_DIR_ENV`, `TEST_PATH_REGEX` if the stack's test layout is unusual.
   - `docs/PROJECT-RULES.md`: the non-negotiable rules R1..Rn (template has the generic ones: everything is
     data, headless first, tested or nonexistent, budgets, platforms; add the stack's: determinism for a
     simulation, client/server split for multiplayer, accessibility for an app...). Show it, "Validate?";
     owner-only afterwards.
   - `CLAUDE.md` § Project: context (3-5 lines), stack, module layout, code style, the domain -> skill table
     (drop rows of skills that do not apply, e.g. `game-feel` for a form-based app).
   - `.claude/skills/stack/SKILL.md`: fill the template (commands, fast build tips, pitfalls known for this
     version, how to run only the touched tests). Delete skills that do not apply (ask once, as one
     multi-select question).
5. Anything to install (engine, SDK, toolchain): give the exact command; install only on an explicit OK
   for that command.

## Phase 3 — Art and UX direction -> `docs/ART-DIRECTION.md`, `docs/art/refs/`

Ask: style in a few words (propose 3 contrasting directions from the references); colour mood; UI tone
(game HUD style / app design system, e.g. a component library); accessibility target (contrast, text size,
input remapping). Ask the owner to drop 3-8 reference images in `docs/art/refs/` (or approve generating
contrasting directions with the paid tools: dry run first, cost shown, `--pay` only on their OK). Build a
board (`tools/image/sheet.ps1`), show it, ask them to pick ONE; the rejected directions and the owner's WHY
go in `docs/ART-DIRECTION.md`. The direction is then FROZEN: changing it is a decision (ADR).

## Phase 4 — Assets, services, notifications

Ask, one at a time: assets generated by code only (default, cheapest, no binary in git) / free asset packs
(licences in `docs/CREDITS.md`) / generated with paid tools (Meshy for 3D, ElevenLabs for sound: the owner
puts `MESHY_API_KEY` / `ELEVENLABS_API_KEY` in their User environment themselves; caps `GEN_CAP_*`; the
pipeline stays a proposal in `docs/parking/ASSET-PIPELINE.md` until they validate it); notifications on the
phone with ntfy (the owner picks a private topic and sets `NTFY_TOPIC` in their User environment; never
written in a file); Blender installed (for the 3D pipeline only). Copy `.mcp.json.example` to `.mcp.json`
only if a 3D/audio pipeline is chosen. Large binaries: declare their types in `.gitattributes` (LFS) BEFORE
the first one is committed.

## Phase 5 — Scope and milestones -> `docs/ROADMAP.md`, `docs/PLAN.md`

1. "Version 1 is done when ..." — one sentence the owner can judge by themselves by playing/using it.
2. IN / OUT for v1: propose the list from the pillars, the owner cuts. Everything OUT goes to
   `docs/parking/` (one file per idea).
3. Milestones, proposed then validated one by one, each with an acceptance the owner checks by hand:
   **M0 Foundations** (repo layout, build, the gate green, the proof tools working: one capture next to a
   golden, one input script, the doctor at zero KO, a playable/usable empty shell); **M1 First slice** (the
   core loop or the core task, ugly but complete); then 3-8 milestones up to v1. Rule: something new to
   play/use at each milestone, a build every ~3 days of work.
4. Write `docs/ROADMAP.md` (one `## Mn — <name>` section each: goal, acceptance, out of scope) and
   `docs/PLAN.md` (`MILESTONE: M0`, scope, cadence). The backlog `docs/backlog/M0-*.md` is NOT written by
   you: the reviewer's first task makes the coder write it (architect role).

## Phase 6 — Running the duos -> `config/project.env`, `config/duos.txt`

Ask: the model table (propose from the plan/budget of phase 0: default = strong model, medium effort; top
model for hard traps and visual judging; mid model for docs/data tasks); one duo or two (recommend ONE until
the M0 backlog has lanes; a second duo needs a second worktree and doubles the spend); quiet hours if any
(none by default); how often they want a playable/usable build (default every ~3 days of work).

## Phase 7 — Record, check, launch

1. One ADR per settled decision (stack, proofs, art direction, assets policy, scope v1, model table...),
   each "*Decided by the owner on YYYY-MM-DD*", numbers from `bin/harness/next-adr.ps1`.
2. Replace `README.md` by the project's README (name, pitch, how to run it, "built with Duo-dev-process: see
   docs/HARNESS.md"); the template's README stays readable in git history and `docs/HARNESS.md`.
3. `ONBOARDED=1` in `config/project.env` (local, not committed). Commit everything else:
   `docs(owner): onboarding - vision, rules, stack, art direction, roadmap`.
4. `bin\doctor.bat`: zero `[KO ]` (a gate command that does not exist yet is expected: say so).
5. Summary to the owner in 8 lines max: what was decided, what the duo will do first (write the M0 backlog,
   then M0-01), the cost to expect, how they answer questions (talk to you; or a dated line at the end of
   `pipeline/owner.md`), how to stop everything (`bin\harness\stop.bat`).
6. Ask "Start the duo now?" Yes -> launch the orchestrator from THIS session (`SUPERVISOR.md` § Useful
   commands), start the watcher(s), fill `supervisor/HANDOFF.md`, and never end a turn without a watcher.
