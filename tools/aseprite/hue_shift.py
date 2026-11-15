"""Shift the hue of one colour family in cut-out key poses, in place (e.g. ChatGPT drew
MURFURRIE's suit lavender; shifting hues 225-265 by -30 makes it light blue and keeps the
shirt navy). Skin, hair and shoes are outside the hue range (or grey) and stay as they are.
Usage: python tools/aseprite/hue_shift.py --from 225 --to 265 --shift -30 [--sat 1.1] a.png b.png ..."""
import argparse
import colorsys
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("files", nargs="+")
ap.add_argument("--from", dest="h0", type=float, required=True, help="hue range start, degrees")
ap.add_argument("--to", dest="h1", type=float, required=True, help="hue range end, degrees")
ap.add_argument("--shift", type=float, required=True, help="degrees to add")
ap.add_argument("--sat", type=float, default=1.0, help="saturation multiplier for shifted pixels")
ap.add_argument("--min-sat", type=float, default=0.08, help="leave greys (below this saturation) alone")
a = ap.parse_args()

for path in a.files:
    im = Image.open(path).convert("RGBA")
    px = im.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < a.min_sat or not (a.h0 <= h * 360 <= a.h1):
                continue
            h = ((h * 360 + a.shift) % 360) / 360
            s = min(1.0, s * a.sat)
            r, g, b = (round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
            px[x, y] = (r, g, b, al)
            n += 1
    im.save(path)
    print(path, n, "pixels shifted")
