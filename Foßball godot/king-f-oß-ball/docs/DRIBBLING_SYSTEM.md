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
2. **Push** — toward a follow spot `dribble_follow_distance` (0.55 m) ahead
   of the player along the carry direction (movement input / facing).
   Standing still → hold the ball close instead of pushing it away.
   Sprinting multiplies the strength by `dribble_sprint_boost` (1.35).
3. **Brake** — ball speed that overshoots the player's speed +
   `dribble_speed_slack` (2.0 m/s) is bled by
   `dribble_brake_strength` (10 N per m/s of overshoot), so pushes never
   run away.
4. **Force cap** — the push+brake vector is limited to
   `dribble_max_force` (14 N) for solver stability.
5. **Wake-safe application** — `ball.sleeping = false`, then
   `apply_force(force)`. Godot forces are one-step; the caller re-applies
   every tick by design. Native `RigidBody3D` methods are never overridden.

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
| `dribble_control_strength` | 7 N | Push force toward the follow spot |
| `dribble_max_force` | 14 N | Total force cap |
| `dribble_follow_distance` | 0.55 m | Carry spot ahead of the player |
| `dribble_sprint_boost` | 1.35 | Strength multiplier while sprinting |
| `dribble_brake_strength` | 10 N/(m/s) | Overshoot bleed |
| `dribble_speed_slack` | 2.0 m/s | Allowed speed over the player's |

## Validation coverage

`tests/phase4_validation.tscn` asserts: a ball at 1.2 m (outside the
interaction window, inside dribble range) is gathered and carried with the
player (stays within 1.6 m, moving > 2 m/s), no teleport (max per-tick
position step < 0.4 m), the ball settles freely after release (deceleration
is the Phase 3 ball's own friction, no recovery snap), and
`dribble_started`/`dribble_stopped` fire.

## Notes for Phase 5+

- `dribble_started/stopped` + the derived `DRIBBLING` state are the AI's
  possession indicator until a formal possession concept exists.
- Skill moves / beats are explicitly out of scope (plan §20).
