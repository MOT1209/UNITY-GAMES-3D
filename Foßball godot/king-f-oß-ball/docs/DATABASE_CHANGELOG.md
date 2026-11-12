# Database changelog

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
