# Feature status

Same status words as CURRENT_PROJECT_AUDIT.md. Tests = headless suites in `tests/`.

## Phase 1 — core stabilization
IMPLEMENTED (tested): results screen, pause menu, match event/statistics pipeline, in-progress match save/load, end-to-end journey
(`phase7_end_to_end_validation`), career/competition update after a match. NEEDS_VERIFICATION: SaveSystem migration chain across all old versions.
## Phase 2 — advanced gameplay
IMPLEMENTED: movement, possession, dribbling, short/long/lob passing, shooting, first touch, goalkeeper, stamina, penalty shootouts.
MISSING: tackle action, physical challenges, fouls, free kicks, corners, throw-ins, offside, referee, match injuries, adjustable assists.
## Phase 3 — tactics and AI
PARTIALLY_IMPLEMENTED: formations, tactics presets, manager substitutions. MISSING: opponent analysis, adaptive AI, difficulty scaling, player instructions.
## Phase 4 — career / manager
PARTIALLY_IMPLEMENTED: career state, club selection, finance. MISSING: manager profile, board objectives, reputation, job offers, staff.
## Phase 5 — development / academy
IMPLEMENTED: academy, scouting, training, aging, retirement (`career_longevity_validation` 59). MISSING: mentoring, position changes, regional scouting depth.
## Phase 6 — transfers / finance
PARTIALLY_IMPLEMENTED: market, contracts, ledger. MISSING: negotiations, agents, bonuses, sponsorship, matchday revenue.
## Phase 7 — world simulation
PARTIALLY_IMPLEMENTED: background simulation, standings, promotion/relegation (`league_pyramid_validation`). MISSING: news, historical records, injuries/suspensions.
## Phase 8 — stadium / atmosphere
MISSING (a stadium arena exists): crowd system, weather, day/night, chants.
## Phase 9 — visuals
IMPLEMENTED: appearances, kit patterns, 3D preview, cards, captain's armband. MISSING: badges, hairstyles, accessories, AnimationTree, LOD.
## Phases 10–12
Phase 10: PARTIALLY_IMPLEMENTED (leagues, domestic cups, tournaments; no continental/World Cup). Phase 11 (replay): MISSING. Phase 12 (multiplayer): MISSING, by design.
## Last full run
2437 checks passed, 0 failed, 31 suites; importer unit tests 14 OK.
