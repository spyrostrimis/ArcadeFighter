"""Make a new key pose from an existing one by swinging a limb around a joint, at the
source sheet's full resolution (before cutout_keys.py scales it down).
Used for KROS's mid kick: his high-kick leg lowered to stomach height.

The figure (FIG box) is copied to the right of the sheet as an extra pose, with the limb
(POLY, in sheet coordinates) rotated around PIVOT by ANGLE degrees (positive = clockwise
on screen, i.e. the foot goes down). Limb pixels closer than KEEP px to the pivot are also
left in place so the joint has no gap.

Usage: python tools/aseprite/rotate_limb.py SHEET OUT --fig x0,y0,x1,y1
         --poly x,y,x,y,... --pivot x,y --angle DEG [--keep 40]"""
import argparse
import numpy as np
from PIL import Image, ImageDraw

p = argparse.ArgumentParser()
p.add_argument("sheet")
p.add_argument("out")
p.add_argument("--fig", required=True)
p.add_argument("--poly", required=True)
p.add_argument("--pivot", required=True)
p.add_argument("--angle", type=float, required=True)
p.add_argument("--keep", type=float, default=40)
args = p.parse_args()

ints = lambda s: [int(v) for v in s.split(",")]
x0, y0, x1, y1 = ints(args.fig)
poly = ints(args.poly)
px, py = ints(args.pivot)

src = Image.open(args.sheet).convert("RGB")
a = np.asarray(src).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
fg = ~((b > g + 60) & (r > g + 60))
MAGENTA = np.array([250, 18, 250])

limb_mask = Image.new("L", src.size, 0)
ImageDraw.Draw(limb_mask).polygon(list(zip(poly[0::2], poly[1::2])), fill=255)
limb = np.asarray(limb_mask) > 0
limb &= fg

yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
near = (xx - px) ** 2 + (yy - py) ** 2 < args.keep ** 2

# body: the figure without the limb (except next to the joint)
body = fg & ~(limb & ~near)
body[:, :x0] = False
body[:, x1 + 1:] = False
# limb on its own, rotated (transparent pixels take the outline colour, not magenta)
rgba = np.dstack([a, limb * 255]).astype(np.uint8)
rgba[~limb, :3] = (30, 20, 25)
rot = Image.fromarray(rgba, "RGBA").rotate(-args.angle, resample=Image.BICUBIC, center=(px, py))
rot = np.asarray(rot).astype(int)
ra = rot[..., 3:4] / 255.0

fig = np.where(body[..., None], a, MAGENTA)
fig = (rot[..., :3] * ra + fig * (1 - ra)).astype(np.uint8)
has = body | (ra[..., 0] > 0.43)
cols = np.where(has.any(0))[0]
c0, c1 = cols.min(), cols.max()

W = src.width + (c1 - c0 + 1) + 80
out = np.tile(MAGENTA.astype(np.uint8), (src.height, W, 1))
out[:, :src.width] = a
part = np.where(has[:, c0:c1 + 1, None], fig[:, c0:c1 + 1], MAGENTA)
out[:, src.width + 40:src.width + 40 + c1 - c0 + 1] = part
Image.fromarray(out).save(args.out)
print(args.out, out.shape, "new pose width", c1 - c0 + 1)
