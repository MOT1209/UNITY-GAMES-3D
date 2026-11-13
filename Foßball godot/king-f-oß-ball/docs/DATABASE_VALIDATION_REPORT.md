# Database validation report

Produced by `DatabaseTools.validate_all` (the Database screen's "Validate" button and `tools/db_cli.tscn -- validate`), run on the shipped `real_2025` world. Numbers below are from an actual run (2026-11-13), not estimates.

## Result
```
checked: clubs 298, players 8013, crests 306, leagues 5
critical errors: 0
warnings: 4
```
Duration: about 1 s for the validation itself (CLI start-up and pack load included: 2.4 s).

## What is checked (critical = must be 0)
- every club (`TeamData.validate`) and player (`PlayerData.validate`) record;
- club <-> country, league, rival and squad references (`TeamDB.validate_relations`), a player in two squads, a player of an unknown club;
- all kits (`validate_kits`: unreadable numbers, clashing kits);
- crests (valid records, unique designs, no identical image files, asset files present);
- every league definition (`LeagueDef.validate`);
- load errors recorded by `TeamDB.errors` (including refused duplicate ids).
Planted errors are detected (tests): player in two squads, out-of-range attribute, broken club reference, unknown rival, crest file missing, duplicate player id.

## Warnings (real findings, not hidden)
Current run after the clean-up (0 critical errors, **2 warnings**):
1. **13 player names look alike** (for example "Alisson" / "Alysson"): both are real players of the source data, so neither can be renamed. No generated player shares or nearly shares a name with anyone (tested).
2. **198 real clubs have no city / founding year / finances**: no verified source has been added (the download hosts are blocked in the build environment); nothing is invented.

Fixed since the first run (see `DATABASE_CHANGELOG.md`, "Open items clean-up"): 982 duplicate/look-alike generated names (1,015 generated players renamed deterministically with `tools/dedupe_names`), 1,416 players without `nationality_id` (`countries.json` now has every nationality of the pack: 116 countries), and the 298 load-time kit repairs (now stored in the pack files, `tools/export_kit_repairs`).

## Statistics (`stats`)
| | |
|---|---|
| clubs | 298 (198 REAL, 100 FICTIONAL) |
| players | 8,013 (2,867 REAL, 5,146 GENERATED) |
| by country | England 64, Spain 62, Italy 60, France 56, Germany 56 |
| divisions | 15 (tier 1: 18-20 clubs, tier 2: 18-24, tier 3: 20) |
| crests | 306 (198 ORIGINAL_ALTERNATIVE, 108 FICTIONAL), 0 missing files |
| countries | 9 (5 real, 4 fictional regions) |
| players with nationality id | 6,597 |

## Known limits
- Validation does not verify real-world facts (that a real club exists, a real player's data): the real data is taken from its sources and estimates are labelled (see `DATA_SOURCE_AND_LICENSES.md`).
- Name look-alike detection compares names one letter apart; spelling variants further apart are not found.
