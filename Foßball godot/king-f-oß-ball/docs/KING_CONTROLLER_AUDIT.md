# KING CONTROLLER — Full repository audit (Phase 0)

Audit date: 2026-11-15. Repository state: commit `5c91386` ("KING CONTROLLER: tiered DLS-style action
layout"), branch working tree clean except unrelated `SUPERMARKET-TYCOON` artefacts outside this project.

Scope of the audit: `Foßball godot/king-f-oß-ball` (Godot 4.7.2, GDScript).

---

## 1. What exists today (real, working code)

The project already ships a **working KING CONTROLLER v2** — it is *not* a stub and it is *not* a
mock-up. The audit below lists every part that was found in the repository, with the file that
implements it.

### 1.1 PC side

| File | Responsibility | State |
|---|---|---|
| `scripts/systems/controller/controller_protocol.gd` | Wire format v2, byte-size check before decoding, strict message validation, sequence + rate rules, message builders | Implemented, verified |
| `scripts/systems/controller/controller_session.gd` | One paired phone, seven lifecycle states, frozen-time shifting | Implemented, verified |
| `scripts/systems/controller/controller_registry.gd` | Pairing token, sessions, slot allocation, resume window, revocation, heartbeat, input-gap release, pause debounce | Implemented, verified |
| `scripts/systems/controller/controller_network.gd` | Ranks `IP.get_local_interfaces()` for the LAN address (virtual/VPN adapters demoted) | Implemented, verified |
| `scripts/systems/controller/king_controller_server.gd` | HTTP (page) + WebSocket transport, connection limits, close handling, `revoke(slot)` | Implemented, verified |
| `scripts/systems/controller/king_controller_hub.gd` | Bridges controller slots to the match `IntentProvider`s, releases everything on loss, drops press edges while paused | Implemented, verified |
| `scripts/systems/controller/qr_encoder.gd` | Pure-GDScript QR encoder (no dependency) | Implemented, verified |
| `scripts/ui/pairing_screen.gd` | View of the shared server: QR, URL, one-time code, address picker, slot list, revoke button | Implemented, verified |
| `scripts/core/game_manager.gd` | Owns the single server (`ensure_controller_server` / `stop_controller_server`) | Implemented, verified |
| `scripts/systems/match/match_manager.gd` | Wires the hub to `human_intent` (slot 0) and `human_intent2` (slot 1), seat-2 dynamic hand-over, AI fallback, pause from the phone | Implemented, verified |

### 1.2 Phone side

`assets/controller/controller_page.html` — one self-contained page (no external requests):

- virtual joystick (radial dead zone, pointer capture, centre reset),
- 8 gameplay actions (`sprint`, `tackle`, `switch_player`, `pass`, `shoot`, `lob_pass`,
  `through_pass`, `cross`) plus the dedicated `pause` system action,
- tiered DLS-style button layout (small pills / mid circles / two big main buttons),
- heartbeat + silence timeout, reconnect with the session credential, one-time token removal from the
  address bar, explicit `bye`,
- release of every input on `blur` / `pagehide` / `visibilitychange` / `orientationchange` /
  `pointercancel` / lost pointer capture,
- languages `en` / `de` / `ar` with full RTL switching, zoom/scroll/selection disabled,
- landscape-only ("rotate" overlay in portrait).

### 1.3 Existing automated tests (baseline, re-run for this audit)

| Suite | Result at audit time |
|---|---|
| `tests/controller_protocol_validation.tscn` | 79 passed, 0 failed (v3 bump + back-compat rules) |
| `tests/controller_session_validation.tscn` | 85 passed, 0 failed |
| `tests/controller_page_validation.tscn` | 48 passed, 0 failed |
| `tests/controller_loopback_validation.tscn` | 67 passed, 0 failed |
| `tests/controller_gameplay_validation.tscn` | 70 passed, 0 failed |
| `tests/controller_qr_validation.tscn` | 57 passed, 0 failed |
| `tests/controller_companion_validation.tscn` | 68 passed, 0 failed (companion data: pure formatters + match adapter contract, Phase 1) |
| `tests/localization_validation.tscn` | 98 passed, 0 failed |
| `tests/two_human_validation.tscn` | 41 passed, 0 failed (4 consecutive clean runs at audit time) |
| `tests/e2e/controller_browser_e2e.js` | Playwright harness, emulated Chromium (not a phone) |

Total: **613 checks, 0 failures** across the nine permanent controller/localization suites (plus the
32-check browser e2e harness) after the Phase 1 companion-data work. The pre-Phase-1 baseline was
447 checks, 0 failures.

---

## 2. Requirement-by-requirement classification

Legend: **OK** = implemented and verified · **PARTIAL** = implemented but not verified on a real device ·
**MISSING** = not implemented · **BROKEN** = implemented but faulty · **BLOCKED** = needs a game system
that does not exist.

### 2.1 Phase 1 — core stability, networking, security

| Requirement | State | Notes |
|---|---|---|
| Reliable server start / stop | OK | `KingControllerServer.start()` walks the port pair (+2, 5 attempts), reports `port_in_use` |
| Server survives scene transitions | OK | the server lives in the `GameManager` autoload, not in the match scene |
| Server survives pause | OK | `PROCESS_MODE_ALWAYS` on server and hub |
| Two phones, two independent slots | OK | `SUPPORTED_SLOTS = 2`, slot 1 = human side, slot 2 = the opponent |
| No cross-team input leakage | OK | the hub routes only to slots that own a provider |
| Reconnect to the original slot | OK | `resume` with the session credential; the older socket is closed |
| AI fallback when a phone disappears | OK | `_release_seat2()` hands the player back to `AIIntent` |
| Pause/Resume from the phone | PARTIAL | implemented and unit-tested; **the previously reported "second phone + pause/resume" failure could not be reproduced in this environment** (no physical phone) |
| Heartbeat / timeout / input-gap release | OK | 3 s heartbeat, 500 ms input gap, all held buttons released |
| Browser backgrounding / screen lock | PARTIAL | the page releases on `visibilitychange`/`blur`; only emulated in the browser harness |
| LAN address selection | OK | `KingControllerNetwork.choose()`, virtual adapters demoted |
| Windows firewall behaviour | PARTIAL | documented, **not verifiable from inside the game** — stays a manual check |
| Token generation / expiry / revocation | OK | CSPRNG, 120 s TTL, one-time, constant-time compare, 10 min revocation memory |
| Message-size limits, rate limits, allowlists | OK | 1024 B cap, 60 msg/s, 10 ping/s, strict field allowlists |
| Protocol documentation | OK | `docs/KING_CONTROLLER_ARCHITECTURE.md` |

### 2.2 Phase 2 — custom controls & layout editor

| Requirement | State | Notes |
|---|---|---|
| Interactive layout editor | **MISSING** | no editor at all |
| Move / resize buttons, spacing, transparency | **MISSING** | — |
| Joystick position / size / dead zone / sensitivity | **MISSING** | the page hard-codes `DEAD = 0.12` and a fixed radius |
| Presets (classic / professional / simple / left-handed / custom) | **MISSING** | — |
| Per-player / per-device profiles | **MISSING** | — |
| Export / import of a configuration file | **MISSING** | — |
| Accessibility (larger buttons, high contrast, simplified layout) | **MISSING** | — |
| Existing gameplay buttons preserved | OK | all 8 actions + pause |

### 2.3 Phase 3 — live match dashboard

| Requirement | State | Notes |
|---|---|---|
| Dashboard UI | **MISSING** | — |
| Score / clock / teams / status | **MISSING** | the data exists in `MatchState`, the phone never receives it |
| Team statistics | **MISSING** | `MatchStats` measures possession, shots, on target, passes, pass accuracy, saves, subs, fouls, cards, corners, throw-ins, goal kicks, offsides |
| Live events | **MISSING** | `MatchState.events` is filled but never sent |
| Efficient updates | **MISSING** | — |

### 2.4 Phase 4 — tactical management

| Requirement | State | Notes |
|---|---|---|
| Tactical panel on the phone | **MISSING** | — |
| Formation / mentality / pressing / line / width / build-up / passing | **MISSING** on the phone | the **game** has all of it (`TacticsPreset`, `FormationData`, `TeamAI`) and the hub screen edits it — only the phone path is missing |
| Substitutions | **MISSING** on the phone | the engine supports them (`MatchManager._swap_player`, `Squad.substitute`) |
| Team-ownership enforcement | MISSING | depends on the phone path |
| Two-phone independence | OK for input; MISSING for tactics | — |

### 2.5 Phase 5 — live mini map

| Requirement | State | Notes |
|---|---|---|
| Mini map | **MISSING** | — |
| Real player / ball positions | MISSING (data available) | `MatchManager.entries`, `ball.global_position`, `PitchSpace` |
| World → map conversion | MISSING | `PitchSpace` gives the frame rules |

### 2.6 Phase 6 — training & haptics

| Requirement | State | Notes |
|---|---|---|
| Interactive training lessons | **MISSING** | — |
| Beginner / intermediate / advanced | **MISSING** | — |
| Progress persistence | **MISSING** | — |
| Haptic feedback | **MISSING** | the browser API (`navigator.vibrate`) is available on the phone page |
| Device compatibility detection | **MISSING** | — |

### 2.7 Phase 7 — analytics & monitoring

| Requirement | State | Notes |
|---|---|---|
| Button / joystick / session / interruption counters | **MISSING** | `KingControllerRegistry.counters` has only 6 coarse counters |
| Measured latency | **MISSING** | must be measured on the phone (the PC cannot measure a round trip alone) |
| Analytics dashboard | **MISSING** | — |
| Versioned local persistence | **MISSING** | — |
| No external telemetry | OK (by absence) | — |

### 2.8 Phase 8 — UI/UX, localisation, accessibility

| Requirement | State | Notes |
|---|---|---|
| KING Premium identity | PARTIAL | the page uses gold `#d4af37` / red `#c0272d` / ink `#0b0b0d`; the brief's exact palette (`#111111`, `#D4AF37`, `#A8862D`, `#A51E2B`, `#E7E3D8`, `#343A40`) is not used verbatim |
| Screen structure (7 screens) | **MISSING** | only one screen |
| Responsive / safe area | PARTIAL | safe-area insets are used for the controller screen only |
| Arabic RTL | OK (controller screen) | the new screens must repeat it |
| German / English complete | OK (controller screen) | — |
| Accessibility | **MISSING** | — |

### 2.9 Phase 9 — integration, QA, release

| Requirement | State | Notes |
|---|---|---|
| Full-suite regression | OK | 383 checks green at baseline |
| Windows 10/11 real-machine testing | PARTIAL | the server runs on this Windows host; **no physical Android phone was available** |
| Android real-device testing | **PARTIAL** | Playwright + emulated Chromium only |
| 10-minute two-phone stability run | NOT DONE | no second physical device |
| Performance measurement | PARTIAL | `tools/perf_benchmark.tscn` exists for the game, not for the controller |
| Release documentation | PARTIAL | architecture + QA report exist; protocol / security / setup / user-guide / test-plan / changelog files do not |

---

## 3. Bugs and risks found during the audit

1. **`KingControllerProtocol.MAX_MSG_BYTES` (1024 B) is too small for a position stream.** 22 players with
   names would not fit; any future live-data message needs either a bigger cap or a compact encoding.
   *Fixed in this edition by a compact, quantised position encoding plus a documented cap raise.*
2. **The pairing token is one-time, so a second phone needs a new QR code.** The PC shows the code, but
   the flow is not obvious in the UI; the pairing screen must state that a second phone needs a new code.
3. **`_close_conn` / `_close_by_id` interplay:** a socket closed by the registry is closed twice in some
   paths (`c["session"] = null` then `_close_conn` → `_connection_gone` sees no session). It is harmless
   today but fragile; the new code keeps a single owner for the close path.
4. **The hub drops input for slots without a provider** (`dropped_unrouted`) but the count is never shown
   to the user; the pairing screen should surface it.
5. **No way to see the real connection quality** on the PC (latency, interruptions) — a gap the analytics
   manager fills.
6. **`MatchStats` does not measure tackles** — only fouls. A "tackles" statistic must be reported as
   *unavailable*, never fabricated.
7. **The page is a single 375-line file**; the Complete Edition needs seven screens, an editor and a
   training engine. It must be split *logically* (sections) while staying self-contained (the page loads
   nothing from the network — a property the page test asserts).

---

## 4. Dependencies between features (real, from the code)

- Live dashboard / mini map depend on `MatchManager` → `MatchState` / `MatchStats` / `entries` / `ball`.
- The PC side of the controller lives in the `GameManager` autoload while the match lives in a separate
  scene, so the match must *publish* its state to the server through a data provider
  (`KingControllerMatchData`) — the server must not reach into the match itself.
- Tactics on the phone depend on `TacticsPreset` being the **live** object of the match copy of the squad
  (`Squad.get_tactics()` returns a reference) — changing it changes `TeamAI` behaviour on the next tick.
- Formation changes depend on `MatchManager._place_team()`, which repositions the eleven from the
  formation + tactics (`FormationData`, `PitchSpace`).
- Substitutions depend on `MatchManager._swap_player()` and `MatchState.record_substitution()`.
- Slot → side mapping depends on `MatchSetup.human_side` (slot 0 = the human side, slot 1 = its opponent).
- Analytics latency can only be measured on the phone (request/response round trip) — the PC can only store
  and aggregate it.
- Training lessons may only teach actions that exist in `KingControllerProtocol.ALLOWED_ACTIONS`.

---

## 5. Phase 0 conclusion

The existing KING CONTROLLER v2 is a **real, tested, working controller** for one or two phones. It is
*not* a companion system: everything in phases 2–8 (layout editor, dashboard, tactics, mini map, training,
haptics, analytics, multi-screen UI) is missing and must be built on top of the existing core, reusing the
registry, the protocol discipline, the hub and the match engine rather than replacing them.

The plan for the Complete Edition therefore **extends** the protocol (versioned, v2 stays readable),
**adds** a match-data provider / analytics manager / training curriculum on the PC, and **rewrites the phone
page** into the seven-screen companion application — without touching the working input path.
