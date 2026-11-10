# KING FOOTBALL — Phase 2 Handoff

Phase 1 is complete and validated. This is the minimal context needed to
start Phase 2 (per `../المرحلة الأول 1.txt` and the later plan docs).

## What exists and is proven (do NOT rebuild)

- `GameManager` autoload (`scripts/core/game_manager.gd`) — state BOOT/MAIN_MENU/IN_MATCH,
  signal `state_changed`, `start_match()` / back-to-menu flow. Extend, don't replace.
- Input, fully mapped in `project.godot` — 13 actions, keyboard + gamepad
  (see docs/CONTROLS.md). Phase 2 gameplay scripts can read them immediately.
- `GameCamera` + `CameraConfig` (`scripts/camera/`, `resources/configurations/game_camera_config.tres`)
  — call `set_follow_target(player)` on possession for player-chase camera.
- Procedural pitch with collision: pitch plane at y≈0, centre at origin,
  **length along Z** (goals at z=±52.5), **width along X**, validated collision plate
  (105×68 m + overscan). Reuse these conventions for player/ball coordinates.
- Goal scenes at z=±52.5 (GoalB yaw π). Each goal has its own collision shapes.
- `scripts/debug/test_target.gd` — placeholder chase target; REPLACE it with real
  players when they exist (delete the debug node from `stadium_prototype.tscn`
  and swap the GameCamera's `follow_target` path).
- UI Arabic-locale quirk — every NEW English UI control must either inherit from a Control
  that already has `layout_direction = 2`, or set it explicitly; see ARCHITECTURE.md §5.

## Suggested Phase 2 order

1. Ball: RigidBody3D + simple collision sphere, kick visuals only.
2. Player controller: CharacterBody3D reading move_* + sprint; camera follows player
   (`set_follow_target`). Manifest stats via exported vars.
3. Pass/shoot/lob: impulses toward input direction / goal area; integrate `pass`,
   `shoot`, `lob_pass`.
4. Dribble: ball ownership when `dribble` pressed while in front of player.
5. Then minimum match loop: kickoff at centre spot (position (0, y, 0)), goal detection
   z crossing at ±52.5 with ball inside goal mouth, score via GameManager extension.
6. AI opponent stub comes later (per plan) — do not touch Stadium visuals.

## Validation expectations to keep green

- `godot --headless --path . res://tests/phase1_validation.tscn` — 49/49 must stay passing;
  Phase 2 additions get their own suite (`tests/phase2_validation.tscn`) instead of editing these checks.
- Keep scene folder conventions (no new file without purpose).

## Environment facts

- Godot 4.7.2 portable editor at `C:\tools\godot\Godot_v4.7.2-stable_win64.exe` (outside repo).
- Build machine locale is `ar_SA` (see ARCHITECTURE.md §5 RTL fix — keep it in mind for UI).
- git: repo initialised; Phase 1 committed. `.godot/` ignored via `.gitignore`.
