"""Builds a simple rigged test mannequin (CED colours) with two actions, to test
the sprite pipeline before the real Mixamo character exists.

Run: C:/Blender/blender.exe -b -P tools/blender/make_mannequin.py -- out.blend
The character faces -Y like a Mixamo import.
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "test_mannequin.blend"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")

BONES = {
    # name: (head, tail, parent)
    "hips": ((0, 0, 0.95), (0, 0, 1.05), None),
    "spine": ((0, 0, 1.05), (0, 0, 1.30), "hips"),
    "chest": ((0, 0, 1.30), (0, 0, 1.45), "spine"),
    "neck": ((0, 0, 1.45), (0, 0, 1.55), "chest"),
    "head": ((0, 0, 1.55), (0, 0, 1.78), "neck"),
}
for side, sx in (("L", 1), ("R", -1)):
    BONES.update({
        f"upper_arm.{side}": ((0.19 * sx, 0, 1.42), (0.21 * sx, 0, 1.14), "chest"),
        f"forearm.{side}": ((0.21 * sx, 0, 1.14), (0.22 * sx, 0, 0.90), f"upper_arm.{side}"),
        f"hand.{side}": ((0.22 * sx, 0, 0.90), (0.22 * sx, 0, 0.82), f"forearm.{side}"),
        f"thigh.{side}": ((0.10 * sx, 0, 0.95), (0.11 * sx, 0, 0.52), "hips"),
        f"shin.{side}": ((0.11 * sx, 0, 0.52), (0.11 * sx, 0.02, 0.10), f"thigh.{side}"),
        f"foot.{side}": ((0.11 * sx, 0.02, 0.10), (0.11 * sx, -0.14, 0.03), f"shin.{side}"),
    })
eb = arm_data.edit_bones
for name, (h, t, p) in BONES.items():
    b = eb.new(name)
    b.head = h
    b.tail = t
    if p:
        b.parent = eb[p]
        b.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- materials
def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m["base_rgb"] = rgb
    return m

def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)

M = {
    "skin": mat("skin", srgb("e7a77a")),
    "hair": mat("hair", srgb("6b3b1e")),
    "sweater": mat("sweater", srgb("7b5236")),
    "pants": mat("pants", srgb("d9c9a8")),
    "boots": mat("boots", srgb("8b5129")),
}

# ---------------------------------------------------------------- body parts
def part(kind, bone, size, material, offset=(0, 0, 0), rot=(0, 0, 0)):
    """Creates a primitive in the bone's rest space and bone-parents it."""
    if kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=1, depth=1)
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = f"{bone}_{kind}"
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    b = arm_data.bones[bone]
    head = arm.matrix_world @ b.head_local
    tail = arm.matrix_world @ b.tail_local
    d = tail - head
    length = d.length
    # orient local Z along the bone
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = q @ Vector(rot).to_track_quat("Z", "Y") if False else q
    o.location = (head + tail) / 2 + Vector(offset)
    sx, sy, sz = size
    o.scale = (sx, sy, sz if sz else length)
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = arm
    o.parent_type = "BONE"
    o.parent_bone = bone
    o.matrix_world = mw
    return o

for side in ("L", "R"):
    part("cyl", f"upper_arm.{side}", (0.055, 0.055, 0), M["sweater"])
    part("sphere", f"upper_arm.{side}", (0.06, 0.06, 0.06), M["sweater"], offset=(0, 0, 0.13))
    part("cyl", f"forearm.{side}", (0.048, 0.048, 0), M["sweater"])
    part("sphere", f"hand.{side}", (0.05, 0.055, 0.06), M["skin"])
    part("cyl", f"thigh.{side}", (0.085, 0.085, 0), M["pants"])
    part("cyl", f"shin.{side}", (0.075, 0.075, 0), M["pants"])
    part("sphere", f"shin.{side}", (0.08, 0.08, 0.08), M["pants"], offset=(0, 0, 0.2))
    part("cube", f"foot.{side}", (0.09, 0.1, 0), M["boots"])
part("sphere", "spine", (0.17, 0.12, 0.2), M["sweater"], offset=(0, 0, 0.05))
part("sphere", "chest", (0.2, 0.13, 0.14), M["sweater"])
part("sphere", "hips", (0.16, 0.12, 0.12), M["pants"])
part("cyl", "neck", (0.05, 0.05, 0), M["skin"])
part("sphere", "head", (0.095, 0.11, 0.12), M["skin"])
part("sphere", "head", (0.1, 0.1, 0.09), M["hair"], offset=(0, 0.025, 0.06))

# ---------------------------------------------------------------- animation helpers
pb = arm.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"


def pose(frame, rots, loc=None):
    """rots: bone -> (x, y, z) degrees in bone-local space."""
    for b in pb:
        r = rots.get(b.name, (0, 0, 0))
        b.rotation_euler = [math.radians(v) for v in r]
        b.keyframe_insert("rotation_euler", frame=frame)
    hip = pb["hips"]
    hip.location = loc or (0, 0, 0)
    hip.keyframe_insert("location", frame=frame)


def new_action(name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    return act


# Fighting stance (bone-local X rotation = swing forward/back for these bones).
STANCE = {
    "upper_arm.L": (-60, 0, 10), "forearm.L": (-95, 0, 0),
    "upper_arm.R": (-45, 0, -10), "forearm.R": (-110, 0, 0),
    "thigh.L": (-25, 0, 8), "shin.L": (35, 0, 0),
    "thigh.R": (20, 0, -8), "shin.R": (25, 0, 0),
    "spine": (6, 0, 0), "head": (-6, 0, 0),
}


def stance(extra=None, breathe=0.0):
    r = dict(STANCE)
    r["spine"] = (6 + breathe * 2, 0, 0)
    r["upper_arm.L"] = (-60 - breathe * 3, 0, 10)
    if extra:
        r.update(extra)
    return r


new_action("idle")
for f, b in ((1, 0.0), (9, 1.0), (17, 0.0)):
    pose(f, stance(breathe=b), loc=(0, 0, -0.06 - 0.012 * b))

new_action("jab")
pose(1, stance(), loc=(0, 0, -0.06))
pose(4, stance({"upper_arm.L": (-75, 0, 10), "forearm.L": (-120, 0, 0)}), loc=(0, 0, -0.06))
pose(6, stance({"upper_arm.L": (-90, 0, 0), "forearm.L": (-5, 0, 0), "spine": (12, 0, -15)}), loc=(0, -0.03, -0.06))
pose(9, stance({"upper_arm.L": (-88, 0, 0), "forearm.L": (-10, 0, 0), "spine": (12, 0, -15)}), loc=(0, -0.03, -0.06))
pose(14, stance(), loc=(0, 0, -0.06))

arm.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_as_mainfile(filepath=out)
print("saved", out)
