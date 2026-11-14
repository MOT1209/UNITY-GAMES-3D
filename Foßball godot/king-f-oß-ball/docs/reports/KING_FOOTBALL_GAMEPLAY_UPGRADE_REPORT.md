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
| P8 Integration + QA | Partial | Windows regression run (see below); Android device test not possible on this Windows host; save-compat unchanged (v3 chain untouched) |

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
| Android | Export preset configured + touch layer; **not device-tested** (no SDK/device on host) |
| iOS | Documented only — no Apple signing/build machine on this host; architecture kept iOS-neutral |
| Bluetooth controller | Not implemented — see `docs/BLUETOOTH_CAPABILITY_REPORT.md` |

## Open items (handed off)
- Real Android device build + 30/60 FPS measurement vs `PERFORMANCE_BASELINE.md` (P8).
- GPU frame-time/FPS baseline (run `profile_match.tscn -- frames` interactively).
- P7 device UX (disconnect/reconnect/vibration) on real hardware.
- Save-size check for debt #13 (8 MB career JSON on mobile).

## Conclusion
P1–P5 are implemented and test-backed. P6 is an honest capability report (no fake
Bluetooth). P7/P8 are partially complete pending real-device access, which is
impossible on this Windows host and is documented as such rather than claimed.