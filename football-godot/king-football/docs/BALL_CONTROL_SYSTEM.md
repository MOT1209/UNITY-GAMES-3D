# Ball Control System — Reception (Phase 4)

Automatic first-touch control: a ball arriving at speed near the player is
brought under control with pure physics. No velocity resets, no snapping,
no possession teleport — the ball slows down *because forces slow it*.

## Where it lives

- `scripts/gameplay/ball_control_system.gd` — `BallControlSystem` (`Node`),
  built by `FootballActions._build_subsystems()`. One method:
  `physics_tick()` returning the ball's planar speed after the step.
- Triggering/state in `football_actions.gd` (`_update_reception`).

## How reception works

1. **Trigger** (in `FootballActions`): a tracked ball within
   `reception_distance` (1.4 m planar) and `max_control_height` (1.2 m),
   moving **toward** the player at ≥ `reception_trigger_speed` (2.0 m/s),
   while the action state is IDLE or DRIBBLING (never mid-kick) → RECEIVING.
   The approach test is `dot(velocity, player − ball) > 0`: a ball that is
   travelling away from the player is never trapped (including a ball the
   dribble is carrying away).
2. **Control** (per tick, in `BallControlSystem`):
   - Exponential damping force `F = −k·v·m` with `k = reception_damping`
     (6.0 /s) — speed decays smoothly, fast balls over several ticks, slow
     balls gently. Force capped at `reception_max_force` (26 N) so an
     8 m/s arrival is tamed, not stopped dead in one tick.
   - Small pull toward the player's feet (`reception_pull` 2.5 N, planar,
     mass-scaled like the damping so both scale together) so touches end
     *at* the player instead of a metre to the side.
   - `ball.sleeping = false` before `apply_force` (forces don't wake).
3. **Completion**: planar speed < `reception_complete_speed` (1.2 m/s) →
   RECEIVING ends, `ball_received(speed)` fires.
4. **Escape hatch**: if the ball leaves `reception_escape_distance`
   (2.0 m planar), reception cancels silently (a hard bounce off a wall,
   for instance).

## Guarantees

- Works for fast and slow arrivals, front and side — it is a force field,
  not a scripted catch.
- Collision behaviour of the ball is untouched; the player body still
  blocks/deflects physically (Phase 3 contract).
- Kicking while receiving cancels reception first (`_after_kick`).

## Tuning knobs (`BallActionConfig` → Reception group)

| Knob | Default | Meaning |
|---|---|---|
| `reception_trigger_speed` | 2.0 m/s | Incoming speed that triggers reception |
| `reception_complete_speed` | 1.2 m/s | Speed under which the touch is done |
| `reception_damping` | 6.0 /s | Exponential bleed rate |
| `reception_pull` | 2.5 N | Feet-ward pull (mass-scaled) |
| `reception_max_force` | 26 N | Total force cap |
| `reception_distance` | 1.4 m | Engagement range |
| `reception_escape_distance` | 2.0 m | Radius at which an in-progress reception is dropped |

## Validation coverage

`tests/phase4_validation.tscn` asserts: an 8 m/s ball sent at the player
enters RECEIVING automatically **at range** (> 0.9 m from the player, i.e.
before the ball reaches the body — the trap, not a bounce off the player),
`ball_received` fires under the completion speed, the ball ends near the
player (< 1.6 m) and under control (< 1.5 m/s), with no teleport (max
per-tick step < 0.35 m). A ball moving *away* from the player never enters
RECEIVING, and neither does a ball carried away by the dribble.

## Notes for Phase 5+

- `ball_received(speed)` is the clean "possession moment" hook for AI
  transitions and pass-completion statistics.
- A deliberate-touch mechanic (trap direction, first touch into space) can
  reuse the same damping force with a directional bias later.
