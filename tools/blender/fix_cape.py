"""Detaches a long coat/cape from the leg bones of a Mixamo-rigged character.

Mixamo's auto-rig skins everything near the legs to the leg bones, so a cape
stretches into a "tent" between the legs. Vertices that are clearly outside the
legs (farther than --inner m from the thigh/shin/foot bones) get their leg weight
moved to the hips, fading in until --outer m.

Run: C:/Blender/blender.exe -b -P tools/blender/fix_cape.py -- IN.fbx OUT.blend [--inner 0.11] [--outer 0.17]
"""
import sys

import bpy
from mathutils import Vector
from mathutils.geometry import intersect_point_line

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]


def opt(n, d):
    return float(argv[argv.index("--" + n) + 1]) if "--" + n in argv else d


INNER = opt("inner", 0.11)
OUTER = opt("outer", 0.17)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
# reset to rest pose so mesh data == bind pose
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

LEG = [f"mixamorig:{s}{p}" for s in ("Left", "Right") for p in ("UpLeg", "Leg", "Foot", "ToeBase", "Toe_End")]
segs = []
for b in arm.data.bones:
    if b.name in LEG and not b.name.endswith(("ToeBase", "Toe_End")):
        segs.append((arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local))


def leg_dist(p: Vector) -> float:
    best = 1e9
    for a, b in segs:
        q, t = intersect_point_line(p, a, b)
        t = max(0.0, min(1.0, t))
        best = min(best, (p - (a + (b - a) * t)).length)
    return best


changed = 0
for ob in bpy.context.scene.objects:
    if ob.type != "MESH":
        continue
    vg = {g.name: g.index for g in ob.vertex_groups}
    leg_idx = {vg[n] for n in LEG if n in vg}
    hips = ob.vertex_groups.get("mixamorig:Hips") or ob.vertex_groups.new(name="mixamorig:Hips")
    for v in ob.data.vertices:
        leg_w = sum(g.weight for g in v.groups if g.group in leg_idx)
        if leg_w <= 0.0:
            continue
        p = ob.matrix_world @ v.co
        d = leg_dist(p)
        if d <= INNER:
            continue
        k = min(1.0, (d - INNER) / (OUTER - INNER))
        moved = 0.0
        for g in v.groups:
            if g.group in leg_idx:
                m = g.weight * k
                ob.vertex_groups[g.group].add([v.index], g.weight - m, "REPLACE")
                moved += m
        hips.add([v.index], moved, "ADD")
        changed += 1
print(f"cape fix: reassigned {changed} vertices (inner {INNER} m, outer {OUTER} m)")
bpy.ops.wm.save_as_mainfile(filepath=dst)
print("saved", dst)
