"""Turns high-res renders (from tools/blender/render_sprites.py) into game sprites.

Run: python tools/pixelize.py RENDER_DIR OUT_DIR NAME [--colors 40] [--outline 1a0e0a]

Steps per frame: majority-vote downscale (crisp pixels, no blur), one shared palette
for ALL frames of the character (so colours never flicker between frames), 1px
outline, crop to a common box per animation. Writes:
  OUT_DIR/NAME.png        sprite sheet (one row per animation)
  OUT_DIR/NAME.json       frame rects + anchor (feet) per animation, fps
  OUT_DIR/preview_<anim>.gif  3x preview on a dark background
"""
import json
import os
import sys

import numpy as np
from PIL import Image

import pixel_ops

args = sys.argv[1:]
RENDER, OUT, NAME = args[0], args[1], args[2]


def opt(name, default):
    return args[args.index("--" + name) + 1] if "--" + name in args else default


COLORS = int(opt("colors", "40"))
SAT = float(opt("sat", "1.35"))
CONTRAST = float(opt("contrast", "1.12"))
OUTLINE = tuple(int(opt("outline", "1a0e0a")[i:i + 2], 16) for i in (0, 2, 4))

meta = json.load(open(os.path.join(RENDER, "meta.json")))
PX = meta["px"]


def downscale(img):
    return pixel_ops.downscale(img, PX, SAT, CONTRAST)


# 1) downscale everything
anims = {}
for name, info in meta["actions"].items():
    anims[name] = [downscale(Image.open(os.path.join(RENDER, name, f))) for f in info["frames"]]

# 2) one palette for all frames
pal_img = pixel_ops.palette_from_frames([f for fr in anims.values() for f in fr], COLORS)


# nothing may show below the floor line (e.g. a stiff cape hem sinking through the floor)
floor_y = int(round(meta["anchor"][1])) + 1
for name in anims:
    for f in anims[name]:
        f[floor_y:, :, 3] = 0

for name in anims:
    anims[name] = [pixel_ops.add_outline(pixel_ops.despeckle(pixel_ops.apply_palette(f, pal_img)), OUTLINE)
                   for f in anims[name]]

# 3) crop per animation to the union box, pack rows
os.makedirs(OUT, exist_ok=True)
ax, ay = meta["anchor"]
rows = []
info_out = {"fps": meta["fps"], "animations": {}}
for name, frames in anims.items():
    alpha = np.zeros((PX, PX), bool)
    for f in frames:
        alpha |= f[:, :, 3] > 0
    ys, xs = np.nonzero(alpha)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crops = [f[y0:y1, x0:x1] for f in frames]
    rows.append((name, crops))
    info_out["animations"][name] = {"w": int(x1 - x0), "h": int(y1 - y0),
                                    "anchor": [round(ax - x0), round(ay - y0)], "frames": []}

sheet_w = max(len(c) * c[0].shape[1] for _, c in rows)
sheet_h = sum(c[0].shape[0] for _, c in rows)
sheet = np.zeros((sheet_h, sheet_w, 4), np.uint8)
y = 0
for name, crops in rows:
    h, w = crops[0].shape[:2]
    for i, c in enumerate(crops):
        sheet[y:y + h, i * w:(i + 1) * w] = c
        info_out["animations"][name]["frames"].append([i * w, y, w, h])
    # preview gif
    frames_img = []
    for c in crops:
        bg = Image.new("RGBA", (w + 8, h + 8), (40, 24, 48, 255))
        bg.alpha_composite(Image.fromarray(c, "RGBA"), (4, 4))
        frames_img.append(bg.resize(((w + 8) * 3, (h + 8) * 3), Image.Resampling.NEAREST).convert("P", palette=Image.Palette.ADAPTIVE))
    frames_img[0].save(os.path.join(OUT, f"preview_{name}.gif"), save_all=True, append_images=frames_img[1:],
                       duration=int(1000 / meta["fps"]), loop=0, disposal=2)
    y += h

Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, NAME + ".png"))
json.dump(info_out, open(os.path.join(OUT, NAME + ".json"), "w"), indent=1)
print("sheet", sheet.shape[1], "x", sheet.shape[0], "->", os.path.join(OUT, NAME + ".png"))
for n, a in info_out["animations"].items():
    print(f"  {n}: {len(a['frames'])} frames {a['w']}x{a['h']} anchor {a['anchor']}")
