"""Generates the placeholder bedroom stage (512x216 pixel art) -> assets/stages/bedroom.png.

Run: python tools/gen_stage.py
Replace the PNG with hand-made art later; the game only needs a 512x216 image
whose floor line (where feet stand) is at y=200.
"""
import math
import os
import random

from PIL import Image, ImageDraw

W, H = 512, 216
FLOOR_TOP = 150
random.seed(7)

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (W, H))
px = img.load()
d = ImageDraw.Draw(img)


def dither_grad(x0, y0, x1, y1, stops, vertical=True, steps=6):
    """Fill rect with a banded, Bayer-dithered gradient through colour stops."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            t = (y - y0) / max(1, (y1 - y0 - 1)) if vertical else (x - x0) / max(1, (x1 - x0 - 1))
            f = t * (len(stops) - 1) * steps
            band = int(f)
            frac = f - band
            if frac * 16 > BAYER[y % 4][x % 4] + 0.5:
                band += 1
            band = min(band, (len(stops) - 1) * steps)
            seg = band // steps
            tt = (band % steps) / steps
            if seg >= len(stops) - 1:
                c = stops[-1]
            else:
                c = mix(stops[seg], stops[seg + 1], tt)
            px[x, y] = c


def glow(cx, cy, rx, ry, color, strength):
    """Additive radial light with dithered falloff."""
    for y in range(max(0, int(cy - ry)), min(H, int(cy + ry))):
        for x in range(max(0, int(cx - rx)), min(W, int(cx + rx))):
            dd = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if dd >= 1:
                continue
            k = (1 - dd) ** 1.6 * strength
            q = (BAYER[y % 4][x % 4] / 16 - 0.5) * 0.12
            k = max(0.0, k + q)
            k = round(k * 5) / 5
            r, g, b = px[x, y]
            px[x, y] = (min(255, int(r + color[0] * k)), min(255, int(g + color[1] * k)), min(255, int(b + color[2] * k)))


def rect(x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=c)


OUT = hexc("1a0c0a")

# ---------------------------------------------------------------- walls
dither_grad(0, 0, W, FLOOR_TOP, [hexc("4a2420"), hexc("7a3e2e"), hexc("8e4c34"), hexc("6e3a2a")])
# side walls darker (room corners)
for y in range(0, FLOOR_TOP):
    for x in range(0, 40):
        if (40 - x) * 0.6 > BAYER[y % 4][x % 4] + (y * 0.02):
            r, g, b = px[x, y]
            px[x, y] = (int(r * 0.78), int(g * 0.72), int(b * 0.78))
    for x in range(W - 40, W):
        if (x - (W - 40)) * 0.6 > BAYER[y % 4][x % 4] + (y * 0.02):
            r, g, b = px[x, y]
            px[x, y] = (int(r * 0.78), int(g * 0.72), int(b * 0.78))
# wall corner lines
d.line([(40, 14), (40, FLOOR_TOP)], fill=hexc("3a1c18"))
d.line([(W - 41, 14), (W - 41, FLOOR_TOP)], fill=hexc("3a1c18"))

# ceiling + crown moulding
dither_grad(0, 0, W, 12, [hexc("2e1612"), hexc("4a2620")])
rect(0, 12, W, 14, hexc("a0644a"))
rect(0, 14, W, 15, hexc("5a2c22"))
rect(0, 15, W, 16, hexc("c07a56"))
rect(0, 16, W, 18, hexc("6a3428"))

# ---------------------------------------------------------------- floor (perspective planks)
VPX, VPY = 256, -70
for y in range(FLOOR_TOP, H):
    dy = y - VPY
    depth = (y - FLOOR_TOP) / (H - FLOOR_TOP)
    w = 2600.0 / dy                     # distance into the room
    for x in range(W):
        u = (x - VPX) / dy * 20.0       # across, in plank units
        col = math.floor(u)
        fu = u - col
        off = ((col * 7) % 5) * 0.37
        row = math.floor(w / 3.0 + off)
        fw = (w / 3.0 + off) - row
        base = [hexc("b8642c"), hexc("a2562a"), hexc("c47436"), hexc("94482a")][(col * 3 + row * 7) % 4]
        c = base
        seam_u = 0.05 + (1 - depth) * 0.06
        if fu < seam_u:
            c = hexc("4e220e")
        elif fw < 0.05 + (1 - depth) * 0.2 and fw >= 0:
            c = hexc("5e2a12")
        else:
            grain = math.sin(u * 40.0 + row * 3.0 + w * 0.8)
            if grain > 0.93:
                c = mix(base, hexc("6a3418"), 0.45)
            elif fu > 0.8:
                c = mix(base, hexc("e09858"), 0.25)
        c = mix(c, hexc("3a1a0e"), (1 - depth) * 0.5)
        px[x, y] = c
glow(256, 182, 160, 20, hexc("ffc070"), 0.3)
rect(0, FLOOR_TOP - 4, W, FLOOR_TOP, hexc("5a2c1c"))
d.line([(0, FLOOR_TOP - 4), (W, FLOOR_TOP - 4)], fill=hexc("a06040"))
d.line([(0, FLOOR_TOP), (W, FLOOR_TOP)], fill=OUT)

# ---------------------------------------------------------------- curtains
CX0, CX1, CY0, CY1 = 120, 392, 22, FLOOR_TOP - 4
rect(CX0 - 6, 20, CX1 + 6, 22, hexc("2a1a14"))  # rod
for x in range(CX0, CX1):
    # pleats: sine shading across x
    ph = math.sin((x - CX0) / 6.2 * math.pi)
    ph2 = math.sin((x - CX0) / 23.0)
    shade = 0.5 + 0.38 * ph + 0.1 * ph2
    for y in range(CY0, CY1):
        sway = math.sin(y / 30.0 + x / 50.0) * 0.05
        s = shade + sway + (BAYER[y % 4][x % 4] / 16 - 0.5) * 0.18
        s = max(0.0, min(1.0, s))
        band = round(s * 4) / 4
        c = mix(hexc("3c2852"), hexc("b49ad2"), band)
        # light from the lamp falls in the middle
        lx = abs(x - 256) / 160
        c = mix(c, hexc("2a1c3a"), min(1.0, lx * 0.5) * (1 - band * 0.3))
        px[x, y] = c
# curtain hem/top
for x in range(CX0, CX1):
    if (x // 3) % 2 == 0:
        px[x, CY0] = hexc("e0c8f0")
d.line([(CX0, CY0), (CX0, CY1)], fill=OUT)
d.line([(CX1 - 1, CY0), (CX1 - 1, CY1)], fill=OUT)

# ---------------------------------------------------------------- mirror (left)
MX0, MY0, MX1, MY1 = 14, 64, 62, 192
# frame shadow
poly = [(MX0, MY0), (MX1, MY0 - 6), (MX1 + 6, MY1 - 4), (MX0 + 4, MY1)]
d.polygon(poly, fill=hexc("6e3a1a"))
d.polygon([(MX0 + 4, MY0 + 4), (MX1 - 3, MY0 - 1), (MX1 + 2, MY1 - 9), (MX0 + 7, MY1 - 5)], fill=hexc("2c2a48"))
# reflection gradient
for y in range(MY0, MY1):
    for x in range(MX0, MX1 + 6):
        r, g, b = px[x, y]
        if (r, g, b) == hexc("2c2a48"):
            t = (y - MY0) / (MY1 - MY0)
            c = mix(hexc("6a5a8a"), hexc("8a4a3a"), t)
            if (x + y) % 9 == 0 or BAYER[y % 4][x % 4] > 12:
                c = mix(c, hexc("b0a0c8"), 0.3)
            px[x, y] = c
# reflected lamp + figure silhouette
glow(40, 84, 10, 6, hexc("ffd890"), 1.0)
d.ellipse([33, 120, 49, 136], fill=hexc("3a2a2a"))
d.rectangle([30, 134, 52, 182], fill=hexc("4a3428"))
d.polygon([(MX0, MY0), (MX1, MY0 - 6), (MX1 + 6, MY1 - 4), (MX0 + 4, MY1)], outline=OUT)
d.line([(MX0 + 2, MY0 + 2), (MX1 - 2, MY0 - 3)], fill=hexc("e8a040"))
d.line([(MX0 + 2, MY0 + 2), (MX0 + 5, MY1 - 2)], fill=hexc("c8802a"))
# glass shine
d.line([(MX0 + 12, MY0 + 10), (MX0 + 22, MY0 + 30)], fill=hexc("d8d0f0"))
d.line([(MX0 + 14, MY0 + 8), (MX0 + 26, MY0 + 32)], fill=hexc("a898c8"))

# ---------------------------------------------------------------- AC unit (right)
AX0, AY0, AX1, AY1 = 412, 36, 486, 66
rect(AX0 + 2, AY0 + 2, AX1 + 2, AY1 + 3, hexc("4a2620"))
dither_grad(AX0, AY0, AX1, AY1, [hexc("f0d8b0"), hexc("d8b88c"), hexc("b8946c")])
d.rectangle([AX0, AY0, AX1 - 1, AY1 - 1], outline=OUT)
for i in range(4):
    y = AY0 + 18 + i * 2
    d.line([(AX0 + 6, y), (AX1 - 7, y)], fill=hexc("6a4a34"))
rect(AX1 - 14, AY0 + 6, AX1 - 6, AY0 + 9, hexc("90c070"))
d.line([(AX0 + 4, AY0 + 3), (AX1 - 4, AY0 + 3)], fill=hexc("fff4dc"))

# ---------------------------------------------------------------- bed (center back)
BX0, BX1, BY0, BY1 = 196, 330, 112, 166
# headboard
rect(BX0 - 4, BY0 - 26, BX1 + 4, BY0 + 6, hexc("5a2e1a"))
d.rectangle([BX0 - 4, BY0 - 26, BX1 + 3, BY0 + 5], outline=OUT)
for x in range(BX0 + 4, BX1, 12):
    d.line([(x, BY0 - 22), (x, BY0 + 2)], fill=hexc("7a4426"))
# mattress + patterned cover
dither_grad(BX0, BY0, BX1, BY1, [hexc("d8c4e8"), hexc("b49ccc"), hexc("8a72a6")])
for y in range(BY0, BY1):
    for x in range(BX0, BX1):
        if ((x * 3 + y * 5) % 11 == 0) or ((x - y) % 13 == 0 and (x + y) % 3 == 0):
            px[x, y] = hexc("6a5288")
        elif (x * 7 + y * 3) % 17 == 0:
            px[x, y] = hexc("f0e8f8")
# pillows
for i in range(2):
    x0 = BX0 + 10 + i * 64
    d.rounded_rectangle([x0, BY0 - 8, x0 + 50, BY0 + 6], radius=5, fill=hexc("f0e6f4"), outline=OUT)
    d.line([(x0 + 4, BY0 + 3), (x0 + 46, BY0 + 3)], fill=hexc("c8b8d8"))
d.rectangle([BX0, BY0, BX1 - 1, BY1 - 1], outline=OUT)
# bed frame + legs
rect(BX0 - 2, BY1, BX1 + 2, BY1 + 6, hexc("6a3a1e"))
d.line([(BX0 - 2, BY1 + 6), (BX1 + 2, BY1 + 6)], fill=OUT)
rect(BX0 + 2, BY1 + 6, BX0 + 6, BY1 + 12, hexc("4a2614"))
rect(BX1 - 6, BY1 + 6, BX1 - 2, BY1 + 12, hexc("4a2614"))

# ---------------------------------------------------------------- nightstand + lamp (right)
NX0, NY0, NX1, NY1 = 432, 140, 474, 176
dither_grad(NX0, NY0, NX1, NY1, [hexc("b06a34"), hexc("8a4e24"), hexc("6a3a1a")])
d.rectangle([NX0, NY0, NX1 - 1, NY1 - 1], outline=OUT)
d.line([(NX0 + 2, NY0 + 14), (NX1 - 3, NY0 + 14)], fill=hexc("4a2614"))
rect(NX0 + 18, NY0 + 6, NX0 + 24, NY0 + 9, hexc("e0b060"))
# lamp
rect(NX0 + 18, NY0 - 14, NX0 + 22, NY0, hexc("8a6a3a"))
d.polygon([(NX0 + 8, NY0 - 14), (NX0 + 32, NY0 - 14), (NX0 + 28, NY0 - 32), (NX0 + 12, NY0 - 32)], fill=hexc("f8d070"), outline=OUT)
glow(NX0 + 20, NY0 - 22, 40, 30, hexc("ffb050"), 0.55)

# ---------------------------------------------------------------- plant (far right)
rect(482, 160, 504, 186, hexc("7a4a2a"))
d.rectangle([482, 160, 503, 185], outline=OUT)
for i in range(70):
    vx = 492 + random.randint(-14, 16)
    vy = 50 + random.randint(0, 112)
    s = random.randint(3, 5)
    col = random.choice([hexc("3e7a2a"), hexc("5a9a34"), hexc("8ac850"), hexc("2a5a1e")])
    d.ellipse([vx - s, vy - s // 2, vx + s, vy + s // 2], fill=col, outline=hexc("143010"))
d.line([(492, 162), (488, 50)], fill=hexc("2a4a14"))

# ---------------------------------------------------------------- hanging lamp (center)
LX = 256
d.line([(LX, 18), (LX, 40)], fill=hexc("2a1a14"))
d.line([(LX + 1, 18), (LX + 1, 40)], fill=hexc("5a3a2a"))
glow(LX, 66, 140, 60, hexc("ffa050"), 0.32)
glow(LX, 70, 50, 22, hexc("ffe0a0"), 0.45)
shade = [(LX - 18, 40), (LX + 18, 40), (LX + 30, 66), (LX - 30, 66)]
d.polygon(shade, fill=hexc("e88a3a"))
for x in range(LX - 30, LX + 31):
    for y in range(40, 67):
        if px[x, y] == hexc("e88a3a"):
            t = (y - 40) / 26
            stripe = (x // 3) % 2
            c = mix(hexc("f8b060"), hexc("c86020"), t * 0.7 + stripe * 0.15)
            px[x, y] = c
d.polygon(shade, outline=OUT)
d.ellipse([LX - 26, 63, LX + 26, 71], fill=hexc("fff4c8"), outline=hexc("e8a040"))
d.ellipse([LX - 14, 65, LX + 14, 69], fill=hexc("ffffff"))

os.makedirs(os.path.join(os.path.dirname(__file__), "..", "assets", "stages"), exist_ok=True)
out = os.path.join(os.path.dirname(__file__), "..", "assets", "stages", "bedroom.png")
img.save(out)
img.resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(os.path.dirname(__file__), "_stage_preview_x3.png"))
print("saved", os.path.abspath(out))
