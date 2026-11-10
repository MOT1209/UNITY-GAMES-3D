# KING FOOTBALL

Stylized 3D football game prototype — **Godot 4.7.2**, built phase by phase
from the Arabic plan documents (`المرحلة الأول 1.txt`).

## Current status

**Phase 2 — Player Controller: COMPLETE** (validated, 57/57 phase-2 checks,
Phase 1 guard still 49/49).

What Phase 2 delivers (on top of Phase 1):

- First controllable football player: reusable `CharacterBody3D` scene
  (`scenes/player/player.tscn`) with a stylized placeholder body
- 8-direction movement — keyboard normalized, gamepad analog magnitude
  preserved, diagonals not faster than straights
- Camera-relative movement (uses the active camera's flattened basis, with an
  automatic world-axis fallback) — configurable, defaults on
- Smooth configurable acceleration / deceleration + sprint (`Shift`)
- Smoothed character rotation that keeps the last facing while idle
- Movement states `IDLE / MOVING / SPRINTING` with animation-ready signals
- Inspector-tunable `PlayerConfig` resource
  (`resources/configurations/player_config.tres`)
- Dedicated test scene: `scenes/development/player_controller_test.tscn`
- Second headless validation suite: `tests/phase2_validation.tscn` (57 checks)

**Phase 1 — Foundation: COMPLETE** (validated, 49/49 automated checks).

What Phase 1 delivers:

- Complete project structure (`scenes/`, `scripts/`, `ui/`, `resources/`, `tests/`, `docs/`)
- Procedurally built stylized stadium: full-size pitch (105 × 68 m) with all
  markings (boundary, halfway line, centre circle + spot, penalty areas,
  goal areas, penalty spots, corner arcs), two goals with posts/crossbar/nets,
  grandstands on 4 sides, floodlights, sky, shadows
- Reusable two-mode camera system: **BROADCAST** (elevated, fixed sideline
  perspective) and **DYNAMIC/FOLLOW** (damped chase camera) — toggled with `V`
- Full InputMap for 13 gameplay actions (keyboard + gamepad bindings each)
- Main menu with working Start Match / Quit flow
- Global `GameManager` autoload owning game state (`BOOT / MAIN_MENU / IN_MATCH`)
- Automated headless validation suite + scripted visual screenshot harness

## Requirements

- Godot **4.7.2 stable** (developed and validated on `Godot_v4.7.2-stable_win64.exe`)
- No external addons or assets — everything is code-generated

## Run

```text
# From the project folder:
godot --path .
# or open project.godot in the Godot editor and press F5.
```

## Validate (headless, no window)

```text
godot --headless --path . res://tests/phase1_validation.tscn
# Expected: "=== Validation summary: 49 passed, 0 failed ===", exit code 0.

# Phase 2 (player controller):
godot --headless --path . res://tests/phase2_validation.tscn
# Expected: "=== Validation summary: 57 passed, 0 failed ===", exit code 0.

# Stadium arena (Blender GLB match scene):
godot --headless --path . res://tests/stadium_arena_validation.tscn
# Expected: "=== Validation summary: 29 passed, 0 failed ===", exit code 0.

# Visual captures (windowed, saves PNGs into assets/placeholders/validation/):
godot --path . res://tests/screenshot_runner.tscn -- menu
godot --path . res://tests/screenshot_runner.tscn -- stadium
godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
godot --path . res://tests/screenshot_runner.tscn -- arena
godot --path . res://tests/screenshot_runner.tscn -- arena_follow
```

## Play the player controller

```text
godot --path . res://scenes/development/player_controller_test.tscn
# or open the scene in the editor and press F6.
# WASD/arrows (or left stick) move · Shift sprint · V toggle camera ·
# Tab reset to centre · Esc menu.
```

## Controls (Phase 2)

`WASD`/arrows **move the player** · `Shift` sprint · `V` toggle camera ·
`Tab` reset (debug) · `Esc` back/pause. Ball actions (Space/E/Q/C/F) are mapped
but intentionally not consumed until later phases.
Full table incl. gamepad bindings: [docs/CONTROLS.md](docs/CONTROLS.md).

## Documentation

- [docs/STADIUM_ARENA.md](docs/STADIUM_ARENA.md) — Blender stadium (GLB) used by the match scene
- [docs/PHASE_2_REPORT.md](docs/PHASE_2_REPORT.md) — Phase 2 features, tests, results
- [docs/PLAYER_CONTROLLER.md](docs/PLAYER_CONTROLLER.md) — controller architecture & tuning
- [docs/PHASE_2_AUDIT.md](docs/PHASE_2_AUDIT.md) — mandatory Phase 2 pre-check
- [docs/PHASE_1_REPORT.md](docs/PHASE_1_REPORT.md) — what was built, tested, and known limitations
- [docs/PHASE_1_AUDIT.md](docs/PHASE_1_AUDIT.md) — initial repository audit
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — code/scene structure and design decisions
- [docs/CONTROLS.md](docs/CONTROLS.md) — input map reference
- [docs/PHASE_3_HANDOFF.md](docs/PHASE_3_HANDOFF.md) — where to pick up for Phase 3 (ball physics)

Phase 3+ (ball physics, passing/shooting, AI, audio, polish) is **not started**
per plan.
