# Dribbling System (Phase 4)

Physics-based ball control while the `dribble` action is held. The ball is
**never attached, positioned or teleported** — control is a per-tick capped
push force toward a spot ahead of the player, exactly as the Phase 3
handoff contract prescribes.

## Where it lives

- `scripts/gameplay/dribbling_system.gd` — `DribblingSystem` (`Node`), built
  by `FootballActions._build_subsystems()`. One method:
  `physics_tick()`, driven by the orchestrator every physics tick.
- Engagement/disengagement + state in `football_actions.gd`.

## How dribbling works

Each physics tick while `dribble` is held (and no kick is in its transient
state):

1. **Range gate** — ball must be within `dribble_distance` (1.6 m, planar)
   and `max_control_height` (1.2 m) of the player. Outside → `false`, the
   ball moves freely; the player simply runs onto it again (no magnet).
2. **Follow-spot spring** — the ball is pushed toward a follow spot
   `dribble_follow_distance` (0.55 m) ahead of the player along the *raw
   movement input* direction. The force is a spring:
   `F = (spot − ball) · dribble_control_strength`, i.e. 7 N per metre of
   planar error — weak next to the spot, strong when the ball lags or runs
   ahead, so the ball is *parked* at the spot instead of being shoved
   blindly. Sprinting multiplies the strength by `dribble_sprint_boost`
   (1.35).
3. **Hold mode (standing still)** — with no movement input there is no
   follow spot, so the system damps the ball's planar velocity
   (`F = −v · dribble_brake_strength`) and keeps it within reach instead of
   pushing it along the last aim direction.
4. **Brake** — ball speed that overshoots the player's speed +
   `dribble_speed_slack` (2.0 m/s) is bled by
   `dribble_brake_strength` (10 N per m/s of overshoot), so pushes never
   run away.
5. **Force cap** — the push+brake vector is limited to
   `dribble_max_force` (14 N) for solver stability.
6. **Wake-safe application** — `ball.sleeping = false`, then
   `apply_force(force)`. Godot forces are one-step; the caller re-applies
   every tick by design. Native `RigidBody3D` methods are never overridden.

The system returns `true` for as long as the ball is inside the range —
"under control" — so the derived state stays `DRIBBLING` even while the
ball is momentarily stationary.

## Signals & state

`dribble_started` / `dribble_stopped` fire on engagement flips; the derived
action state shows `DRIBBLING` while engaged. Any kick (pass/shot/lob)
immediately stops dribble control. Releasing the button stops it the same
tick.

## Tuning knobs (`BallActionConfig` → Dribbling group)

| Knob | Default | Meaning |
|---|---|---|
| `dribble_distance` | 1.6 m | Engagement range (larger than the 0.9 m interaction window) |
| `max_control_height` | 1.2 m | Vertical gate |
| `dribble_control_strength` | 7 N/m | Spring gain (force per metre of error to the follow spot) |
| `dribble_max_force` | 14 N | Total force cap |
| `dribble_follow_distance` | 0.55 m | Carry spot ahead of the player |
| `dribble_sprint_boost` | 1.35 | Strength multiplier while sprinting |
| `dribble_brake_strength` | 10 N/(m/s) | Overshoot bleed; also the stand-still hold damping |
| `dribble_speed_slack` | 2.0 m/s | Allowed speed over the player's |

## Validation coverage

`tests/phase4_validation.tscn` asserts: a ball at 1.2 m (outside the
interaction window, inside dribble range) is gathered and carried with the
player, is parked at the follow spot ahead of the player (local z < 0 and
< 1.2 m from the player — a constant push instead puts it at 1.5 m and
fails), no teleport (max per-tick position step < 0.4 m), and after release
the ball coasts freely (slower than at release, drifting > 2 m away — no
recovery snap). Standing still with the dribble held damps a rolling ball
(5 m/s → < 1 m/s) and keeps it within reach. `dribble_started`/
`dribble_stopped` fire.

## Notes for Phase 5+

- `dribble_started/stopped` + the derived `DRIBBLING` state are the AI's
  possession indicator until a formal possession concept exists.
- Skill moves / beats are explicitly out of scope (plan §20).
