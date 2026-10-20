# Backlog — format of the milestone files

> WRITTEN BY: the reviewer (architect) when splitting a milestone; the coder ticks boxes and closes entries. BUDGET: 60 lines.
One file per milestone: `docs/backlog/M<n>-<slug>.md`, entries in recommended order. The lanes script
reads it: `python tools/lanes.py --milestone M1 [--ref main] [--json]`.

## Head of the file

Source (`docs/ROADMAP.md` § M1), the milestone's loop, its smallest playable/usable slice, its scenario
with numbers (skill `systems-design` § For the reviewer), what is out of scope, the lanes and the order:
`00 -> 01 -> 02; 03 ∥ 04 after 02; End`. **∥** = independent of its neighbours once its prerequisites are done.

## An entry

```
## M1-03 — <title>

**Prerequisites**: M1-01, M1-02. **Domains**: code, ui. **Model**: default. **Timebox**: 1 day. **Fallback**: <what is delivered if time runs out>.
**Lane**: <name>. **Zones**: <path>, <path>.
**Reference**: docs/<file> § <section>; ADR-NNNN.
**Goal**: <one sentence a user would understand>.
**Acceptance**
- [ ] <checkable criterion, with its number and its source>
- [ ] <proof: scenario / input script + capture / capture next to reference>
**Load**: nothing | add <action>.
```

- **Closed**: ✅ at the end of the title, followed by the task numbers: `## M1-03 — <title> ✅ (041, 043)`.
  An entry is also done when all its boxes are ticked.
- **Prerequisites** cite entry ids (ranges `M1-04 to M1-06` allowed). The words "owner decision" or
  "pause" in the prerequisites BLOCK the entry until removed.
- **Split**: a big entry gets a line `**Split (TASK nnn)**: 1/3 ... ; 2/3 ... ; 3/3 ...`, each part marked
  done with its task number.

## Lanes and zones

- A **lane** is a chain of entries one duo advances; its **zones** are the paths (files or folders; a
  folder covers its sub-folders) it may touch. **Two lanes never share a zone**: the script refuses it.
  Shared files (index, docs read by all) are listed at the head as "common" and changed only by the End task.
- Special lanes: `single` (backlog not split into lanes yet: one duo), `end` (the End of milestone entry,
  ready only when every other lane is finished), `*` (backlog invalid: only the first duo runs, to fix it).

## End of milestone (always the last entry)

```
## End of M1 — playable build, acceptance replayed, process review

**Lane**: end. **Zones**: docs, build.
**Goal**: close the milestone (skill `build-release` § The gesture, End of milestone).
**Acceptance**
- [ ] Package built; every acceptance criterion of `docs/ROADMAP.md` § M1 replayed from the package.
- [ ] Load test of the milestone green; process review written; `docs/STATE.md` and `docs/OWNER.md` updated.
```

The task for it is titled `TASK: <nnn> — [End of M1] <title>`.
