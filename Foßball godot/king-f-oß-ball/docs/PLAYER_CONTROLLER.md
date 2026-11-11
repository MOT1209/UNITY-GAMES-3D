# KING FOOTBALL — Player Controller (Phase 2)

## Files

- `scripts/player/player_controller.gd` — `class_name PlayerController`, extends `CharacterBody3D`
- `scripts/player/player_config.gd` — `class_name PlayerConfig` Resource
- `scripts/player/player_character_visual.gd` — drives the character model's animations from controller signals
- `resources/configurations/player_config.tres` — project defaults instance
- `scenes/player/player.tscn` — reusable player scene
- `assets/models/characters/player.glb` — the real character model (Idle/Walk/Run/Kick)
- `scenes/development/player_controller_test.tscn` + `scripts/development/player_controller_test.gd` — test environment
- `tests/phase2_validation.gd/.tscn` — headless validation suite

## Scene hierarchy

```text
Player (CharacterBody3D, origin at the FEET)
├── CollisionShape3D        capsule r=0.30, h=1.86, centered at y=0.93 → bottom exactly at origin
└── VisualRoot (Node3D)     carries PlayerCharacterVisual (animation driver)
    └── Character           instance of assets/models/characters/player.glb
```

Conventions:

- **Root origin = feet.** The GLB's origin is at the feet too (bottom_y ≈ 0),
  so the `Character` node needs no offset inside `VisualRoot`.
- The character's logical forward is **−Z** (Godot convention). The root itself
  rotates toward movement; the model already faces −Z, so no correction is
  baked into either the controller or the scene.

## Character model (GLB)

`player.glb` (from the KingFootball_Characters pack) replaced the Phase 2
placeholder visuals (Body/Head/FacingMarker/Legs). Measured: 1.81 m tall,
0.78 m wide — matches the 1.86 m collision capsule. Scale 1 unit = 1 m;
Animations: `Idle`, `Walk`, `Run`, `Kick`.

`PlayerCharacterVisual` (attached to `VisualRoot`) listens to the controller's
signals — the controller itself stays visual-agnostic:

| Controller signal/state | Animation |
|---|---|
| `IDLE` | `Idle` |
| `MOVING` (speed ≤ 3.2 m/s) | `Walk` |
| `MOVING` (speed > 3.2 m/s) | `Run` |
| `SPRINTING` | `Run` |

- Clips cross-fade over `anim_fade` = 0.18 s (`walk_max_speed` and the fade
  are Inspector-tunable on `VisualRoot`).
- `Kick` is reserved for Phase 4: the gameplay layer calls
  `VisualRoot.play_kick()` when a kick action fires; locomotion resumes on the
  next state/speed change.

The rest of the pack is already imported in
`assets/models/characters/` for later phases (all face −Z, origin at feet):
`referee.glb` (Idle/Walk/Run/Whistle/ShowCard/SprayMark),
`assistant_referee.glb` (Idle/Walk/Run/FlagUp/FlagSide/FlagDiagonal), and the
props `whistle`, `card_yellow`, `card_red`, `spray_can`, `flag`. The pack's
`ball.glb` (Ø 0.22 m, origin at centre) is a documented alternative to the
procedural Phase 3 ball; the procedural ball stays the default because the
phase-3 suite validates against it.

## Controller architecture

`_physics_process` pipeline (per fixed tick):

1. **Input** — `Input.get_vector("move_left","move_right","move_forward","move_backward")`
   (InputMap only; digital keyboards come normalized, stick magnitude is preserved).
2. **Direction conversion** — `_input_to_world_dir(input)`:
   - `World` reference → forward is −Z, right is +X.
   - `CameraRelative` (default) → forward/right follow the active viewport
     camera's basis flattened to the ground plane (camera pitch ignored, so no
     vertical velocity is introduced). A vertical camera or missing camera
     falls back to the world axes.
3. **Horizontal velocity** — moved toward `dir * max_speed` with
   `move_toward` (acceleration while steering, deceleration on release).
   This keeps diagonal-by-analog speeds ≤ max speed and makes direction
   changes smooth.
4. **Gravity** — vertical component handled separately; while grounded a tiny
   downward bias keeps floor detection stable, airborne speed is clamped to
   `max_fall_speed`.
5. **`move_and_slide()`** with `floor_snap_length` / `floor_max_angle` from
   the config.
6. **Facing** — yaw pulled toward `atan2(-dir.x, -dir.z)` with exponential
   damping (`rotation_speed`); the last facing is kept while idle.
7. **States / signals** — see below.

## States & signals

`enum MovementState { IDLE, MOVING, SPRINTING }` (player var `movement_state`,
`get_state_name()` for HUD/logs).

| Signal | Emitted when |
|---|---|
| `movement_state_changed(state)` | state transitions only |
| `speed_changed(speed)` | speed moved by ≥ 0.25 m/s since the last emission |
| `facing_direction_changed(dir)` | the directional intent turns by ≥ ~15° |

These are consumed live by `PlayerCharacterVisual` (see the character-model
section above) and remain open hooks for a future `AnimationTree` blend.

## Sprint

`Input.is_action_pressed("sprint")` + sprint_enabled in config → max speed becomes
`sprint_speed`. No stamina logic (explicitly postponed). Sprint while standing
still stays IDLE.

## Configuration (Inspector-tunable, via PlayerConfig resource)

| Parameter | Default | Meaning |
|---|---|---|
| `normal_speed` | 5.5 m/s | run speed |
| `sprint_speed` | 8.0 m/s | sprint max |
| `acceleration` / `deceleration` | 18 / 22 | gain in m/s per second |
| `rotation_speed` | 10.0 | turn damping strength |
| `movement_reference` | CAMERA_RELATIVE | movement basis |
| `gravity` / `max_fall_speed` | 18 / 40 | gameplay gravity |
| `grounded_downward_bias` | 0.5 | stable-ground contact bias |
| `floor_snap_length` / `floor_max_angle_degrees` | 1.0 / 45° | floor contact |

## Input dependencies (InputMap actions only)

Consumed now: `move_forward`, `move_backward`, `move_left`, `move_right`, `sprint`.
Guaranteed available for later phases (not read here): `pass`, `shoot`,
`lob_pass`, `dribble`, `tackle`, `switch_player`, `pause`.

## Testing

- Headless suite: `godot --headless --path . res://tests/phase2_validation.tscn`
  (assets, scene structure, directions incl. world fallback, diagonal
  normalization, sprint up/down, deceleration→IDLE, signals, analog magnitude,
  camera-relative + fallback, wall collision, test-scene integration).
- Manual: launch `scenes/development/player_controller_test.tscn`
  (`godot --path . res://scenes/development/player_controller_test.tscn` or
  open and press F6). Walk the pitch, sprint, steer into the crates, toggle
  camera modes with **V** and confirm control feels right in both.

## Known notes

- The Phase 1 pitch collision plate's top face sits 3 cm below the visual grass:
  the player effectively sinks ~3 cm into the lawn surface. Invisible in play;
  fix belongs to the pitch asset, not the controller (Phase 1 left untouched).
- The capsule (r=0.3) cannot walk between the goalposts — the ball-centric
  movement of later phases should treat the goal area specially anyway.
