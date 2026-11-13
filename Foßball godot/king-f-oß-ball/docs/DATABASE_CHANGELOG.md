# Database changelog

## Phase 9 - save migration and performance
- `SAVE_VERSION = 3`, `_migrate_2_to_3`, `backup_if_outdated` (`.v2.bak`), malformed-block validation, single-parse restore. Suite `db_migration_validation` (46 checks).
- Measured with `tools/profile_db` (`DbProfiler`); three real bottlenecks fixed: crest cache thrash (entry limit 256 < 298 clubs -> byte-budget LRU, 1024 entries / 24 MB), kit drawing (row-band culling, pixel-identical; 1x kit in long lists), double parsing in `restore`. Suite `db_performance_validation` (16 checks, generous limits). `docs/PERFORMANCE_REPORT.md`.

## Phase 8 - full integration
- New suite `db_integration_validation` (54 checks): club -> match, transfer + loan, youth promotion -> match, crest change across screens, save and reload, a career with a fictional third-tier club.
- Gap found and fixed: alternative crest designs added in play were not saved (a club pointing at one fell back to its original crest after a reload). `CrestRegistry.alternatives_to_dict / load_alternatives`, saved under `"crests"` in the save file (optional key, old saves unaffected).
- `docs/DATABASE_INTEGRATION_REPORT.md`.

## Phase 7 - management tools
- `DatabaseTools` (stats, validate_all, search, profiles, metadata editing, export/import/generate), screen "Database tools" (clubs / players / crests / database tabs), `tools/db_cli`, 52 translation keys (ar/de/en), `ScreenRegistry` now 22 screens (`phaseT10_validation` updated).
- `NameIndex` look-alike check made linear time (`within_one_edit`).
- `DATABASE_VALIDATION_REPORT.md` (real run: 0 critical errors, 4 warnings), `DATABASE_TOOLS_SPEC.md`; suite `db_tools_validation` (85 checks).

## Phase 6 - generation engine
- New `scripts/systems/generation/` (NameBank, NameIndex, ClubGenerator, WorldGenerator), `data/generation/config.json`, tools `generate_world`, pack layer `data/packs/real_2025/fictional/` (100 clubs, 2,800 players), third division in all 5 leagues, 100 more crests (306), `TeamDB.skip_fictional_layer`, `YouthGenerator.pool_for` uses NameBank.
- Existing tests that assumed 198 clubs / two tiers were updated (`league_pyramid_validation`, db_* suites); `run_all.sh` suite timeout raised to 1500 s.
- New suite `db_generation_validation` (60 checks).

## Phase 5 - kits and visual identity
- `KitEditor.problems / repair / readable_on`, `TeamDB.kit_repairs / validate_kits` (31 clashing away kits, 3 goalkeeper clashes, ~390 unreadable numbers repaired at load).
- `TeamKit.crest / for_team`, `PlayerCharacterVisual.apply_crest` (badge on the chest bone), match and portrait kits carry the crest, portrait key includes the crest.
- New suite `db_kits_validation` (34 checks); `tools/model_view` crest mode.

## Phase 4 - original crest system
- New `scripts/systems/crests/` (CrestData, CrestSymbols, CrestRenderer, CrestGenerator, CrestRegistry, CrestCache, CrestService), `data/crests/crests.json` (206) + `blocklist.json`, `TeamDB.crests`.
- `UIKit.crest / team_cell` (tables accept Control cells); crests in team select, details, career, leagues, standings, transfers, results, match HUD and player cards.
- Tools `generate_crests`, `crest_gallery`, `kit_gallery`; suite `db_crests_validation` (83 checks).
- Review feedback: crest rendering polished; kit preview now draws a real kit (`KitRenderer`, `KitService`) instead of colour blocks; `phaseT10_validation` updated for that (the old check counted 4 colour swatches). Full run: 2692 passed, 0 failed.

## Squad management as a pitch (user request, between phases 3 and 4)
- New `SquadPitch` (starting XI as cards on a dark pitch, placed by formation coordinates, LTR-pinned), `PlayerCard.minimal`/`relayout()`, slot picker popup using the unchanged `Squad` API; dropdown list kept behind a toggle (existing tests/controls intact).
- New tool `tools/squad_shot`, suite `squad_pitch_validation` (26 checks). Full run: 2581 passed, 0 failed.

## Phase 3 - unified player database
- `PlayerData`: first/last name, nationality id, birth year, height/weight, secondary positions, player type, contract id (all optional, derived or empty for real players).
- New `AttributeDetail` (18 derived attributes, deterministic, overall unchanged), `TeamDB.link_player`.
- `CareerState.season_stats` + `stats_for`; `record_match(report, competition_id)`; `app_hub` passes the fixture's competition id.
- New suite `db_players_validation` (50 checks).

## Phase 2 - unified club database
- Added `data/countries.json`, `CountryData`, `TeamDB.load_countries / country_id_for / link_team / link_leagues / validate_relations`.
- Extended `TeamData` (identity, football, finance, stadium, crest id, history) with optional fields; `ClubType` enum.
- `ClubCreator` marks user clubs CUSTOM; `SaveManager.restore` links clubs of older saves.
- New suite `db_clubs_validation` (35 checks). Full run: 2505 passed, 0 failed.

## Phase 1 - audit and architecture
- `DATABASE_AUDIT.md`, `DATABASE_ARCHITECTURE.md`, `DATABASE_MIGRATION_PLAN.md`. Baseline 2470 passed, 0 failed.
