"""Export an .aseprite file to the game's sprite sheet format (assets/fighters/<id>/<id>.png + .json).
Every tag becomes an animation (tag name = game move name, e.g. idle, walk_f, st_lp).
The 'feet' slice marks the point that stands on the floor.
Frame durations are turned into repeats at the game's 15 fps.
A tag whose user data is "hit:<n>" marks frame n of the tag (0 = first) as the move's hit pose
(otherwise the game uses the widest frames).
Usage: python tools/aseprite/export.py art/ced/ced.aseprite ced"""
import json, os, subprocess, sys, tempfile
from PIL import Image

ASEPRITE = r"C:\Aseprite\Aseprite.exe"
FPS = 15.0

src, cid = sys.argv[1], sys.argv[2]
out_dir = os.path.join("assets", "fighters", cid)
os.makedirs(out_dir, exist_ok=True)
tmp = tempfile.mkdtemp()
sheet, data = os.path.join(tmp, "sheet.png"), os.path.join(tmp, "sheet.json")
subprocess.run([ASEPRITE, "-b", src, "--sheet", sheet, "--sheet-type", "packed", "--data", data,
                "--format", "json-array", "--list-tags", "--list-slices", "--trim",
                "--shape-padding", "1"], check=True)
meta = json.load(open(data))
frames = meta["frames"]
feet = next(s for s in meta["meta"]["slices"] if s["name"] == "feet")["keys"][0]["bounds"]
fx, fy = feet["x"], feet["y"]

anims = {}
for tag in meta["meta"]["frameTags"]:
    rects, anchors = [], []
    hit_frame = None
    if str(tag.get("data", "")).startswith("hit:"):
        hit_frame = tag["from"] + int(tag["data"][4:])
    hit = None
    for i in range(tag["from"], tag["to"] + 1):
        fr = frames[i]
        r, sss = fr["frame"], fr["spriteSourceSize"]
        reps = max(1, round(fr["duration"] / 1000 * FPS))
        if i == hit_frame:
            hit = [len(rects), len(rects) + reps - 1]
        for _ in range(reps):
            rects.append([r["x"], r["y"], r["w"], r["h"], fx - sss["x"], fy - sss["y"]])
    anims[tag["name"]] = {"frames": rects}
    if hit:
        anims[tag["name"]]["hit"] = hit

img = Image.open(sheet).convert("RGBA")
img.save(os.path.join(out_dir, cid + ".png"))
json.dump({"fps": FPS, "source": src.replace("\\", "/"), "animations": anims},
          open(os.path.join(out_dir, cid + ".json"), "w"), indent=1)
# preview gif of each tag
for name, a in anims.items():
    fs = []
    for x, y, w, h, ax, ay in a["frames"]:
        c = Image.new("RGBA", (160, 160), (40, 30, 50, 255))
        c.alpha_composite(img.crop((x, y, x + w, y + h)), (80 - ax, 150 - ay))
        fs.append(c.resize((320, 320), Image.NEAREST))
    fs[0].save(os.path.join(out_dir, f"preview_{name}.gif"), save_all=True, append_images=fs[1:],
               duration=int(1000 / FPS), loop=0)
print(cid, {k: len(v["frames"]) for k, v in anims.items()}, img.size)
