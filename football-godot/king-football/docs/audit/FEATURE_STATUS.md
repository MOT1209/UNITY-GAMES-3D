# KING FOOTBALL — Feature Status (repair-programme snapshot)

Date: 2026-11-17 · HEAD `9fdb5bb` · Labels: **[RAN]** executed this session · **[READ]** source read this session · **[DOC]** documented only.

The long-form, per-round status is `docs/FEATURE_STATUS.md` (57 KB, rounds 1–3 + transfers v2 + career). This file
classifies every system the master repair prompt names, for the current repair cycle. Status words:
Complete+verified / Implemented-needs-improvement / Partial / Broken / Missing / Not-yet-verified.

## Phase 2 — Match engine

| Feature | Status | Evidence |
|---|---|---|
| Match loop, clock, half/full time | Complete+verified | `match_flow_validation` green [DOC prev]; code [READ] |
| Fouls, cards, free kicks | Complete+verified | `match_rules_validation`, `match_restarts_validation` green |
| Advantage rule (PR #40) | Complete+verified | `match_rules.gd:28-219`, 15 checks [READ] |
| Offside (strict ahead, 6 s window) | Complete+verified | commit `6668124`, suite green [DOC] |
| Throw-ins, corners, goal kicks, penalties + shoot-out | Complete+verified | `match_restarts_validation` [DOC prev] |
| Handball | **Missing** | No body-part contact data; engine cannot observe hand contact [READ prev audit, re-confirmed: `match_rules.gd` fouls only from tackle rolls] |
| Passing, through balls, shooting, lob, dribbling, tackling | Implemented-needs-improvement | Systems exist (`gameplay/`, docs PASSING/SHOOTING/DRIBBLING/LOB); feel not measured |
| Sprint + stamina, acceleration/deceleration | Implemented | `player_ai.gd` sprint gate on difficulty [READ]; stamina via attributes [DOC] |
| Difficulty affecting decision quality | **Implemented+verified [RAN]** — `AIDifficulty` profiles now shape pass evaluation, shoot range, keeper speed and press distance on top of the existing think-interval/sprint/reaction timing. NORMAL stays bit-identical; physics/random untouched. `ai_difficulty_validation` 44/0 [RAN] | F3 closed |

## Phase 3 — AI

| Feature | Status |
|---|---|
| Attacking AI (positioning, passing/shooting decisions, profiles) | Implemented — pass profile evaluation, shoot range, relaxed back-pass fallback (`player_ai.gd:88-135`) [READ] |
| Defensive AI (pressing, marking, line) | Implemented [DOC]; depth not audited this session |
| Goalkeeper AI | Implemented [DOC prev audit]; "excessively powerful GK" tuning not measured |
| AI manager tactics changes | Implemented (`manager_ai.gd`, difficulty-scaled) [READ] |
| Difficulty profiles for decision noise | **Implemented+verified [RAN]** — `scripts/systems/match/ai_difficulty.gd` (EASY narrows / HARD widens option space, deterministic, clamped), wired into `MatchAIDriver`, `TeamAI.pressers`, `PlayerAI._keeper`. Suite registered in `run_all.sh` | F3 closed |

## Phase 4–6 — Career, transfers, world

| Feature | Status |
|---|---|
| Career core (profile, board objectives, news, awards) | Complete+verified (`phase9_manager_validation`, `phase12_awards_validation`) [DOC] |
| Career wizard onboarding | Implemented+tested (`career_wizard_validation`) [DOC] |
| Youth academy, scouting, training, dressing room | Implemented+tested (`academy/scouting/training/dressing_room_validation` suites) [DOC] |
| International breaks (call-ups, fatigue, injuries) | Implemented (commit `fdcd02d`, `fdcd02d` C5.1) [DOC] |
| Transfers v2 (listing, search, negotiation, counter-offers, loans, clauses) | Complete+verified (`transfers_v2_validation` 1967-line market) [DOC] |
| Transfer history season labelling | **Fixed+verified [RAN]** — write side `transfer_market.gd:_log()` now stores `"season": cur_season`; read side `news_feed.gd` uses `effective_season = deal_season if > 0 else career.season` (old saves without `season` fall back to current career season); `load_state()` casts `season` to int only when the key is present, keeping old-save round-trips byte-identical (fixed `season:1`→`1.0` JSON float regression). `phase11_world_validation` 33/0 (`_test_transfer_history_season`), `transfers_v2_validation` 180/0 |
| Agent representation / commissions | **Implemented+verified [RAN]** (F5 closed) — `scripts/systems/transfers/agent_fees.gd` (`class_name AgentFees`, deterministic 5% signing / 3% renewal commission, bounded, no new save data), `FinanceLedger.book_agent_fee` + `agent_fee` category, booked from `TransferMarket._transfer`/`renew_contract` with pre-checks. `transfers_v2_validation` 180/0, `phase10_finance_validation` 22/0, `db_migration_validation` 46/0, `world_save_consistency_validation` 171/0 |
| Finance ledger, economy v2, shirt income | Implemented+tested (`phase10_finance_validation`, `economy_v2_validation`) [DOC] |
| League pyramid, promotion/relegation, fixtures, tables | Complete+verified (`league_pyramid_validation`, `phase11_world_validation`) [DOC] |
| Continental competitions | Complete+verified (`phase14_continental_validation`) [DOC] |
| Simulated matches updating the world | Implemented (`match_simulator`, `living_world_validation`) [DOC] |

## Phase 7–9 — Controller, UI, analytics

| Feature | Status |
|---|---|
| KING Controller pairing, sessions, two phones, live data v3 | Complete+verified (`controller_*_validation`, `two_human_validation`) [DOC] |
| Controller custom layouts / profiles / haptics / tactics-from-phone | Stale report claim — layouts/profiles/haptics already existed (`controller_settings.gd`, Haptics Off/Light/Strong). F7 added a LAN/no-TLS threat-model security note to `assets/controller/controller_page.html` (en/de/ar) + 8 checks in `controller_page_browser_test.js` (28/0). TLS itself deliberately deferred |
| Menus (hub, career, squad, transfers, competitions, settings, wizard) | Implemented+tested (`screens_ux_validation`, `ui_layout_validation`, `ui_scroll_validation`, ar+en screenshots) [DOC] |
| Arabic RTL + de/en localization | Complete+verified (`localization_validation`, `arabic_ui_validation`, `phase7_localization_validation`) [DOC] |
| Match analytics (PR #41): xG, shot map, heatmaps, results views | Complete+verified this session [READ] — `expected_goals.gd` documented model, `match_report.heatmaps()`, `MatchResultsView` heatmap/shot-map views, xG shown only when report declares `ESTIMATED` |
| Passing network / passing map | **Implemented+verified [RAN]** (F4 closed) — `scripts/systems/match/passing_network.gd` (`class_name PassingNetwork`) builds nodes/edges from real logged passes. Pass events recorded in dedicated `MatchState.pass_events` (never the shared `events` log, so commentary/sound/crowd/referee/controller stay clean); `MatchReport` stores a compact `passing_network` (not raw events, avoiding F11 save bloat). Results panel gated by `_has_pass_data()`. `passing_network_validation` 39/0, `match_analytics` 38/0, `match_event_log` 27/0, `controller_companion` 68/0; Godot `--import` exit 0; registered in `run_all.sh` |
| Match commentary (event-driven, ar/de/en) | Complete+verified (`match_commentary_validation`, 64-line dictionary) [DOC/READ] |
| Replay system (buffer, director, player) | Implemented (`replay_buffer.gd`, `replay_player.gd`) [READ] |

## Phase 10–12 — Platforms, testing, release

| Feature | Status |
|---|---|
| Windows build/runtime | Not-yet-verified on real GPU — headless + CI software rendering only |
| Android presets + export script | Present [DOC] (min SDK 24 / target 36, Gradle build on, arm64+v7) — **no Gradle export ever run, no device test** (F8) |
| Touch input layer | Implemented+tested (`mobile_input_validation`) [DOC] |
| Automated tests (99 suites) | Complete+verified; Windows baseline being recorded this session [RAN] |
| Save/load v3 + migrations | Complete+verified (`db_migration_validation`, `world_save_consistency_validation`) [DOC]; size risk F11 |
| Release readiness checks | Implemented (`release_readiness_validation`) [DOC] — final release blocked on device verification |

## Known broken

Nothing known broken at HEAD. The 3 historical full-suite failures (`career_p1_long_validation`: save-size
assertion + 2 timing budgets) remain the only failing checks, measured on CI software rendering.
