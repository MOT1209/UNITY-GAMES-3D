# KING FOOTBALL — Phase 1 Report

Godot **4.7.2 stable** (all validation executed with
`C:\tools\godot\Godot_v4.7.2-stable_win64.exe`, kept outside the repo).
Date of completion: 2026-11-10.

## 1. Scope reviewed

Executed the plan in `../المرحلة _الولا 1.txt` (Phase 1 only):
project structure, main scene, stadium prototype with full pitch markings and
two goals, reusable BROADCAST/FOLLOW camera, InputMap, basic UI, documentation,
mandatory CLI + visual validation.

## 2. What was implemented

| Area | Deliverable | Files |
|---|---|---|
| Project config | Godot 4.7, GL Compatibility + Jolt, 1280×720 canvas_items stretch, 13 InputMap actions, autoload | `project.godot` |
| Boot | Main scene → menu; GameManager state machine | `scenes/main/main.tscn`, `scripts/core/game_manager.gd` |
| Stadium | Procedural pitch 105×68 m, all markings (boundary, halfway, centre circle+spot, penalty areas, goal areas, penalty spots, corner arcs), mow stripes, collision | `scripts/environment/football_pitch.gd`, `scenes/environment/football_pitch.tscn` |
| Goals | 2 goals with posts, crossbar, nets, collision | `scenes/environment/goal.tscn` |
| Stands | Grandstands ×4 + floodlights, correct row orientation | `scripts/environment/stadium_stands.gd` |
| Camera | Reusable GameCamera: BROADCAST (offset (56,38,0), FOV 40) + DYNAMIC/FOLLOW (FOV 65, damped), `V` to toggle | `scripts/camera/game_camera.gd`, `camera_config.gd`, `resources/configurations/game_camera_config.tres` |
| Debug | Orbiting red follow-test orb | `scripts/debug/test_target.gd` |
| UI | Main menu (Start/Quit wired; Settings disabled), stadium HUD (title, camera mode label, hints) | `ui/main_menu/main_menu.tscn`, `scripts/ui/*.gd` |

## 3. Validation (all TESTED — no unverified claims)

### 3.1 Headless automated suite
`godot --headless --path . res://tests/phase1_validation.tscn`
→ **49 passed, 0 failed**, exit code 0 (re-verified after the final UI fix).
Covers: InputMap presence & bindings, script parsing, scene loading, camera
config application, broadcast positioning, damped follow behaviour and actual
follow movement, mode switching, UI wiring, GameManager transitions.

### 3.2 Visual validation (windowed captures, real renderer)
Scripted, deterministic (test orb pinned at world (0,0,14); verified against
`Camera3D.unproject_position` in true screen space):
- `assets/placeholders/validation/phase1_menu.png` — menu layout
- `assets/placeholders/validation/phase1_stadium.png` — broadcast view: pitch lines/stripes,
  stands, goals, HUD in designed positions
- `assets/placeholders/validation/phase1_stadium_follow.png` — follow camera centered
  on the orb with HUD label "Camera: Dynamic"
- `assets/placeholders/validation/mirror_probe.png` — UI-direction regression probe

### 3.3 Important bug found & fixed (RTL UI mirroring)
**Symptom:** on this machine every Label rendered horizontally mirrored
(left-designed text appeared right-anchored and vice versa).
**Root cause (proven by isolation, `tests/mirror_probe.tscn`):** the system locale is
`ar_SA`; Godot GUI controls default `layout_direction` to the application locale →
RTL → Godot mirror-flips horizontal alignment/label placement semantics.
The capture pipeline itself (`get_viewport().get_texture().get_image()`) was proven
NOT to be at fault (3D world and non-text Controls rendered at true coordinates).
**Fix:** explicit `layout_direction = 2` (Left-to-Right) on the menu scene root and on
each stadium HUD label. **Verified by recapturing all three views.**

## 4. Acceptance criteria status

| Criterion (plan) | Status |
|---|---|
| Project structure (scenes/scripts/resources/ui/docs/tests) | ✅ |
| Main scene boots into menu → stadium | ✅ TESTED (headless + capture; Start Match wiring covered by validation suite) |
| Full pitch markings + 2 goals, nets, stands, lighting, sky, shadows | ✅ built & visually verified |
| Reusable camera with BROADCAST + mode switch interface | ✅ TESTED (headless follow/switch checks + captures) |
| DYNAMIC/FOLLOW camera with damping | ✅ TESTED (headless: follows target, actually moves) |
| InputMap: 13 actions, keyboard + gamepad each | ✅ TESTED headless (presence & bindings) — no gameplay consumer yet (Phase 2) |
| Validation passes headless | ✅ 49/49, exit 0 |
| Documentation set | ✅ (this file, README, ARCHITECTURE, CONTROLS, AUDIT, HANDOFF) |

## 5. Known limitations / open visual polish

1. **Follow-view corners look very dark**: shadowed stand interiors produce near-black
   corners behind the stands. Character of the stylized scene and mathematically correct,
   but a filler DirectionalLight3D (energy ≈ 0.35, no shadows, azimuth opposite the sun)
   is recommended as optional polish. NOT implemented in Phase 1.
2. **Frame-rate dependent captures**: screenshots rely on vertical frames; stabilised by
   pinning the orb and fixed frame counts.
3. **`mirror_probe.tscn` window flash**: opening/running the project opens a visible window
   briefly when run — headless suite is entirely windowless while screenshots are windowed by nature.
4. Pitch geometry is prototype-simple (box lines); arbiter-grade accuracy (line width
   tolerances, exact arc segments) is out of Phase 1 scope.
5. Legacy repo-root `main.tscn` and `icon.svg` retained untouched as project-history.

## 6. How to reproduce validation yourself

```text
:: headless, expected "49 passed, 0 failed"
godot --headless --path . res://tests/phase1_validation.tscn

:: UI RTL-direction regression probe (windowed, saves PNG)
godot --path . res://tests/mirror_probe.tscn

:: visual captures
godot --path . res://tests/screenshot_runner.tscn -- menu
godot --path . res://tests/screenshot_runner.tscn -- stadium
godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
```
