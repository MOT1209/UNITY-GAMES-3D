# Ball Interaction (Phase 3)

How the player "sees" the ball and how gameplay actions reach it. This layer
is detection + force entry only — **no possession, no attachment, no
teleporting**. Phase 4 (dribbling / passing / shooting) reads exactly these
signals and calls exactly these methods.

## BallProximityDetector (scripts/ball/ball_proximity_detector.gd)

A `Node3D` you drop under any host (the ball test scene mounts it on the
player at `Player/BallDetector`). It samples the host's origin each physics
tick and scans `get_tree().get_nodes_in_group("football_ball")` — no physics
area needed, so it works with any number of balls.

### Tunables

| Property | Default | Meaning |
|---|---|---|
| `ball_group` | `football_ball` | group scanned |
| `detection_radius` | 2.5 m | planar radius in which a ball is "nearby" |
| `interaction_distance` | 0.9 m | planar distance for a real interaction window |
| `max_interaction_height` | 1.0 m | vertical offset gate (rejects phantom mid-air traps) |
| `show_rings` | off | dev-only ring overlay (ImmediateMesh, test scene only) |

### Signals

- `ball_detected(ball: Node3D)` — a ball entered the radius, or tracking
  switched to a different (closer) ball.
- `ball_lost` — the tracked ball left the radius or was freed.
- `ball_interaction_available(available: bool)` — emitted whenever the
  "clean interaction window" flips on/off (distance + height + ball present).

### Queries (Phase 4 API surface)

- `get_current_ball() -> Node3D` — nearest tracked ball or null.
- `is_ball_nearby() -> bool`
- `is_interaction_available() -> bool` — the single gameplay gate
  ("can trap / kick / shoot?").
- `get_distance_to_ball() -> float` (0 when none).
- `get_direction_to_ball() -> Vector3` — normalized planar direction to the
  ball (ZERO when none; useful for auto-aiming a pass).

### Design notes

- **Planar detection on purpose.** The radius check ignores height; only the
  interaction window applies `max_interaction_height`. A lobbed ball stays
  "detected" through its arc instead of flickering
  `ball_lost` → `ball_detected` every bounce (a real bug caught by validation).
- The interaction ring doubles as the Phase 4 trap range — keep both numbers
  in sync when tuning.
- Frees are handled: a tracked ball removed mid-frame emits `ball_lost` once.

## Ball action entry point

All ball actions go through `BallController.apply_kick(direction, power,
lift, spin)` — see `BALL_PHYSICS.md`. It flattens the direction, applies the
speed ceiling to the *result*, wakes sleeping balls, and emits `kicked(speed)`.

```gdscript
# Phase 4 example shape (not implemented yet):
if detector.is_interaction_available():
    var ball: BallController = detector.get_current_ball() as BallController
    ball.apply_kick(detector.get_direction_to_ball(), 8.0, 1.0)
```

For sustained pushes (dribbling) use the inherited `apply_force()` every
physics tick — it is consumed after one step. For raw impulses use the
inherited `apply_impulse()`; both must wake a sleeping ball first
(`apply_kick()` is the wake-safe alternative).

## Test scene (dev)

`scenes/development/ball_physics_test.tscn` — real pitch + player (with
detector + rings) + ball + HUD + obstacles. Dev-only keys (raw keys, no
InputMap actions, so they cannot collide with player controls):

| Key | Action |
|---|---|
| `1` | touch pass (6 m/s) toward the ball |
| `2` | driven kick (14 m/s, 2 lift) |
| `3` | lob (7 m/s, 9 lift) |
| `4` | power shot (24 m/s, 0.5 lift) |
| `R` | ball back to centre |
| `T` | full reset (ball + player) |
| `B` | drop the ball from 6 m (bounce demo) |

HUD shows ball status/distance/interaction state live. Kicks are aimed using
the detector's planar direction when available, otherwise forward.
