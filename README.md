# Arcade Fighter

Retro 16-bit pixel-art fighting game in Godot 4.7: **CED vs KROS** in the bedroom stage.

## Play

- Double-click `play.bat`, or open `project.godot` in Godot and press F5.
- Menu: **VS CPU** → pick your fighter → pick the CPU opponent (mirror matches are allowed).
- **ONLINE** → HOST ROOM shows a 6-letter code; your opponent picks JOIN ROOM and types it.
  No IP or port forwarding needed; rollback netcode. Details: [docs/online.md](docs/online.md).
  Builds must ship `libwebrtc_native.windows.template_release.x86_64.dll` next to the .exe.

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

**CED special: Flying Knee** = down, down-forward, forward + punch. He runs in, knees the
opponent in the face, then hammers down with a punch that knocks down (block it standing).

## Layout

```
scripts/sim/      deterministic game logic (integer math), no rendering
  match_sim.gd    rounds, timer, collisions, hits; save_state()/load_state() for rollback
  fighter.gd      fighter state machine, input buffer, physics
  char_data.gd    stats + frame data + hitboxes per move  <- tune balance here
  inp.gd          input bitmask (same format for keyboard, CPU and future netplay)
scripts/ai/cpu.gd CPU opponent (Easy/Normal/Hard on the title screen)
scripts/render/   placeholder art: puppet.gd/poses.gd draw the characters, hud.gd, effects.gd
scripts/screens/  title, character select, fight, online menu
scripts/net/      online: MQTT signalling, WebRTC room (net_room.gd), rollback.gd, Net autoload
addons/webrtc_native/  official godotengine/webrtc-native GDExtension (Windows x86_64)
assets/stages/bedroom.png   stage art (512x216; feet stand on y=200)
tools/gen_stage.py          regenerates the placeholder stage
tests/simtest.gd            headless CPU-vs-CPU + rollback determinism test
tests/nettest.gd            headless rollback sync test (latency, jitter, loss, disconnect, desync)
tests/jitter_test.gd        headless check that fighters don't flicker between poses ("trembling")
tests/roomprobe.gd          real signalling + WebRTC connection in one process
tests/online_pair.sh        two game windows host/join a room and play online matches
tests/move_shot.gd          in-game screenshots of one move (+ hit boxes), for sprite work
```

Character art: one move at a time from ChatGPT key-pose sheets, see
[docs/move_workflow.md](docs/move_workflow.md).

## Tests

```bash
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/simtest.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/nettest.gd
C:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/jitter_test.gd
```

Debug launch options (after `--`): `--demo` (CPU vs CPU), `--p1=kros --p2=ced`,
`--screen=select|fight`, `--shot=<prefix> --shot_at=60,300` (save screenshots, then quit).

## Next steps

- Real sprite art, move by move ([docs/move_workflow.md](docs/move_workflow.md)). Moves without sprites still use the procedural puppet.
- Local 2 players: P2 input actions already exist. It needs P2 keyboard keys and a select screen for two players.
- Online: add a TURN relay for players behind symmetric NAT (see docs/online.md, Limits).
