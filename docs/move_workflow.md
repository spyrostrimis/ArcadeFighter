# One move per session: ChatGPT key poses → Aseprite → game

This is the process for adding a character move. One session per move:

1. **You** open a new session and name the move, the character and the key, e.g.
   *"Heavy kick for CED, C (key)"*.
2. **Claude** checks the move and replies with the ChatGPT prompt (and which images to attach).
3. **You** generate the sheet in ChatGPT and paste it into the session.
4. **Claude** cuts it out, builds the move in Aseprite, puts it in the game, checks it in-game and
   sends you screenshots.
5. When you're happy: commit and push.

Claude: follow every step below; don't skip the in-game check.

---

## Reference

### Keys and move names

| Key | Button | Standing | Crouching (hold ↓) | Jumping |
|---|---|---|---|---|
| A | light punch | `st_lp` | `cr_lp` | `j_lp` |
| S | medium punch | `st_mp` | `cr_mp` | `j_mp` |
| D | heavy punch | `st_hp` | `cr_hp` (anti-air uppercut) | `j_hp` |
| Z | light kick | `st_lk` | `cr_lk` (low) | `j_lk` |
| X | medium kick | `st_mk` | `cr_mk` (low) | `j_mk` |
| C | heavy kick | `st_hk` | `cr_hk` (sweep, knocks down) | `j_hk` |

Other animations the renderer asks for (`scripts/render/fighter_view.gd`, `_sprite_anim`):
`idle`, `walk_f`, `walk_b`, `crouch`, `jump`, `block`, `cr_block`, `hit_high`, `hit_low`,
`knockdown`, `getup`, `ko`, `win`, `lose`. Specials have their own names (CED: `flying_knee`).
Any animation without sprites falls back to the placeholder puppet.

**If the move name and the key don't match** (e.g. "high kick, D": D is heavy punch), ask
before doing anything.

### Characters

| | CED | KROS |
|---|---|---|
| Standing height (game px) | **92** (= Ryu's scale, see `art/ref/sf_scale.png`) | **97** (a little taller) |
| Look | short brown hair, stubble, brown knit sweater, baggy beige trousers, brown lace-up boots | grey curly hair, goatee, black ruffled shirt, black brocade vest with gold watch chain, gold brooch, pendant, black jeans, tall black boots; red/black velvet cape with gold Greek-key trim |
| Style references to attach in ChatGPT | `art/ced/ref/hp_keys.webp` (+ `art/ref/mockup.webp`) | `art/kros/ref/kicks_nocape.webp` (+ `art/kros/ref/ref_nocape.webp`) |
| Aseprite file | `art/ced/ced.aseprite` | `art/kros/kros_nocape.aseprite` (fights in this), `art/kros/kros.aseprite` (cape: round intro only) |
| Build script | `tools/aseprite/build_ced.lua` | `tools/aseprite/build_kros.lua` (builds both costumes) |
| Sprite set | `assets/fighters/ced/` | `assets/fighters/kros_nocape/` (+ `kros/`) |

KROS wears the cape only in the round intro (it blinks and fades away), then fights without it.
So **KROS's fight moves need only the no-cape sheet**. The cape costume has `idle` and `cape`,
plus `st_mk`/`st_hk` from before.

Both face **right** in all art (the game mirrors them).

### Done so far

| Character | Moves with sprites |
|---|---|
| CED | `idle`, `st_hp`, `flying_knee` (Mixamo, see `docs/character_pipeline.md`) |
| KROS | `idle`, `st_mk`, `st_hk` (both costumes), `cape` |

Update this table when a move is added.

---

## Step 1: before writing the prompt (Claude)

1. Read the move's frame data in `scripts/sim/char_data.gd`: `_mv(startup, active, recovery, …, box)`.
   Total game frames = startup + active + recovery (60 fps). Sprite frames run at 15 fps, so the
   animation has about **total / 4 steps**.
2. Decide the key poses, usually 2–4: **wind-up / chamber → hit pose (extended) → (recoil) → back to stance**.
   The stance is always pose 1 (it is the scale reference, and the move ends on it).
   In-betweens can often be made instead of drawn (`tools/aseprite/inbetween_arm.py` slides a
   forearm back; `tools/aseprite/rotate_limb.py` swings a limb around a joint), so ask
   ChatGPT only for poses that need real drawing.
3. Look at what the hit box says: a `box` of `[x, y, w, h]` (px forward from the feet, up from
   the floor) tells how high and far the hit lands; the hit pose should reach there.

## Step 2: the ChatGPT prompt (Claude writes it, you run it)

Tell the user which images to attach (from the table above: the character's existing key-pose
sheet, so ChatGPT keeps the same style and proportions), then give the prompt. Template:

> Using the attached character sheet as the exact style and character reference, draw **[NAME]**
> doing a **[MOVE: e.g. standing heavy kick, a high roundhouse to the head]** as a key-pose sheet
> for a 16-bit arcade fighting game (Street Fighter Alpha style pixel art):
>
> - **[N] poses side by side, left to right, in this order:** 1) [fighting stance, same as the
>   attached sheet], 2) [wind-up: …], 3) [hit pose: …], [4) …]
> - Full body in every pose, facing right, side-on like a fighting game sprite.
> - All poses the **same size and scale**, standing on the **same floor line** (the soles of the
>   stance at the same height in every pose; jumping poses higher above it).
> - Poses **must not touch or overlap**: clear empty space between them (nothing reaching into the
>   next pose's space, including limbs, hair and clothing).
> - **Flat pure magenta background (#FF00FF)**, no floor, no shadows, no motion lines, no effects,
>   no text.
> - Same face, hair, outfit, colours and proportions as the reference. Wide image (about 3:1).

Character-specific lines to add:
- **CED**: "brown knit sweater, baggy beige trousers, brown lace-up boots, short brown hair, stubble."
- **KROS**: "**without the cape**: black ruffled shirt, black brocade vest with gold watch chain and
  gold brooch, silver pendant, black jeans, tall black boots, grey curly hair, goatee."

For crouching moves add "crouched low, about two-thirds of standing height"; for jumping moves
"in the air, knees tucked", and keep pose 1 as the standing stance (for the scale).

## Step 3: after the user pastes the sheet (Claude)

The pasted image's path is in the message (e.g. `S:\Temp\...\images\1.webp`).

1. **Save the sheet** into the repo: `art/<char>/ref/<move>.webp` (keep the original format).
2. **Check it**: look at the image. Poses separated? Background flat magenta? Same character?
   If ChatGPT broke a rule badly (poses overlap, wrong outfit), say so and give a corrected
   prompt instead of forcing it.
3. **Cut it out** at the character's height, scaled from the stance:

```bash
python tools/aseprite/cutout_keys.py art/ced/ref/st_hk.webp art/ced/keys/st_hk 92 --ref 1
```

   It splits figures by empty magenta columns (it prints the poses it found) and writes
   `art/<char>/keys/<move>_1.png …` plus `<move>_preview.png` (4x). **Read the preview.** If two
   poses were merged into one (they touch), separate them first (e.g. paint a magenta column
   between them in a copy of the sheet, saved as `art/<char>/ref/<move>_split.png`).
4. **Extra frames** if needed: `inbetween_arm.py` (forearm in-between) or `rotate_limb.py`
   (swing a leg/arm; works on the full-resolution sheet before cutting: see its docstring and the
   KROS mid kick in `docs/character_pipeline.md`).
5. **Add the move to the build script** (`build_ced.lua` / `build_kros.lua`):
   - load the new key files (the scripts line every pose up by the feet: CED by the back foot,
     KROS by the standing foot / between the feet),
   - add a sequence of `{pose, steps}` (1 step = 1/15 s = 4 game frames) whose steps add up to
     about total/4,
   - add its tag (the tag name is the move name), next to the other `newTag` lines.
   - **Timing rule:** the game shows sprite frame `sf * n / total` (n = steps), so the hit pose
     must already be on screen at the first active frame: steps before the hit pose ×
     total / n ≤ startup. Otherwise the hit freezes (hitstop) on the wind-up pose.
   - KROS: fight moves go in the no-cape file only; guard with `if prefix == "nocape" then … end`.
6. **Rebuild and export**:

```bash
C:/Aseprite/Aseprite.exe -b --script-param dir=art/ced/keys --script-param out=art/ced/ced.aseprite --script tools/aseprite/build_ced.lua
```

   CED only: the rebuild drops the Mixamo move, so import it again right after:

```bash
C:/Aseprite/Aseprite.exe -b --script-param file=art/ced/ced.aseprite --script-param dir=art/ced/moves/flying_knee --script-param tag=flying_knee --script-param ax=43 --script-param ay=104 --script-param count=17 --script tools/aseprite/import_frames.lua
```

```bash
python tools/aseprite/export.py art/ced/ced.aseprite ced
```

   KROS: run `build_kros.lua` with `prefix=cape out=art/kros/kros.aseprite` and with
   `prefix=nocape out=art/kros/kros_nocape.aseprite`, then export both (`kros`, `kros_nocape`).
   CED's `build_ced.lua` still loads its keys by the old `hp_` names: add new moves with their
   own `<move>_` file names.

7. **Re-import in Godot** (otherwise the game keeps the old texture):

```bash
C:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --import
```

## Step 4: check it in the game (Claude)

```bash
C:/Godot/Godot_v4.7.2-stable_win64.exe --path . --script res://tests/move_shot.gd -- --char=ced --move=st_hk --boxes --out=D:/Games/ArcadeFighter/build/shots/st_hk
```

(`--char=kros --vs=ced` for KROS.) It walks up to the opponent, does the move, saves a screenshot
every 2 frames and a contact sheet `<char>_<move>_sheet.png`. Hurt boxes are drawn blue and the
active hit box red. Check:

- the hit pose is on screen when the opponent gets hit (not the wind-up),
- the red box sits on the fist/foot; if not, change the move's `box` in `char_data.gd`
  (only the box: startup/active/recovery are balance, ask before changing them),
- the feet stay planted (no sliding/jumping between poses) and the height matches the idle.

Then run the sim and netplay tests (both must print `RESULT: PASS`):

```bash
C:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/simtest.gd
```

```bash
C:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/nettest.gd
```

**Send the user** the contact sheet (without `--boxes`) and a GIF of the move (SendUserFile).
Save the GIF as `art/<char>/keys/<move>_ingame.gif`.

## Step 5: commit and push (when the user says so)

- Branch: the current working branch (now `ced-sprites`). Never `main` without asking.
- Commit the sheet, keys, `.aseprite`, exported sprite set, build script and any `char_data.gd`
  box change. Message: `<CHAR> <move> from ChatGPT key poses` plus a short body.
- `git push`.
- Update the "Done so far" table above in the same commit.
