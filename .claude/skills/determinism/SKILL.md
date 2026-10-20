---
name: determinism
description: Keep the simulation, generation and replay deterministic - seeded random streams, fixed tick instead of wall-clock time, ordered containers, portable maths, reference hashes identical on every platform, recorded sessions replayed to the same state hash. Use for every task that touches simulation, procedural generation, random numbers, the protocol, saves or replay. Do NOT use for pure client presentation (interpolation, camera, UI timers), which may use real time.
---

# Determinism

Same seed + same inputs = same result, on every supported platform. The project's rules on this:
`docs/PROJECT-RULES.md`. Make the forbidden calls fail mechanically (linter deny-list) rather than by
review; allow them only LOCALLY outside simulation and generation, with the reason on the line above.

## The gesture

1. **Random**: a seeded generator from ONE project module; sub-seeds derived by
   `derive(seed, tag, index)` (a stable hash). Never the global/thread RNG, never time-seeded.
2. **Maths of generation**: functions with portable results (a software maths library or the project's
   own), not the platform's `sin`/`exp`/`pow`, which differ between OS and CPU. No fused multiply-add
   unless every platform does it.
3. **Time**: the simulation advances by **tick** (fixed rate, e.g. 30 Hz). No wall clock, no real-time
   delta inside the simulation.
4. **Order**: ordered maps or an explicit sort before any iteration that affects state; commands applied
   sorted by (link/player, sequence number).
5. **Parallelism**: only when each piece is a pure function of `(seed, coordinate)`.
6. **Proof**: a reference-hash test (noise, generated content, state after N ticks) identical on every
   platform (CI); a recorded session (seed + commands) replayed headless gives the same state hash.

## State hash and sessions

- The state hash is an ordered, stable hash (e.g. FNV-1a 64 over sorted entities); never the language's
  default hasher, whose algorithm is not guaranteed between versions.
- Everything that is hashed must also be SAVED and survive any "park/unpark" of an entity; otherwise a
  reload diverges.
- A reference constant that changes is a change of worlds/results: an ADR, never "fixing a test". The
  failing test prints the new value.

## Pitfalls already paid

- Integer division and modulo round toward zero: coordinate -1 lands in cell 0. Use Euclidean division.
- NaN does not have the same sign bit on every CPU: canonicalise NaN (or forbid it) before hashing bits.
- A third-party physics engine: enable its deterministic mode, no SIMD/parallel features; hash bodies
  sorted by YOUR stable ids, never by the engine's handles. Decide sleep in the world (rest + contact),
  never from the engine's internal counter that no save carries.
- A restart point of the physics rebuilt when the SAVE is WRITTEN made the live game diverge from its
  reloaded twin: everything that must be equal between live, reloaded and witness runs is a function of
  the tick, never of an I/O event.
- An entity created during a system is not visible to queries before the system ends: state needed later
  in the same tick lives in a resource, not only in the component.
- A new system that EMITS every tick breaks tests that compare an exact message drain: filter the new
  messages and test them separately; never weaken the assertion.
- Walking float by float (`next_up` loops) across a range can take 10^9 steps: use bisection.
- An optional field added to an input with a `None` default keeps every hash: verify it by re-running
  all scenarios, do not assume.
- Property tests: commit the regression files they write; keep generators simple.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
