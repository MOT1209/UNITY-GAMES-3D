# Cross-platform strategy (P4 foundations)

Status: **P4 mobile foundations implemented (tested on desktop, configured for Android).**
Part of the re-scoped gameplay + cross-platform program
([audit §7](audits/GAMEPLAY_AND_CROSS_PLATFORM_AUDIT.md)).

## Platform matrix — honest status

| Platform | Status | Evidence / limit |
|---|---|---|
| Windows desktop | **Supported, tested** | Every headless suite in `tests/run_all.sh` runs here; the real-GPU baseline is in [PERFORMANCE_BASELINE.md](PERFORMANCE_BASELINE.md). |
| Android | **Configured, NOT device-tested** | `export_presets.cfg` (APK preset, arm64-v8a + armeabi-v7a, immersive landscape), touch input layer, GL Compatibility renderer. **No Android SDK/keystore/device on this build host: an APK has never been built or run here.** First device build is a P8 gate. |
| iOS | **Documentation only** | Requires Apple signing + macOS/Xcode; this host is Windows. iOS is deliberately not claimed as supported. See "iOS path" below. |
| Bluetooth controller (phone as pad) | **P6 spike, not implemented** | Godot 4.7 has no Bluetooth API; see the audit and the KING CONTROLLER Wi-Fi path (P5) as the supported alternative. |

## What P4 delivers

### Touch controls feeding the same intent layer

`scripts/systems/input/touch_controls.gd` (`TouchControls`, a `CanvasLayer` owned by the
MatchManager with the HUD) and `scripts/systems/input/touch_joystick.gd` (`TouchJoystick`):

- **Single seam, no parallel input path.** The stick + 8 action buttons + pause button feed the
  match's shared human `IntentProvider` in **driven mode** (`set_driven(true)` + `set_move()` +
  queued `press()/release()`), exactly like the KING CONTROLLER (P5) and the validation suites
  already do. Gameplay code cannot tell stick from keyboard from phone-controller.
- **Edge discipline follows the driven-intent contract:** buttons queue press/release requests
  from input events; `_physics_process` applies them exactly once per physics tick after
  `intent.begin_tick()`, together with the stick's `output` (screen convention identical to
  `Input.get_vector("move_left", "move_right", "move_forward", "move_backward")`: +x right,
  −y forward). Charged kicks (pass/shoot/lob/through/cross) therefore work unchanged, including
  quick taps.
- **Desktop is untouched:** the layer activates only when `DisplayServer.is_touchscreen_available()`
  (or explicitly via `set_active(true)` for tests/debug); on deactivate it leaves driven mode and
  zeroes the held state, so keyboard/gamepad raw input resumes cleanly.
- **Safe area:** the layout is offset by `DisplayServer.get_display_safe_area()` (notches /
  rounded corners) — DLS-style stick bottom-left, kick cluster bottom-right, pause top-right.
- Localized button labels: `TOUCH_*` keys in `translations/match.csv` (en/de/ar).

### Project configuration (`project.godot`)

- `[input_devices]`: `pointing/emulate_mouse_from_touch=true` (native touch works with the
  standard Control nodes), `pointing/emulate_touch_from_mouse=false` (desktop mouse behaviour
  unchanged; flip it temporarily to try the touch layer with a mouse).
- `[display]`: `window/handheld/orientation="sensor_landscape"`; stretch mode `canvas_items`
  with `expand` aspect already scales the HUD to phones and tablets.

### Android export preset (`export_presets.cfg`)

One runnable preset "Android": APK, arm64-v8a + armeabi-v7a, immersive mode, GL Compatibility
(the renderer the whole game already targets), test/tools/docs excluded from the pack. Building
it requires installing the Godot Android export templates + Android SDK and a debug keystore —
**none of that exists on this host, so no APK was produced here.** The preset is verified as
configuration (it loads in the editor); the build itself is a P8 checklist item.

## Tests

`tests/mobile_input_validation.tscn` (26 checks, registered in `tests/run_all.sh`): stick axis
convention/clamping/release, layer inert-by-default on desktop, driven-mode activation, stick →
move vector, queued press holds an action with the edge consumed exactly once, queued release
drops it, deactivation cleans up, real-match wiring (one layer per match feeding
`human_intent`, pause wired once, P3 actions present), and an end-to-end **touch tap really
charges and kicks the ball** in a real match. Regression: input_system 29, gameplay_feel 37,
match_rules 33, phase4 159.

## iOS path (documentation only — no support claimed)

The Godot 4.7 iOS export path requires: macOS with Xcode, Apple Developer account + signing
certificates, and the iOS export templates. None of these exist on this Windows host, so iOS is
out of scope until a Mac (or CI macOS runner) is available. Everything gameplay-side (GL
Compatibility renderer, canvas_items stretch, touch layer, safe area) is already the
platform-neutral work an iOS build would consume; no iOS-specific code was written and none is
claimed.

## Open items handed to later phases

- P5 KING CONTROLLER (Wi-Fi/QR): **DONE** — see [KING_CONTROLLER_ARCHITECTURE.md](KING_CONTROLLER_ARCHITECTURE.md).
- P8: real Android device build + 30/60 FPS measurement on a real device against
  [PERFORMANCE_BASELINE.md](PERFORMANCE_BASELINE.md); save-size check (debt #13).
- Small-screen UI pass for the menu screens (hub screens already reflow, untested below ~6").
