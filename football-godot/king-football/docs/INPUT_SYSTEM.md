# Input system

Owner document for input architecture (P2 input hardening; extends and keeps
`CONTROLS.md` as the key-binding reference). Status words per `FEATURE_STATUS.md`.

## Layers

```
Devices (keyboard / gamepad / touch later / remote later)
        │
        ▼
Godot InputMap — 14 gameplay actions, every action bound to keyboard + gamepad
        │                       (project.godot; see CONTROLS.md)
        ▼
IntentProvider  ── raw mode: reads the global Input (default, unchanged)
        │           driven mode: fed programmatically (AIIntent subclass today;
        │                     touch UI / KING CONTROLLER adapters later)
        ▼
Gameplay systems read intents only
  - player movement + BallActions: `player.intent`
  - switch_player: `MatchManager.human_intent`
  - human tackle: the tackler entry's node intent (`MatchRules.update`)
```

Rules:

1. **Gameplay code never reads `Input.*` directly.** The three P2 call sites
   (`switch_player`, `tackle`, per-player movement/kicks) all go through the
   intent layer now; only UI screens and dev scenes read events directly, which
   is allowed (they are UI, not gameplay).
2. **One shared human channel.** `MatchManager.human_intent` is created once per
   match and attached to every human selection (raw mode reads global Input, so
   behaviour is identical to pre-P2). Touch/remote adapters later flip it to
   driven mode and feed it — no gameplay change needed.
3. **Driven-mode contract** (same as `AIIntent`): the driver calls
   `begin_tick()` once per tick before applying new state, then `set_move()`,
   `press()`, `release()`. Edges (`just_pressed`/`just_released`) live exactly
   one `begin_tick()` cycle; holds persist until `release()`.

## Device settings (`scripts/systems/input/input_settings.gd`)

Persisted in `user://settings.cfg`, section `input` (same file as the language
setting, no duplicate settings store):

| Key | Default | Effect |
|---|---|---|
| `move_deadzone` | 0.2 | InputMap deadzone of the four movement actions |
| `button_deadzone` | 0.5 | InputMap deadzone of all button actions |
| `rumble` | true | goal-rumble pulses on connected physical controllers |

`InputSettings.apply_saved()` runs once at boot (GameManager) so saved values
are live from the first frame. `pulse()` is a no-op when disabled, when no
joypad is connected, or headless — it never throws.

## Device lifecycle (`scripts/systems/input/device_monitor.gd`)

Match-scoped (owned by `MatchManager` with the HUD, no singleton):

- Watches `Input.joy_connection_changed`.
- When the **last** joypad disconnects mid-match: KING-styled overlay
  "controller disconnected — reconnect to keep playing" (localized ar/de/en,
  `INPUT_CONTROLLER_*` keys in `translations/match.csv`).
- When a joypad connects: short "controller connected" notice.
- Mouse/keyboard play is unaffected (the overlay only appears when a joypad was
  in use).

## Physical controllers

- Godot device agnostic: Xbox, PlayStation (DualShock 4 / DualSense via OS
  drivers) and standard HID gamepads all map through the InputMap bindings in
  `project.godot` (see `CONTROLS.md` for the full table).
- Rumble uses `Input.start_joy_vibration` on every connected joypad; verified
  present in Godot 4.7.2 (`ClassDB` check), platform-dependent strength.
- Device disconnect/reconnect handled by the monitor above; per-device custom
  remapping and per-model profiles are future phases (KING CONTROLLER P7), not
  implemented yet.

## Tests

`tests/input_system_validation.tscn` (registered in `tests/run_all.sh`):

- raw-mode providers behave exactly like the pre-P2 global reads (29 checks
  total, all green on first run)
- driven-mode contract: clamp, edges, holds, `begin_tick`, `release_all`
- real-match wiring: every human selection shares `human_intent`; switch and
  tackle route through the intent channel (driven tackle reaches the rules)
- settings persistence round-trip incl. restart cycle, applied to the live
  InputMap, restored defaults after the test
- device-monitor transitions (handler seam; no hardware required)

## Deliberately not implemented here

- Touch input, virtual joystick, mobile layouts → P4 (mobile foundations).
- Remote controller input (KING CONTROLLER) → P5; will drive
  `human_intent` in driven mode — the seam is ready.
- Per-device remapping UI and controller profiles → P7.
- iOS support: nothing claimed; see the cross-platform audit §7.
