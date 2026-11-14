# ArcadeFighter

Godot 4.7 retro 16-bit fighting game (CED vs KROS). See README.md for controls and layout.

- **Adding a character move** (the user names a move, character and key, then pastes a ChatGPT
  sheet): follow [docs/move_workflow.md](docs/move_workflow.md) step by step.
- Other sprite sources (3D/Mixamo, mixing sources): [docs/character_pipeline.md](docs/character_pipeline.md).
- The sim (`scripts/sim/`) must stay deterministic for rollback netplay: integer math, no
  rendering, no randomness outside the seeded RNG. Visual-only effects belong in `scripts/render/`.
- Tools: Godot `C:/Godot/Godot_v4.7.2-stable_win64.exe`, Aseprite `C:/Aseprite/Aseprite.exe`,
  Blender `C:/Blender/blender.exe`.
