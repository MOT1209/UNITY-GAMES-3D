# Phase 3 Report — Ball Physics System

**Status: COMPLETE** — validated headlessly, all suites green.

## Scope (per `المرحلة الثالثه.txt`)

A reusable, physically simulated football ball plus the interaction layer
Phase 4 needs — nothing more (no dribbling, passing, possession, AI).

## Delivered

| File | Role |
|---|---|
| `scripts/ball/ball_controller.gd` | `RigidBody3D` behaviour, kick/impulse/force APIs, reset/stop, queries, `_integrate_forces` clamp + settle ramp |
| `scripts/ball/ball_config.gd` (+ `.tres`) | Inspector-tunable physics resource |
| `scripts/ball/ball_visual.gd` | procedural paned ball texture (equirect ImageTexture) |
| `scripts/ball/ball_debug.gd` | dev-only velocity arrow overlay |
| `scripts/ball/ball_proximity_detector.gd` | detection/interaction layer + signals + dev rings |
| `scenes/ball/football_ball.tscn` | reusable ball scene |
| `scenes/development/ball_physics_test.tscn` + script | interactive test scene (pitch + player + detector + HUD + obstacles, dev keys 1/2/3/4/R/T/B) |
| `tests/phase3_validation.tscn` | headless validation suite (101 checks) |

Design details: `BALL_PHYSICS.md`, `BALL_INTERACTION.md`.

## Validation results

```
=== Validation summary: 101 passed, 0 failed ===      # phase3 (exit 0)
=== Validation summary: 49 passed, 0 failed ===       # phase1 regression
=== Validation summary: 57 passed, 0 failed ===       # phase2 regression
```

Coverage highlights:

- **Structure** — script/scene/resource loads, sphere shape r=0.11, mass
  0.43 kg, layers (ball=4 / mask=5), CCD on, physics material, damping,
  procedural texture applied, BallDebug node.
- **Gravity/bounce** — falls from 5 m, rests at centre = radius, never
  penetrates ground; apexes ≈ h₀·bounce² (≈1.5 m first apex after a 5 m
  drop), energy decays ≥10% per bounce, stable rest.
- **Rolling/friction** — 10 m/s kick carries momentum (≈9.5 m/s at 0.5 s),
  decays smoothly (4.0 m/s at 1.5 s), rolls >6 m in 1.5 s, stops in ≤15 s
  (measured ≈8 s / ≈19 m), stable ground contact; 0.6 m/s kick settles in
  <0.3 s via the ramp and never creeps again.
- **Kick API** — planar direction honoured, power honoured as Δv, `kicked`
  emitted, lift applied vertically, stacked kicks clamp at `max_ball_speed`.
- **Impulse/force** — inherited `apply_impulse()` Δv = impulse/mass;
  inherited `apply_force()` accelerates under a re-applied-per-tick push.
- **Reset/stop** — instant stop, stays stopped + supported, explicit and
  default resets land/settle correctly, `ball_reset` emitted per call.
- **Player interaction** — 8 m/s ball never overlaps the capsule
  (min distance > 0.28 m), blocked/deflected (no pass-through), player
  pushing moves the ball physically, player movement states intact.
- **CCD** — no tunnelling through 1 m wall at 22 m/s, no floor tunnel on a
  10 m drop.
- **Detector** — far ball invisible, detection on entry with correct
  ball/distance/direction, interaction window on/off (incl. airborne gate),
  `ball_lost` exactly once on exit, queries cleared.
- **Debug** — overlay off by default, propagates enable, visible + drawn
  while moving, hides again; detector rings drawable.
- **Integration** — Phase 1 pitch still builds collision, Phase 2 player
  still moves beside the ball, ball reacts on the real pitch, camera tracks;
  test scene structure (pitch, ball, detector, camera, HUD, obstacles).

## Issues fixed during validation

1. `ImmediateMesh.surface_add_color()` does not exist in 4.7 → per-surface
   unshaded materials in `ball_debug.gd` + ring overlay (also fixed a missing
   `surface_end()` between back-to-back surfaces).
2. Jolt only populates `get_contact_count()` with `contact_monitor = true` →
   the settle ramp was silently dead; enabled with `max_contacts_reported = 8`.
3. Tuning rebalanced for the measured decay profile: friction 0.75 → 0.45,
   linear damping 0.28 → 0.15, angular damping 1.2 → 0.5, settle threshold
   0.3 → 0.45 m/s (too much sliding friction made the ball brake like a
   handbrake; the old tail crept for ~9 s).
4. Detection radius made planar — an airborne ball was outside the 3D radius
   and flickered `ball_lost`/`ball_detected` per bounce.
5. Suite-side corrections to match engine semantics: bounce tracker no longer
   counts the initial drop as a bounce; force test re-applies `apply_force()`
   per tick (Godot 4 forces are one-step); reset test waits 2 s (fall from
   y=3 + bounces); kick power measured at 3 ticks with a decay-aware bound.

## Launching the test scene

```text
godot --path . res://scenes/development/ball_physics_test.tscn
# or open the scene in the Godot editor and press F6.
```

Controls: `WASD`/arrows move · `Shift` sprint · `V` camera · `1/2/3/4` kick
(soft / driven / lob / power) · `R` ball to centre · `B` drop from 6 m ·
`T` full reset · `Esc` menu. The ball test also has a scripted capture:
`godot --path . res://tests/screenshot_runner.tscn -- ball` (output:
`assets/placeholders/validation/phase3_ball_test.png`).

## Known limitations (accepted for Phase 3)

- Player body still on layer 1, so ball–player filtering is purely physical;
  Phase 4 may refine layers.
- `apply_impulse()`/`apply_force()` never wake a sleeping ball (engine
  behaviour) — documented; gameplay uses `apply_kick()`.
- Ball texture is procedural and stylized (12 pentagons + seams), not a
  real product texture.
- No audio hooks yet (Phase 6 per plan).
