# KING FOOTBALL — Development Roadmap (repair programme)

Date: 2026-11-17 · Based on the Phase-0 audit of HEAD `9fdb5bb` and `docs/audits/MASTER_AUDIT_2026-11-16.md`.

Ordering rule: stability evidence first, then rules/AI realism, then management depth, then platform verification.
Every item lists its verification gate; nothing is "done" without it.

## Stage 0 — Baseline (this session)
- [x] Fast-forward `main` to `origin/main` (`9fdb5bb`), preserve user changes.
- [x] Re-verify PRs #40/#41/#42 in source (not from docs).
- [x] Create `docs/audit/` audit set.
- [ ] Record Windows quick-suite baseline → `STABILIZATION_REPORT.md` (run in progress).
- [ ] Decide B1 handling: re-measure the two timing budgets on Windows before touching code.

## Stage 1 — Stability & measurement
1. Windows baseline: quick suite; then full suite (or at minimum `career_p1_long_validation` alone) to re-measure
   the 3 failing checks on real hardware timing.
   Gate: numbers recorded in `STABILIZATION_REPORT.md`; budgets re-justified or code fix planned.
2. Add targeted logging for B2 (two-human pause flake) behind a debug flag; repeated runs on Windows.
   Gate: either a captured trace (→ fix) or a documented cannot-reproduce after N runs.

## Stage 2 — Match rules & engine realism (master prompt Phase 2)
1. F3 difficulty decision profiles: decision-noise / option-evaluation parameters per difficulty; physics untouched.
   Gate: `sim_matches.tscn` stat table (shots, pass accuracy, turnovers) per difficulty in FEATURE_STATUS;
   quick suite green; `sim_fingerprint` documented.
   Status 2026-11-17: implemented. `scripts/systems/match/ai_difficulty.gd` (AIDifficulty, NORMAL bit-neutral),
   integrated in `player_ai.gd` (keeper factor ×), `team_ai.gd` (pressers bonus param), `match_ai_driver.gd`
   (profile + shoot-range bonus). Suite: `tests/ai_difficulty_validation.tscn` — 44 passed / 0 failed.
2. TD7 handball prerequisite: design doc for ball-contact body-part tagging (arm hit shapes on player body),
   then implement handball reusing the foul/free-kick/penalty path.
   Gate: new cases in `match_rules_validation`; sim run with handball events in the log.

## Stage 3 — AI depth (Phase 3)
1. Attacking/defensive decision layers consume difficulty profiles from Stage 2.1.
2. Goalkeeper tuning review: measure save rates across difficulties in `sim_matches`; ensure not overpowered.
   Gate: measured table; no regressions in `ai_attack_validation`, `match_flow_validation`.

## Stage 4 — Transfers & career depth (Phases 4–5)
1. F5 agent fees: agent entity/commission booked through the finance ledger on signing/renewal.
   Gate: `transfers_v2_validation` cases + ledger audit assertions.
   Status 2026-11-17: implemented (no agent entity — a deterministic, bounded commission derived from the
   deal money, so nothing new is persisted and SAVE_VERSION stays 3). `scripts/systems/transfers/agent_fees.gd`
   (signing 5% of the fee, bounded 5k–2M; renewal 3% of a year's wage, bounded 1k–1M), booked as a new
   `agent_fee` ledger category via `FinanceLedger.book_agent_fee` at the single choke point `_transfer`
   (covers human buys and AI offers) and in `renew_contract`, with affordability checked before committing.
   Localized with `FIN_AGENT_FEE` in `translations/transfers.csv` (en/de/ar). Suite: `transfers_v2_validation`.
2. Cross-system interaction audit of career menus (squad/fitness/morale/finance actually affecting matches and
   board mood) — targeted at isolated-menu risk found in Phase 0.
   Gate: new integration cases in `career_flow_validation` or a focused new suite.

## Stage 5 — Controller & UX (Phases 7–8)
1. F7 controller layouts/profiles stored client-side (no protocol change); haptics toggle.
   Gate: `controller_page_browser_test.js` + existing controller suites green.
2. Doc drift sweep (B3): reconcile README, MASTER_ROADMAP, plan.md with FEATURE_STATUS.

## Stage 6 — Performance & platforms (Phase 10)
1. Windows: profile with `tools/profile_match.tscn` on real GPU; record FPS budget in `PERFORMANCE_REPORT.md`.
2. Android: run `tools/export_android.sh` on a host with the Android SDK; if a device is available, run the
   `docs/ANDROID_RELEASE.md` checklist and `adb dumpsys gfxinfo`. Otherwise document unverified state honestly.
   Gate: artifacts + checklist results; no silent claims.

## Stage 7 — Release preparation (Phase 12)
1. `release_readiness_validation` green; version bump; README reflects reality.
2. Translation re-import hygiene (commit deliberately after editor sessions).
3. Final report with per-claim evidence.

## Explicitly deferred
- International competitions beyond the existing continental suite (needs design before code).
- TLS for the controller transport (documented threat model accepted for LAN; revisit if public exposure is planned).
- Handball before TD7 prerequisite exists.
