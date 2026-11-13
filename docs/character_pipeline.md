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
