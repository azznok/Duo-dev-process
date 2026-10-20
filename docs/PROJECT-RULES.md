# Project rules (non-negotiable)

> WRITTEN BY: the owner only (drafted by the supervisor at onboarding, then validated). BUDGET: 120 lines.
> PROTECTED: agents never modify it (the gate checks it). Summarised in `CLAUDE.md`. A change = an ADR.

**Status: TEMPLATE — the generic rules below are kept; the stack's rules are added at onboarding phase 2.**

## R1 — Everything is data
Content (items, levels, texts, recipes, screens' copy, tuning values) is defined in data files (`<format,
folder>`), validated by a command of the gate. Never a balancing value hard-coded.

## R2 — Headless first
Every logic feature is testable without a window, from a test or a scenario. The UI only shows and sends.

## R3 — Tested or nonexistent
No feature without a test. A visible feature also has a reference capture (`tests/golden/`), produced by
`<screenshot command>`. A user action is proven by a scenario, and by a raw input script when it goes
through controls, UI or camera (`docs/RULES.md` §1).

## R4 — User actions go through one path
Every user action is a `<command / message / API call>` handled by the logic layer, even locally: scenarios,
replays, tests and (later) multiplayer use the same path.

## R5 — Performance budgets
| Measure | Budget | How it is measured |
|---|---|---|
| <frame time / tick / page load / API p95> | <value> | <bench or tool> |
A benchmark that regresses by more than 10 % blocks the merge (checked at milestone end).

## R6 — Platforms
Nothing breaks a target platform (<list>). OS-specific code lives only in modules made for it.

## R7 — Dependencies
Licences compatible with the project's (<MIT / Apache-2.0 / ...>). Every new dependency is justified in the
task report. The framework version is pinned (`<version>`) and upgraded only in a dedicated task.

## Stack-specific rules (added at onboarding)
<Examples, keep only what applies:
- Determinism: same seed and same inputs give the same result; seeded RNG only; no wall clock in the
  simulation (use the tick); no iteration over unordered maps in logic; reference hashes per platform.
- Client/server split: the simulation never depends on rendering; the server is authoritative.
- Relative positions: positions are expressed in their parent's frame, never huge absolute floats.
- Accessibility: text scale, contrast ratio >= 4.5:1, every action reachable by keyboard / controller.
- Security (apps): no secret in the client, input validated server-side, dependencies audited.>
