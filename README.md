# Arcade Fighter

Retro 16-bit pixel-art fighting game in Godot 4.7: **CED vs KROS** in the bedroom stage.

## Play

- Double-click `play.bat`, or open `project.godot` in Godot and press F5.
- Menu: **VS CPU** → pick your fighter → pick the CPU opponent (mirror matches are allowed).

| Action | Keys | Gamepad |
|---|---|---|
| Move / jump / crouch | Arrow keys | D-pad / left stick |
| Block | Hold away from the opponent (hold down-back for low attacks) | |
| Light / Medium / Heavy punch | A / S / D | X / Y / RB |
| Light / Medium / Heavy kick | Z / X / C | A / B / RT |
| Pause | Esc or P (Q to quit while paused) | Start |
| Show hitboxes | F2 | |
| Fullscreen | F11 | |

Rules: best of 3 rounds, 99-second timer. Light attacks chain into each other.
Crouching heavy punch is an anti-air uppercut, and crouching heavy kick is a sweep.
Jump attacks must be blocked standing, and low kicks must be blocked crouching.

## Layout

```
scripts/sim/      deterministic game logic (integer math), no rendering
  match_sim.gd    rounds, timer, collisions, hits; save_state()/load_state() for rollback
  fighter.gd      fighter state machine, input buffer, physics
  char_data.gd    stats + frame data + hitboxes per move  <- tune balance here
  inp.gd          input bitmask (same format for keyboard, CPU and future netplay)
scripts/ai/cpu.gd CPU opponent (Easy/Normal/Hard on the title screen)
scripts/render/   placeholder art: puppet.gd/poses.gd draw the characters, hud.gd, effects.gd
scripts/screens/  title, character select, fight
assets/stages/bedroom.png   stage art (512x216; feet stand on y=200)
tools/gen_stage.py          regenerates the placeholder stage
tests/simtest.gd            headless CPU-vs-CPU + rollback determinism test
```

## Tests

```bash
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/simtest.gd
```

Debug launch options (after `--`): `--demo` (CPU vs CPU), `--p1=kros --p2=ced`,
`--screen=select|fight`, `--shot=<prefix> --shot_at=60,300` (save screenshots, then quit).

## Next steps

- Real sprite art: swap the procedural puppet for sprite sheets. Frame data and hitboxes stay in `char_data.gd`.
- Local 2 players: P2 input actions already exist. It needs P2 keyboard keys and a select screen for two players.
- Online room codes: the sim is deterministic and can be saved and restored (tested), which rollback netcode needs.
