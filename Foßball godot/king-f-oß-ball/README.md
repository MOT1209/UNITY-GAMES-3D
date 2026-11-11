# KING FOOTBALL

Stylized 3D football game prototype — **Godot 4.7.2**, built phase by phase
from the Arabic plan documents (`المرحلة الأول 1.txt`).

## Current status

**Phase 3 — Ball Physics System: COMPLETE** (validated, 101/101 phase-3
checks; Phase 1 guard 49/49, Phase 2 guard 57/57).

What Phase 3 delivers (on top of Phases 1–2):

- Reusable physics football ball: `RigidBody3D` scene
  (`scenes/ball/football_ball.tscn`) with FIFA-like size/mass, bounce,
  rolling friction, speed ceiling and continuous collision detection (CCD)
- Kick / impulse / force APIs with a wake-safe `apply_kick()`, plus
  `reset_ball()` / `stop_ball()` and speed/direction queries
- Clean rolling stops via a ground "settle" ramp (no endless creeping)
- `BallProximityDetector`: detection + interaction-window layer with
  `ball_detected` / `ball_lost` / `ball_interaction_available` signals —
  the Phase 4 (dribbling/passing) integration point
- Procedural paned ball texture (no external assets) + dev-only velocity
  arrow overlay
- Dedicated test scene: `scenes/development/ball_physics_test.tscn`
  (real pitch + player + detector rings + HUD + obstacles)
- Third headless validation suite: `tests/phase3_validation.tscn` (101 checks)

**Phase 2 — Player Controller: COMPLETE** (validated, 57/57 phase-2 checks,
Phase 1 guard still 49/49).

What Phase 2 delivers (on top of Phase 1):

- First controllable football player: reusable `CharacterBody3D` scene
  (`scenes/player/player.tscn`) now carrying the real animated character model
  (`assets/models/characters/player.glb` — Idle/Walk/Run/Kick driven from the
  controller signals; the referee/assistant/prop GLBs are imported too)
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

# Phase 3 (ball physics):
godot --headless --path . res://tests/phase3_validation.tscn
# Expected: "=== Validation summary: 101 passed, 0 failed ===", exit code 0.

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

## Play the ball physics test scene

```text
godot --path . res://scenes/development/ball_physics_test.tscn
# or open the scene in the editor and press F6.
# WASD/arrows move the player · Shift sprint · V toggle camera · Esc menu.
# Ball dev keys: 1 touch pass · 2 driven kick · 3 lob · 4 power shot ·
#                R ball to centre · T full reset · B drop from 6 m.
```

## Controls (Phase 2)

`WASD`/arrows **move the player** · `Shift` sprint · `V` toggle camera ·
`Tab` reset (debug) · `Esc` back/pause. Ball actions (Space/E/Q/C/F) are mapped
but intentionally not consumed until later phases.
Full table incl. gamepad bindings: [docs/CONTROLS.md](docs/CONTROLS.md).

## Documentation

- [docs/BALL_PHYSICS.md](docs/BALL_PHYSICS.md) — ball physics architecture & tuning
- [docs/BALL_INTERACTION.md](docs/BALL_INTERACTION.md) — detector + kick API integration surface
- [docs/PHASE_3_REPORT.md](docs/PHASE_3_REPORT.md) — Phase 3 features, tests, results
- [docs/PHASE_4_HANDOFF.md](docs/PHASE_4_HANDOFF.md) — where to pick up for Phase 4 (dribbling/passing)
- [docs/STADIUM_ARENA.md](docs/STADIUM_ARENA.md) — Blender stadium (GLB) used by the match scene
- [docs/PHASE_2_REPORT.md](docs/PHASE_2_REPORT.md) — Phase 2 features, tests, results
- [docs/PLAYER_CONTROLLER.md](docs/PLAYER_CONTROLLER.md) — controller architecture & tuning
- [docs/PHASE_2_AUDIT.md](docs/PHASE_2_AUDIT.md) — mandatory Phase 2 pre-check
- [docs/PHASE_1_REPORT.md](docs/PHASE_1_REPORT.md) — what was built, tested, and known limitations
- [docs/PHASE_1_AUDIT.md](docs/PHASE_1_AUDIT.md) — initial repository audit
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — code/scene structure and design decisions
- [docs/CONTROLS.md](docs/CONTROLS.md) — input map reference
- [docs/PHASE_3_HANDOFF.md](docs/PHASE_3_HANDOFF.md) — Phase 3 handoff (history)

Phase 4+ (dribbling/passing/shooting, AI, audio, polish) is **not started**
per plan.
