# PLAN — now

> WRITTEN BY: the owner and the supervisor (the reviewer proposes, and moves the `MILESTONE:` line at a green
> milestone end). BUDGET: 60 lines. This file says WHERE we are and points to the sources: roadmap
> `docs/ROADMAP.md`, backlog `docs/backlog/`, decisions `docs/adr/`. Every change reaches the reviewer as a diff.

MILESTONE: M0

## Current milestone: M0 — Foundations

- **Done when**: the acceptance of M0 in `docs/ROADMAP.md` holds.
- **Order**: `docs/backlog/M0-*.md` (written by the first task), the owner's priority requests
  (`pipeline/owner.md`) first. One task at a time PER DUO; two duos at most on disjoint lanes
  (`python tools/lanes.py`).
- **Criteria waiting for the owner** (we move on with the rest): <none>.

## Scope, for now

**IN**: M0.
**OUT** (later milestones, see `docs/ROADMAP.md`): everything else. Ideas outside the milestone:
`docs/parking/`. No binary asset until `docs/parking/ASSET-PIPELINE.md` is validated.

## Cadence of builds

- A playable/usable build at the **end of each milestone** (`docs/WORKFLOW.md` § Milestone end), played by
  the owner, and every ~3 days of work as soon as there is something to see.

<!-- Optional, with two duos: a line "PARALLEL_MILESTONE: M1" lets the second duo start the next milestone's
lanes while the current one ends (its "end" lane excepted). -->
