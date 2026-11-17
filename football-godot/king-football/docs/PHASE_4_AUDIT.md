# Phase 4 Audit — Pre-Implementation Project Review

Mandatory audit performed before Phase 4 (gameplay mechanics), per the Phase 4
master prompt §3. Everything below was verified by reading the actual files and
re-running the validation suites on 2026-11-11 — **not** taken from memory.

## 0. Suite verification (re-run, exit codes checked)

| Suite | Result |
|---|---|
| `tests/phase1_validation.tscn` | `Validation summary: 49 passed, 0 failed` |
| `tests/phase2_validation.tscn` | `Validation summary: 57 passed, 0 failed` |
| `tests/phase3_validation.tscn` | `Validation summary: 103 passed, 0 failed` |

## 1. Existing systems that can be reused (no duplication)

### Phase 2 — Player (`scripts/player/player_controller.gd`, `player.tscn`)
- `PlayerController` (CharacterBody3D): camera-relative 8-direction movement,
  sprint, smoothed facing, `MovementState {IDLE, MOVING, SPRINTING}` with
  `movement_state_changed`, `speed_changed`, `facing_direction_changed`.
- Public queries: `get_current_speed()`, `get_state_name()`.
- `PlayerConfig` resource pattern (`resources/configurations/player_config.tres`)
  — Phase 4 gameplay tuning should use the same resource pattern.
- Visual: `VisualRoot/Character` = `player.glb` driven by
  `player_character_visual.gd` (listens to controller signals; `play_kick()`
  is **already reserved** for Phase 4 kicking actions).
- Player body: layer 1 (value 1). Ball masks world+ball only (value 5), so the
  ball already collides with the player body.

### Phase 3 — Ball (`scripts/ball/ball_controller.gd`, `ball_proximity_detector.gd`)
- `BallController` (RigidBody3D, group `football_ball`, layer 3/value 4,
  mask 1+4=5): `apply_kick(dir, power, lift=0, spin=ZERO)` — wake-safe,
  ceiling-checked, emits `kicked(speed)`; inherited `apply_impulse()` /
  `apply_force()` (one-step, do NOT override native methods); `reset_ball()`,
  `stop_ball()`; queries `get_ball_speed()`, `get_ball_direction()`.
  Speed ceiling 30 m/s, settle ramp < 0.45 m/s on ground, CCD on,
  contact_monitor on.
- `BallProximityDetector` (Node3D): signals `ball_detected`, `ball_lost`,
  `ball_interaction_available`; queries `get_current_ball()`,
  `is_ball_nearby()`, `get_distance_to_ball()`, `get_direction_to_ball()`
  (planar, normalized), `is_interaction_available()` (0.9 m planar +
  ≤1.0 m height gate). Detection radius 2.5 m. Not mounted in `player.tscn`
  yet (only in the ball test scene).

### InputMap (`project.godot`, untouched, validated)
- `pass` = Space / Joy A(0) · `shoot` = E / Joy B(1) · `lob_pass` = Q / Joy Y(3)
  · `dribble` = C / Joy X(2) · `tackle` = F / Joy L3(10) — all exist,
  **consumed by nothing**. Movement (`move_*`, sprint) untouched by Phase 3.
- Analog direction comes from the existing `move_*` actions
  (`Input.get_vector` keeps stick magnitude).

### Camera (`scripts/camera/game_camera.gd`)
- Broadcast + dynamic follow with `switch_mode()` / `mode_changed` —
  camera-relative aim reuses the same flattened-basis math the controller uses.

### Environment / foundation
- `scenes/environment/football_pitch.tscn`, `goal.tscn`,
  `stadium_prototype.tscn`, `stadium_arena.tscn` (GLB match scene).
- Dev scene conventions: `scenes/development/` + `scripts/development/`,
  HUD labels, dev-only raw keys, `tests/screenshot_runner.gd` for captures.
- `GameManager.return_to_menu()` + `pause` action for scene exits.

## 2. Signals / methods available as the integration contract
- Player → visuals: `movement_state_changed`, `speed_changed`,
  `facing_direction_changed`.
- Detector → gameplay: `ball_interaction_available(available)` etc.
- Ball → gameplay/UI: `kicked(speed)`, `ball_reset(position)`.

## 3. Missing dependencies (to be built in Phase 4 — nothing conflicts)
1. A **central interaction layer** on the player that owns the detector and
   exposes `can_interact_with_ball()`, `get_ball_relative_position()`,
   `get_ball_distance()`, `get_kick_direction()`, `get_action_availability()`.
2. Kick-power charging (pass/shoot), cooldowns, action-state machine
   (IDLE/RECEIVING/PASSING/SHOOTING/LOB_PASSING/DRIBBLING) —
   separate from the player's movement state.
3. Subsystems: passing, shooting, lob, dribbling, ball control/reception —
   each a small script with a shared `BallActionConfig` resource.
4. Mounting a `BallDetector` child under the persistent player scene.
5. Phase 4 validation suite + test scene + dev UI.

## 4. Integration problems identified
- `player.tscn` has **no** detector child yet — Phase 4 adds it
  (`BallActions` node + `BallDetector` child) without touching the
  controller script's core.
- `apply_force()` is one-step → dribbling must re-apply per physics tick
  and wake the ball first (or use small `apply_kick()` pulses).
- Never write `ball.global_position` during play (only `reset_ball()`'s
  freeze cycle).
- Godot 4.7: overriding inherited `RigidBody3D.apply_impulse/apply_force` in
  GDScript is an error — extend with new method names only.
- Dev raw keys in the ball test scene (1/2/3/4/R/T/B) must stay dev-only;
  real gameplay uses the existing InputMap actions.

## 5. Required modifications (minimal-diff plan)
- `player.tscn`: add `BallActions` (Node3D, gameplay script) with
  `BallDetector` child. No controller-script changes.
- New `scripts/gameplay/` package + `BallActionConfig` resource.
- New `scenes/development/football_mechanics_test.tscn` + script (HUD).
- New `tests/phase4_validation.tscn/.gd` following the `[PASS]/[FAIL]`
  + summary + `quit(1 on fail)` convention; Phase 1–3 suites stay untouched.

## 6. Decision: collision layers stay as-is
Player stays on layer 1. The handoff's "refine layers if needed" is not
needed: ball mask 5 already collides with the player body, gameplay kicks go
through `apply_kick()` (impulse, not collision), and no Phase 4 feature
requires separating world from player contact.

## 7. Out of scope (plan §20 — enforced)
Team AI, opponent/goalkeeper AI, formations, match rules, scoreboard, timer,
fouls, offside, full animation system, multiplayer, career/tournament,
advanced skill moves. `tackle` action stays unconsumed (future phase).
