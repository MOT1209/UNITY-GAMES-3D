# Current project audit (2026-11-12)

Verified by inspecting `scripts/` (about 16.4k lines of GDScript, 101 `class_name` scripts, 4 autoloads) and by running
`tests/run_all.sh` (now 2470 checks, 0 failed, 32 suites). Status words: IMPLEMENTED, PARTIALLY_IMPLEMENTED, MISSING, BROKEN,
NEEDS_OPTIMIZATION, NEEDS_VERIFICATION. "Proof" is the file or test that backs the status.

| # | Area | Status | Proof / note |
|---|------|--------|--------------|
| 1 | Repository structure | IMPLEMENTED | `scripts/{ball,camera,core,data,gameplay,player,players,teams,ui,environment,systems/*}`, 10 scene folders |
| 2 | Project configuration | IMPLEMENTED | `project.godot`, autoloads Loc, GameManager, TeamDB, AppHub |
| 3 | Scenes and dependencies | NEEDS_VERIFICATION | no automatic broken-reference scan exists; every suite loads its scenes |
| 4 | Scripts and autoloads | IMPLEMENTED | 4 autoloads; `AppHub` and `GameManager` are large singletons (see TECHNICAL_DEBT) |
| 5 | PlayerData and Player ID | IMPLEMENTED | `scripts/data`, `scripts/players`; `player_visual_integration_validation` (72) |
| 6 | Match engine | IMPLEMENTED | `systems/match/*` (14 scripts); `match_flow_validation` 77, `phase7_end_to_end_validation` 35 |
| 7 | Ball physics | IMPLEMENTED | `scripts/ball`; `phase3_validation` |
| 8 | Player movement and animation | IMPLEMENTED | `scripts/player`, `scripts/players/player_animation_library.gd`; `player_visual_validation` 137 |
| 9 | Football AI | PARTIALLY_IMPLEMENTED | `player_ai.gd`, `team_ai.gd`, `manager_ai.gd`; no opponent analysis, no adaptive difficulty |
| 10 | Teams and squads | IMPLEMENTED | `systems/teams`, `systems/squads` |
| 11 | Competitions and league simulation | IMPLEMENTED | `systems/competitions`; `league_pyramid_validation` 110 |
| 12 | Career and finance | PARTIALLY_IMPLEMENTED | `career_state.gd`, `finance_ledger.gd` (108 lines); no manager profile, board, reputation, sponsors |
| 13 | Youth Academy | IMPLEMENTED | `systems/academy`, `scouting`, `promotion` |
| 14 | Transfer market | PARTIALLY_IMPLEMENTED | `transfer_market.gd`; AI-club transfers in-season, agents, release clauses, loans: NEEDS_VERIFICATION |
| 15 | Save and load | IMPLEMENTED | `save_manager.gd` (versioned), `match_save.gd`; round trip in end-to-end test |
| 16 | Player cards and collection | IMPLEMENTED | `ui/cards`; `player_card_validation` 82 (1 skipped without a window) |
| 17 | Localization and RTL | IMPLEMENTED | `Loc`, `ErrorText`; `localization_validation` 90, `phase7_localization_validation` 19 |
| 18 | UI and menus | IMPLEMENTED | 21 screens in `ui/screens`; no controller navigation test: NEEDS_VERIFICATION |
| 19 | Test suites | IMPLEMENTED | 31 suites, `run_all.sh` guards that every suite is listed |
| 20 | Performance | NEEDS_OPTIMIZATION | software-renderer numbers only, see PHASE7_PERFORMANCE_REPORT.md; real GPU NOT MEASURED |
| 21 | Missing systems | MISSING | injuries, weather, crowd, replay, commentary, badges, networking |
| 22 | Duplicate / obsolete code | NEEDS_VERIFICATION | `scripts/player` vs `scripts/players` split is historical (controller vs data/visual); not merged |
| 23 | Broken references | NEEDS_VERIFICATION | none seen at runtime; no static scan |
| 24 | Documentation consistency | PARTIALLY_IMPLEMENTED | README says Phase 5+ "not started" in an older paragraph; Phase 7 docs are current |
