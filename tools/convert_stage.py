"""Converts a high-res painted/AI stage image into the game's native pixel stage.

Run: python tools/convert_stage.py [source] [out] [colors]
Defaults: assets/stages/bedroom_source.png -> assets/stages/bedroom.png, 96 colours.
The result is 512x216 (the stage scrolls; the screen shows 384x216, feet at y=200).
"""
import os
import sys

from PIL import Image, ImageFilter

W, H = 512, 216
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets", "stages", "bedroom_source.png")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "assets", "stages", "bedroom.png")
colors = int(sys.argv[3]) if len(sys.argv) > 3 else 96

im = Image.open(src).convert("RGB")
# scale to the target width, then crop extra height from the top (ceiling)
scale = W / im.width
nh = round(im.height * scale)
small = im.resize((W, nh), Image.Resampling.BOX)
if nh >= H:
    small = small.crop((0, nh - H, W, nh))
else:
    small = small.resize((W, H), Image.Resampling.BOX)
# light sharpen so edges read as pixels, then a fixed palette for a 16-bit look
small = small.filter(ImageFilter.UnsharpMask(radius=1.0, percent=60, threshold=2))
pal = small.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
pal.convert("RGB").save(out)
pal.convert("RGB").resize((W * 3, H * 3), Image.Resampling.NEAREST).save(os.path.join(here, "_stage_preview_x3.png"))
print("saved", out, "from", im.size, "scale", round(scale, 4))
