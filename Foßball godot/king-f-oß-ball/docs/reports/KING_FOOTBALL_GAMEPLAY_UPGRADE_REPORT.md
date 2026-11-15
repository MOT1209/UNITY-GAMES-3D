# KING FOOTBALL — gameplay & cross-platform upgrade report (P8)

Date: 2026-11-14. Scope: master prompt phases P1–P8. This report is evidence-based;
items that could not be verified on this host are stated as such (no simulated success).

## Phase status

| Phase | Status | Evidence |
|---|---|---|
| P1 Performance baseline | Done | `docs/PERFORMANCE_BASELINE.md` — Intel UHD 605, CPU/instantiation/memory numbers; GPU FPS not measured (headless) |
| P2 Input hardening | Done | `input_system_validation` 29/29; `docs/INPUT_SYSTEM.md` |
| P3 Human cross/through + first touch | Done | `gameplay_feel_validation` 37/37 |
| P4 Mobile foundations (Android) | Done | `mobile_input_validation` 26/26; `export_presets.cfg`; `docs/CROSS_PLATFORM_STRATEGY.md` |
| P5 KING CONTROLLER (Wi-Fi/QR) | Done | `controller_protocol_validation` 25/25; `controller_loopback_validation` 21/21; `docs/KING_CONTROLLER_ARCHITECTURE.md` |
| P6 Bluetooth spike | Done (report only) | `docs/BLUETOOTH_CAPABILITY_REPORT.md` — no API in Godot 4.7; Wi-Fi is supported path; no fake impl |
| P7 Physical controller polish | Partial | Existing device monitor + input settings; real-device UX not testable on this host |
| P8 Integration + QA | Partial → updated this session | Windows regression run (see below); Android device test DONE this session on real device a7595e4c (debug APK built/signed/installed/launched via com.godot.game.GodotAppLauncher, controller pairing verified over LAN with WebSocketPeer.accept_stream JSON frames, touch input dispatched); save-compat unchanged (v3 chain untouched); GPU FPS baseline + device FPS open |
| P9/P10 KING CONTROLLER rework | Done (upstream) | Protocol v2, registry/session split, secure pairing, second human (P10). All controller suites green this session: `controller_session_validation` 85/85, `controller_protocol_validation` 72/72, `controller_loopback_validation` 67/67, `controller_gameplay_validation` 70/70, `controller_page_validation` 48/48, `two_human_validation` 41/41 |
| Freeze-aware heartbeat fix | Done this session | Root cause of "phone pairs but cannot play": a synchronous `MatchManager.begin()` (~2.7 s) freezes the single-threaded server while the phone keeps streaming; the first registry tick after the build saw >3 s of silence and killed the session with `heartbeat_timeout` right as the match started. Fix: the transport passes a clamped "served time" per tick and the frozen remainder is fast-forwarded out of the session stamps (`skip_frozen`), so heartbeat / input-gap / resume rules measure only time the server could actually serve. Verified by the previously failing 3 gameplay checks (now stable across 3 runs) with zero regressions in the other suites |

## Windows regression run (this host)

Suites re-run and green on 2026-11-14:
- `input_system_validation`: 29/29
- `gameplay_feel_validation`: 37/37
- `mobile_input_validation`: 26/26
- `controller_protocol_validation`: 25/25
- `controller_loopback_validation`: 21/21
- `match_rules_validation`: 33/33 (prior run, unchanged)

The full `tests/run_all.sh` could not be executed end-to-end in this environment
because the bash harness could not locate the Godot binary via a Unix path; the
individual suites above were run directly with the Windows binary and pass.

## Save compatibility
The v3 save chain was not modified by P1–P6 (career/manager/finance/world systems
untouched). No migration required.

## Platform matrix (honest)

| Platform | Status |
|---|---|
| Windows (desktop) | Tested (this host) — regression green |
| Android | Export preset configured + touch layer; **device-tested** this session on real device a7595e4c (debug APK built/signed/installed/launched, controller pairing verified over LAN, touch input dispatched); 30/60 FPS measurement vs `PERFORMANCE_BASELINE.md` still open |
| iOS | Documented only — no Apple signing/build machine on this host; architecture kept iOS-neutral |
| Bluetooth controller | Not implemented — see `docs/BLUETOOTH_CAPABILITY_REPORT.md` |

## Open items (handed off)
- Real Android device build: DONE this session (debug APK built/signed/installed/launched on a7595e4c; controller pairing verified over LAN). 30/60 FPS measurement vs `PERFORMANCE_BASELINE.md` still open (P8).
- GPU frame-time/FPS baseline (run `profile_match.tscn -- frames` interactively).
- P7 device UX (disconnect/reconnect/vibration) on real hardware.
- Save-size check for debt #13 (8 MB career JSON on mobile).

## Conclusion
P1–P5 are implemented and test-backed. P6 is an honest capability report (no fake
Bluetooth). P7/P8 are implemented and test-backed on the dev host; real-device
access exists now (Android a7595e4c) and was used for the controller path, but
final FPS numbers on device and P7 device UX (disconnect/reconnect/vibration) and
the GPU frame-time baseline are still open and are documented as such rather than
claimed.