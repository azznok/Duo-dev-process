---
name: art-judge
description: The reviewer judges whether an image (capture, golden, sheet, mock-up) is right for the project's art direction - canon questions from docs/ART-DIRECTION.md, references in docs/art/refs, the owner's verdict gallery, the blind judge's gap list, "make it exist first". Use at every visual judgement of a ui or visual task, to pose or change a golden, and to calibrate at the process review. The coder uses only § Readability measurements. Do NOT use to judge feel or balance (the owner plays) or to change the style (owner only, docs/ART-DIRECTION.md).
---

# Art judge

The judge is a pass of the **reviewer**, never the coder. Style comes from `docs/ART-DIRECTION.md`
(owner's choices); this skill applies it, it never changes it. The coder proves "readable and
coherent" (§ Readability measurements); the reviewer says "right for the art direction".

## Make it exist first (this overrides everything below)

Accept what **exists, works and reads**. The canon and the blind judge are an OPINION: every gap they
find is written to the polish list (`docs/STATE.md` § Polish, one line per gap with its capture), and
the **owner chooses** which polish to do after playing. Refuse only for: a broken capture (black,
background only, wrong scene), the object absent, or a capture that does not show what the task asks.
No plea either way: not the coder's effort, not "better than before", not "a future task will fix it".

## Order of a judgement

1. **Gallery first**: `docs/art/gallery/` (owner's verdicts). Read the entries whose image resembles the
   one judged (same kind: sky, character, menu...). The owner's reasons weigh more than this canon.
2. **Blind judge** (before you): each line `- art-judge: <capture> | <reference>` of the task is judged
   by a separate call that sees ONLY the two images (`bin/harness/prompts/blind-judge.md`), ending in
   `BLIND-JUDGE: YES (0 gaps)` or `BLIND-JUDGE: NO (<n> gaps)`. You remove a gap only with evidence from
   the loupe: `BLIND-JUDGE CONTESTED: gap <n>, <loupe evidence>`.
   The coder may run the same judge before the report (`bin/harness/self-judge.ps1`, 2 tries per task);
   their `SELF-JUDGE:` line is not a verdict, the harness judge always runs again.
3. **Describe** the capture ALONE from its thumbnail (`python tools/image/vignette.py`), <= 5 lines,
   no judgement, BEFORE opening any reference.
4. **Canon**: answer each closed question of `docs/ART-DIRECTION.md` § Canon yes / no / not applicable,
   with the reference image that shows the "yes". A criterion without object ("no sky in a menu") is
   "not applicable", never "yes".
5. **Inventory** of the reference, one detail per line, each "present" / "absent" / "different" on the
   capture: silhouette and proportions, ORIENTATION (where the user faces, which side the controls are),
   parts, colours (hue AND saturation AND depth), surfaces (plain or patterned: a pattern absent from
   the reference is a gap), fine details, own light. Two states (off / active): both captures.
6. **Verdict**, one line: `art: accepted (gaps to polish: <n>)` or `art: refused (<broken | absent | wrong scene>)`.

Writing the task = writing the `- art-judge:` lines: a capture framed on the element, at the angle of
its reference. Without a reference, no art-judge line: the image is judged on readability only.

## Generic canon (copy into docs/ART-DIRECTION.md § Canon at onboarding, then adapt)

1. Shapes: the forms read as the style says (e.g. clean blocks, flat UI cards), no foreign style.
2. Surfaces: texture/no texture as the style says; no photographic noise if the style is flat.
3. Light: no flat unlit face, no pure-black area where the style wants depth cues.
4. Palette: 3 to 5 harmonised hues per scene/screen, no rainbow.
5. Hierarchy: what the user can act on is more salient (saturation, contrast) than the background.
6. Readability: in greyscale, foreground, background and interactive things stay distinct.
7. Scale: sizes are measured against a known unit (a character against a door, a button against text).
8. Consistency: an element in a full scene matches its validated stand-alone version, face by face.
9. UI: safe margin, one corner per family of information, one font family, nothing in the centre that
   blocks the view.
10. Originality: not a reskin of the references' sources.

## Readability measurements (the coder's side; numbers go in the report)

- Greyscale test of the capture; clipped pixels (pure black or white) <= 1-2 %.
- Count of dominant hues; foreground/background contrast; a colour-blindness simulation.
- Fixed viewpoints: each look-defining view has a scene and a golden; a change of look = before/after
  on the same scene. Colours and render settings live in data, never in code.

## Calibration (process review)

Re-judge a sample of the gallery (>= 6 entries, >= 2 refusals) WITHOUT reading their verdicts.
Agreement = identical verdicts / sample. **Below 90 %**: revise the canon in the same task (badly posed
question, missing example) and write the agreement in the review's journal entry.

## Pitfalls already paid

- Judging a shape before reading its definition (what a "corner" piece is) produced wrong verdicts.
- A character measured as decoration: scale is measured against the unit, not eyeballed.
- Asserting a detail of a reference without looking at it ("no rivets") - look first, then claim.
- A judge that writes "yes, with named gaps" hides refusals: a gap is a gap; it goes to polish.
- Concept images are DIRECTIONS read as thumbnails, never pixel targets; a shape seen in a concept does
  not define a shape of the engine.
- A score of distance to a concept is an alert, never a verdict: shape, scale and state are invisible to it.
- An unreachable criterion after tuning the data is NAMED with its concept and becomes a backlog entry
  (an engine feature); it is never declared valid. The engine grows toward the art direction.
