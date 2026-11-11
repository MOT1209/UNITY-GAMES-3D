# Phase 4 Handoff — Dribbling / Passing / Shooting

Phase 3 (ball physics) is complete and validated. Everything Phase 4 needs is
exposed; nothing gameplay-related is implemented yet. Pick up here.

## State of the world

- Ball: `scenes/ball/football_ball.tscn` (`BallController`, group
  `football_ball`, layer 3 / value 4, mask 5). Config resource:
  `resources/configurations/ball_config.tres` (defaults live in
  `ball_config.gd` — the `.tres` pins nothing).
- Detector: `BallProximityDetector` (scripts/ball/ball_proximity_detector.gd),
  already mounted in the ball test scene at `Player/BallDetector` with
  `show_rings = true`.
- Player: untouched Phase 2 controller (`player.tscn`, layer 1). Phase 3
  deliberately did not modify it.
- InputMap: `pass`, `shoot`, `lob_pass`, `dribble`, `tackle` exist but are
  consumed by nothing (validated untouched). Dev keys 1/2/3/4/R/T/B in the
  ball test scene are raw-key and test-scene-only.
- Validation suites: `tests/phase3_validation.tscn` (101 checks) plus the
  Phase 1 (49) and Phase 2 (57) guards — keep all three green.

## Integration points (the contract)

### 1. Reading the ball

```gdscript
var detector: BallProximityDetector = $Player/BallDetector
if detector.is_interaction_available():          # distance + height gate
    var ball := detector.get_current_ball() as BallController
    var dir := detector.get_direction_to_ball()  # planar, auto-aim friendly
```

Signals: `ball_detected(ball)`, `ball_lost`,
`ball_interaction_available(available)`. Detection radius is planar
(2.5 m default); interaction adds `interaction_distance` (0.9 m) and
`max_interaction_height` (1.0 m).

### 2. Acting on the ball

- **Pass / shoot:** `ball.apply_kick(direction, power, lift, spin)` —
  wake-safe, ceiling-checked, emits `kicked(speed)`.
- **Dribble / steady push:** inherited `ball.apply_force(...)` **every physics
  tick** (forces are one-step) and wake first if the ball may be sleeping —
  or simply nudge with small `apply_kick()` pulses.
- **Raw impulse (tackle knock etc.):** inherited `ball.apply_impulse(...)`;
  does not wake a sleeping ball.
- **Reset / stop:** `ball.reset_ball(pos = INF)` / `ball.stop_ball()`; the
  ball emits `ball_reset(position)`.

### 3. Physics rules to respect

- Don't override `apply_impulse`/`apply_force` on `BallController` — overriding
  native `RigidBody3D` methods is an error in 4.7; extend with new names
  (e.g. `try_trap()`) instead.
- Don't write `global_position` mid-simulation — use `reset_ball()`'s freeze
  cycle pattern.
- Per-step adjustments belong in `_integrate_forces()` (see the clamp + settle
  ramp there), not in `_physics_process` impulse spam.
- Jolt contact data requires `contact_monitor = true` (already set on the
  ball). If you add your own bodies that need `get_contact_count()`, remember
  this.
- Godot 4.7 specifics that bit Phase 3: no `ImmediateMesh.surface_add_color()`
  (use per-surface materials), no `@static` annotation, no `sqrtf/cosf/...`.

## Suggested Phase 4 build order

1. `PlayerBallInteraction` node under the player: owns the detector, exposes
   `try_trap()`/`try_pass()`/`try_shoot()` driven by the existing InputMap
   actions; gameplay kick powers as `PlayerConfig`-style resource
   (`BallActionConfig`).
2. Possession-lite state machine on the interaction node (trap window →
   carrying → kick), ball remains a free rigid body the whole time — push it
   with per-tick `apply_force()` while dribbling.
3. Collision-layer refinement *if needed*: move the player body off layer 1
   onto its own layer (e.g. layer 2, value 2) so ball masks can separate
   world (1) from player (2); update `ball_controller.gd`'s
   `LAYER_WORLD_VALUE`/`collision_mask` and the phase-3 suite assertions
   (`Ball: collision layer 3 (value 4)`, `Ball: mask = 5`) together.
4. Aim assist: reuse `detector.get_direction_to_ball()` for directional kicks;
   camera-relative aiming comes free via the Phase 2 camera basis.
5. Extend `tests/phase4_validation.tscn` in the same pattern
   (`[PASS]/[FAIL]` + summary + `quit(1 on fail)`), and keep the Phase 1–3
   suites untouched.

## How each Phase 4 mechanic maps to the Phase 3 interfaces

| Plan section | Mechanic | Phase 3 interface to reuse |
|---|---|---|
| §6 Passing | ground + directional pass | `apply_kick(detector.get_direction_to_ball(), power, 0)` — power from `BallActionConfig` |
| §7 Shooting | shot with power charging | `apply_kick(dir, charged_power, 0.5)` — the ceiling already clamps the result |
| §8 Lob passing | elevated pass | `apply_kick(dir, power, lift)` — `lift` (m/s up) is the arc knob |
| §9 Dribbling | carry/push ball | per-tick `apply_force(push)` while `is_interaction_available()`; wake first or small `apply_kick()` pulses |
| §10 Ball control | trap / first touch / reception | `detector.is_interaction_available()` gate + damp `ball.linear_velocity` toward the carrying speed per tick (do not attach/teleport) |
| §11 Kick power | charge meter | own the charge in Phase 4, pass the final value as `power`; direction from `get_direction_to_ball()` |
| §13 Action states | IDLE/CARRYING/KICKING… | mirror `PlayerController.MovementState` pattern on the new interaction node |
| §17 Stability | receptions under load | reuse `reset_ball()` for out-of-play repositions; never write `global_position` mid-simulation |

## Test scene conventions (carried from Phase 2 handoff)

- Dev scenes in `scenes/development/`, scripts in `scripts/development/`.
- HUD labels use `layout_direction = 2` (RTL) where Arabic text is shown.
- Screenshots via `tests/screenshot_runner.tscn` pattern (windowed).
- Docs to add for Phase 4: `PHASE_4_AUDIT.md` (pre-check), feature doc,
  `PHASE_4_REPORT.md`, and a `PHASE_5_HANDOFF.md`.
