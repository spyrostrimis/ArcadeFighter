"""Cut CED's key poses out of a ChatGPT sheet (figures on flat magenta, side by side)
and scale them to game size. All poses share one scale so they line up.
Usage: python tools/aseprite/cutout_keys.py art/ced/ref/hp_keys.webp art/ced/keys/hp 113
Writes <prefix>_1.png, _2.png ... (RGBA, feet on the bottom row) and a 4x preview."""
import sys
import numpy as np
from PIL import Image

src, prefix, target_h = sys.argv[1], sys.argv[2], int(sys.argv[3])
a = np.asarray(Image.open(src).convert("RGB")).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
fg = ~((b > g + 60) & (r > g + 60))          # anything that isn't magenta

# figures = runs of non-empty columns
col = fg.sum(0) > 0
runs, x = [], 0
while x < len(col):
    if col[x]:
        s = x
        while x < len(col) and col[x]:
            x += 1
        if x - s > 50:
            runs.append((s, x - 1))
    x += 1
rows = np.where(fg.any(1))[0]
top, bot = rows.min(), rows.max()            # shared floor line = lowest sole
scale = (bot - top + 1) / target_h

outs = []
for i, (x0, x1) in enumerate(runs, 1):
    crop = a[top:bot + 1, x0:x1 + 1].astype(np.uint8)
    alpha = (fg[top:bot + 1, x0:x1 + 1] * 255).astype(np.uint8)
    im = Image.fromarray(np.dstack([crop, alpha]), "RGBA")
    w = max(1, round(im.width / scale))
    small = np.asarray(im.resize((w, target_h), Image.LANCZOS)).copy()
    op = small[..., 3] >= 110
    small[..., 3] = np.where(op, 255, 0)
    # silhouette edge -> dark outline (downscaling greys it out)
    pad = np.pad(op, 1)
    edge = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    rgb = small[..., :3].astype(int)
    lum = rgb @ [0.3, 0.59, 0.11]
    dark = edge & (lum > 70)
    small[dark, :3] = (rgb[dark] * 0.35 + np.array([40, 22, 20]) * 0.65).astype(np.uint8)
    out = Image.fromarray(small, "RGBA")
    out.save(f"{prefix}_{i}.png")
    outs.append(out)
    print(f"pose {i}: {out.size}")

W = sum(o.width for o in outs) + 10 * (len(outs) + 1)
prev = Image.new("RGBA", (W, target_h + 20), (60, 70, 90, 255))
x = 10
for o in outs:
    prev.alpha_composite(o, (x, 10))
    x += o.width + 10
prev.resize((prev.width * 4, prev.height * 4), Image.NEAREST).save(f"{prefix}_preview.png")
print("scale", round(scale, 3))
