# KING FOOTBALL — Architecture (Phase 1)

Godot 4.7.2 · renderer: GL Compatibility (+ Jolt Physics 3D) · window 1280×720 with
`canvas_items` stretch, `expand` aspect.

## Folder layout

```text
scenes/
  main/main.tscn                 boot scene (project main scene) → instantiates main menu
  stadium/stadium_prototype.tscn full prototype: environment + goals + stands + camera + HUD
  environment/football_pitch.tscn  procedural pitch (script-built)
  environment/goal.tscn          one goal (posts ×2, crossbar, 3 net boxes, 4 collision shapes)
  camera/game_camera.tscn        reusable two-mode Camera3D
  player/player.tscn             reusable football player (CharacterBody3D, Phase 2)
  development/player_controller_test.tscn  Phase 2 dedicated test scene (pitch+player+camera+crates)
ui/
  main_menu/main_menu.tscn       menu (Start Match → stadium; Settings disabled guard)
scripts/
  core/game_manager.gd           autoload singleton (global name `GameManager`)
  camera/camera_config.gd        class_name CameraConfig (Resource)
  camera/game_camera.gd          class_name GameCamera (Camera3D)
  player/player_config.gd        class_name PlayerConfig (Resource)
  player/player_controller.gd    class_name PlayerController (CharacterBody3D)
  environment/football_pitch.gd  procedural pitch builder
  environment/stadium_stands.gd  grandstands + floodlights
  environment/stadium_prototype.gd  stadium scene glue + HUD
  development/player_controller_test.gd  test-scene glue (crates, HUD, camera hint)
  debug/test_target.gd           orbiting red orb only used to validate the follow camera
  ui/main_menu.gd, ui/menu_button.gd
resources/configurations/
  game_camera_config.tres        CameraConfig resource instance (project defaults)
  player_config.tres             PlayerConfig resource instance (project defaults)
tests/
  phase1_validation.gd/.tscn     headless validation suite (49 checks)
  phase2_validation.gd/.tscn     headless player-controller suite (57 checks)
  screenshot_runner.gd/.tscn     scripted visual captures (menu / stadium / stadium_follow)
  mirror_probe.gd/.tscn          regression probe for the RTL/UI-direction issue (see below)
docs/                            this documentation set
```

Canonical rule vs. legacy content: repo-root `main.tscn` is an untouched scratch
file retained as-is; the live boot scene is `scenes/main/main.tscn`.

## Core design decisions

## 1) Scene boot & state

`scenes/main/main.tscn` (main scene) is a thin wrapper that shows the main menu.
`GameManager` (autoload, no `class_name` — an identical name would collide with the
singleton and fail to compile on Godot 4.7) owns a state enum `BOOT → MAIN_MENU → IN_MATCH`
and emits `state_changed`. Menu buttons call it: `start_match()` swaps to
`scenes/stadium/stadium_prototype.tscn`; Esc from the stadium goes back to the menu.

## 2) Procedural stadium

The pitch is generated in code (`football_pitch.gd`), not modelled: a grass surface with
mow stripes (48 dark/light bands along the pitch length axis, Z), thin box meshes for
lines on the 105 × 68 m coordinate grid (length = Z, width = X, centre = origin),
ring segments for the centre circle and penalty arcs, disc meshes for spots, plus a
StaticBody3D collision plate. Benefits: zero asset imports, deterministic layout, easy
tweaks; costs: geometry is prototype-quality by design.

Goals are instances of `goal.tscn` placed at z = ±52.5 m; GoalB is rotated π yaw so its
mouth faces the pitch. Stands/floodlights are built by `stadium_stands.gd` on 4 sides with
rows correctly receding away from the pitch.

## 3) Camera system (reusable by design)

`GameCamera` embeds no gameplay logic and is configured only through a `CameraConfig`
resource (`broadcast_look_target`, `broadcast_position_offset`, `broadcast_fov`,
`follow_fov/distance/height/speed`…). Two modes:

- `BROADCAST` — static elevated sideline view (offset (56, 38, 0), FOV 40 — chosen so the
  camera sits above the stand roofs).
- `FOLLOW` — exponential-damped chase of `follow_target` (FOV 65, distance 16 m, height 9 m).

Interface: `switch_mode()` / `set_mode()` / `set_follow_target()`, signal `mode_changed`.
The stadium wires `InputEvent` action `camera_toggle` (V / gamepad Back) to it.
`scripts/debug/test_target.gd` exists **only** to give the follow camera a moving target
until real players arrive in Phase 2.

## 4) Input

All 13 actions are defined in `project.godot` with keyboard **and** gamepad bindings
(see docs/CONTROLS.md). Phase 2 consumes the movement + sprint actions in `player_controller.gd`;
camera toggle / pause stay scene-level; ball actions are reserved for Phase 3.

## 5) Player controller (Phase 2) — overview

The player is a reusable `CharacterBody3D` scene with its **origin at the
feet** and the logical forward at **−Z**. The controller reads only InputMap
actions (`move_*`, `sprint`), converts input through the *active viewport
camera's flattened basis* (camera-relative, with a world-axis fallback), and
applies horizontal acceleration/deceleration (`move_toward`) separately from
gravity. Sprint raises the max speed while held (no stamina yet). A small
state machine (`IDLE/MOVING/SPRINTING`) plus throttled signals
(`movement_state_changed` / `speed_changed` / `facing_direction_changed`)
provide the animation integration surface. All tuning lives in the
`PlayerConfig` resource (`resources/configurations/player_config.tres`),
mirroring the camera pattern. Full details: docs/PLAYER_CONTROLLER.md.
The dedicated test scene is
`scenes/development/player_controller_test.tscn`; it wires the follow camera
to the real player and provides collision-test crates + state/speed HUD.

## 6) UI directionality and localization (superseded the Phase-1 "force LTR" workaround)

The game is multilingual from its foundation: **Arabic (RTL), German, English**. The central autoload
`Loc` (`scripts/core/localization.gd`) owns the language, the translation tables
(`translations/*.csv`), the font stack and the **layout direction of the root window**
(`Window.set_layout_direction`, RTL for Arabic). Controls inherit it, so containers mirror automatically;
elements that must not mirror (football pitch diagram `PitchDiagram`, scoreboard HUD, language picker) are
forced LTR explicitly. The old workaround of forcing `layout_direction = 2` on the main menu root was removed
(it would have kept Arabic LTR). The Phase-1 prototype HUD labels in `scenes/stadium/stadium_prototype.tscn`
and the developer test scenes are still forced LTR and are not localized. Full details:
[LOCALIZATION_SYSTEM.md](LOCALIZATION_SYSTEM.md), [ARABIC_RTL_SUPPORT.md](ARABIC_RTL_SUPPORT.md).
`tests/mirror_probe.tscn` is the original Phase-1 probe.

## 7) Management and match layers (added after Phase 5)

| Layer | Key scripts | Notes |
|---|---|---|
| Data | `scripts/data/*`, `scripts/core/team_database.gd` (`TeamDatabase`, autoload `TeamDB`), `save_manager.gd` | JSON saves use **full float precision**; ints are restored after JSON |
| Career | `systems/career/career_state.gd`, `systems/competitions/*`, `systems/transfers/*` | `advance_week` runs wages, loans **and** one academy training + scouting week |
| Academy | `systems/academy/*`, `training/*`, `scouting/*`, `promotion/*` | calendar-driven (`sync_to_calendar`, idempotent); `Academy.over_age_ids/keep_extended` |
| Match | `systems/match/match_manager.gd` (+ `team_ai`, `player_ai`, `manager_ai`, `pitch_space`, `match_state`) | `frame_side()` flips ends at half-time; keeper = `scripts/teams/team_goalkeeper.gd`; kits via `TeamKit.from_dict` |
| UI | `scripts/ui/*` (hub, `UIKit`, screens, `LanguagePicker`, `PitchDiagram`) | every text through `Loc`; open screens rebuild on `language_changed` |
| Tests | `tests/run_all.sh`, `phase*_validation`, `phaseT*_validation`, `phase6_integration_validation`, `localization_validation` | `localization_visual` (windowed screenshots) is run manually |

## Rendering notes

- `gl_compatibility` was chosen for maximum hardware reach (this machine's Intel UHD 605
  renders fine at 720p). The `d3d12` rendering-device driver entry in `project.godot`
  only applies to RenderingDevice-based methods and is inert under GL Compatibility.
- Shadows, procedural sky and light energy configured inside `stadium_prototype.tscn`.


## Phase 7 additions

`MatchState` owns `MatchStats`; `MatchManager` wires gameplay signals into it, builds a `MatchReport` in `_finish()` (published as `GameManager.last_match_report` before the finish signals) and shows `MatchResultsView`. `PauseMenu` drives `pause_match/resume_match/restart_match/quit_match`; `MatchSave` persists a running match (`user://saves/match.json`). `ErrorText` maps system error strings to translation keys. See PHASE7_IMPLEMENTATION_REPORT.md.
