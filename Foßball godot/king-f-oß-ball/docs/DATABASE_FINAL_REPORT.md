# KING FOOTBALL — database system: final report (phase 10)

State: `main` after PR #17 (phases 1-9 merged). Godot 4.7.2 headless.

## Result at a glance
| Item | Target (master prompt) | Delivered (measured) |
|---|---|---|
| Clubs | 250-350 | 298 (198 real, 100 fictional third tier) |
| Players | 8,000-12,000 | 8,013 (2,867 real `tm_*`, 5,146 generated) |
| Countries / leagues | - | 116 countries (112 real nationalities + 4 fictional regions), 5 leagues, 15 divisions, 3 tiers each |
| Crests | original, no official crests | 306 procedurally drawn originals (licence status `ORIGINAL_NOT_AFFILIATED`), 5 variants, LRU cache |
| Stable ids | yes | club/player ids never change (checked across transfer, loan, promotion, save/load) |
| Save format | backward compatible | v3, chain v0 -> v1 -> v2 -> v3, `.v2.bak` backup |
| Tools | clubs/players/crests/database | in-game "Database tools" screen (4 tabs) + `tools/db_cli` |
| Languages | ar (RTL), de, en | all new keys in 3 languages; no missing cells in the translation files (shell.csv has 8 empty cells that are Arabic-only plural forms by design) |

## Verification actually run
- Full `tests/run_all.sh` on the final merged `main` (3db413d): **3243 checks passed, 0 failed, 0 suites failed** (earlier run on the phase 9 branch before the merge with main: 3222 passed, 0 failed).
- `db_cli validate` on the real world: 298 clubs, 8,013 players, 306 crests, 5 leagues; **0 critical errors, 4 warnings** (below).
- `python3 -m unittest tools/import_real/tests`: 14 tests, 7 pass, **7 skipped** ("run fetch.py first": they need the downloaded source data, which was not fetched here). They were not run.

## Honest limits and open items
1. **Validator warnings (not errors), after the clean-up:** 2. 13 player names look alike, all between two *real* players (cannot be renamed); 198 real clubs have no city, founding year or finances because no verified source could be added (nothing is invented). Fixed in the clean-up: duplicate generated names (1,015 renamed), missing `nationality_id` (116 countries now), load-time kit repairs (stored in the pack files).
2. **Real data:** the 2,867 real players come from the existing Transfermarkt-derived pack, for personal/development use; see `DATA_SOURCE_AND_LICENSES.md`. No official crests are included or imitated.
3. **Not measured:** portrait rendering and in-match frame time (need a GPU; the container is headless). Not visually inspected: the German layout of the Database tools screen.
4. **Demo scene:** `TeamPlayer.setup` has no database players; its look is a fixed seed per team and number. Left on purpose.
5. **Importer unit tests:** 7 of 14 still skipped; `fetch.py` gets HTTP 403 from the build environment's proxy, so the source data cannot be downloaded here. Run `python3 tools/import_real/fetch.py` on a machine with access.
6. **Detailed attributes** (18) are derived from the 7 core attributes, not stored; the overall rating and match balance are unchanged. This is a deliberate decision recorded in `DATABASE_AUDIT.md`.

## Document map
Audit `DATABASE_AUDIT` · architecture `DATABASE_ARCHITECTURE` · migration `DATABASE_MIGRATION_PLAN` · clubs `CLUB_DATABASE_SPEC` · players `PLAYER_DATABASE_SPEC` · crests `CREST_SYSTEM_SPEC` · kits `KIT_SYSTEM_SPEC` · generation `DATA_GENERATION_SPEC` · sources and licences `DATA_SOURCE_AND_LICENSES` · tools `DATABASE_TOOLS_SPEC` · validation `DATABASE_VALIDATION_REPORT` · integration `DATABASE_INTEGRATION_REPORT` · performance `PERFORMANCE_REPORT` · history `DATABASE_CHANGELOG`.
