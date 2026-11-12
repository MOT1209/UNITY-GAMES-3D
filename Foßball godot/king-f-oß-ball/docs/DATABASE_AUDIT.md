# Database audit (Phase 1 of the clubs / players / crests system)

Date: 2026-11-12. Scope: whole repository `Foßball godot/king-f-oß-ball` (Godot 4.7.2).

## Measured baseline (actually executed)
- Command: `tests/run_all.sh <godot 4.7.2 linux>` after `godot --headless --import` (a fresh clone has no `.godot/` class cache; without the import step every suite fails with "Identifier ... not declared").
- Result: **2470 passed, 0 failed** over 29 validation suites (one check reports 1 skipped). Matches `docs/FEATURE_STATUS.md`.
- Importer unit tests: `python3 -m unittest discover -s tools/import_real/tests`: 14 run, **7 skipped** (not passed), 0 failed. The skipped ones were not verified.

## What exists and works
| Area | Evidence |
|---|---|
| `TeamDB` autoload: teams/players dictionaries (O(1) by id), duplicate-id rejection, atomic register, data packs | `scripts/core/team_database.gd` |
| `TeamData` (id, names, colours, 4 kit slots, stadium_id, reputation, budget, squad_ids) with `validate` | `scripts/data/team_data.gd` |
| `PlayerData` single source of truth, 7 core attributes, overall by position weights, potential, contract, appearance dict, development history | `scripts/data/player_data.gd` |
| Pack `real_2025`: 198 clubs, 5,213 players (2,867 real `tm_`, rest generated `gen_`), 5 countries x 2 divisions, 112 nationalities, no duplicate player ids | `data/packs/real_2025/` |
| Default fictional world: 8 clubs, 4 national teams | `data/clubs`, `data/national_teams` |
| Leagues, promotion/relegation, play-offs, validation against TeamDB | `league_def.gd`, `league_pyramid.gd` |
| Deterministic appearance stored on the player, versioned (v2) | `player_appearance.gd` |
| Cards (5 tiers) read live PlayerData; portraits with LRU cache | `player_card_data.gd`, `card_category.gd`, `player_portrait_renderer.gd` |
| Academy + deterministic youth generator (country name pools for 4 fictional + 5 real countries) | `systems/academy/` |
| Transfers keep the player id (only `team_id`/squad change) | `transfer_market.gd` |
| Saves: version 2, migration chain v0->v1->v2, atomic write, all-or-nothing restore | `save_manager.gd` |
| Localization ar/de/en with RTL | `localization.gd`, `translations/` |
| Importer for real data (openfootball CC0 + transfermarkt-datasets) | `tools/import_real/` |

## What is incomplete
1. **Crests.** All 198 real clubs have `logo: ""`, so they all fall back to the same generic shield in club colours. `LogoService` (4 geometric templates + validated import) is used only by `customize_screen.gd` and `club_creator.gd`; no table, HUD, card, profile, transfer or kit surface draws a crest. No crest metadata, variants, cache or provenance.
2. **Countries.** Stored as free text (`"England"`); no id, code, flag, status record.
3. **`TeamData` fields missing** from the brief: full_name, nickname, city, region, founding_year, club_type, league/division link, rivals, detailed finances, stadium name/capacity/level, accent colour, crest id, history.
4. **`PlayerData` fields missing:** first/last name (single `display_name`), nationality id, birth date, height/weight, secondary positions, player_type, contract id. Season- and competition-aware stats exist only as flat counters in `CareerState.player_stats`.
5. **Kits** are colour/pattern data rendered on the 3D jersey, but no crest placement, material or accent and no crest on the shirt.
6. **No management tools** (club/player/crest managers, validation/stat/export/import CLI).
7. **Scale:** 198 clubs / 5,213 players versus target 250-350 / 8,000-12,000.

## Conflicts with the brief and decisions
| Conflict | Decision |
|---|---|
| Brief lists ~22 attributes; engine, cards, overall and training use 7 | Keep the 7 as truth; derive the rest deterministically (`AttributeDetail`); overall untouched |
| "Do not use placeholder logos as final assets" vs no licence for real crests | Original procedural alternative crest per club (shape + generic symbol + club colours), provenance recorded; no official logo shipped |
| Brief: real club data only if verified | Pack already marks estimates (`rating_note`); new fields stay empty unless sourced |
| Brief: fictional clubs must work like real ones | Fictional 3rd tier uses the same `TeamData`/`LeagueDef` path (user decision) |

## Risks
- Save compatibility (mitigated by optional fields + v3 migration + backup).
- Balance drift if overall/attribute formulas change (they will not).
- Licence: Transfermarkt-derived data is development/personal use only (see `data/packs/real_2025/SOURCES.md`); needs legal review before release.
- Memory/time with ~9k players (to be measured in phase 9, not assumed).
- Environment: Godot must `--import` once before headless tests.

## Reuse list
`TeamDB`, `TeamData`/`PlayerData` (extend), `LogoService` (extend into crests), `PlayerAppearance`, `SquadGenerator`, `YouthGenerator.pool_for`, `LeagueDef`/`LeaguePyramid`, `SaveManager.migrate`, `PlayerPortraitRenderer` LRU pattern, `tools/import_real/build_pack.py`, `tests/run_all.sh` (new suites must be added to its `SUITES` list: guard 1 enforces it).
