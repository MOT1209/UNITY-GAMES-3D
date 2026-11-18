# KING FOOTBALL — Phase 3 Audit (Ball Physics System)

Date: 2026-11-10 · Auditor: Phase 3 implementation agent · Scope: pre-implementation
inspection of the existing project before adding the ball physics system.

## 1. Inspected artifacts

| Artifact | Result |
| --- | --- |
| `project.godot` | Godot 4.7, GL Compatibility, **physics engine = Jolt Physics**, autoload `GameManager`, 13 InputMap actions (all with keyboard + gamepad). No project-level gravity overrides. |
| `scenes/main/main.tscn`, `ui/main_menu/*` | Phase 1 menu flow intact, untouched. |
| `scenes/environment/football_pitch.tscn` + `scripts/environment/football_pitch.gd` | Procedural pitch (105 × 68 m). Ground collision plate (`Pitch/GroundCollision`, StaticBody3D) top face at **y = −0.03**, layer 1. Grass visual surface top at y = 0. Ready for ball physics as designed in Phase 1. |
| `scenes/environment/goal.tscn` | Static body with posts/crossbar/back wall, default layer 1 — ball must collide via mask. |
| `scenes/player/player.tscn` + `player_controller.gd` | Phase 2 controller: CharacterBody3D, capsule r 0.3 h 1.86, feet-origin. States IDLE/MOVING/SPRINTING + signals. Default collision layer 1, mask 1. Config resource assigned. |
| `scripts/player/player_config.gd` + `player_config.tres` | Resource pattern confirmed (to mirror for `BallConfig`). |
| `scenes/camera/game_camera.tscn` + `game_camera.gd` | Two modes (BROADCAST/FOLLOW), `follow_target` export, signal `mode_changed`. Reusable as-is. |
| `scenes/development/player_controller_test.tscn` + script | Test scene pattern: pitch + player + camera + HUD labels (`layout_direction = 2` per ARCHITECTURE §5) + procedural crates. To be mirrored for the ball test scene. |
| `tests/phase1_validation.gd/tscn`, `tests/phase2_validation.gd/tscn` | Headless suites with `[PASS]/[FAIL]` + summary; must not be edited (regression guards). |
| `docs/` | Phase 1/2 audits, reports, handoff, controls, architecture all present and consistent. |
| Input actions `pass/shoot/lob_pass/dribble/tackle/switch_player` | Mapped but intentionally unused — reserved for Phase 4+. Phase 3 dev-test controls therefore use **raw physical keys** (digits/R/T/B) not present in the InputMap, so nothing dev-only leaks into gameplay input. |

## 2. Verified behavior (re-run of existing suites)

- `tests/phase1_validation.tscn` → 49/49 passed (headless).
- `tests/phase2_validation.tscn` → 57/57 passed (headless).

The Player Controller is considered **working** before ball integration.

## 3. Gaps relevant to Phase 3

1. No ball scene, scripts, or collision layers for a dynamic body anywhere in the project.
2. Ground collision plate top is at y = −0.03 while grass visual sits at y = 0 → a ball
   resting on the plate sinks ~3 cm into the grass visuals. Accepted (grass "grip" look,
   matches how the player rests at the same plate level). Documented in BALL_PHYSICS.md.
3. Player body still occupies collision layer 1 (shared with static world). For Phase 3
   this is sufficient: the ball's mask includes layer 1, so ball↔player collisions work.
   Layer refinement (e.g., dedicated PLAYER layer) is deferred to Phase 4 and flagged in
   the handoff document.
4. Project physics engine is **Jolt**; friction/bounce combine behavior differs slightly
   from the Godot builtin solver, so all ball parameters are Inspector-tunable and were
   validated headless on this engine.

## 4. Blockers

None. No existing functionality needs to be rewritten; Phase 1/2 assets are preserved.
`player.tscn` and the controller are **not modified** by Phase 3.

## 5. Integration decisions taken at audit time

- **Collision layer plan:** 1 = World/Static (existing, including player body for now),
  3 = Ball (`collision_layer = 4`, `collision_mask = 5` world + ball).
- **Ball physics body:** `RigidBody3D` + SphereShape3D r 0.11, mass 0.43, physics
  material (friction/bounce from `BallConfig`), speed clamp + settle decay inside
  `_integrate_forces()` (no per-frame impulses, no transform overwrites).
- **Continuous collision detection:** enabled on the ball — justified by real shot speeds
  (≈ up to 30 m/s ⇒ ~0.5 m per physics step > ball diameter); confirmed necessary by the
  headless tunneling test in `tests/phase3_validation.tscn`.
- **Ball proximity detector:** standalone reusable component
  (`scripts/ball/ball_proximity_detector.gd`), added as a child of the player only inside
  the test scene — `player.tscn` remains untouched.
- **Dev test controls:** digits 1–4 (kick presets), `R` reset ball, `T` reset ball+player,
  `B` drop ball from height — none collide with any existing gameplay action.
