---
name: load-test
description: Headless load test - many simulated users playing every feature at once for a fixed number of ticks from a seeded load profile, invariants checked every tick, a text report and a JSON report, replaying a failure by its seed, reducing it to a minimal scenario, adding an action to the milestone's profile. Use at the end of every milestone, when a task carries `LOAD: add <what>`, or to hunt a defect that only appears under load. Do NOT use for micro-benchmarks (docs/BENCHES.md) or as the proof of one feature (a scenario proves it).
---

# Load test

Why: a scenario proves the gesture you planned, not the one you did not. The first seeded load test of
a project found, on its first run, a collision defect that dozens of hand-written scenarios had never
touched.

## When

- End of milestone (the milestone gate runs `MILESTONE_LOAD_CMD`); a task with `LOAD: add <what>`: after
  the addition. Background runs per duo: `BACKGROUND_LOAD_CMD` (`config/project.env`).
- Build in release first; machine idle for any timing (no heavy build of another duo).

## The profile (data, one per milestone)

- A list of actions `(action, weight, duration)` drawn from the seed, for N users, M ticks; every action
  goes through `Command`s like a real user (never an internal call, never a teleport).
- Each action counts its commands; an action that produced 0 commands on a seed is a coverage gap, not
  a defect (give it to the users who can do it).
- **The test grows with the product**: each feature task adds its action and its invariant.

## Invariants

Checked every tick (no overlap/inside-wall, no NaN, conservation of items, tick time budget,
save -> reload -> same hash as the live run and as a witness that never saves). **Never weakened** to
make the report green: a real defect is reported (`docs/STATE.md`) and fixed.

## Reading the report

- `FAIL tick T user U <what> <value seen>`: an invariant broken, code 1.
- A tick-time failure: noise or real peak? Re-run on an idle machine before any fix.
- A kept temporary folder: the run failed; read it.

## Replaying a failure

1. Same command line (printed at the head of the report), same seed: same hash, same `FAIL`.
2. **Export** the run as a scenario, replay it: the defect reproduces without the load.
3. **Reduce** (delta debugging over users, entities, end tick, commands) keeping the SAME value seen;
   the reduced scenario fails the same way.
4. **Where it diverges**: write per-tick hashes of both runs and `cmp` them: first differing tick.
5. The fix adds the reduced scenario to `scenarios/`; the seed stays in its header.
6. **Swarm** mode: each seed plays a random subset of each table; it finds failures the full mix drowns.
7. **Faults** (dropped / duplicated commands, cut save): deterministic from the seed; an expected
   divergence is reported as such, it does not fail.

## Pitfalls already paid

- A `FAIL` that appears with a new action is not necessarily caused by it: remove its lines from the
  export and replay; replay the same file with `main`'s binary: same value to the bit = an older
  defect revealed.
- Adding an action changes every load hash (the draw): list them.
- Running more than ~4 load runs in parallel pushes ticks over budget: false failures.
- Reduction hits its replay cap on long runs: keep only the faulty user by hand first, then reduce.
  Reduce from a COPY of the binary (it locks the exe and blocks builds).
- An invariant judged after the tick sees that tick's physics: judge a command against the state it
  was issued in.
- With nobody connected nothing is loaded: an invariant test connects a user first, or nothing fails.
- An invariant on an event emitted mid-tick is judged on the LAST message per user of that tick.

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
