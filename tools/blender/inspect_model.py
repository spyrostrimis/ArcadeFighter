"""Imports a model (fbx/obj/glb), prints a report and renders front + side previews.

Run: C:/Blender/blender.exe -b -P tools/blender/inspect_model.py -- MODEL OUT_PREFIX
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
path, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(path)[1].lower()
if ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=path)
elif ext == ".obj":
    bpy.ops.wm.obj_import(filepath=path)
else:
    bpy.ops.import_scene.gltf(filepath=path)
scene = bpy.context.scene
bpy.context.view_layer.update()

print("=== REPORT", os.path.basename(path))
meshes = [o for o in scene.objects if o.type == "MESH"]
arms = [o for o in scene.objects if o.type == "ARMATURE"]
tris = 0
lo = Vector((1e9, 1e9, 1e9))
hi = -lo
for o in meshes:
    me = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    tris += sum(len(p.vertices) - 2 for p in me.polygons)
    for v in me.vertices:
        w = o.matrix_world @ v.co
        lo = Vector(map(min, lo, w))
        hi = Vector(map(max, hi, w))
    print(f"mesh {o.name}: verts {len(me.vertices)} mats {[s.material.name if s.material else None for s in o.material_slots]}"
          f" vcols {len(me.color_attributes)} uv {len(me.uv_layers)} parent {o.parent.name if o.parent else None}"
          f" groups {len(o.vertex_groups)}")
print(f"total tris {tris}  bbox min {tuple(round(c, 3) for c in lo)} max {tuple(round(c, 3) for c in hi)}"
      f" size {tuple(round(c, 3) for c in (hi - lo))}")
for a in arms:
    bones = [b.name for b in a.data.bones]
    print(f"armature {a.name}: {len(bones)} bones e.g. {bones[:6]}")
for act in bpy.data.actions:
    print(f"action {act.name}: frames {tuple(act.frame_range)}")
for img in bpy.data.images:
    print(f"image {img.name}: {img.size[:]} packed {img.packed_file is not None} file {img.filepath}")

# ---- preview renders (original materials)
center = (lo + hi) / 2
height = (hi - lo).z
cam_data = bpy.data.cameras.new("C")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(height, (hi - lo).x, (hi - lo).y) * 1.1
cam = bpy.data.objects.new("C", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
sun = bpy.data.objects.new("S", bpy.data.lights.new("S", "SUN"))
sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
scene.collection.objects.link(sun)
scene.world = bpy.data.worlds.new("W")
scene.world.color = (0.35, 0.35, 0.38)
r = scene.render
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        r.engine = eng
        break
    except TypeError:
        pass
r.resolution_x = 512
r.resolution_y = 512
scene.view_settings.view_transform = "Standard"
for name, d in (("front", Vector((0, -1, 0))), ("side", Vector((-math.cos(math.radians(30)), -math.sin(math.radians(30)), 0)))):
    cam.location = center + d * 20
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    r.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("=== END")
