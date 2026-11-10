# KING FOOTBALL — Phase 2 Report (Player Controller System)

## Result

A first fully controllable football player now exists inside the existing
project: a reusable `CharacterBody3D` scene with 8-direction camera-relative
movement, smooth acceleration/deceleration, sprint, smoothed rotation, a
lightweight state machine with clean signals, and a dedicated headless
validation suite.

**Validation status:**

- `godot --headless --path . res://tests/phase1_validation.tscn` → **49 passed, 0 failed** (Phase 1 untouched, still green)
- `godot --headless --path . res://tests/phase2_validation.tscn` → **57 passed, 0 failed**

Note on the eight FAILs seen mid-development: all were test-harness methodology
issues (thresholds not accounting for the acceleration ramp, a missing
`_hold("move_left")` in the diagonal test, a removed helper during refactor,
`get_column()` not present in this engine build, a missing `extends Node3D`).
They were fixed in the *tests/development script*, not worked around; no
controller behaviour was ever wrong in those runs.

## Features implemented

- Player scene `scenes/player/player.tscn`: feet-origin CharacterBody3D +
  capsule collider + placeholder stylized visuals (gold torso, head, legs,
  red −Z facing marker) with physics/visual separation (`VisualRoot`).
- Controller `scripts/player/player_controller.gd`:
  - 4+4 diagonal movement via InputMap (`Input.get_vector`, digital normalized,
    analog magnitude preserved).
  - Camera-relative movement (active viewport camera, basis flattened to the
    ground plane; pitch ignored, no vertical velocity leaks) with automatic
    fallback to world axes when no camera is present.
  - Configurable acceleration (18) / deceleration (22) — nothing snaps to
    max speed; measurements: terminal speed 5.50 m/s, diagonal 5.50 m/s,
    sprint ≈8 m/s, stop < 0.05 m/s well within 1.5 s.
  - Smoothed yaw rotation (`rotation_speed` exponential damping, last facing
    preserved while idle; verified yaw for all run directions).
  - Sprint via `sprint` action (no stamina — documented deferral).
  - States `IDLE / MOVING / SPRINTING` + signals
    `movement_state_changed`, `speed_changed` (≥0.25 m/s steps),
    `facing_direction_changed` (≥15° steps) — animation-ready interface.
- Config resource `PlayerConfig` (`resources/configurations/player_config.tres`)
  following the existing `CameraConfig` pattern; all gameplay numbers exported,
  no magic gameplay constants in code.
- Test scene `scenes/development/player_controller_test.tscn`: Phase 1 pitch +
  player + Phase 1 camera (FOLLOW mode wired to the player, `V` toggles modes)
  + sun/sky + four collision-test crates + RTL-safe HUD showing state and live
  speed.
- Integration: the controller reads the *active viewport camera* (no changes to
  `game_camera.gd` — it stays playable and reusable; Broadcast mode keeps the
  player visible with the elevated fixed view).

## Files created

| Path | Purpose |
|---|---|
| `scripts/player/player_controller.gd` | CharacterBody3D controller |
| `scripts/player/player_config.gd` | `PlayerConfig` Resource |
| `resources/configurations/player_config.tres` | config defaults |
| `scenes/player/player.tscn` | reusable player scene |
| `scenes/development/player_controller_test.tscn` | test environment |
| `scripts/development/player_controller_test.gd` | test-scene glue + crates + HUD |
| `tests/phase2_validation.gd` / `.tscn` | headless Phase 2 suite |
| `docs/PHASE_2_AUDIT.md` | mandatory pre-implementation audit |
| `docs/PLAYER_CONTROLLER.md` | technical reference |
| `docs/PHASE_2_REPORT.md` | this report |
| `docs/PHASE_3_HANDOFF.md` | Ball Physics handoff |

## Files modified

| Path | Change |
|---|---|
| `README.md` | status + validation + phase 2 section |
| `docs/CONTROLS.md` | Phase 2 consumption table |
| `docs/ARCHITECTURE.md` | player folder layout + design decisions |

No Phase 1 file was functionally changed (project.godot, camera, pitch,
stadium, menu, phase 1 tests all untouched).

## Tests executed (with results)

Static: scripts parse (3), scenes load (2), PlayerConfig loads, InputMap
reused (5 checks) — all PASS.
Player structure: root type, capsule bottom = origin, VisualRoot body/head,
facing marker, lower body, config assigned — all PASS (7 checks).
Headless behaviour (each via multi-tick physics simulation with simulated
InputMap actions):

| Check | Result |
|---|---|
| Grounded after settling, y stable (no float/sink/through-floor) | PASS |
| No drift while idle; stable vertical position | PASS |
| move_forward/backward/left/right exact directions (world fallback) | PASS ×4 |
| Forward-left diagonal direction ≈ 45° | PASS |
| Diagonal speed = straight speed (≤ 0.15 diff; 5.50 vs 5.50) | PASS |
| Run speed ≈ 5.5 m/s per config | PASS |
| Sprint raises speed (~8 m/s), state SPRINTING | PASS ×2 |
| Sprint release restores 5.5 m/s and MOVING | PASS ×2 |
| Deceleration: stop < 0.05 m/s ≤ 1.5 s, state IDLE, grounded during brake | PASS ×3 |
| Signals: transitions (IDLE→MOVING→SPRINTING→IDLE), speed events, single facing event for a straight run, final IDLE | PASS ×6 |
| Analog strength 0.4 → partial speed (deadzone-mapped), not binary | PASS |
| Camera-relative: forward follows flattened camera forward (−X) | PASS |
| Camera fallback after camera removal → world −Z | PASS |
| Wall collision: stops before wall face (~−5.4 vs face −5.7), grounded, velocity fully blocked | PASS ×3 |
| Test scene: structure, camera→player wiring, obstacles, HUD, config | PASS ×6 |
| Test scene: player drivable on the pitch | PASS |

## Remaining issues / known limitations

- **Visual verification is headless-only**: behaviour is proven through physics
  simulation and structural checks; a human look at the placeholder model,
  HUD and camera framing in `player_controller_test.tscn` is still worth one
  manual pass (open the scene → F6). Jolt physics runtime is active during the
  headless tests, so collision results are real physics results.
- The player sinks ~3 cm into the visual grass because the Phase 1 pitch
  collision plate top is at y = −0.03 (documented; pitch intentionally
  untouched — Phase 1 must stay green).
- Gamepad device testing was not possible on this machine: bindings and analog
  handling are *configuration-validated* (InputMap events + simulated analog
  strengths), not hardware-tested.
- Placeholder visuals are deliberately simple squat figures; real models/
  animations are later phases (interface points documented in
  PLAYER_CONTROLLER.md).
- `switch_player` (Tab) in the test scene currently just teleports the player
  to the centre spot as a debug convenience — real switching is a later phase.

## How to run the test scene

```text
godot --path . res://scenes/development/player_controller_test.tscn
```

or open it in the editor and press F6. Controls: WASD/arrows or left stick to
move, Shift to sprint, V toggles Broadcast/Dynamic camera, Tab resets to the
centre spot, Esc returns to the main menu.

## Phase 2 acceptance checklist

- [x] Phase 1 architecture preserved (49/49 re-verified)
- [x] Reusable player scene exists
- [x] CharacterBody3D implemented correctly (feet origin, capsule, config)
- [x] Keyboard movement works (all 8 directions; direction tests)
- [x] Gamepad movement prepared and verified to hardware limits (bindings +
      analog simulation; hardware test pending)
- [x] Camera-relative movement works (incl. fallback test)
- [x] Acceleration and deceleration work (measured ramps & full stop)
- [x] Sprint works (raises & restores speed, state active)
- [x] Smooth character rotation works (direction-specific yaw, idle sticky)
- [x] Movement states work (verified transitions + signals)
- [x] Ground detection works (is_on_floor, grounded bias stable)
- [x] Gravity and collision work (fall clamp, wall stop, no floor cheats)
- [x] Dynamic camera integration works (follow camera wired to player in
      the test scene and driven by simulation)
- [x] Broadcast camera remains functional (mode toggle unchanged; phase 1
      suite re-verifies broadcast positioning)
- [x] Player test scene is complete
- [x] Documentation updated
- [x] Validation tests performed (57/57 phase 2, 49/49 phase 1)
- [x] No known critical errors remain
- [x] Phase 3 handoff complete (docs/PHASE_3_HANDOFF.md)

## Phase 3 NOT started (ball physics) — deliberate scope boundary.
