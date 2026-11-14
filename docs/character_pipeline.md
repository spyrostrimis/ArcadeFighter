# Character pipeline: ChatGPT → 3D → Mixamo → Blender → pixel sprites

You do steps 1–3 (they need your accounts). Steps 4–5 are automated and Claude runs them.

## 1. ChatGPT: a clean reference image per character

Image-to-3D tools need **one full-body image, front view, in A-pose, on a plain background**.
Paste your mockup and use:

> Using CED from this image, draw him as a full-body 3D-modelling reference: front view, standing in a
> neutral A-pose (arms straight, about 30 degrees away from the body, palms down, legs slightly apart),
> facing the camera, plain white background, even lighting, no shadows. Realistic adult proportions,
> same face, hair, brown knit sweater, baggy beige trousers and brown lace-up boots. Nothing covering
> the arms or legs, no props, no text. Clean, detailed, not pixel art.

For **KROS**, ask for the same thing **without the cape** (and with the coat no longer than the hips).
Auto-rigging treats a cape as part of the body and it tears badly when he kicks. Claude adds the cape
back in Blender as a separate piece that follows his shoulders.

## 2. Image → 3D model

Use one of these image-to-3D sites (free tiers exist; check each site's licence before selling the game):
**Meshy**, **Tripo**, or **Hunyuan3D**.

- Upload the front A-pose image and generate a **textured** model.
- Download it as **FBX** (or GLB/OBJ: Claude can convert those to FBX in Blender).
- Don't use the site's own rigging. Mixamo does that.

## 3. Mixamo: rig + animations (mixamo.com, free Adobe account)

1. **Upload Character** → the 3D file. Place the markers (chin, wrists, elbows, knees, groin), Skeleton: Standard.
2. Download the rigged character once: **FBX Binary, T-pose, With Skin**. Save it as
   `D:\Games\ArcadeFighter\art\ced\ced.fbx`.
3. For each animation: search, tweak the sliders (Speed and **Character Arm-Space**, which keeps arms out
   of the body), tick **In Place** when it's offered, then download **FBX Binary, Without Skin, 30 fps**.
   Save it into `art\ced\anims\`, **named after the game move** (the file name becomes the animation name).

**First test: only `idle.fbx`** (search "fighting idle" or "boxing idle").

The full set for later. Mixamo names vary, so these are search ideas:

| File name | Search Mixamo for |
|---|---|
| idle | fighting idle, boxing idle |
| walk_f / walk_b | fight walk forward / backward, boxing step |
| crouch | crouch idle, crouching block |
| jump | jump (in place) |
| st_lp / st_mp / st_hp | jab, cross punch, hook punch |
| st_lk / st_mk / st_hk | low kick, mma kick, roundhouse kick |
| cr_lp / cr_mp / cr_hp | crouch punch, body jab, uppercut |
| cr_lk / cr_mk / cr_hk | crouch kick, sweep (leg sweep) |
| j_p / j_k | jump punch, flying kick |
| block / cr_block | center block, crouch block |
| hit_high / hit_low | head hit, stomach hit |
| knockdown / getup | knocked down / falling back, getting up |
| ko | falling back death |
| win | victory, taunt |

## 4. Render (Claude)

```bash
C:/Blender/blender.exe -b -P tools/blender/render_sprites.py -- --input art/ced/ced.fbx --anims art/ced/anims --out build/render/ced
```

Side view turned 30° toward the camera, cel shading with 3 tones, outlines, 15 fps. The camera angle,
size (`--ppm`, game pixels per metre) and outline thickness are options of the script.

## 5. Pixelize + pack (Claude)

```bash
python tools/pixelize.py build/render/ced assets/fighters/ced ced --colors 40
```

Each 4×4 block of the render becomes one game pixel (majority vote, so the pixels are crisp, not blurry).
All frames share one palette, so colours don't flicker. You also get a 1px outline, a sprite sheet with a
JSON file, and preview GIFs. Touch up the sheet in Aseprite if you like, then the game uses it.

The pipeline was tested on `tools/blender/test_mannequin.blend` (a stand-in built by
`tools/blender/make_mannequin.py`).

## Mixing sources: one Mixamo move into a hand-made character

A character's sprite sheet can mix sources: CED's idle and heavy punch are hand-made in Aseprite,
his Flying Knee comes from a Mixamo animation. The `.aseprite` file is the hub: every source ends
up there as a tag, so it can be touched up and is exported with everything else.

1. On Mixamo, download the animation **With Skin** (FBX Binary, 30 fps) and **without** "In Place"
   if the move travels (dash, jump-in). Save it as `art/<char>/moves/<move>.fbx`.
2. Write `art/<char>/moves/<move>.json` (see `art/ced/moves/flying_knee.json`): speed per section
   (`timing`), how far it travels (`fwd_scale`) and how high it jumps (`lift_scale`), and which
   sprite sheet's colours to use (`palette`), so it matches the hand-made frames.
3. Run:

```bash
python tools/mixamo_move.py art/ced/moves/flying_knee.json
```

```bash
C:/Aseprite/Aseprite.exe -b --script-param file=art/ced/ced.aseprite --script-param dir=art/ced/moves/flying_knee --script-param tag=flying_knee --script-param ax=52 --script-param ay=127 --script-param count=17 --script tools/aseprite/import_frames.lua
```

```bash
python tools/aseprite/export.py art/ced/ced.aseprite ced
```

   The first prints the frame count and anchor for the second. It renders the move in Blender with
   the travel and jump taken out (the sprite stays on its feet anchor), pixelizes it, and writes the
   travel/jump per game frame to `scripts/sim/move_paths.gd`; the game moves the fighter along that
   path, so hit boxes, push boxes and rollback all follow it. A `preview.gif` shows the result.
4. Add the move's frame data in `scripts/sim/char_data.gd` (a `"path"` and its `"hits"`) and how to
   do it in `"specials"`.

Re-running the import replaces the tag, so it is safe after changing the spec. Frames you retouch
in Aseprite are overwritten by a re-import: retouch last.

## KROS in Aseprite: two costumes (with and without cape)

Like CED, KROS's moves come from ChatGPT key-pose sheets (figures on flat magenta), one sheet per
costume with the same three poses (stance, knee chamber, high kick): `art/kros/ref/kicks_cape.webp`
and `art/kros/ref/kicks_nocape.webp`. The mid kick is made from the high kick by lowering the leg.
Each costume is its own `.aseprite` file and sprite set: `kros` (cape) and `kros_nocape`. Both have
`idle`, `st_mk` and `st_hk`, 110 px tall. In a match KROS wears the cape at the start of each round; during the "ROUND n" banner it blinks
and fades away in place (`FighterView`, `CAPED` / `FADE_AT` / `FADE_LEN`), then he fights in
`kros_nocape`. The fading cape is the `cape` tag of `kros.aseprite`, cut out by
`tools/aseprite/cape_cutout.py` (`art/kros/keys/cape_1.png art/kros/keys/nocape_1.png art/kros/keys/cape_only.png`)
before `build_kros.lua` runs. After re-exporting a sheet, run `godot --headless --path . --import`
so the game picks up the new texture.

```bash
python tools/aseprite/rotate_limb.py art/kros/ref/kicks_cape.webp art/kros/ref/kicks_cape_mk.png --fig 1080,0,1960,667 --poly 1550,230,1780,160,1960,130,1960,250,1780,265,1550,365 --pivot 1525,305 --angle 20 --keep 45
```

```bash
python tools/aseprite/cutout_keys.py art/kros/ref/kicks_cape_mk.png art/kros/keys/cape 110
```

```bash
C:/Aseprite/Aseprite.exe -b --script-param dir=art/kros/keys --script-param prefix=cape --script-param out=art/kros/kros.aseprite --script tools/aseprite/build_kros.lua
```

```bash
python tools/aseprite/export.py art/kros/kros.aseprite kros
```

The same four with `nocape` / `kros_nocape` make the other costume. In-game check:
`godot --path . --script res://tests/kros_shot.gd -- --out=DIR [--skin=kros]` (a skin forces one costume, no cape fade).
