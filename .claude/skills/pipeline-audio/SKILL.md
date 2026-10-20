---
name: pipeline-audio
description: Produce a sound for the app - ElevenLabs dry run then paid (only if the task says so), audio gate, listening page for the owner, measured conversion to WAV/OGG, text recipe, reference from data, proof by a log line. Use for a task with DOMAINS audio. Do NOT use for licensed or purchased music, to tune a mix in code without a new file, or while docs/parking/ASSET-PIPELINE.md is not validated by the owner (then no sound file enters the repo).
---

# Pipeline audio

Direction and rules: `docs/parking/ASSET-PIPELINE.md` § 11 (and § 5-8: formats, recipe, LFS,
budgets). Here: the gesture and the traps.

**You never listen. No agent ever plays a sound.** The owner listens. The proof of a sound is
its log line (file loaded, duration, loop flag, trigger), never "I heard it".
A paid batch needs the owner's explicit yes for THAT batch and the task saying `--pay`.

## The gesture

1. The sound is in the inventory of `docs/parking/ASSET-PIPELINE.md` § 11 (otherwise: add it).
   Search a free sound first (CC0), licence in `docs/CREDITS.md`.
2. **Prompt**, audible and precise (source, material, gesture, distance, count); the tool adds the
   anti-hum suffix and refuses "quiet / faint / near-silent". Dry run:
   `python tools/gen/elevenlabs.py sound --prompt "..." --seconds 3 --out assets_src/audio/<name>/raw_a.mp3`
   then `--pay` if the task allows. 3 variants at most (`batch jobs.json`).
3. **Gate**: `python tools/audio/gate.py assets_src/audio/<name>/*.mp3`. REJECTED = redo, never offer it.
4. **Owner's listen**: `python tools/audio/listen_page.py assets_src/audio/<name>` -> the report gives
   the page path; the supervisor shows it. Wait for the owner's choice (keep / redo how).
5. **Conversion** of the chosen file:
   `python tools/audio/convert.py assets_src/audio/<name>/raw_b.mp3 <shipped folder>/<name>.ogg --mode hit`
   (`loop` for a real loop, `split` for a series of steps). The printed measurements go into the report.
6. **Recipe** (origin, prompt, chosen variant, steps, credits, validated by), LFS declared BEFORE
   `git add`, file referenced from data (volume, loop flag in data, not in code).
7. **Proof**: a headless test or bench that triggers the sound and reads the log line
   (file, duration, loop, moment). Never a played sound.

Dependencies: `numpy`, `soundfile` (OGG needs a libsndfile with Vorbis, shipped with recent
`soundfile` wheels). Missing: ask the owner (no install by an agent).

## Traps already paid for

- A "quiet / faint" prompt returns hiss or inaudible sub-bass: the owner rejected it as "broken".
- A generated mp3 can carry 70-80 % of its energy below 50 Hz: high-pass 40 Hz (default of
  `convert.py`), measured before / after.
- A sound named "loop" is not a loop: the loop flag is set on the shipped asset or in data, and
  re-read. A sound replayed on a timer is NOT a loop (otherwise it never ends).
- Mono = mean of the channels: the level loss (phase cancellation) is measured, not assumed.
- A series of footsteps: split by attacks and bring every step to the SAME active level (9 dB
  apart in a raw series); the app varies them by +-3 dB afterwards.
- Vorbis is lossy: the re-measured peak can move by a few tenths of a dB; re-measure the OGG.
- No continuous ambience by default (it tires and masks signals).
- A replaced sound is deleted only after a grep proves nothing cites it.

## To be completed by the duo

<!-- Procedure done twice, trap paid once: one line here, in the task's commit. -->
