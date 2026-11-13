# Database migration plan

Current save format: `SaveManager.SAVE_VERSION = 3` (v0 -> v1 -> v2 -> v3 chain in `SaveManager.migrate`). **Implemented in phase 9** (see the bottom of this file).

## Principles
- IDs never change (club ids, player ids). Migration only adds fields.
- All new fields are optional with defaults, so v2 saves load even without migration code paths being hit.
- `SaveManager.restore` stays all-or-nothing: the live database is untouched if validation fails.
- A backup `<save>.v2.bak` is written before a save is upgraded and rewritten. Nothing is overwritten silently.
- Derived data (detailed attributes, crest images) is NOT stored; it is recomputed from stored seeds, so it cannot drift.

## v2 -> v3 steps
1. Teams: add `country_id` (from the country name via `countries.json`), `club_type` (REAL if `real`, else FICTIONAL), `crest_id = "crest_" + id`, defaults for the new club fields. Existing `logo` kept as a custom override.
2. Players: split `name` into `first_name`/`last_name` (last space-separated token; `name` stays the display name), `nationality_id` from nationality, `player_type` from id prefix (`tm_` REAL, `youth_` YOUTH, else GENERATED). Existing `appearance` is kept as is.
3. Career stats (`extras.career.player_stats`): re-key flat counters under `{season, competition_id}`; the old totals are kept as the `legacy` bucket so no data is lost.
4. Bump `save_version` to 3.

## Data pack changes
- `real_2025` gains `crests/` and a fictional third tier. Existing ids unchanged; new ids use the `fic_` prefix, so no collision.
- `build_pack.py` stays the generator for real data; new fields come from `club_meta.json` only where a verified source exists.

## Tests (executed per phase)
- Build a real v2 save with the current game, migrate, compare every id, stat and appearance field byte-for-byte for unchanged fields.
- Corrupt/incomplete records are reported, not crashed on; a failed migration leaves the original file and its backup intact.

## What was implemented (phase 9)
- `SaveManager._migrate_2_to_3`: teams get `club_type` (from `real`), `country_id` (via `countries.json`), `crest_id = "crest_" + id` (clubs only); players get `first_name`/`last_name` (`PlayerData.split_name`), `nationality_id`, `player_type`; the `crests` list is added; flat career `player_stats` are copied into `season_stats[pid]["0:legacy"]` (the flat counters stay as they were). Values that already exist are never overwritten.
- `SaveManager.backup_if_outdated(path)`: writes `<file>.v<N>.bak` (byte copy) before an older save is saved over or loaded; an existing backup is never replaced; corrupt files are ignored; a failed copy returns an error and `AppHub.save_game/load_game` stop. Called from both.
- `SaveManager.validate` now also rejects malformed blocks (non-list teams/players, non-dict records, bad academies/scouting/training/squads) and parses each record once; `restore` reuses the parsed result. A rejected save leaves the live database untouched.
- Alternative crest designs are saved under `"crests"` (optional key).
- Tested by `tests/db_migration_validation` (46 checks): real v2 fixture, v0/v1 chain, byte-identical backup, corrupt/newer/duplicate/missing cases.
