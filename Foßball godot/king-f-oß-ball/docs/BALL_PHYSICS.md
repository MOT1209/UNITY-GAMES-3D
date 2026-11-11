# Ball Physics (Phase 3)

Architecture and tuning reference for the reusable football ball. Everything
here is validated headlessly by `tests/phase3_validation.tscn` (101 checks,
see `PHASE_3_REPORT.md`).

## Scene structure

```
football_ball.tscn
├── BallController      (RigidBody3D root, group "football_ball")
│   ├── CollisionShape3D  (SphereShape3D, r = 0.11 m)
│   ├── BallVisual        (MeshInstance3D, procedural paned texture)
│   └── BallDebug         (dev-only velocity overlay, hidden by default)
```

Physics and visuals are separated: `BallController` owns simulation only;
`BallVisual` (child `BallMesh` + generated `ImageTexture`) never affects it.
The visual never rotates with the solver jitter because it is a free child.

## Configuration — `BallConfig` (scripts/ball/ball_config.gd)

Project defaults live in `resources/configurations/ball_config.tres`; the
`.tres` stores no values, so `ball_config.gd` defaults are the single source of
truth. Every instance can point at its own copy via the `config` export.

| Property | Value | Why |
|---|---|---|
| `radius` | 0.11 m | FIFA size 5 |
| `mass` | 0.43 kg | regulation ball |
| `linear_damping` | 0.15 | low so passes carry; ground decel comes from friction + settle ramp |
| `angular_damping` | 0.5 | spin decay; rolling decel ≈ linear + angular damping via the friction coupling |
| `friction` | 0.45 | Jolt combines multiplicatively with the pitch (1.0) → sliding decel ≈ 0.45·g |
| `bounce` | 0.55 | vertical apex scales by bounce² per impact (validated: 5 m drop → ≈1.5 m first apex) |
| `max_ball_speed` | 30 m/s | realistic top speed + solver safety; clamped in `_integrate_forces` |
| `settle_speed` | 0.45 m/s | horizontal speed below which the settle ramp engages while grounded |
| `reset_height` | 0.5 m | default `reset_ball()` drop height onto the centre spot |
| `gravity_scale` | 1.0 | project gravity (9.8 m/s², Jolt) |
| `continuous_collision` | true | 30 m/s ≈ 0.5 m per step > ball diameter — prevents tunnelling (validated at 22 m/s) |

### Measured decay profile (headless probe, 10 m/s rolling kick)

```
t=0.83 s v=5.09   t=1.5 s v=4.03   t=3 s v=2.38
t=5 s v=1.18      stop at 7.98 s after 19.3 m
0.6 m/s kick → full stop in 17 ticks (0.28 s, settle ramp)
```

## Physics pipeline

Per-step work lives **only** in `_integrate_forces()` (no per-frame impulses,
no transform writes while simulating):

1. **Speed ceiling** — velocity clamped to `max_ball_speed` once per step.
2. **Rolling settle ramp** — while `get_contact_count() > 0` and planar speed
   < `settle_speed`, planar velocity is multiplied by 0.82 per step (→ ZERO
   below 0.02 m/s). This is what makes the ball stop *cleanly* instead of
   creeping for many seconds.

**Jolt caveat (important):** `PhysicsDirectBodyState3D.get_contact_count()`
only returns data when the body has `contact_monitor = true` (the ball sets it
in `_apply_config`, with `max_contacts_reported = 8`). Without it the ramp is
silently dead — this bit us during tuning.

## Angular motion

The ball rolls — rotation is *physical*, not scripted: ground friction spins
the body up until contact matches, impacts add rotation, and `angular_damping`
(0.5 1/s) decays airborne spin. Rolling deceleration therefore emerges from
the friction coupling between `angular_velocity` and linear speed
(ω ≈ v / r when fully rolling: 10 m/s → ≈90 rad/s, validated headlessly —
the phase-3 suite asserts real angular velocity and per-tick orientation
change while rolling). The visual mesh is a child of the `RigidBody3D`, so
the paned texture visibly reflects every rotation with zero extra code.

## Kick / integration APIs

- `apply_kick(direction, power, lift = 0, spin = ZERO)` — gameplay one-shot.
  Direction is flattened to planar (falls back to `-global_transform.basis.z`
  when vertical), `power` is planned planar Δv, `lift` is vertical m/s, `spin`
  is added to `angular_velocity`. The target speed is computed up-front so the
  ceiling applies to the *result*. Wakes a sleeping ball and emits `kicked`.
- `apply_impulse()` / `apply_force()` — used **inherited** from `RigidBody3D`.
  GDScript overrides of native methods are an error in Godot 4.7. Engine-level
  caveats (documented in the script):
  1. they do not wake a sleeping ball — wake it first or use `apply_kick()`;
  2. `apply_force()` is consumed after a single physics step — sustained pushes
     re-apply it every physics tick.
- `reset_ball(to_position = INF)` — freeze-cycle teleport (one static tick,
  never a raw transform write mid-simulation), clears all motion, emits
  `ball_reset`. Default: centre spot at `reset_height`.
- `stop_ball()` — zeroes velocity and sleeps the body; sleeping bodies ignore
  gravity, so the ball rests exactly where it is.

## Queries

- `get_ball_speed()` → m/s.
- `get_ball_direction()` → normalized 3D velocity, `Vector3.ZERO` under
  0.05 m/s (avoids jitter directions at rest).

## Collision layers

| Layer | Bit | Members |
|---|---|---|
| 1 — World/Static | 1 | pitch, goals, obstacles, **player body (unchanged from Phase 2)** |
| 3 — Ball | 4 | ball only |

Ball: `collision_layer = 4`, `collision_mask = 5` (World + Ball). Player still
lives entirely on layer 1, so Phase 1/2 behaviour is untouched; the ball is
physically blocked/deflected by the player capsule. Phase 4 may move the player
off layer 1 for ball-specific filtering — see `PHASE_4_HANDOFF.md`.

## CCD

`continuous_cd = true` is justified, not default-flipped: top shots reach
30 m/s ≈ 0.5 m per 60 Hz step, larger than the ball diameter (0.22 m).
Validated: no tunnelling through a 1 m wall at 22 m/s and on a 10 m drop.

## Debug overlay

`BallDebug` (child node, dev-only): draws a velocity arrow (length ∝ speed,
clamped) in world space — top-level so it does not spin with the ball — or a
rest "X" when stopped. ImmediateMesh carries no per-vertex colours in 4.7;
each coloured group is its own surface with its own unshaded material passed
to `surface_begin()`. Disabled by default; enabled via
`BallController.debug_enabled` or the Inspector.
