# Gameplay and cross-platform audit

Mandatory pre-implementation audit for the KING FOOTBALL gameplay + cross-platform + KING CONTROLLER
program (master prompt, 2026-11). Status words follow `docs/FEATURE_STATUS.md`.

Inspected for this audit: `project.godot`, `scripts/gameplay/` (8 files), `scripts/systems/match/`
(full match engine), `scripts/player/` + `scripts/players/`, `scripts/core/` (autoloads, saves),
`scripts/ui/` (kit + screens), `tests/run_all.sh` + suite list, `docs/FEATURE_STATUS.md`,
`docs/TECHNICAL_DEBT.md`, `docs/MULTIPLAYER_ARCHITECTURE.md`, `docs/CONTROLS.md`. Grep-verified
claims: no touch code, no networking code, no Bluetooth code, no vibration calls, no joypad
connection/disconnection handling, no runtime InputMap remapping anywhere in `scripts/`.

---

## 1. Executive summary

- The project is **not a prototype**: Phases 1–5 of gameplay (controller, ball physics, passing,
  shooting, dribbling, reception, formations, goalkeeper), the full 3D playable match engine with
  AI layers, rules (fouls/cards/offside/restarts), tactics, career/management (T-phases 1–14),
  localization (ar/de/en), a versioned atomic save system and **49 headless validation suites**
  (~13 min full run) are implemented and tested.
- Therefore **five of the twelve phases in the master prompt already exist in tested form**.
  The master prompt's "do not rebuild" rule must be applied to its own phase list: the phases are
  re-scoped below to deltas only (§7).
- The real gaps are exactly the ones the master prompt targets: **touch/mobile input,
  centralised input abstraction hardening, physical-controller device lifecycle, and KING
  CONTROLLER (zero networking code exists today)** — plus honest cross-platform feasibility work
  (Android export config does not exist; iOS cannot be built or verified on this machine).
- No broken or fake implementations were found. The codebase is unusually explicit about what is
  not implemented (`docs/TECHNICAL_DEBT.md` has 15 honest entries).

## 2. Existing functionality mapped against the master prompt

| Master prompt requirement | Status | Evidence |
|---|---|---|
| Player movement (walk/jog/sprint/accel/turns) | IMPLEMENTED (tested) | `scripts/player/player_controller.gd`; `phase2_validation` 57/57 |
| Ball physics (friction, bounce, spin base, CCD, speed ceiling) | IMPLEMENTED (tested) | `scenes/ball/football_ball.tscn`, `BallController.apply_kick()`; `phase3_validation` 103/103 |
| Ball control / first touch | IMPLEMENTED (tested) | `scripts/gameplay/ball_control_system.gd`; `phase4_validation` 159/159 |
| Passing (ground, lob, directional, charged power) | IMPLEMENTED (tested) | `passing_system.gd`, `lob_pass_system.gd`, `kick_power_controller.gd` |
| Shooting (power, elevation, charge) | IMPLEMENTED (tested) | `shooting_system.gd` |
| Dribbling (physics-based, no teleport) | IMPLEMENTED (tested) | `dribbling_system.gd` (follow-spot spring + overshoot brake) |
| Goalkeeper (dive/catch/throw, forces only) | IMPLEMENTED (tested) | `scripts/teams/team_goalkeeper.gd`; `phase5_validation` 218/218 |
| Match rules: fouls, cards, free kicks, penalties | IMPLEMENTED (tested 33) | `match_rules_validation` |
| Throw-ins, corners, goal kicks, offside | IMPLEMENTED (tested 27) | `match_restarts_validation` |
| Team AI (formations, mentality, pressing, support runs) | IMPLEMENTED (tested) | `team_ai.gd`, `manager_ai.gd`, `player_ai.gd`; `phase8_tactics_validation` 20, `ai_attack_validation` |
| Match stats/report/events pipeline | IMPLEMENTED (tested) | `match_state.gd`, `match_stats.gd`, `match_report.gd` |
| In-progress match save | IMPLEMENTED (tested) | `match_save.gd`, `match_snapshot.gd` (atomic + `.bak`) |
| Save versioning, stable ids | IMPLEMENTED | `scripts/core/save_manager.gd` v3, migration chain v0→3; stable player/club ids (`tm_*`, `yth_*`, pack ids) |
| Localization (needed for controller UI) | IMPLEMENTED | `Loc` autoload, ar (RTL) / de / en |
| Presentation: weather, crowd, replays, sounds | IMPLEMENTED (tested 49) | `crowd_system.gd`, `replay_buffer/player.gd`, `MatchSounds` |
| 3D playable match with human control | IMPLEMENTED | `match_manager.gd` — human controls one player via `IntentProvider`; `switch_player` exists |

## 3. Missing functionality (the real work)

1. **Touch input: nothing exists.** No touch bindings, no virtual joystick, no
   `InputEventScreen*` handling, no `emulate_touch_from_mouse`, no safe-area/responsive mobile UI.
   14 actions are keyboard+gamepad only.
2. **Input abstraction is thin.** `IntentProvider`/`AIIntent` (`scripts/systems/match/`) is the
   right seam, but 3 gameplay-relevant call sites still read `Input.*` directly:
   `match_manager.gd:361` (`switch_player`), `match_rules.gd:60` (`tackle`), plus UI
   `_unhandled_input`. No single `InputManager` owns devices.
3. **Device lifecycle: none.** No `joy_connection_changed` handling, no dead-zone/sensitivity
   configuration, no runtime remapping (pause menu only *displays* bindings), no vibration calls
   (`Input.vibrate_handheld` never used).
4. **Networking: zero code.** `docs/MULTIPLAYER_ARCHITECTURE.md` is design-only. KING CONTROLLER
   (QR pairing, WebSocket transport, phone controller UI, protocol, multi-device slots) is
   entirely unbuilt. This is the largest greenfield item.
5. **Mobile/cross-platform config: none.** No `[android]`/`[ios]` overrides, no export presets,
   no mobile rendering/perf tuning (renderer is already `gl_compatibility`, which is mobile-fit).
6. **Known gameplay gaps vs. DLS-like feel** (documented limits, not bugs): no crosses/through
   balls for the *human* hand-held action set (AI has them), throw-ins/goal kicks restart with the
   ball at rest (no throwing animation), free kicks without wall/set-piece animation, penalties
   not as a duel, offside ignores "interfering with play", no referee model/advantage rule,
   goal conversion still rare (TECHNICAL_DEBT #14).
7. **Performance: never measured on real hardware** (TECHNICAL_DEBT #7: software renderer only).
   The master prompt's FPS targets have no baseline yet.

## 4. Broken functionality

None found. Verified non-issues: no TODO/FIXME in production code, no duplicate gameplay
implementations (`MatchManager` explicitly reuses `player.tscn` / `FootballActions` /
`BallController`), no fake success paths. The quick Poisson `match_simulator.gd` for unplayed
matches is a documented separate path, not a hidden duplicate of the engine.

Documented limits carried into this program (to state, not silently fix): restarts without
throwing animation, offside simplification, code-only referee, statistical awards for simulated
matches, transfer history stores week only (TECHNICAL_DEBT #10).

## 5. Architecture problems (manage, don't rewrite)

| # | Problem | Impact on this program |
|---|---|---|
| A1 | `scripts/player` (controller) vs `scripts/players` (data/visual) naming (debt #3) | Onboarding confusion; no code change required now |
| A2 | `AppHub`/`GameManager` are large singletons (debt #2) | New networking/controller systems must take dependencies as arguments, not grow these |
| A3 | `match_manager.gd` ~750 lines (debt #1) | Touch + controller wiring should hook the existing signals, not extend the orchestrator |
| A4 | Physics not bit-deterministic across machines (MULTIPLAYER_ARCHITECTURE.md) | For KING CONTROLLER this is **not** a blocker: the phone sends inputs only; the PC simulates. Full multiplayer stays out of scope |
| A5 | UI is code-generated for 1280×720, no mobile adaptation | Mobile layouts need a scale/safe-area pass in `ui_kit.gd`, not new screen code |
| A6 | Test suite bottleneck: 12-season test (~13 min run) | New suites must be cheap; keep guards (`*_validation.tscn` must be registered, no duplicate `class_name`) |

## 6. Reusable components (build on these, in priority order)

1. **`IntentProvider` / `AIIntent`** (`scripts/systems/match/`) — the single seam where a future
   `RemoteControllerIntent` (phone input) or `TouchIntent` plugs in with zero gameplay-code
   changes. This is the most important reuse in the whole program.
2. **`BallController.apply_kick()` + `BallActionConfig`** — all ball interaction stays physical
   through one API; tuning is data, not code.
3. **Stable ids + `SaveManager` v3 migrations** — phone sessions/assignments can be persisted
   safely; no duplicate source of truth needed.
4. **`tests/run_all.sh` + 49 suites + guards** — the verification pattern for every new phase
   (headless `.tscn` suites printing "N passed, M failed").
5. **Code-generated `UIKit` + `Loc` (ar/de/en)** — controller screens, QR screen and mobile HUD
   can be built as normal screens with instant localization.
6. **`docs/MULTIPLAYER_ARCHITECTURE.md`** — input-as-data, event formats and snapshot thinking
   carry over directly to the controller protocol.

## 7. Recommended implementation sequence (re-scoped master prompt phases)

Original prompt phases 1–5 (movement, ball physics, ball control, passing, shooting, dribbling,
goalkeeper basics) are already delivered and tested; they are replaced by **P3, a feel/quality
pass**. Phases are deliberately small, each with a headless test suite and a status report.

- **P1 — Performance baseline (new).** Measure real FPS/CPU/GPU/memory on Windows
  (engine matches, dev scenes), record in `docs/PERFORMANCE_BASELINE.md`. Everything later
  is measured against this. *Cost: small. Risk: low.*
- **P2 — Input system hardening.** Route the 3 remaining `Input.*` gameplay call sites through
  the intent layer; add device lifecycle (connect/disconnect detection with a clear "controller
  disconnected" state), dead-zone/sensitivity settings persisted like other settings; extend
  `docs/CONTROLS.md` → `docs/INPUT_SYSTEM.md`. *Tests: input device simulation suite.*
- **P3 — Gameplay feel pass (DLS-inspired responsiveness).** Attribute-driven first-touch
  quality under pressure, human crosses/through-pass actions (the AI already has the logic),
  player-switching intelligence (nearest-to-ball + manual), shot aim assist tuning, pass target
  assist. Verify with `tools/sim_matches.tscn` metrics + `ai_attack_validation`-style suite.
  No architecture change; tuning + the two missing human actions.
- **P4 — Mobile foundations (Android first).** Export preset + `[android]` input/emulate-touch
  config, virtual joystick + action buttons producing the same 14 actions through the intent
  layer, responsive/safe-area UIKit pass, 30/60 FPS measurement against P1. **iOS: documentation
  only** (no Apple signing/build machine on this host) — explicitly stated, never claimed as
  support.
- **P5 — KING CONTROLLER v1: QR over local Wi-Fi.** PC-side pairing screen (KING identity),
  one-time pairing token in QR, WebSocket server bound to the LAN, versioned input protocol
  (sequence, rate limit, freshness, slot auth) reusing `IntentProvider` as the sink, phone-side
  controller UI served by the PC (browser page — no app store dependency) with the same virtual
  controls as P4, multi-device slots, reconnect handling. Tests: protocol unit suite + loopback
  integration suite (the pattern already proposed in MULTIPLAYER_ARCHITECTURE.md §Test).
- **P6 — Bluetooth investigation spike.** Godot 4.7 has **no built-in Bluetooth API**; requires
  per-platform plugins (Android JNI, Windows WinRT). Deliverable: measured capability report +
  either a minimal Android-only implementation or an explicitly documented limitation with the
  Wi-Fi path as the supported alternative. **No simulated success allowed.**
- **P7 — Physical controller polish.** Device detection/profiles, disconnect/reconnect UX,
  vibration where the platform supports it, per-device mapping display. Tested with scripted
  input simulation; real-device checks documented honestly.
- **P8 — Cross-platform integration + QA.** Windows regression run, Android device testing,
  save-compatibility check (v3 chain untouched), final report
  `docs/reports/KING_FOOTBALL_GAMEPLAY_UPGRADE_REPORT.md`.

Master-prompt document requirements are mapped onto the existing docs tree to avoid duplicate
sources of truth: `INPUT_SYSTEM.md` (new, supersedes `CONTROLS.md`), `PERFORMANCE_BASELINE.md`
(new), `KING_CONTROLLER_ARCHITECTURE.md` (new, at P5), `CROSS_PLATFORM_STRATEGY.md` (new, at P4),
`GAMEPLAY_ARCHITECTURE.md` (new, consolidating the phase 1–5 docs), `ROADMAP.md` = update
`MASTER_ROADMAP.md` in place.

## 8. Technical risks

| Risk | Severity | Mitigation |
|---|---|---|
| Bluetooth feasibility (no engine API; plugins per OS) | High | P6 is a spike first; QR/Wi-Fi is the primary supported path; no fake claims |
| iOS build/signing impossible on this Windows host | High | iOS documented as "prepared, untested"; scope keeps architecture iOS-neutral (no desktop-only APIs in shared layers) |
| LAN WebSocket security on Android (self-signed certs, cleartext policy) | Medium | Pairing-token model, LAN-only binding, protocol versioning + rate/freshness checks; browser-page client avoids app store & cert-store issues |
| Performance unknowns on mobile (Jolt physics, 22 players, portraits) | Medium | P1 baseline first; mobile budget checks at P4; `gl_compatibility` already selected |
| 8 MB career JSON on mobile devices (debt #13) | Low-Medium | Keep saves desktop-first for v1; measure at P4 |
| Feel-pass regressions to rare-goals bug history (debt #14/15) | Medium | Every AI change re-measured with `tools/sim_matches.tscn`; card-rate guard |
| Suite runtime growth | Low | New suites must stay under a per-suite budget; reuse the existing timeout pattern |

## 9. Bottom line

The master prompt's own rules (audit first, extend, never fake) are best served by starting at
**P1 (performance baseline)** and **P2 (input hardening)** — the foundations every later phase
consumes — then P3 gameplay feel, P4 mobile, P5 KING CONTROLLER QR, with Bluetooth and iOS kept
honest as spikes/documentation until real evidence exists.
