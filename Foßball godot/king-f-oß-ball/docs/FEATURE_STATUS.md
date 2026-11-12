# Feature status

Same status words as CURRENT_PROJECT_AUDIT.md. Tests = headless suites in `tests/`.

## Phase 1 — core stabilization
IMPLEMENTED (tested): results screen, pause menu, match event/statistics pipeline, in-progress match save/load, end-to-end journey
(`phase7_end_to_end_validation`), career/competition update after a match. NEEDS_VERIFICATION: SaveSystem migration chain across all old versions.
## Phase 2 — advanced gameplay
IMPLEMENTED: movement, possession, dribbling, short/long/lob passing, shooting, first touch, goalkeeper, stamina, penalty shootouts.
IMPLEMENTED (tested, `match_rules_validation` 33): tackle (human `tackle` button and AI), attribute-based win chance, fouls (from-behind detection), free kicks (ball on the spot, 9.15 m clearance), penalties (spot and box cleared), yellow/red cards, send-off, HUD notices, statistics, report, results screen, save/restore of red cards. IMPLEMENTED (tested, `match_restarts_validation` 27): ball out of play (throw-in, corner, goal kick), offside (second-last-opponent rule, indirect free kick), counters in stats/report/results screen. MISSING: match injuries, adjustable assists. Limits: throw-ins and goal kicks restart with the ball placed at rest (no throwing animation); offside ignores 'interfering with play' without touching the ball; pending offside passes are not stored in match saves. Limits: the 'referee' is the rule code in `MatchRules`; there is no referee model or advantage rule; free kicks have no wall/set-piece animation; penalties are taken in open play, not as a shoot-out duel.
## Phase 3 — tactics and AI
IMPLEMENTED (tested, `phase8_tactics_validation` 20): formations, mentality, pressing, defensive line, NEW team width, build-up style and passing style now change AI pass choice and pressure response (they were stored but unused before), shoot range from mentality/style, AI manager difficulty (easy never adapts, normal from minute 70, hard from 60 and reads the opponent), opponent analysis from measured match statistics. MISSING: individual player instructions, adaptive tactics that learn across matches, set-piece routines. Limits: the AI reads only the current match's statistics.
## Phase 4 — career / manager
IMPLEMENTED (tested, `phase9_manager_validation` 25): manager profile (reputation, board confidence, contract, trophies, history), board objective from the club's rating rank in its division, season review from the real final position (met / partial / failed, champion, relegation), sacking, contract renewal / expiry, resignation, job offers by reputation (the weakest clubs always hire), taking a job (AppHub switches club and squads), save / load with old-save defaults, Career screen panel (ar/de/en). MISSING: staff management, training management beyond the academy, cup / continental objectives, financial objectives. Limits: only the league position is judged.
## Phase 5 — development / academy
IMPLEMENTED: academy, scouting, training, aging, retirement (`career_longevity_validation` 59). MISSING: mentoring, position changes, regional scouting depth.
## Phase 6 — transfers / finance
IMPLEMENTED (tested, `phase10_finance_validation` 22): ledger-audited finances, weekly sponsorship for every club (grows with reputation), `FinanceLedger.report()` (income / expense by category and week range), seller negotiation with counter-offers and a three-round limit, AI clubs trading in two transfer windows (weeks 1-6, 24-29) through the same `buy()` rules, deterministic, never touching the user's players. Market, contracts, wages, loans, renewals and matchday / prize revenue existed before. MISSING: agents and agent fees, bonuses and release clauses, loan conditions beyond the fee, player-side contract expectations beyond a minimum wage, a UI for the negotiation (it is an API now), a UI for the financial report.
## Phase 7 — world simulation
IMPLEMENTED (tested, `phase11_world_validation` 30): injuries (probability model seeded by match uid and player, reproducible) and suspensions (red card = 1 match, 5 yellows = 1 match) with weekly countdown and save / load, weekly background injuries, lineups repaired automatically (injured reserves no longer invalidate a squad), world event log, news built only from real state (transfers, injuries, bans, champions, promotions, relegations, dismissals) shown on the Career screen in ar/de/en, records computed from stored statistics (top scorer, most appearances, best rating, champions). Earlier: background league simulation, standings, promotion / relegation (`league_pyramid_validation`), AI squad upkeep and transfers (Phase 6). MISSING: club reputation changes over seasons, derby / rivalry news, dedicated news and records screens, suspensions carrying across matches of one week precisely (a ban lasts one calendar week). Limits: the transfer history stores only the week, so old transfers show in the current season.
## Phase 8 — stadium / atmosphere
MISSING (a stadium arena exists): crowd system, weather, day/night, chants.
## Phase 9 — visuals
IMPLEMENTED: appearances, kit patterns, 3D preview, cards, captain's armband. MISSING: badges, hairstyles, accessories, AnimationTree, LOD.
## Phases 10–12
Phase 10: PARTIALLY_IMPLEMENTED (leagues, domestic cups, tournaments; no continental/World Cup). Phase 11 (replay): MISSING. Phase 12 (multiplayer): NOT IMPLEMENTED by design; the architecture is documented in MULTIPLAYER_ARCHITECTURE.md.
## Last full run
2594 checks passed, 0 failed, 37 suites; importer unit tests 14 OK.
