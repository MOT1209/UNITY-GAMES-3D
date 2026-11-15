# KING CONTROLLER - P9 QA report

Date: 2026-11-15. Everything below was executed in a Linux container (headless Godot 4.7.2 and Chromium via
Playwright). **No real phone, no real Wi-Fi, no Windows machine was available.** Nothing in this report is a
real-device result unless it says so, and no local simulation is presented as one.

## 1. Initial defects (measured before any change)
| # | Defect | Evidence (baseline probe) |
|---|---|---|
| P9.1 | A real browser can never move a player: the page sent `Date.now()` as `t`, the server compared it with its own monotonic clock. | `browser-style input (t=1794721201371, server ticks=996): ok=false reason=stale_freshness`; the same input without `t`: `ok=true` |
| P9.2 | No real Pause: the page's Pause button sent `switch_player`; `pause` was not an allowed action. | `pause allowed: false` |
| P9.3 | Four slots advertised, one wired. | `slots advertised: 4; slots wired by the match: 1` |
| P9.4 | `MAX_MSG_BYTES` existed but the server never used it. | `MAX_MSG_BYTES used by server: false` |
| P9.6 | Disconnect left stick and buttons running for a 5 s "grace". | `0.5 s after disconnect: provider driven=true move=(1,0) sprint held=true` |
| P9.7 | LAN address = first 192.168.* or first anything (virtual adapters, loopback possible). | `lan_ip picked here: 192.0.2.2` |
| - | A phone paired on the menu *before* the match was ignored by the match. | code audit + `controller_gameplay_validation` |
| - | Found by the new loopback test: the HTTP responder never buffered the request (value-type `PackedByteArray` copy), so **the page was never actually served**. Fixed. | `controller_loopback_validation` first run: HTTP checks failed with empty responses |
| - | Arabic page: no RTL, wrong through-pass label. | page audit |

Root causes: clock-domain mismatch; protocol designed on edges (press/release lists) so a lost packet left a button
stuck; transport, rules and UI mixed in one class so rules were untestable; hard-coded constants never consulted.

## 2. Task status
| Task | Status | Notes |
|---|---|---|
| P9.1 timestamp / freshness | **DONE** (PC + emulated browser) | server arrival time; seq / rate / timeout rules documented and tested. Real-phone latency: NOT TESTED |
| P9.2 dedicated pause | **DONE** | real `MatchManager` pause / resume driven through real sockets |
| P9.3 slots | **DONE** | 1 slot advertised and wired; 2-4 shown unsupported; no sharing; cleanup tested |
| P9.4 message limits / validation | **DONE** | size before JSON; malformed JSON / type / version / field / range tests; no tokens in logs |
| P9.5 pairing / session security | **DONE** (within the documented limits) | no TLS - stated everywhere |
| P9.6 lifecycle / heartbeat | **DONE** | 7 states, heartbeat, input gap, release on loss, status on PC and phone |
| P9.7 LAN discovery | **PARTIAL** | ranking, error messages and port check tested with Windows-style adapter names; the real Windows adapter list and firewall prompt are NOT TESTED |
| Phone page | **DONE** in emulated Chromium; **NOT TESTED** on a real phone | all required controls except "Press" |
| "Press" button | **PARTIAL / open decision** | the game has no separate press action (only `tackle`); a button without gameplay would be fake, so it was not added |
| PC pairing screen | **DONE** | tested against the live server state (QR, URL, slots, revoke, new code, stop/start, close/reopen) |
| Real-device validation (PC + Android, same Wi-Fi) | **NOT TESTED / BLOCKED** | no device or Wi-Fi in this environment |
| Performance on real hardware | **NOT TESTED** | see section 5 |
| Documentation | **DONE** | architecture, status, strategy, controls updated; the old "real-device test DONE" claim in FEATURE_STATUS was unverifiable and was withdrawn |

## 3. Automated results
Full run `tests/run_all.sh --full` (before the final fix): 66 suites, 4,019 checks passed, **1 failed** - `localization_validation`: two new German strings (`PAIR_PORTS`, `PAIR_SLOT_LINE`) were identical to the English text. Fixed; `localization_validation` (92), `release_readiness_validation` (35, its old controller-limit check was ported to the registry), `arabic_ui_validation` (38), `phase7_localization_validation` (19) and `controller_gameplay_validation` (70) were re-run afterwards and pass. The complete 66-suite run was not repeated after that one-line translation fix.
| Suite | Result |
|---|---|
| controller_protocol_validation | 72 passed, 0 failed |
| controller_session_validation | 81 passed, 0 failed |
| controller_loopback_validation | 67 passed, 0 failed |
| controller_gameplay_validation | 70 passed, 0 failed |
| controller_page_validation | 48 passed, 0 failed |
| mobile_input_validation | 26 passed, 0 failed |
| input_system_validation | 29 passed, 0 failed |
| gameplay_feel_validation | 37 passed, 0 failed |
| match_rules_validation | 33 passed, 0 failed |
| `node tests/e2e/controller_browser_e2e.js` (emulated Pixel 7 landscape, real server) | 32 passed, 0 failed |

The E2E drives real touch events (Chrome DevTools protocol) and covers: pairing, token removed from the URL,
Arabic RTL and label, stick up -> `move.y < 0`, every button press / release, Pause = one request and no player
action, window blur and touchcancel release a held button, closing the page while holding a button -> the game
sees `lost` and the release, English / German labels. Screenshot: `docs/qa/p9/controller_page_ar_emulated.png`
(emulated viewport, not a phone).

## 4. Real-device validation checklist - all **NOT TESTED**
Run on a Windows PC and an Android phone on the same Wi-Fi, record the result next to each line.
1. PC firewall prompt appears / ports 7250-7251 reachable from the phone - NOT TESTED
2. PC pairing screen shows the right LAN address (not a virtual adapter) - NOT TESTED
3. QR scans with the phone camera and opens the page - NOT TESTED
4. Page pairs and shows Connected - NOT TESTED
5. Stick moves the player in the right direction - NOT TESTED
6. Every button reacts once per touch; no stuck buttons with multi-touch - NOT TESTED
7. Pause / resume from the phone - NOT TESTED
8. Switching the phone to airplane mode / leaving Wi-Fi: PC shows Connection lost, player stops - NOT TESTED
9. Return to Wi-Fi: page reconnects (Reconnecting -> Connected) - NOT TESTED
10. Phone locked / app in background and back - NOT TESTED
11. Screen rotation - NOT TESTED
12. Revoke from the PC; phone shows "Removed by the PC" - NOT TESTED
13. New code after revoke; second phone refused while the first is connected - NOT TESTED
14. Arabic / German / English phone language - NOT TESTED
15. Input latency feel on Wi-Fi - NOT TESTED
16. Close the pairing screen with a phone connected; keep playing - NOT TESTED
17. Keyboard / gamepad still work during and after the phone session - NOT TESTED
18. Android APK touch controls unchanged - NOT TESTED
19. 10-minute stability (no drops, no growth) - NOT TESTED
20. Windows path with VPN / Hyper-V adapters present - NOT TESTED

## 5. Performance / stability notes (PC, headless, not a measurement of a real network)
- One `Time.get_ticks_msec()` per frame; per-connection buffers are bounded (WebSocket inbound 8 KiB); at most 16
  HTTP and 8 WebSocket connections; HTTP requests capped at 8 KiB and 5 s.
- Sockets and sessions are closed on `stop()`, on node exit and on match teardown (tested: stop closes every
  open connection; a torn-down match leaves no driven provider).
- The pairing screen rebuilds its small slot list once per second and on events; it is only alive while open.
- Not measured: latency over real Wi-Fi, CPU on a low-end PC, battery on the phone.

## 6. Known limitations
No TLS (LAN only); one controller; "Press" has no gameplay action; no iOS-specific testing; no Bluetooth;
rate limiting is per connection, not per IP; the firewall state cannot be detected by the game.
