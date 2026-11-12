# KING FOOTBALL

Stylized 3D football game prototype — **Godot 4.7.2**, built phase by phase
from the Arabic plan documents (`المرحلة الأول 1.txt`).

## Current status

**Master plan (everything that is left, with acceptance criteria):
[plan.md](plan.md)** — read this first.

### Integration & multilingual status (2026-11-12)

Run **everything** with `tests/run_all.sh <godot-4.7.2-console-exe>` (per-suite timeout, duplicate
`class_name` guard, every `*_validation.tscn` must be listed): 19 suites, ~1,800 checks. Details and the
honest list of what is and is not done: **[docs/STABILIZATION_REPORT.md](docs/STABILIZATION_REPORT.md)**.

- **Career ↔ academy**: training/scouting advance only with the career calendar; Over-Age Prospects list
  (promote / release / keep); stable Unicode-safe club ids.
- **Match engine**: ends switch at half-time; the real `TeamGoalkeeper` (dive / catch / throw) and real kit
  data are used in `MatchManager`; goal detection fixed (the arena trigger could not see the real ball).
- **Languages: Arabic (RTL), German, English** — central `Loc` autoload, CSV tables, runtime switching,
  persisted choice, bundled Noto Sans Arabic. See [docs/LOCALIZATION_SYSTEM.md](docs/LOCALIZATION_SYSTEM.md),
  [docs/ARABIC_RTL_SUPPORT.md](docs/ARABIC_RTL_SUPPORT.md), [docs/MULTILINGUAL_QA_REPORT.md](docs/MULTILINGUAL_QA_REPORT.md).
- **Not done**: real-team data import, in-progress match save, many system-layer error messages are still English.

**Phase 5 (part 1) — Teams, Formations & Goalkeeper: COMPLETE** (validated,
218/218 phase-5 checks; guards still green — Phase 1 49/49, Phase 2 57/57,
Phase 3 103/103, Phase 4 159/159, Arena 29/29).

**Phase 4 — Football Gameplay Mechanics: COMPLETE** (validated, 159/159
phase-4 checks; guards still green — Phase 1 49/49, Phase 2 57/57,
Phase 3 103/103, Arena 29/29).

What Phase 5 (part 1) delivers:

- Kick-off formations for 4-4-2, 4-3-3, 3-5-2 and 4-2-3-1
  (`scripts/teams/formation.gd`) with an exported JSON mirror that the test
  suite keeps in sync
- Two teams line up in their formation with kit colours, shirt numbers from a
  shared atlas and individual looks (skin, hair, beard, boots, height, build)
- A goalkeeper who plays: guards his line, reads the shot, dives, catches the
  ball **with forces only** (never frozen, never teleported) and throws it
  back into play
- `scenes/teams/teams_demo.tscn` — arena + both teams + ball; keys 1–4 switch
  the gold team's formation
- Fifth headless validation suite: `tests/phase5_validation.tscn`
  (218 checks)

See [docs/TEAMS_AND_FORMATIONS.md](docs/TEAMS_AND_FORMATIONS.md).

What Phase 4 delivers (on top of Phases 1–3):

- Modular gameplay package `scripts/gameplay/` — one responsibility per
  system: `football_actions.gd` (central player↔ball interaction layer +
  derived action-state machine), `passing_system.gd`, `shooting_system.gd`,
  `lob_pass_system.gd`, `dribbling_system.gd`, `ball_control_system.gd`
  (reception), `kick_power_controller.gd` (per-action power charging) and a
  shared `BallActionConfig` resource
- Player scene now carries the `BallActions` node + `BallDetector` child;
  the ball is never attached or teleported — every kick goes through the
  Phase 3 `apply_kick()` API, dribble/reception control is per-tick capped
  `apply_force()` pushes
- Ground passing (quick tap = default power, hold = charge up), directional
  aiming with an intent↔ball blend, cooldowns + repeated-input protection
- Shooting with variable power and charge-scaled elevation (ground → lifted)
- Lob passing with a fixed configurable vertical impulse (natural arc)
- Physics-based dribbling: follow-spot spring + overshoot brake, sprint boost,
  hold-the-ball behaviour when standing still, free ball when control is lost,
  no artificial ball-following
- Ball reception/control: approaching balls are damped under control
  automatically (fast/slow, front/side), `ball_received` on clean touch
- Input integration for the existing `pass` / `shoot` / `lob_pass` /
  `dribble` actions (keyboard + gamepad), Phase 2 movement untouched
- Gameplay test scene `scenes/development/football_mechanics_test.tscn`
  (pitch, player, ball, camera, obstacles, KING-styled dev HUD)
- Fourth headless validation suite: `tests/phase4_validation.tscn`
  (159 checks incl. runtime physics + input simulation)

**Phase 3 — Ball Physics System: COMPLETE** (validated, 103/103 phase-3
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
# Expected: "=== Validation summary: 103 passed, 0 failed ===", exit code 0.

# Phase 4 (gameplay mechanics):
godot --headless --path . res://tests/phase4_validation.tscn
# Expected: "=== Validation summary: 159 passed, 0 failed ===", exit code 0.

# Phase 5 (teams, formations, goalkeeper):
godot --headless --path . res://tests/phase5_validation.tscn
# Expected: "=== Validation summary: 219 passed, 0 failed ===", exit code 0.

# Stadium arena (Blender GLB match scene):
godot --headless --path . res://tests/stadium_arena_validation.tscn
# Expected: "=== Validation summary: 29 passed, 0 failed ===", exit code 0.

# Visual captures (windowed, saves PNGs into assets/placeholders/validation/):
godot --path . res://tests/screenshot_runner.tscn -- menu
godot --path . res://tests/screenshot_runner.tscn -- stadium
godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
godot --path . res://tests/screenshot_runner.tscn -- arena
godot --path . res://tests/screenshot_runner.tscn -- arena_follow
godot --path . res://tests/screenshot_runner.tscn -- ball
godot --path . res://tests/screenshot_runner.tscn -- mechanics
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

## Play the gameplay mechanics test scene

```text
godot --path . res://scenes/development/football_mechanics_test.tscn
# or open the scene in the editor and press F6.
# WASD/arrows move the player · Shift sprint · V toggle camera · Esc menu.
# Gameplay: Space pass (hold to charge) · E shoot (hold = power + elevation) ·
#           Q lob pass · C dribble (hold).
# Ball dev keys: 1 touch pass · 2 driven kick · 3 lob · 4 power shot ·
#                R ball to centre · T full reset · B drop from 6 m.
```

## Controls

`WASD`/arrows **move the player** · `Shift` sprint · `V` toggle camera ·
`Esc` back/pause.

Phase 4 gameplay actions: `Space` **pass** (quick tap = default power, hold =
charge up to max) · `E` **shoot** (hold = power + elevated shot) ·
`Q` **lob pass** · `C` **dribble** (hold to control the ball). `F` tackle stays
mapped but is not consumed until a later phase.
Full table incl. gamepad bindings: [docs/CONTROLS.md](docs/CONTROLS.md).

## Documentation

- [docs/TEAMS_AND_FORMATIONS.md](docs/TEAMS_AND_FORMATIONS.md) — Phase 5 part 1: teams, formations & goalkeeper
- [docs/PHASE_4_REPORT.md](docs/PHASE_4_REPORT.md) — Phase 4 features, tests, results
- [docs/PHASE_5_HANDOFF.md](docs/PHASE_5_HANDOFF.md) — where to pick up for the rest of Phase 5
- [docs/PASSING_SYSTEM.md](docs/PASSING_SYSTEM.md) — ground passing design & tuning
- [docs/SHOOTING_SYSTEM.md](docs/SHOOTING_SYSTEM.md) — shooting & charge design
- [docs/LOB_PASSING_SYSTEM.md](docs/LOB_PASSING_SYSTEM.md) — lob pass design
- [docs/DRIBBLING_SYSTEM.md](docs/DRIBBLING_SYSTEM.md) — dribbling design & tuning
- [docs/BALL_CONTROL_SYSTEM.md](docs/BALL_CONTROL_SYSTEM.md) — ball reception/control design
- [docs/PHASE_4_AUDIT.md](docs/PHASE_4_AUDIT.md) — mandatory Phase 4 pre-check
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

Phase 5+ per plan: team AI, opponent/goalkeeper AI, formations, match rules,
scoreboard/timer, fouls — **not started**. The `tackle` action and
`play_kick()`/`play_tackle()` animation hooks remain reserved for them; see
[docs/PHASE_5_HANDOFF.md](docs/PHASE_5_HANDOFF.md).


## Management & career layer (Phases T1–T12)

KING FOOTBALL now includes a data-driven club ecosystem on top of the match
mechanics: team/player databases (JSON, fictional seed data), squads and
tactics, youth academy with scouting/training/promotion, club creator and kit
editor, leagues/cups/group tournaments, transfers/loans/contracts/finances,
a Club Manager career, versioned saves, a management hub UI and a match engine
(AI layers + attribute-driven gameplay).

- Start from the main menu → **Management Hub**.
- Docs: `docs/TEAM_PLAYER_DATABASE.md` (all T-phases). Tests: `tests/run_all.sh [godot]`
  runs every `res://tests/*_validation.tscn` suite headless.
- New autoloads: `TeamDB` (database), `AppHub` (management state).
