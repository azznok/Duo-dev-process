---
name: pipeline-3d
description: Produce or integrate a 3D asset (model, creature, prop, part) - search for a free asset first, Meshy concept image then 3D (dry run, then paid only if the task says so), Blender cleanup headless or by MCP, primitive kit by code for flat-faced objects, GLB measurement, recipe, LFS, capture in the app next to the reference. Use for a task with DOMAINS 3d. Do NOT use to place already-integrated assets in a scene, for UI, for sound (pipeline-audio), or while docs/parking/ASSET-PIPELINE.md is not validated by the owner (then: everything by code).
---

# Pipeline 3D

The normative rules are `docs/parking/ASSET-PIPELINE.md` (search first, attempts, gates A-E,
budgets, LFS, recipes). Here: the gesture, in order, and the traps already paid for. This skill
grows: a trap paid once is added at the bottom, in the task's commit.

**While the owner has not validated the pipeline**: no binary enters the repo; a task that needs
one ends `STATUS: IMPOSSIBLE` with a proposed question. Paid calls (`--pay`) only if the task says so.

## The gesture

1. **Search first** (project, then free sources, 20 min max). Found: licence in `docs/CREDITS.md`
   and in the recipe, then step 6.
2. **Flat-faced object** (box, chamfer, frame, panel, pipe)? Build it by code, 0 credits:
   `tools/mesh/gltf_lib.py` (`Mesh.box`, `cylinder_y`, `torus_y`, `write_glb`) or a Blender script
   run headless. One PARAMETRIC generator per family of sizes (every dimension a ratio of the
   section), never one drawing per size. Iterate on the numbers (a plan file), not on the GLB.
3. **Concept image** from the validated reference in `docs/art/refs/`:
   `python tools/gen/meshy.py image --prompt "<subject>, <style block>" --ref docs/art/refs/<ref>.png --out assets_src/3d/<name>/concept_v1.png`
   (dry run), then `--pay` if the task allows. Board next to the reference: `tools/image/sheet.ps1`.
   For a 3D model: FLAT views (front, side, back), checked by eye (gate A).
4. **3D** once the views pass gate A, from those views ONLY:
   `python tools/gen/meshy.py batch jobs.json` with `{"type": "3d", "views": [...], "out": ..., "api": {...}}`
   (`api` = Meshy parameters as is, e.g. `"should_remesh": false` for hard surfaces).
5. **Clean** in Blender (`blender -b --factory-startup --python <script> -- <in> <out> ...`, a
   versioned script, never hand edits): scale, pivot on the ground, facing axis, merge, decimate to
   budget, bake colour + normals if needed, collision. Gate C.
6. **Measure** (gate B): `python tools/mesh/glb_measure.py <glb> --budget N [--nodes]`.
   Matte materials / cut a generated base: `python tools/mesh/glb_mat.py`.
7. **Recipe** (origin, prompt, sources, steps with arguments, budget >= measured, credits), LFS
   declared BEFORE `git add`, then `git lfs ls-files`. Data references the file; the data check passes.
8. **In the app** (gate D): capture near and far (skill `proofs`), next to the validated concept;
   the art judge decides (skill `art-judge`). Animation: gate E, `tools/blender/contact_sheet.py`.

`blender` = config `BLENDER_EXE` (nothing installed by an agent). The harness starts the Blender
MCP for tasks with DOMAINS 3d (`tools/blender/boot.py`).

## Traps already paid for

**Generation (Meshy)**
- Iterate on the IMAGE (a few credits), not on the 3D (tens). Never texture a rejected silhouette.
- Image-to-image: 5 references at most (HTTP 400 beyond, nothing billed); to show more, paste them
  into ONE strip image. To fix one detail, use the image itself as the reference with
  "same subject, same pose... but <change>": the rest is kept.
- A lineup of more than ~6 characters: the generator loses, doubles or changes some. Assemble the
  board from validated portraits (PIL, free) instead of paying for attempts.
- A three-quarter view among the 3D input views: the model comes out squashed. Flat views only.
- The quad remesh comes out "mushy" on hard surfaces: `should_remesh: false`, clean in Blender.
- Some models IGNORE `target_polycount`: the budget is held at cleanup. No brutal collapse (torn
  mesh): planar dissolve, then gentle collapse. Plain decimation, fitted boxes, voxel remesh alone
  were refused (dirty, hollow, pixelated).
- A generated mesh = dozens of overlapping shells: "one single piece" is judged on the image.
- What the generator misses (revolved parts, thin parts, moving parts, glowing parts) is redone
  by CODE as separate named objects, dimensions and colours read on the generated model (printed),
  never by eye. When the generated body resists, rebuild the body by code too.
- 2 Meshy jobs in parallel at most; never poll a status by hand: `meshy.py resume`.

**Blender**
- Blender is Z up, glTF is Y up: import maps X->X, Y->-Z, Z->Y, export the reverse. Reason in glTF.
- A relative output path in background Blender resolves against Blender's folder, not the current
  one: always `os.path.abspath`.
- An object created while a namesake exists is called `name.001`: the data names the exact node; rename.
- A Boolean DIFFERENCE adds an EMPTY material slot first: the object exports WITHOUT material
  (white). After the Boolean: clear the materials, then assign.
- A bevel with 2-3 segments reads ROUNDED ("cushion"): a sharp chamfer = 1 segment.
- A revolved ring costs segments x profile x 2 triangles: count before (96 x 48 blew the budget, 72 x 28 was enough).
  Smooth it (`face.smooth = True`, then sharp profile edges back): flat-shaded, it shows concentric stripes.
- Scale is set in Blender, never in export/import options (they were not applied); bones do not
  follow a `transform_apply`: check by re-importing into an empty scene.
- Auto rig: humanoid bipeds only. "Bone Heat" fails on a generated mesh with NO visible error (six
  identical contact-sheet thumbnails): `tools/blender/weight_distance.py`.
- A transparent part (glass, visor) = separate geometry.
- Silent Blender after a PC reboot: `tools/blender/boot.py` enables the add-on and starts the server explicitly.

**Measurement and judging**
- `glb_measure.py`'s global box ignores node translations: the true box is `--nodes`.
- Colours of a generated mesh: fix them PER MATERIAL (faces classified by their baked pixel), read
  on the reference by pixel and cited in the script; the judge compares flat colours to the board.
- A relief under ~3 % of the object size is not read in a capture: make it protrude, not recess.
- Emissive on a LIGHT albedo comes out whitish after tone mapping; a strong glow saturates towards
  yellow. Set the lit colour by the albedo and a weak glow; measure on the capture before the judge.
- A small object in the frame: the judge invents details. Contrast is won by the BACKGROUND.
- The player's character inside the captured silhouette reads as part of the object: frame it out.
- The blind judge varies between attempts: fix the gaps seen twice.

**Git**
- Nothing over 10 MB in a commit: the file stays on the owner's disk, named in the recipe with its size.
- A PNG that will not open ("out of memory") may be an LFS pointer: `git lfs pull` (or smudge it).

## To be completed by the duo

<!-- Procedure done twice, trap paid once: one line here, in the task's commit. -->
