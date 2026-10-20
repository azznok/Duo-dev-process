---
name: systems-design
description: Design of systems - loops (game loops or user journeys), resources, crafting and progression, economy and balance in numbers, discovery, onboarding. Use to design or split a gameplay/feature task (reviewer) or to tune game/app values (coder). Do NOT use to decide the vision (docs/VISION.md, owner only) or for code (skill stack).
---

# Systems design

The design is written in `docs/VISION.md`, `docs/BRIEF.md` and the ADRs. This skill says how to
TRANSLATE it into tasks and values, without reinventing it.

## The rules

1. **A feature task names its loop**: what verb the user performs, what they get, what it unlocks
   (short term: minutes; medium: hours; long: tens of hours / weeks of use). A feature with no place in a
   loop = a question to the owner.
2. **Playable/usable end to end early**: prefer the minimal complete loop (gather -> make -> use; or
   sign up -> do the core thing -> see the result) to a perfect isolated brick. A build where the user
   DOES something beats an invisible system.
3. **Atomic transactions**: a recipe, purchase or form consumes all or nothing, checked on the server
   side (`Command`); nothing lost or duplicated (a conservation test).
4. **Each tier unlocks a verb or a place**, not only bigger numbers.
5. **Rarity is a bonus, never a gate** unless the vision says otherwise; no dead end at the base tier
   (base resources renewable or abundant).
6. **Balance comes from rules and data**: each important rule has a scenario with numbers; values live
   in data files.
7. **Curves before values**: time to reach each tier, cost of a reference build, consumption per minute
   - a table in the report, not an intuition.
8. **Warnings before danger**: a need or limit declines by readable steps with a warning; failure costs
   time, not the whole progress (unless the vision wants it).
9. **Dead time**: a trip, wait or process longer than ~30 s without a user decision is justified or
   shortened.
10. **Show, do not tell**: the world or app shows (map, preview, silhouettes, empty states) rather than
    instructs; no forced tutorial unless the vision asks.
11. **The owner judges the fun**: the agent delivers the loop, the numbers and the build. An open design
    question goes to `docs/QUESTIONS.md` with a default that does not stop the duo.

## For the reviewer (writing a task)

Before writing a gameplay/feature task, write in it:
- the loop (rule 1) and where the task sits in it;
- the smallest playable/usable slice (rule 2);
- the expected numbers (rule 7), each with its source (doc, ADR) or marked "in data, tuned at playtest";
- the scenario that proves them (rule 6), and the input script if the user's gesture changes.
At the head of a milestone backlog: the milestone's loop, its smallest playable slice and its numbered
scenario, then a table of computed quantities with their source.

## Pitfalls already paid

- A first playtest that found "nothing to do, just a cube": the owner wants something to SEE and to DO
  quickly; a build with no action cannot be judged.
- "Linear movement, no gravity": movement must have weight (acceleration, inertia) as soon as it exists.
- A budget expressed on a quantity supposed to cause the cost (shapes per chunk) pointed at the wrong
  optimisation: measure the real cost per phase first.
- A value computed in a doc and copied into a backlog drifts when the owner changes the source: cite the
  ADR next to every number, keep the old value in parentheses when it changes.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
