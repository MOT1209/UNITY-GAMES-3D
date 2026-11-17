# Phase 5 Handoff — Team AI / Match Rules

Phase 5 **part 1** (teams, formations, goalkeeper) is complete and validated —
218/218 phase-5 checks, guards still green (49/57/103/159/29). What is left
of Phase 5 (outfield AI, match rules) starts here. Pick up below.

## What part 1 already delivered

- `scripts/teams/` — `Formation` (4-4-2, 4-3-3, 3-5-2, 4-2-3-1 + the slot →
  world math), `TeamSheet`, `MatchTeam`, `TeamPlayer`, `TeamGoalkeeper` (guard /
  dive / catch / throw) and `TeamsDemo`.
- `scripts/player/` — `TeamKit`, `PlayerLook`, `GoalkeeperVisual`; the one
  animation driver `PlayerCharacterVisual` now also dresses the model.
- `scenes/teams/teams_demo.tscn` — arena + both teams + ball, keys 1–4 switch
  the gold team's formation.
- `resources/formations/formations.json` — the exported mirror of the
  formation table (the suite keeps the two in sync).
- `tests/phase5_validation.tscn` (218 checks).
- Details: [docs/TEAMS_AND_FORMATIONS.md](TEAMS_AND_FORMATIONS.md).

The outfield players **hold their kick-off slot** — they have no movement AI
yet. The goalkeeper already plays with the real `BallController` (no
teleports, no velocity writes, kicks through `apply_kick()`), so the outfield
AI must obey the same contract.

## State of the world

- **Player**: `scenes/player/player.tscn` (layer 1). The controller script
  is untouched Phase 2 (`player_controller.gd`); gameplay lives in the
  `BallActions` child node (see below). States: movement
  `IDLE/MOVING/SPRINTING` + gameplay `IDLE/RECEIVING/PASSING/SHOOTING/
  LOB_PASSING/DRIBBLING` (separate machines).
- **Gameplay node**: `scripts/gameplay/football_actions.gd`
  (`FootballActions`, mounted as `Player/BallActions`), with
  `Player/BallActions/BallDetector` = `BallProximityDetector`. Subsystems
  built in `_ready()`: PassingSystem, ShootingSystem, LobPassSystem,
  DribblingSystem, BallControlSystem, KickPowerControllers
  (PassCharge/ShootCharge/LobCharge).
- **Ball**: unchanged Phase 3 (`scenes/ball/football_ball.tscn`, layer 3 /
  value 4, mask 5, group `football_ball`). Config:
  `resources/configurations/ball_config.tres`.
- **Gameplay config**: `resources/configurations/ball_action_config.tres`
  (`BallActionConfig`) — every gameplay number is inspector-tunable there.
- **InputMap**: `pass` (Space/A), `shoot` (E/B), `lob_pass` (Q/Y),
  `dribble` (C/X) are now **consumed by Phase 4**. `tackle` (F/L3) is still
  unmapped to gameplay — reserved for a later phase. Movement/sprint/
  pause/camera actions unchanged.
- **Test scene**: `scenes/development/football_mechanics_test.tscn`
  (pitch + player + ball + camera + obstacles/wall + HUD; dev keys
  1/2/3/4/R/T/B). Visual capture: `-- mechanics` screenshot mode.
- **Validation**: `tests/phase4_validation.tscn` (159 checks) and
  `tests/phase5_validation.tscn` (218 checks). Add further Phase 5 work as
  new suites; do not weaken these.

## What Phase 4 exposes (the AI/rules contract)

### Per-action gameplay → engine mapping (what actually moves the ball)

| Action | Trigger | Engine effect | Signals |
|---|---|---|---|
| Pass | `pass` press→release | `BallController.apply_kick(dir, power, 0)` | `pass_started(power)`, `pass_completed` |
| Shot | `shoot` press→release | `apply_kick(dir, power, lift)` lift = lerp(0.3→3.0 by charge) | `shot_started(power, lift)`, `shot_completed` |
| Lob | `lob_pass` press→release | `apply_kick(dir, power, lob_lift=6.5)` | `lob_started(power, lift)` (no completed per plan §14) |
| Dribble | `dribble` hold | per-tick capped `apply_force`: follow-spot spring (or velocity damping when standing still) + overshoot brake | `dribble_started`, `dribble_stopped` |
| Reception | automatic (ball ≥ 2 m/s **toward** the player, ≤ 1.4 m) | per-tick capped damping + feet-pull forces | `ball_received(speed)` |
| Charge | any kick held | power ramps 0→1 over 0.9 s after 0.12 s quick-tap threshold; a final `0.0` ratio is published on release/cancel | `charge_changed(action, ratio)` |

Every direction is a camera-relative intent blended toward the ball
(`*_direction_adjustment`), power clamped to config min/max, all kicks
wake-safe mass-scaled impulses. No teleports, no velocity writes, ever.

### Queries (read these; do not duplicate the logic)

`FootballActions` (on any player instance):

- `get_tracked_ball() -> BallController` — nearest tracked ball or null
- `can_interact_with_ball() -> bool` — the 0.9 m + height gate
- `get_ball_distance() -> float`, `get_ball_relative_position() -> Vector3`
  (player-local frame), `get_kick_direction() -> Vector3` (aim direction)
- `get_action_availability() -> Dictionary` — keys `ball_nearby`, `interact`,
  `pass`, `shoot`, `lob`, `dribble`
- `action_state` + `get_action_state_name()`; `get_charge_ratio(action)`

`BallProximityDetector` (under BallActions): `get_current_ball()`,
`is_ball_nearby()`, `get_distance_to_ball()`, `get_direction_to_ball()`,
`is_interaction_available()` + `ball_detected/ball_lost/
ball_interaction_available`.

`BallController`: `get_ball_speed()`, `get_ball_direction()`, `kicked(speed)`,
`ball_reset(position)`, plus the kick/impulse/force/reset/stop APIs.

### Signals for AI decision-making

- **Possession-ish**: `ball_received(speed)` on a player = "this player now
  has the ball"; `dribble_started/stopped` while holding `dribble` = active
  carrier; `action_state == DRIBBLING`.
- **Ball left the player**: any `*_started` on a player = the ball is now in
  flight (pair with `BallController.kicked(speed)` for the actual speed).
- **Shot detection for a keeper**: `shot_started(power, lift)` + the ball's
  velocity direction — distinguish from `lob_started` (fixed high lift).
- **Player state**: `movement_state_changed` (IDLE/MOVING/SPRINTING) +
  `action_state_changed` (gameplay states) are orthogonal; AI can gate on
  both.

## Integration points & rules for Phase 5

1. **AI steering**: drive AI players with the same `PlayerController`
   movement API (`Input` actions are the human path; for scripted AI,
   either emit InputMap actions or add a `PlayerConfig.movement_reference =
   WORLD` + a small intent-provider node — do not fork the controller).
2. **Never write `ball.global_position`** during play; only `reset_ball()`
   (freeze cycle) may move it. All ball actuation goes through
   `apply_kick/apply_impulse/apply_force` (wake forces first).
3. **Never override** inherited `RigidBody3D.apply_impulse/apply_force`
   in GDScript (Godot 4.7 error). Extend with new method names.
4. **Forces are one-step** — re-apply per physics tick (see
   `DribblingSystem.physics_tick` for the pattern).
5. **`_ready()` doesn't run on non-tree instances** — any new subsystem
   must be validated on a player actually inside the tree.
6. **`tackle`** is still free: a tackle system can follow the subsystem
   pattern (`scripts/gameplay/tackle_system.gd` + config group +
   `_after_kick`-style transient state) without touching existing files'
   core.
7. **Goalkeeper/reactive AI**: `shot_started(power, lift)` gives shot
   geometry immediately; the ball's speed ceiling (30 m/s) bounds all
   projectiles.

## Known Phase 4 limitations Phase 5 should know

- Reception is proximity-based (1.4 m); "call for a pass" / targeted
  receiving does not exist yet.
- No pass-target/assist system: direction blending is the whole aim model.
- Player walks through the ball when not dribbling (accepted arcade
  behaviour; ball mask 5 still collides with the player body).
- No animation blending for kicks; `play_kick()` is a guarded hook only.
- Dribbling releases control entirely beyond 1.6 m (by design).

## Suggested Phase 5 verification loop

1. Read `docs/PHASE_4_REPORT.md` (§ Unverified) for accepted gaps.
2. Run all five suites before touching anything (expect 49/57/103/29/159).
3. Add `tests/phase5_validation.tscn` in the same `[PASS]/[FAIL]` +
   summary + `quit(1)` convention; simulate AI via the same
   `Input.action_press` pattern where physics timing matters.
4. New gameplay numbers go into `BallActionConfig` groups, never hard-coded.

## Reference docs

`PHASE_4_REPORT.md` (features/tests/limits) · `PASSING_SYSTEM.md` /
`SHOOTING_SYSTEM.md` / `LOB_PASSING_SYSTEM.md` / `DRIBBLING_SYSTEM.md` /
`BALL_CONTROL_SYSTEM.md` (mechanic details + tuning tables) ·
`BALL_PHYSICS.md` / `BALL_INTERACTION.md` (Phase 3 engine contract) ·
`PHASE_4_AUDIT.md` (what existed before Phase 4).
