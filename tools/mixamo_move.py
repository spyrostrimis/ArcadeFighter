"""Turns one Mixamo animation (FBX "With Skin") into a game move: pixel frames for
Aseprite plus the root motion (travel + jump height) that the game sim plays back.

Run: python tools/mixamo_move.py art/ced/moves/flying_knee.json [--no-render]

The spec file (next to the FBX) says how to fit the clip to the game:
  "fbx":         the Mixamo download
  "timing":      [[from_src_frame, to_src_frame, speed], ...] speed = source frames (30 fps)
                 per game frame (60 fps): 1.0 = twice as fast as Mixamo, 0.5 = Mixamo speed
  "fwd_scale":   multiply the ground travel (Mixamo moves are often far too long for a 384px screen)
  "lift_scale":  multiply the jump height
  "ground":      [[from, to], ...] source frames that stay on the floor (running steps
                 would otherwise count as tiny jumps)
  "every":       game frames per sprite frame (4 = 15 fps, like the hand-made animations)
  "ppm":         game pixels per metre (match the hand-made sprites' size)
  "palette":     sprite sheet whose colours the frames are quantized to (keeps styles together)

Writes:
  art/<cid>/moves/<move>/f_00.png ...   frames, all with the same size and feet anchor
  art/<cid>/moves/<move>/move.json      anchor, frame count, root path per game frame
  scripts/sim/move_paths.gd             all moves' root paths, for the sim (regenerated)
Then: tools/aseprite/import_frames.lua puts the frames into the .aseprite file as a tag.
"""
import glob
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixel_ops  # noqa: E402

BLENDER = r"C:\Blender\blender.exe"

spec_path = sys.argv[1]
spec = json.load(open(spec_path))
cid = spec_path.replace("\\", "/").split("/")[1]
move = os.path.splitext(os.path.basename(spec_path))[0]
render_dir = os.path.join("build", "render", f"{cid}_{move}")
out_dir = os.path.join(os.path.dirname(spec_path), move)

# ---------------------------------------------------------------- render (Blender)
if "--no-render" not in sys.argv:
    subprocess.run([BLENDER, "-b", "-P", "tools/blender/render_sprites.py", "--",
                    "--input", spec["fbx"], "--name", move, "--root-motion", "--step", "1",
                    "--ppm", str(spec.get("ppm", 60)), "--yaw", str(spec.get("yaw", 50)),
                    "--out", render_dir], check=True, stdout=subprocess.DEVNULL)
meta = json.load(open(os.path.join(render_dir, "meta.json")))
act = meta["actions"][move]
src0 = act["src_range"][0]
root = act["root"]          # per source frame: [forward_px, up_px]
PX = meta["px"]

# ---------------------------------------------------------------- timing: game frame -> source frame
src_at = []                 # fractional source frame for each game frame
for a, b, speed in spec["timing"]:
    s = float(a)
    while s < b - 1e-6:
        src_at.append(s)
        s += speed
src_at.append(float(spec["timing"][-1][1]))
n_game = len(src_at)


def root_at(s: float):
    i = s - src0
    lo = int(math.floor(i))
    hi = min(lo + 1, len(root) - 1)
    t = i - lo
    return [root[lo][k] * (1 - t) + root[hi][k] * t for k in (0, 1)]


fs, ls = spec.get("fwd_scale", 1.0), spec.get("lift_scale", 1.0)
path = []
for s in src_at:
    fwd, up = root_at(s)
    if any(a <= s <= b for a, b in spec.get("ground", [])):
        up = 0.0
    path.append([round(fwd * fs * 100), round(up * ls * 100)])
path[-1][1] = 0             # always end on the floor

# ---------------------------------------------------------------- frames
every = spec.get("every", 4)
picks = [round(src_at[g]) for g in range(0, n_game, every)]
pal = pixel_ops.palette_from_image(spec["palette"], skip_darkest=1) if spec.get("palette") else None
outline = tuple(int(spec.get("outline", "0d0309")[i:i + 2], 16) for i in (0, 2, 4))
floor_y = int(round(meta["anchor"][1])) + 1
frames = []
for s in picks:
    img = Image.open(os.path.join(render_dir, move, f"f_{s - src0:04d}.png"))
    f = pixel_ops.downscale(img, PX, spec.get("sat", 1.2), spec.get("contrast", 1.1), spec.get("bright", 1.25))
    f[floor_y:, :, 3] = 0
    if pal is None:
        pal = pixel_ops.palette_from_frames([f], 40)
    frames.append(pixel_ops.add_outline(pixel_ops.despeckle(pixel_ops.apply_palette(f, pal)), outline))

alpha = np.zeros((PX, PX), bool)
for f in frames:
    alpha |= f[:, :, 3] > 0
ys, xs = np.nonzero(alpha)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
os.makedirs(out_dir, exist_ok=True)
for old in glob.glob(os.path.join(out_dir, "f_*.png")):
    os.remove(old)
for i, f in enumerate(frames):
    Image.fromarray(f[y0:y1, x0:x1], "RGBA").save(os.path.join(out_dir, f"f_{i:02d}.png"))
anchor = [round(meta["anchor"][0] - x0), round(meta["anchor"][1] - y0)]
info = {"frames": len(frames), "size": [int(x1 - x0), int(y1 - y0)], "anchor": anchor,
        "every": every, "game_frames": n_game, "src_frames": picks, "path": path}
json.dump(info, open(os.path.join(out_dir, "move.json"), "w"))

# preview strip (3x) with the root motion applied, to judge the move at a glance
W, H = 420, 170
prev = []
for i, f in enumerate(frames):
    g = i * every
    c = Image.new("RGBA", (W, H), (40, 30, 50, 255))
    fx = 40 + path[g][0] // 100 - anchor[0]
    fy = H - 10 - path[g][1] // 100 - anchor[1]
    c.alpha_composite(Image.fromarray(f[y0:y1, x0:x1], "RGBA"), (int(fx), int(fy)))
    prev.append(c.resize((W * 2, H * 2), Image.NEAREST))
prev[0].save(os.path.join(out_dir, "preview.gif"), save_all=True, append_images=prev[1:],
             duration=int(1000 * every / 60), loop=0)

# ---------------------------------------------------------------- sim data
paths = {}
for mj in sorted(glob.glob("art/*/moves/*/move.json")):
    parts = mj.replace("\\", "/").split("/")
    paths[f"{parts[1]}/{parts[3]}"] = json.load(open(mj))["path"]
lines = ["class_name MovePaths",
         "## GENERATED by tools/mixamo_move.py - do not edit by hand.",
         "## Root motion of travelling moves: per game frame [forward, up] in 1/100 px,",
         "## relative to where the move started.", "", "const DATA := {"]
for k, p in paths.items():
    lines.append(f'\t"{k}": {json.dumps(p, separators=(",", ":"))},')
lines.append("}")
open("scripts/sim/move_paths.gd", "w", newline="\n").write("\n".join(lines) + "\n")

print(f"{cid}/{move}: {n_game} game frames, {len(frames)} sprite frames {x1 - x0}x{y1 - y0}, "
      f"anchor {anchor}, travel {path[-1][0] / 100:.0f}px, peak {max(p[1] for p in path) / 100:.0f}px")
for g in range(0, n_game, 2):
    print(f"  g{g:3d} src {src_at[g]:5.1f}  x {path[g][0] / 100:6.1f}  y {path[g][1] / 100:5.1f}")
