# SKINNING WEIGHTS BY DISTANCE - the fallback when Bone Heat refuses.
#
# Why this file exists: on a generated mesh (Meshy...), Blender's automatic assignment
# ("Automatic Weights", Bone Heat) FAILS - "failed to find solution for one or more
# bones". The mesh stays parented to the armature, every vertex group is EMPTY, and
# the animation moves nothing: the contact sheet comes out with six IDENTICAL
# thumbnails and you hunt for the bug in the keyframes for half an hour. The cause is
# the topology of the generated mesh (overlapping shells, non-manifold), not the rig.
#
# What this script does instead: for each vertex it finds the TWO closest bone
# segments (point-to-segment distance, not point-to-head) and splits the weight in
# 1/d^2 between them, then smooths. Crude, and largely enough for round creatures;
# a generated creature was skinned this way and passed the animation gate.
#
# Usage (inside Blender, mesh and armature already parented):
#     exec(open(r"...\tools\blender\weight_distance.py").read())
#     set_weights(bpy.data.objects["Creature_Mesh"],
#                 bpy.data.objects["Creature_Rig"],
#                 ignore=("root",), smoothing=4)
#     check_weights(bpy.data.objects["Creature_Mesh"])
#
# Pure ASCII.
import bpy


def _segment_distance(p, a, b):
    """Distance from point p to the segment [a, b] (not to the line)."""
    ab = b - a
    len2 = ab.length_squared
    if len2 < 1e-9:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / len2))
    return (p - (a + ab * t)).length


def set_weights(mesh, arm, ignore=(), smoothing=4, power=2.0, minimum=1e-4):
    """Spreads the weights of `mesh` over the bones of `arm`, by distance.

    ignore: names of bones that must carry no weight (typically "root", which is a
    reference and not a limb - giving it weight glues the creature to the ground as
    soon as the root is animated).
    Returns (vertices processed, bones used).
    """
    bones = [b for b in arm.data.bones if b.name not in ignore]
    if not bones:
        raise RuntimeError("no usable bone (is everything in ignore?)")

    # The vertex groups must exist AND be empty before starting.
    for b in bones:
        if b.name in mesh.vertex_groups:
            mesh.vertex_groups.remove(mesh.vertex_groups[b.name])
        mesh.vertex_groups.new(name=b.name)

    # Bone segments in WORLD space, brought back into the mesh's local space: the two
    # objects can have different transforms, and a rig posed at the origin guarantees
    # nothing (a scale mismatch was paid for once).
    to_local = mesh.matrix_world.inverted()
    segments = []
    for b in bones:
        a = to_local @ (arm.matrix_world @ b.head_local)
        c = to_local @ (arm.matrix_world @ b.tail_local)
        segments.append((b.name, a, c))

    for v in mesh.data.vertices:
        p = v.co
        dists = sorted((_segment_distance(p, a, c), name) for name, a, c in segments)
        weights = [(name, 1.0 / max(d, minimum) ** power) for d, name in dists[:2]]
        total = sum(w for _n, w in weights)
        for name, w in weights:
            mesh.vertex_groups[name].add([v.index], w / total, 'REPLACE')

    # Smoothing is what makes the result acceptable: without it, the joints between
    # segments tear into staircase steps.
    if smoothing > 0 and not bpy.context.window_manager.windows:
        # blender -b has no window, so no VIEW_3D area to override with (see below)
        print("weight_distance: no window (background Blender), smoothing SKIPPED - run it from a UI/MCP session")
    elif smoothing > 0:
        # vertex_group_smooth is an OPERATOR, and it is demanding TWICE (paid for once):
        # (1) it needs a VIEW_3D area in the context, which the MCP server does not
        # provide -> temp_override; (2) its poll refuses OBJECT mode, it wants EDIT or
        # WEIGHT_PAINT. A plain "active + selected object" is not enough: poll() returns
        # False and the call fails with "context is incorrect", which looks like
        # anything but "wrong mode".
        prev = bpy.context.view_layer.objects.active
        selection = [o for o in bpy.context.view_layer.objects if o.select_get()]
        win = bpy.context.window_manager.windows[0]
        area = next((a for a in win.screen.areas if a.type == 'VIEW_3D'), win.screen.areas[0])
        try:
            with bpy.context.temp_override(window=win, area=area, region=area.regions[-1]):
                bpy.ops.object.select_all(action='DESELECT')
                mesh.select_set(True)
                bpy.context.view_layer.objects.active = mesh
                bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
                for _ in range(smoothing):
                    bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=1)
                bpy.ops.object.mode_set(mode='OBJECT')
        finally:
            try:
                bpy.ops.object.select_all(action='DESELECT')
                for o in selection:
                    o.select_set(True)
                bpy.context.view_layer.objects.active = prev
            except Exception:
                pass

    return len(mesh.data.vertices), len(bones)


def check_weights(mesh, threshold=0.999):
    """Counts the vertices with no weight and those whose sum is not ~1.

    Call it AFTER set_weights: an orphan vertex never moves, and that is the only
    thing that tells "the rig does not work" from "the rig works but this vertex
    stayed behind".
    """
    orphans = 0
    off_norm = 0
    for v in mesh.data.vertices:
        s = sum(g.weight for g in v.groups)
        if s <= 0.0:
            orphans += 1
        elif abs(s - 1.0) > (1.0 - threshold):
            off_norm += 1
    return orphans, off_norm


print("distance weights ready: set_weights(mesh, arm, ignore, smoothing) then check_weights(mesh)")
