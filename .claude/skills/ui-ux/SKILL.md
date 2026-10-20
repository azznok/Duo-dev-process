---
name: ui-ux
description: The user's interface - HUD, menus, inventories and lists, forms, settings, console, gamepad and keyboard navigation, accessibility and localisation, with measurable criteria (text size, contrast, clicks, response time, resolutions). Use for every task with DOMAINS ui and any screen the user sees. Do NOT use for camera or movement controls (skill game-feel), for the look of the world (skill art-judge) or to decide the style (owner, docs/ART-DIRECTION.md).
---

# UI / UX

Decisions already taken live in ADRs (search `docs/DECISIONS.md`: "UI", "language", "font").

## The rules

1. **Text size**: >= 24 px at 1080p by default in a game (>= 16 px CSS in an app), scalable to 200 %
   without loss or overflow.
2. **Contrast** >= 4.5:1 for text, >= 3:1 for icons and large text; outline or shadow on any text drawn
   over a scene. Measured by script on the capture, on the TEXT ALONE (tight zone, no badge).
3. **Never colour alone** to carry information (red/green above all); the capture passes a
   colour-blindness simulation.
4. **Anchored layout**, reference resolution `<1920x1080>`; captures at 2 resolutions at least (small
   and large, plus ultra-wide or phone width when supported); safe margin ~5 %.
5. **Everything without a mouse**: initial focus on each screen, directional/tab navigation, glyphs or
   shortcuts that follow the last device used.
6. **Actions, not keys**: each command has an action name; remapping lives in data with conflict
   detection; Back/Escape is not remappable.
7. **The UI reacts to changes** (events, change detection), it does not poll every frame; in play the
   HUD covers < ~15 % of the screen.
8. **Conventions of the genre** for lists and inventories (shift-click transfers, drag splits, hover
   tooltip; in apps: undo, standard shortcuts). A common operation = 3 clicks at most.
9. **Visual response < 100 ms** to any hover or press; > 1 s needs a progress indication.
10. **No hard-coded user text**: a translation key; plan 30-40 % longer translations; a pseudo-language
    (lengthened, accented) for every new screen; the font covers every supported language.
11. **The UI is a client**: changing shared state = a `Command` to the server/back end; a stack of
    screens; "pause" never freezes a shared server.
12. **Discoverable**: any non-obvious action (capture the cursor, open the inventory) has an on-screen
    hint until the user has done it once.
13. **Errors say what to do**: an error message names the problem and the next step, in the user's words.

## The proof

Raw input script (keyboard AND gamepad/tab navigation) ending in captures (skill `proofs`), at 2
resolutions at least; measures of rules 1, 2 and 9 in the report; the pseudo-language for a new screen.

## Review (reviewer)

Refuse: hard-coded text; a screen not navigable without a mouse; contrast or size not measured;
information carried by colour alone; shared state changed without a `Command`.
Beauty: skill `art-judge`.

## Pitfalls already paid

- Escape closed TWO screens in the same frame: the screen's handler was not ordered before the
  console's; order input handlers explicitly and ignore input when an overlay owns it.
- An absolutely positioned panel ignores the others: messages slid UNDER another column, a hint touched
  a label. With a modal open, check every absolute placement on the capture of that screen; a row that
  does not fit wraps, it is never clipped.
- An empty float sum is `-0.0`: displayed "-0.00", and a "set if changed" check never redraws it
  (`-0.0 == 0.0`). Every displayed number goes through one formatting function (tabular digits).
- A new translation key must also be added to every test fixture locale, or the data tests count
  unexpected errors.
- A glyph outside the basic Latin range is checked with the loupe, never on a thumbnail.
- The mouse wheel is often not an action in the input layer: scripts must send it explicitly.
- A contrast measured on a zone that includes a badge or icon gives a meaningless figure: tight zone,
  and measure the ACTIVE state right after the gesture (idle states may be dimmed on purpose).

## Filled by the duo

<!-- Procedure done twice or pitfall paid: one line here, in the task's commit. -->
