"""Renders a rigged character's animations as high-res toon frames for pixelizing.

Usage (Blender in background mode):
  C:/Blender/blender.exe -b -P tools/blender/render_sprites.py -- \
      --input CHARACTER.fbx|.blend [--anims DIR_WITH_MIXAMO_FBX] --out OUTDIR \
      [--actions idle,jab] [--step 2] [--yaw 30] [--elev 6] [--px 192] [--ppm 62] [--scale 4]
      [--name MOVE] [--root-motion] [--frames 1-81]

- The character must face -Y (Mixamo default). The camera looks from its left side,
  turned `yaw` degrees toward the front, so the character faces screen-right.
- Every Mixamo animation FBX in --anims becomes an action named after the file.
- --name: the input FBX itself carries the animation (Mixamo "With Skin" download):
  name that action MOVE instead of treating it as the bind pose.
- --root-motion: for moves that travel (dashes, jumps). The hips' ground travel and the
  feet's height are taken out of every frame, so the sprite stays on its anchor, and are
  written to meta.json as "root": [[forward_px, up_px], ...] for the game to move the fighter.
- Output: OUTDIR/<action>/f_0000.png ... plus OUTDIR/meta.json (anchor pixel of the
  world origin = feet position, per action frame lists, fps).
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    if "--" + name in argv:
        return argv[argv.index("--" + name) + 1]
    return default


INPUT = arg("input")
ANIMS = arg("anims")
OUT = os.path.abspath(arg("out", "render_out"))
ACTIONS = arg("actions")
STEP = int(arg("step", "2"))
YAW = float(arg("yaw", "50"))
ELEV = float(arg("elev", "6"))
PX = int(arg("px", "192"))           # final canvas size in game pixels
PPM = float(arg("ppm", "64"))        # game pixels per metre (a 1.75 m person in a fighting stance ~ 115 px)
SCALE = int(arg("scale", "4"))       # supersampling factor for the render
OUTLINE_M = float(arg("outline", "0.012"))
TEX = int(arg("tex", "192"))
NAME = arg("name")
ROOT_MOTION = "--root-motion" in argv
FRAMES = arg("frames")      # shrink textures to this size: removes photo noise, keeps colour areas

# ---------------------------------------------------------------- load
if INPUT.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=INPUT)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=INPUT, automatic_bone_orientation=False)
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == "ARMATURE")
# the rigged character file from Mixamo carries its bind pose as "Armature|mixamo.com|Layer0"
for a in bpy.data.actions:
    if "|" in a.name or "mixamo.com" in a.name:
        a.name = NAME or "tpose"
        if NAME:
            a.use_fake_user = True
if arm.animation_data is None:
    arm.animation_data_create()


def assign(action):
    arm.animation_data.action = action
    try:
        if action.slots and arm.animation_data.action_slot is None:
            arm.animation_data.action_slot = action.slots[0]
    except AttributeError:
        pass


if ANIMS:
    for fn in sorted(os.listdir(ANIMS)):
        if not fn.lower().endswith(".fbx"):
            continue
        before = set(bpy.data.actions)
        objs_before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(ANIMS, fn), automatic_bone_orientation=False)
        new_actions = [a for a in bpy.data.actions if a not in before]
        for o in list(set(bpy.data.objects) - objs_before):
            bpy.data.objects.remove(o, do_unlink=True)
        if new_actions:
            a = new_actions[0]
            a.name = os.path.splitext(fn)[0].lower().replace(" ", "_")
            a.use_fake_user = True

# ---------------------------------------------------------------- simplify textures
for img in bpy.data.images:
    if img.size[0] > TEX and img.size[1] > 0:
        img.scale(TEX, max(1, int(TEX * img.size[1] / img.size[0])))

# ---------------------------------------------------------------- toon materials + outline
outline_mat = bpy.data.materials.new("sprite_outline")
outline_mat.use_nodes = True
nt = outline_mat.node_tree
nt.nodes.clear()
em = nt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (0.01, 0.006, 0.005, 1)
o_out = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(em.outputs[0], o_out.inputs[0])
outline_mat.use_backface_culling = True


def toonify(m):
    if m is None or m.name == "sprite_outline" or m.get("_toon"):
        return
    m["_toon"] = True
    m.use_nodes = True
    nt = m.node_tree
    base_socket = None
    base_value = tuple(m.diffuse_color)
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            inp = n.inputs["Base Color"]
            if inp.is_linked:
                base_socket = inp.links[0].from_socket
            else:
                base_value = tuple(inp.default_value)
            break
    if "base_rgb" in m.keys():
        base_value = (*m["base_rgb"], 1)
    for n in list(nt.nodes):
        if n.type in ("OUTPUT_MATERIAL", "BSDF_PRINCIPLED"):
            nt.nodes.remove(n)
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (0.62, 0.55, 0.58, 1)
    els[1].position = 0.22
    els[1].color = (0.90, 0.84, 0.80, 1)
    e3 = els.new(0.55)
    e3.color = (1.12, 1.06, 1.0, 1)  # warm highlight to match the lamp-lit stage
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    if base_socket is not None:
        nt.links.new(base_socket, mix.inputs[6])
    else:
        mix.inputs[6].default_value = base_value
    emis = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], emis.inputs["Color"])
    nt.links.new(emis.outputs[0], out.inputs["Surface"])


for o in scene.objects:
    if o.type != "MESH":
        continue
    for slot in o.material_slots:
        toonify(slot.material)
    if not o.material_slots:
        o.data.materials.append(bpy.data.materials.new("default"))
        toonify(o.material_slots[0].material)
    n_mats = len(o.material_slots)
    o.data.materials.append(outline_mat)
    sol = o.modifiers.new("sprite_outline", "SOLIDIFY")
    sol.thickness = -OUTLINE_M / max(0.001, max(o.matrix_world.to_scale()))
    sol.use_flip_normals = True
    sol.use_rim = False
    sol.material_offset = n_mats

# ---------------------------------------------------------------- camera + light
size_m = PX / PPM
margin_m = 10 / PPM
target = Vector((0, 0, size_m / 2 - margin_m))
cam_data = bpy.data.cameras.new("SpriteCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = size_m
cam = bpy.data.objects.new("SpriteCam", cam_data)
scene.collection.objects.link(cam)
yaw = math.radians(YAW)
elev = math.radians(ELEV)
d = Vector((-math.cos(yaw) * math.cos(elev), -math.sin(yaw) * math.cos(elev), math.sin(elev)))
cam.location = target + d * 20
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
cam_data.clip_end = 100
scene.camera = cam

sun_data = bpy.data.lights.new("SpriteSun", "SUN")
sun_data.energy = 3.0
sun_data.use_shadow = False  # clean flat toon bands, no shadow noise
sun = bpy.data.objects.new("SpriteSun", sun_data)
scene.collection.objects.link(sun)
# light from the camera side, above and a little in front (upper-left on screen)
ld = (d + Vector((0, -0.6, 1.0))).normalized()
sun.rotation_euler = (-ld).to_track_quat("-Z", "Y").to_euler()
if scene.world is None:
    scene.world = bpy.data.worlds.new("W")
scene.world.color = (0, 0, 0)

# ---------------------------------------------------------------- render settings
r = scene.render
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        r.engine = eng
        break
    except TypeError:
        continue
try:
    scene.eevee.taa_render_samples = 1
except AttributeError:
    pass
r.film_transparent = True
r.resolution_x = PX * SCALE
r.resolution_y = PX * SCALE
r.resolution_percentage = 100
r.image_settings.file_format = "PNG"
r.image_settings.color_mode = "RGBA"
r.filter_size = 0.01
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"

# anchor: where the world origin (feet) lands, in final game pixels from top-left
bpy.context.view_layer.update()
co = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
anchor = [co.x * PX, (1 - co.y) * PX]

# ---------------------------------------------------------------- render each action
names = [a.name for a in bpy.data.actions]
if ACTIONS:
    names = [n for n in ACTIONS.split(",") if n in names]
fps = scene.render.fps / scene.render.fps_base
meta = {"px": PX, "ppm": PPM, "anchor": anchor, "fps": fps / STEP, "actions": {}}
os.makedirs(OUT, exist_ok=True)
for name in names:
    act = bpy.data.actions[name]
    assign(act)
    f0, f1 = (int(round(v)) for v in act.frame_range)
    if FRAMES:
        f0, f1 = (int(v) for v in FRAMES.split("-"))
    frames = []
    root = []
    hips = next((b for b in arm.pose.bones if b.name.endswith("Hips")), None)
    base_loc = arm.location.copy()
    h0 = None
    for i, f in enumerate(range(f0, f1 + 1, STEP)):
        scene.frame_set(f)
        if ROOT_MOTION and hips is not None:
            arm.location = base_loc
            bpy.context.view_layer.update()
            h = arm.matrix_world @ hips.head
            low = min((arm.matrix_world @ b.head).z for b in arm.pose.bones)
            if h0 is None:
                h0 = h.copy()
            lift = max(0.0, low - 0.02)
            # character faces -Y; sideways drift (x) is depth for the side camera: drop it
            arm.location = base_loc - Vector((h.x - h0.x, h.y - h0.y, lift))
            bpy.context.view_layer.update()
            root.append([round(-(h.y - h0.y) * PPM, 2), round(lift * PPM, 2)])
        path = os.path.join(OUT, name, f"f_{i:04d}.png")
        r.filepath = path
        bpy.ops.render.render(write_still=True)
        frames.append(os.path.basename(path))
    meta["actions"][name] = {"frames": frames, "src_range": [f0, f1]}
    if root:
        meta["actions"][name]["root"] = root
    arm.location = base_loc
    print(f"rendered {name}: {len(frames)} frames")
with open(os.path.join(OUT, "meta.json"), "w") as fh:
    json.dump(meta, fh, indent=1)
print("done ->", OUT)
