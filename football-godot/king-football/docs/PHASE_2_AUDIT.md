# KING FOOTBALL — Phase 2 Audit (mandatory pre-implementation check)

Audited: Phase 1 deliverables before starting the Player Controller work.
Verified by: reading every Phase 1 file **and** re-running the Phase 1 validation
suite headless:

```
C:\tools\godot\Godot_v4.7.2-stable_win64.exe --headless --path . res://tests/phase1_validation.tscn
Result: Validation summary: 49 passed, 0 failed
```

## Reviewed items

| Item | Path | Status |
|---|---|---|
| Project settings / InputMap | `project.godot` | ✅ 13 actions, keyboard + gamepad, deadzones 0.2 (move) / 0.5 (buttons) |
| Godot version pin | `config/features` | ✅ 4.7, GL Compatibility + Jolt Physics (not downgraded) |
| Boot scene | `scenes/main/main.tscn` → main menu | ✅ works, untouched by Phase 2 |
| Stadium | `scenes/stadium/stadium_prototype.tscn` | ✅ works with TestTarget orb + camera |
| Pitch | `scenes/environment/football_pitch.tscn` + `scripts/environment/football_pitch.gd` | ✅ procedural 105×68 m, ground StaticBody3D present (top face at y = −0.03) |
| Goals | `scenes/environment/goal.tscn` | ✅ posts/crossbar/nets + collision, at z = ±52.5 |
| Camera | `scripts/camera/game_camera.gd`, `scenes/camera/game_camera.tscn`, `resources/configurations/game_camera_config.tres` | ✅ BROADCAST + FOLLOW modes, `set_follow_target()` interface ready for the player |
| Camera config | `CameraConfig` resource pattern | ✅ Phase 2 mirrors this pattern with a `PlayerConfig` resource |
| InputMap actions for Phase 2 | `move_forward/backward/left/right`, `sprint` | ✅ exist with keyboard + gamepad bindings — nothing to add |
| Naming / conventions | class_name + Resource config + procedural builders | ✅ Phase 2 follows the same rules |

## Notes that affect Phase 2 implementation

1. **Camera-relative movement**: `GameCamera` is reusable and exposes the mode/target
   interface; the controller itself will read the *active viewport camera*
   (`get_viewport().get_camera_3d()`) — no changes to `game_camera.gd` required.
2. **Ground height quirk**: the pitch collision plate's top face sits at y = −0.03,
   3 cm below the visual grass top (y = 0). The player's feet-real origin will rest
   3 cm below the visual surface. Negligible visually, documented as a known note —
   the Phase 1 pitch is *not* modified (do not rewrite working systems).
3. **RTL quirk**: every new English UI label must set `layout_direction = 2`
   explicitly (see ARCHITECTURE.md §5) — applied to all Phase 2 HUD labels.
4. **Test target orb**: `TestTarget` in the stadium remains Phase 1's follow-camera
   test object; Phase 2 does *not* remove it (keeps 49/49 guard green). The player
   integration happens in the dedicated Phase 2 test scene, where the follow camera
   targets the real player.
5. **No blockers found.** No Phase 1 dependencies needed fixing.

## Decision

Proceed directly to implementation with Phase 1 architecture, InputMap, camera and
naming conventions reused as-is.
