# KING FOOTBALL — Phase 3 Handoff (Ball Physics System)

Phase 2 (player controller) is complete and validated headless
(`tests/phase2_validation.gd`) with Phase 1 still at 49/49.

## What now exists and must be preserved

- **Player** (`scenes/player/player.tscn`, `scripts/player/player_controller.gd`):
  reusable CharacterBody3D, feet-origin, logical forward −Z.
  - States: `movement_state` ∈ {IDLE, MOVING, SPRINTING}; signals
    `movement_state_changed` / `speed_changed` / `facing_direction_changed` are
    the settle-in points for animation (later phase) and gameplay glue.
  - Config lives in `resources/configurations/player_config.tres`
    (`PlayerConfig`); camera-relative movement is on by default and needs no
    camera wiring thanks to the viewport fallback.
- **Camera**: `GameCamera` follows `follow_target`; in the Phase 2 test scene it
  is wired to the player. Nothing about the controller hard-links a camera.
- **Input**: consumed actions → `move_*`, `sprint`. Untouched and ready →
  `pass`, `shoot`, `lob_pass`, `dribble`, `tackle`, `switch_player`, `pause`.
- **Pitch conventions (from Phase 1, still authoritative):** centre (0,0,0),
  length along Z, goals at z = ±52.5, grass top at y = 0, collision plate top at
  y = −0.03. Ground StaticBody3D is `Pitch/GroundCollision`.

## Suggested Phase 3 work order (Ball Physics)

1. `scripts/ball/ball_config.gd` (Resource) + `scenes/ball/ball.tscn`:
   RigidBody3D + SphereShape3D (fIFA-size ≈ r 0.11), default layer/mask so it
   collides with the pitch plate, goals, crates **and the player capsule**.
2. Kick goodness later can iterate on `BallConfig`; keep config-resource
   pattern consistent with `CameraConfig` / `PlayerConfig`.
3. Kick interface placeholder (Phase 3 scope: momentum only, no dribbling AI):
   player side exposes nothing yet — implement an `apply_central_impulse`
   wrapper on the ball script; do not wire gameplay actions into it.
4. Integration points confirmed: pitch ground body exists; player capsule
   (r=0.3, h=1.86) can push the ball — decide bounce vs. absorb there.
5. Validation: add `tests/phase3_validation.tscn` **beside** phase1/phase2
   suites — never edit earlier suites (they are the regression guards).

## Rules carried over

- Do not touch `scenes/stadium/stadium_prototype.tscn` visuals; the TestTarget
  orb may only be removed once real matches own the camera.
- Arabic-locale RTL quirk: every new English UI control gets
  `layout_direction = 2` (ARCHITECTURE.md §5).
- Godot 4.7.2 portable at `C:\tools\godot\Godot_v4.7.2-stable_win64.exe`.
- Keep `docs/` updated per phase (audit → report → handoff).
