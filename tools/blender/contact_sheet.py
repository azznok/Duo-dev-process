# contact_sheet.py - the contact sheet of the animation gate (docs/parking/ASSET-PIPELINE.md, gate E).
# Renders N frames of an animation loop into ONE assembled image (grid), through an
# orthographic camera framed on the target object. No dependency outside Blender
# (numpy ships with it). Runs INSIDE Blender, two ways:
#   blender -b scene.blend --factory-startup --python tools/blender/contact_sheet.py -- \
#       <target object> <action> 0,6,12,16,23,27 <out.png> [thumb_px] [columns]
#   or from a Blender session (MCP):  exec(open(r"<path>", encoding="utf-8").read())
#                                     contact_sheet("Creature", "Creature_Loop", [0, 6, 12], r"...\out.png")
# Six IDENTICAL thumbnails mean nothing moves: suspect empty skin weights before the keyframes
# (tools/blender/weight_distance.py).

import os
import sys

import bpy
import numpy as np
from mathutils import Vector


def _frame_camera(target, margin=1.35):
    """Orthographic side camera (looking +Y, Blender is Z-up), framed on the target's bounding box."""
    cam_data = bpy.data.cameras.get("CamSheet") or bpy.data.cameras.new("CamSheet")
    cam = bpy.data.objects.get("CamSheet")
    if cam is None:
        cam = bpy.data.objects.new("CamSheet", cam_data)
        bpy.context.scene.collection.objects.link(cam)
    bbox = [target.matrix_world @ Vector(c) for c in target.bound_box]
    centre = sum(bbox, Vector()) / 8.0
    height = max(v.z for v in bbox) - min(v.z for v in bbox)
    width = max(v.x for v in bbox) - min(v.x for v in bbox)
    depth = max(v.y for v in bbox) - min(v.y for v in bbox)
    size = max(height, width, depth, 1e-3)
    cam_data.type = 'ORTHO'
    # margin in height: the loop moves the body up and down
    cam_data.ortho_scale = max(height, width) * margin
    # distance and clipping follow the object's size: a fixed distance only fits one unit scale
    cam.location = centre + Vector((0, -10 * size, 0))
    cam_data.clip_end = 30 * size
    cam.rotation_euler = (np.pi / 2, 0, 0)  # looks along +Y
    bpy.context.scene.camera = cam
    return cam


def contact_sheet(target_name, action_name, frames, out_path, thumb=360, columns=3):
    # A relative path in a background Blender is resolved against Blender's own folder,
    # not the current directory: always absolute.
    out_path = os.path.abspath(out_path)
    scn = bpy.context.scene
    target = bpy.data.objects[target_name]
    # the requested action on every armature that knows it
    act = bpy.data.actions[action_name]
    for ob in bpy.data.objects:
        if ob.type == 'ARMATURE':
            if ob.animation_data is None:
                ob.animation_data_create()
            ob.animation_data.action = act
    _frame_camera(target)
    scn.render.resolution_x = thumb
    scn.render.resolution_y = thumb
    scn.render.film_transparent = False
    # Workbench: a CLEAN camera render (no viewport overlays - the OpenGL viewport render
    # embedded gizmos and the grid the first time it was tried)
    engine = scn.render.engine
    scn.render.engine = 'BLENDER_WORKBENCH'

    tiles = []
    for f in frames:
        scn.frame_set(f)
        bpy.ops.render.render(write_still=False)
        img = bpy.data.images['Render Result']
        # Render Result does not expose its pixels directly: go through a saved file
        tmp = out_path + (".tile%03d.png" % f)
        img.save_render(tmp)
        loaded = bpy.data.images.load(tmp)
        px = np.array(loaded.pixels[:], dtype=np.float32)
        px = px.reshape(loaded.size[1], loaded.size[0], 4)
        tiles.append(px[::-1])  # origin at the top
        bpy.data.images.remove(loaded)
        os.remove(tmp)

    rows = (len(tiles) + columns - 1) // columns
    h, w = tiles[0].shape[0], tiles[0].shape[1]
    grid = np.ones((rows * h, columns * w, 4), dtype=np.float32)
    for i, t in enumerate(tiles):
        r, c = i // columns, i % columns
        grid[r * h:(r + 1) * h, c * w:(c + 1) * w] = t

    out = bpy.data.images.new("ContactSheet", columns * w, rows * h, alpha=True)
    out.pixels = grid[::-1].ravel().tolist()
    out.filepath_raw = out_path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    scn.render.engine = engine
    print("CONTACT SHEET OK -> %s (%d thumbnails, frames %s)" % (out_path, len(tiles), frames))


if "--" in sys.argv:
    _a = sys.argv[sys.argv.index("--") + 1:]
    if len(_a) < 4:
        print("usage: blender -b scene.blend --python contact_sheet.py -- <target> <action> <f1,f2,...> <out.png> [thumb] [columns]")
    else:
        contact_sheet(_a[0], _a[1], [int(x) for x in _a[2].split(",")], _a[3],
                      int(_a[4]) if len(_a) > 4 else 360, int(_a[5]) if len(_a) > 5 else 3)
