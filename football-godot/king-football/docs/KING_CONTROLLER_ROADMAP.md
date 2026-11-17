# KING CONTROLLER — Phase roadmap (Complete Edition)

Companion to [KING_CONTROLLER_AUDIT.md](KING_CONTROLLER_AUDIT.md) (what exists today) and
[KING_CONTROLLER_RISKS.md](KING_CONTROLLER_RISKS.md) (what can go wrong). Every phase below names the
actual files it touches. A phase is only "done" when its tests are green **and** its acceptance
criteria are met — test counts are recorded in the QA report, never invented.

Protocol note: the working tree already contains the **v3 protocol layer** (uncommitted,
`scripts/systems/controller/controller_protocol.gd` + new `controller_match_data.gd`): message
validation for `view` / `tactic` / `telemetry`, builders for the companion frames, and the pure
match-data formatters. Nothing else consumes them yet — the server, hub, match and phone page are
still v2-only. Each phase below integrates one slice of this surface for real.

---

## Phase 0 — Repository audit (DONE)

Deliverables: this doc set (AUDIT / ARCHITECTURE / ROADMAP / RISKS / SECURITY). Baseline re-run at
audit time: protocol 79/0 (after aligning the tests with the v3 bump), session 85/0, page 48/0,
loopback 67/0, gameplay 70/0, QR 57/0, two-human 41/0, browser e2e 32/0. **447 automated checks,
0 failures.**

## Phase 1 — Core stability, networking & security

Status: mostly pre-existing (P9/P10); the audit classifies it OK with three PARTIAL items.

Progress in this edition (recorded, not claimed):

1. **v3 protocol bump finished at test level** — `tests/controller_protocol_validation.gd` (79/0)
   now pins `PROTOCOL_VERSION == 3` + `MIN_PROTOCOL_VERSION == 2` and proves a v2 client is accepted
   on the input path (`ping`/`resume`/`input`) while v3-only types from a v2 client are rejected;
   `tests/controller_loopback_validation.gd` (67/0) no longer hard-codes v2.
2. **Second-phone QR hint** — `scripts/ui/pairing_screen.gd` shows, as soon as one slot is taken,
   that a second phone needs its own code («New code» → scan the fresh QR); keys
   `PAIR_SECOND_PHONE` / `PAIR_DROPPED_INPUT` added to `translations/shell.csv` (en/de/ar,
   `localization_validation` 98/0).
3. **`dropped_unrouted` surfaced** — `KingControllerHub` bumps a shared counter on the server
   (`king_controller_server.gd`), the pairing screen shows it whenever inputs arrived for a seat
   with no match running.
4. **`docs/KING_CONTROLLER_SECURITY.md`** written from verified mechanisms only.
5. **Known flake** (`tests/two_human_validation.gd:222`): NOT reproduced — 4 consecutive clean
   runs (41/0 each) at audit time; the earlier 2-of-3 failure rate coincided with an orphaned game
   process competing for resources. Plan: measure again during phase 9; change nothing in gameplay
   code without a reproduction.

Remaining for this phase (next work chunk): the **match adapter contract** —
`scripts/systems/match/match_manager.gd` must provide the read-only methods
`KingControllerMatchData.CONTRACT` requires (`controller_side_for_slot`, `controller_side_info`,
`controller_tactical_state`, `controller_player_name`; the two validated writes
`controller_apply_tactic` / `controller_substitute` land with phase 4). This unblocks phases 3–5.

Acceptance: all suites green, the flake is fixed or precisely documented with the reproduction rate,
the security doc states only implemented mechanisms.

## Phase 2 — Custom controls & layout editor (phone page + server)

Everything here lives on the phone (`assets/controller/controller_page.html`) plus a small server side
for persistence-free profile sync.

1. **Page upgrade to v3** (`PROTOCOL = 3`): a screen switcher (controller stays the primary screen),
   and the `view {view,on}` message so the PC stops streaming data for screens that are not open.
2. **Layout editor**: drag/resize buttons and the stick in a dedicated edit mode (editing mode must
   not emit gameplay input — buttons are disabled while editing); transparency, button size, stick
   size/position/dead-zone/sensitivity sliders; reset-to-default.
3. **Presets**: Classic (current tiered layout), Professional, Simple, Left-handed, Custom. Real
   different geometry, not labels.
4. **Profiles**: layout keyed by `session slot` (slot 0 / slot 1), stored in `localStorage` with a
   version prefix; validated import/export as JSON (no executable code — parse + allowlist).
5. **Accessibility**: larger-buttons mode, high-contrast palette, simplified layout.
6. Tests: extend `tests/controller_page_validation.gd` (static guarantees) and the e2e harness for
   editor interactions; server-side nothing changes (layouts are phone-local by design — document it).

Acceptance: layouts persist across reconnect + reload, each slot has its own layout, all 9 actions
still work, e2e green.

## Phase 3 — Live match dashboard

1. **Server integration**: `king_controller_server.gd` instantiates `KingControllerMatchData`, the
   match attaches/detaches it (lifecycle hooks already exist around match_manager.gd:298); a
   throttled push loop (dashboard ≈ 1 Hz, events immediate) that only sends to sessions whose current
   view is `dashboard` (`view` messages, phase 2).
2. **Page dashboard screen**: score, teams, clock, phase, formations, stats tables, timeline, event
   list. Unavailable statistics (`tackles`) render as "–", never as a number.
3. Tests: new `tests/controller_companion_validation.gd` — pure formatter tests (no match needed) +
   a real-match loopback check that the payload matches `MatchState`/`MatchStats` exactly.

Acceptance: dashboard numbers are the real match numbers (proven by the loopback test against a live
match), no fabricated stats, no traffic when the screen is closed.

## Phase 4 — Tactical management

1. **Server**: route `tactic` messages — derive the side from the *session's slot* (never from the
   phone), call the match adapter (`controller_apply_tactic` / `controller_substitute`), reply
   `tactic_result`. Ownership rule: slot 0 → the human side, slot 1 → the opposing side; a phone can
   never name a team (the validator already strips any such field).
2. **Match adapter**: implement the two write methods in `match_manager.gd` with match-state checks
   (phase, finished, substitution legality) reusing `_swap_player` and `record_substitution`.
3. **Page tactics screen**: formation picker (the presets `FormationData` really has), sliders for
   pressing/line/width, substitution list (bench from the squad), confirm dialogs, `query` on open.
4. Tests: ownership (slot 1 cannot change slot 0's team), invalid value rejection, finished-match
   rejection, illegal substitution rejection; integration test through the real match.

Acceptance: a tactic from the phone changes the real match behaviour, wrong requests get a reason
code, two phones are fully independent.

## Phase 5 — Live mini map

1. **Server**: 2–3 Hz `positions` stream to `map`-view sessions only, using
   `KingControllerMatchData.collect_positions` (already quantised to 0..1000, 22 players < 1 KB).
2. **Page map screen**: pitch canvas, team colours, ball marker, controlled-player highlight; team
   orientation from the `attack` field (second-half side switch is already modelled).
3. Tests: coordinate rounding vs `PitchSpace` bounds, half-switch flip, payload size budget.

Acceptance: positions are the real `global_position` values, the map updates smoothly on a real
phone, no movement commands from the map (the game has no tactical movement system — documented).

## Phase 6 — Training & haptics

1. **Training**: curriculum limited to the 9 real actions + the two-phone setup lesson; the PC sends
   `training {catalogue}` and connection facts; lesson progress lives on the phone (`localStorage`,
   versioned). Difficulty changes the task, not a label.
2. **Haptics**: `navigator.vibrate` guarded by `'vibrate' in navigator`; per-event toggles (press,
   pair, loss, reconnect); never while input is streaming during gameplay; unsupported devices get no
   error and no settings noise.
3. Tests: page validation for the lesson/task wiring (tasks must assert real controller events), a
   haptic feature-detect check.

Acceptance: each lesson validates a real button/stick event, progress persists, translations
complete in en/de/ar.

## Phase 7 — Analytics & performance monitoring

1. **PC manager** (`scripts/systems/controller/` — new `controller_analytics.gd`): extend the
   registry's 6 counters with per-action counts, session durations, disconnect reasons; store the
   phone-reported `telemetry` (rtt_ms is **phone-measured**, labelled as such); versioned JSON under
   `user://` with size limits and a clear-history action; no network transmission.
2. **Analytics screen** on the phone + a small PC view; measured vs estimated values labelled.
3. Tests: counter consistency, persistence round-trip, retention limit, telemetry cap (5 s).

Acceptance: every number traces to a real event; nothing leaves the machine.

## Phase 8 — UI/UX, localisation & accessibility

1. Design tokens: switch the page palette to the brief's exact values (`#111111`, `#D4AF37`,
   `#A8862D`, `#A51E2B`, `#E7E3D8`, `#343A40`) — team colours on the map/dashboard stay football
   colours.
2. Screen structure: one navigation bar, controller first, secondary screens never block gameplay
   input; safe-area + responsive checks at 1280×720 and 2400×1080.
3. Localisation: extend the page's `I18N` for every new screen; Arabic RTL direction per screen;
   pairing-screen additions go through `translations/shell.csv` + `scripts/core/loc.gd`.
4. Tests: page validation gains per-screen translation completeness checks; screenshot sweep
   (screens_ux pattern) for the new screens.

## Phase 9 — Final integration & QA

1. Full-suite regression (all existing + new suites, plus the game's own suites — not only the
   controller ones).
2. Windows verification on this host: adapter selection, firewall prompt flow, two-port binding.
3. **Real-device pass** (needs the owner's phones): QR scan, two phones simultaneously, 10-minute
   continuous session, backgrounding/screen-lock, reconnect storm, haptics. Results recorded as
   observed — simulated runs are labelled as simulated.
4. Documentation set finalised: PROTOCOL / SECURITY / SETUP / USER_GUIDE / TEST_PLAN / QA /
   CHANGELOG + the implementation and release-readiness reports with the honest feature matrix.

---

## Sequencing rule

Phase 1 must land (v3 protocol + match adapter contract + flake fix) before any phone-page feature
(phase 2+) is built on it, because the page upgrade and the streams depend on the server side. Phases
2→8 are sequential per the master prompt; each phase keeps the whole suite green before the next
starts. No commit/push without the owner's explicit approval.
