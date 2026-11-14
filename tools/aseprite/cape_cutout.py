"""Cut KROS's cape out on its own: the cape = what the caped stance has outside the cape-less
stance's silhouette (lined up by the feet, the way build_kros.lua lines them up). Drawn behind
the cape-less idle it looks like the caped idle, so the cape can blink and fade on its own at
round start (FighterView).
With --fill, the gaps the body was covering are filled with the cape's dark lining, so it reads
as a whole cloth away from the body (for a future cape toss).
Usage: python tools/aseprite/cape_cutout.py art/kros/keys/cape_1.png art/kros/keys/nocape_1.png art/kros/keys/cape_only.png [--fill]
Output has the same size and feet position as the first input."""
import sys
import numpy as np
from PIL import Image

SOLE_ROW = 107
INSIDE = np.array([[58, 12, 24], [74, 16, 30], [46, 9, 20]])   # velvet lining, 3 tones


def feet(op):
    x = np.where(op[SOLE_ROW])[0]
    return (x.min() + x.max()) // 2


cape = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).copy()
body = np.asarray(Image.open(sys.argv[2]).convert("RGBA"))
cop, bop = cape[..., 3] > 0, body[..., 3] > 0
dx = feet(cop) - feet(bop)

# body silhouette in the cape image's frame, grown by 1 px
sil = np.zeros_like(cop)
h, w = bop.shape
for y in range(h):
    for x in np.where(bop[y])[0]:
        X = x + dx
        if 0 <= X < sil.shape[1]:
            sil[y, X] = True
grow = sil.copy()
grow[1:] |= sil[:-1]; grow[:-1] |= sil[1:]
grow[:, 1:] |= sil[:, :-1]; grow[:, :-1] |= sil[:, 1:]

keep = cop & ~grow
out = np.zeros_like(cape)
out[keep] = cape[keep]
# fill between the cape's outer edges, row by row and column by column, so the parts the
# body was covering (chest, arms) close up into one cloth
fill = keep.copy()
for _ in range(2 if "--fill" in sys.argv else 0):
    for y in range(h):
        xs = np.where(fill[y])[0]
        if len(xs) >= 2:
            fill[y, xs.min():xs.max() + 1] = True
    for x in range(fill.shape[1]):
        ys = np.where(fill[:, x])[0]
        if len(ys) >= 2:
            fill[ys.min():ys.max() + 1, x] = True
new_px = fill & ~keep
ys, xs = np.where(new_px)
out[ys, xs, :3] = INSIDE[(xs // 4 + (xs // 9) % 2) % 3]   # vertical folds
out[ys, xs, 3] = 255
# outline the new edges
op = out[..., 3] > 0
pad = np.pad(op, 1)
edge = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
out[edge & ~keep, :3] = (28, 8, 14)
Image.fromarray(out, "RGBA").save(sys.argv[3])
Image.fromarray(out, "RGBA").resize((out.shape[1] * 4, h * 4), Image.NEAREST).save(
    sys.argv[3].replace(".png", "_preview.png"))
print(sys.argv[3], out.shape, "dx", dx)
