# KING CONTROLLER — Risk register (Complete Edition)

Companion to [KING_CONTROLLER_AUDIT.md](archive/KING_CONTROLLER_AUDIT.md) and
[KING_CONTROLLER_ROADMAP.md](KING_CONTROLLER_ROADMAP.md). Every entry lists the evidence (file/line)
and the current mitigation. Nothing here is speculative unless marked *observed* or *suspected*.

## R1 — Transport is unencrypted LAN traffic (inherent, documented)

- **Evidence:** `king_controller_server.gd` serves plain HTTP + WebSocket; the architecture doc
  states no TLS. Anyone on the same Wi-Fi can read tokens/credentials or inject inputs.
- **Impact:** high (an attacker on the LAN could steer the match).
- **Mitigation:** trusted-network-only guidance, LAN-only binding, no port forwarding; token is
  one-time, 120 s; credential stored hashed; rate limits per connection. **This risk cannot be
  eliminated in scope** (no TLS in Godot's WS server without external help); it stays documented.
- **Phase:** 1 (doc), 9 (final wording).

## R2 — Pairing token is a convenience barrier, not strong auth (inherent)

- **Evidence:** 8 chars / 40 bits, 5 wrong guesses replace the token, 120 s TTL — documented in
  `controller_protocol.gd` constants and the architecture doc.
- **Mitigation:** one-time use + revocation memory (10 min) + constant-time compare. Residual risk
  accepted and documented.

## R3 — Known flake: two-human "and resume it" (`tests/two_human_validation.gd:222`)

- **Evidence:** failed ~2 of 3 runs in earlier sessions; passed clean in the Phase 0 re-run
  (41/0). *Suspected* resume press processed while the tree is paused, dropping the press edge
  (P9 behaviour by design) so the test's expectation races it.
- **Impact:** medium (CI trust), not a gameplay bug reported by a user.
- **Plan:** reproduce headless ×10 before changing anything; then fix the timing in the test or
  debounce resume in `king_controller_hub.gd`. Tracked as Phase 1 item 3.

## R4 — MAX_MSG_BYTES raised 1024 → 4096 for v3 (in flight, uncommitted)

- **Evidence:** `controller_protocol.gd` diff. The hot path is separately capped
  (`MAX_INPUT_BYTES = 1024`), so input frames never grew.
- **Risk:** a bigger cap admits bigger junk frames; mitigated by the existing per-frame validation,
  per-connection invalid-packet cap (20) and rate limits. Phase 3 must keep real position frames
  well under 1 KB (the quantised encoding already does).

## R5 — Protocol version transition (v2 → v3)

- **Evidence:** `MIN_PROTOCOL_VERSION = 2`; a v2 client is still accepted but must not use v3
  message types (validated, tested in `controller_protocol_validation.gd`).
- **Risk:** an old cached page served by a running game may try a new URL; harmless (v2 accepted).
  The reverse (new page, old game) fails cleanly with `bad_version` and a clear message.
- **Note:** the running game serves the page it cached at `_ready` — an HTML change requires a game
  restart to reach phones (observed).

## R6 — Close-path double close in the server (fragile, harmless today)

- **Evidence:** audit §3 item 3 (`_close_conn` / `_close_by_id` interplay).
- **Plan:** single close owner when the companion streams are wired into the server (phase 3); do
  not touch the working input path before that.

## R7 — Match adapter contract added to `match_manager.gd` (READ-ONLY part done, writes still pending)

- **Evidence (now):** `match_manager.gd` provides the four read-only CONTRACT methods —
  `controller_side_for_slot`, `controller_side_info`, `controller_tactical_state`,
  `controller_player_name` — and answers safely before `begin()`. Verified by the new
  `tests/controller_companion_validation.tscn` (68 checks, 0 failures): the contract is exercised on
  the real `MatchManager` instance and the collectors (`collect_match`, `collect_positions`) read a
  contract-shaped match with a real `MatchState` / `MatchStats` (a real goal through the real
  pipeline). The two validated writes (`controller_apply_tactic`, `controller_substitute`) are still
  missing and land with phase 4 (R8).
- **Impact:** high for phases 3–5 (partially removed: reads are live, writes pending); zero risk
  until a phone calls the missing writes because nothing routes them yet.

## R8 — Substitution / tactic writes can corrupt a live match

- **Evidence:** the engine supports `_swap_player`, `record_substitution`, `Squad.substitute`, but
  match-state checks (phase, legality) live inside the match code paths; the phone path must
  re-validate server-side (slot→side ownership) *and* in the adapter.
- **Plan:** phase 4 with explicit rejection reason codes; tests for finished match, illegal sub,
  cross-team request.

## R9 — Phone-side environment limits (real device)

- **Observed:** low-RAM Android kills browser tabs ("Geringer Speicherplatz"); page reload loses
  `sessionStorage` (the session credential is per-tab by design) → user must re-pair with a fresh
  QR. This is a UX cost, not a bug; the resume window (120 s) covers backgrounding, not tab kills.
- **Mitigation options evaluated in phase 2:** keep resume working, fast re-pair flow, and document
  that a killed tab means a new QR scan.

## R10 — Testing without a physical phone

- **Evidence:** Playwright harness emulates mobile Chromium; a real phone was available
  intermittently (USB dropouts observed; camera QR scan verified once).
- **Impact:** phases 2–6 acceptance criteria *on a real phone* cannot be self-certified; they will
  be marked IMPLEMENTED, REAL DEVICE TEST PENDING in the feature matrix, never COMPLETE AND
  VERIFIED.

## R11 — Fake-data temptation in dashboard/map/analytics

- **Evidence:** `MatchStats` does not measure tackles (audit §3 item 6); `UNAVAILABLE_STATS` guards
  the dashboard; the map uses only real `global_position` values; analytics only aggregate real
  events.
- **Rule:** any number that cannot be traced to the match engine or a measured packet is a bug, not
  a feature.

## R12 — Untracked in-flight work could be lost

- **Evidence:** git status shows `M scripts/systems/controller/controller_protocol.gd`,
  `?? controller_match_data.gd`, `?? docs/archive/KING_CONTROLLER_AUDIT.md`, plus this doc set. Nothing is
  committed yet (per owner instruction commits need explicit approval).
- **Mitigation:** files stay in the working tree; a commit is proposed at the first safe checkpoint
  (end of phase 1).
