# Arcade Fighter

Retro 16-bit pixel-art fighting game in Godot 4.7: **CED, KROS, MURFURRIE and SHORTY** in the bedroom stage.

## Play

- Double-click `play.bat`, or open `project.godot` in Godot and press F5.
- Menu: **VS CPU** → pick your fighter → pick the CPU opponent (mirror matches are allowed).
- **2 PLAYERS** → both players pick at the same time with their own keys (LP/LK confirm,
  MP/MK cancel your pick, ESC back). A second gamepad is player 2.
- **SETTINGS** → volumes (master/music/sound), keyboard keys for P1 and P2, rounds, round
  time, CPU level, fullscreen and window size, plus development helpers: FPS counter,
  hitboxes, input history, training health (no KO) and a CPU dummy (stand/crouch/jump/block).
  Saved to `user://settings.cfg`. Online matches always use the default rules.
- **ONLINE** → HOST ROOM shows a 6-letter code; your opponent picks JOIN ROOM and types it.
  No IP or port forwarding needed; rollback netcode. Details: [docs/online.md](docs/online.md).
  Builds must ship `libwebrtc_native.windows.template_release.x86_64.dll` next to the .exe.

| Action | P1 keys | P2 keys | Gamepad |
|---|---|---|---|
| Move / jump / crouch | Arrow keys | I J K L | D-pad / left stick |
| Block | Hold away from the opponent (hold down-back for low attacks) | | |
| Light / Medium / Heavy punch | A / S / D | Numpad 4 / 5 / 6 | X / Y / RB |
| Light / Medium / Heavy kick | Z / X / C | Numpad 1 / 2 / 3 | A / B / RT |
| Pause | Esc or P (Q to quit while paused) | | Start |
| Show hitboxes / input history | F2 / F3 | | |
| Fullscreen | F11 | | |

Rules: best of 3 rounds, 99-second timer. Light attacks chain into each other.
Crouching heavy punch is an anti-air uppercut, and crouching heavy kick is a sweep.
Jump attacks must be blocked standing, and low kicks must be blocked crouching.

**CED special: Flying Knee** = down, down-forward, forward + punch. He runs in, knees the
opponent in the face, then hammers down with a punch that knocks down (block it standing).

**MURFURRIE special: Spit** = down, down-forward, forward + punch. A glob of spit flies
straight at head height, then drops to the floor about halfway across the screen. Crouch
under it while it flies high, or block it. One on screen at a time.

| | Reach | Punches | Kicks | Speed |
|---|---|---|---|---|
| CED | medium | weakest | strongest | fastest |
| KROS | longest | strongest | weakest | slowest |
| MURFURRIE | shortest | medium | medium | medium (a bit more health) |

**SHORTY** is half the size of the others: many high attacks pass over his head. He is the
fastest fighter but takes 10% more damage from every hit. His buttons are swapped: the
**punch buttons are headbutts** (slow, heavy, they lunge forward) and the **kick buttons are
punches** (very quick and weak, they hit low: block them crouching; the heavy ones dart
forward). Round 1 of his matches opens with his intro: he poses with two ladies, who walk
off before the round is announced.

## Layout

```
scripts/sim/      deterministic game logic (integer math), no rendering
  match_sim.gd    rounds, timer, collisions, hits; save_state()/load_state() for rollback
  fighter.gd      fighter state machine, input buffer, physics
  char_data.gd    stats + frame data + hitboxes per move  <- tune balance here
  inp.gd          input bitmask (same format for keyboard, CPU and future netplay)
scripts/ai/cpu.gd CPU opponent (Easy/Normal/Hard on the title screen)
scripts/render/   placeholder art: puppet.gd/poses.gd draw the characters, hud.gd, effects.gd
scripts/screens/  title, character select, settings, fight, online menu
scripts/core/     game.gd (input map), settings.gd (saved options), sfx.gd, music.gd (procedural chiptune)
scripts/net/      online: MQTT signalling, WebRTC room (net_room.gd), rollback.gd, Net autoload
addons/webrtc_native/  official godotengine/webrtc-native GDExtension (Windows x86_64)
assets/stages/bedroom.png   stage art (512x216; feet stand on y=200)
tools/gen_stage.py          regenerates the placeholder stage
tests/simtest.gd            headless CPU-vs-CPU + rollback determinism test
tests/balance_test.gd       headless CPU win rates + damage per move, CED vs KROS or -- --a=X --b=Y (fails outside 35-65%)
tests/nettest.gd            headless rollback sync test (latency, jitter, loss, disconnect, desync)
tests/settings_test.gd      headless settings screen: volume, key rebinding/swap, save + load, match rules
tests/local2_test.gd        headless local 2 players: title -> both pick -> P2 keys drive fighter 2
tests/jitter_test.gd        headless check that fighters don't flicker between poses ("trembling")
tests/cpu_strength.gd       CPU win rate vs scripted "player" tactics (sweep spam, jump-ins, turtling...)
tests/roomprobe.gd          real signalling + WebRTC connection in one process
tests/online_pair.sh        two game windows host/join a room and play online matches
tests/move_shot.gd          in-game screenshots of one move (+ hit boxes), for sprite work
tests/spit_shot.gd          in-game screenshots of MURFURRIE's Spit at a distance (--gap, --crouch, --block)
```

Character art: one move at a time from ChatGPT key-pose sheets, see
[docs/move_workflow.md](docs/move_workflow.md).

## Tests

```bash
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/simtest.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/nettest.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/jitter_test.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/balance_test.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/local2_test.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/settings_test.gd
```

Debug launch options (after `--`): `--demo` (CPU vs CPU), `--p1=kros --p2=ced`,
`--screen=select|fight|settings`, `--set=input_display:1,dummy:4` (settings for this run only), `--shot=<prefix> --shot_at=60,300` (save screenshots, then quit).

## Next steps

- Real sprite art, move by move ([docs/move_workflow.md](docs/move_workflow.md)). Moves without sprites still use the procedural puppet.
- Online: add a TURN relay for players behind symmetric NAT (see docs/online.md, Limits).
