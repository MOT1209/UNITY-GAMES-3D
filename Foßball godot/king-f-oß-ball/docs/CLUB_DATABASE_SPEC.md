# Club database spec (implemented in database phase 2)

Source of truth: `TeamData` (`scripts/data/team_data.gd`), loaded and indexed by `TeamDB` (`scripts/core/team_database.gd`). Countries: `data/countries.json` -> `CountryData`.

## Club fields
| Group | Fields |
|---|---|
| Identity (pre-existing) | `id` (stable), `display_name`, `short_name`, `category`, `is_real`, `country` (text), `logo_path`, `primary_color`, `secondary_color`, `kits`, `stadium_id`, `reputation`, `budget`, `competition_ids`, `squad_ids` |
| Identity (new, all optional) | `full_name`, `nickname`, `city`, `region`, `founding_year` (0 = unknown), `club_type` (REAL / FICTIONAL / CUSTOM), `country_id`, `description` |
| Football (new) | `league_id` (division id, e.g. `eng_d1`), `division` (tier, 1 = top), `manager_id`, `rival_club_ids` |
| Finance (new) | `transfer_budget`, `wage_budget`, `current_balance`, `weekly_expenses`, `sponsorship_income`; `financial_status()` is derived (UNKNOWN / CRISIS / TIGHT / HEALTHY) |
| Stadium / visual (new) | `stadium_name`, `stadium_capacity`, `stadium_level` (1-5), `crest_id`, `accent_color` |
| History (new) | `history` dictionary (`historical_leagues`, `trophies`, `promotions`, `relegations`, `records`) |

Not yet filled for any real club: `full_name`, `nickname`, `city`, `region`, `founding_year`, finance block, `stadium_name/capacity`, `rival_club_ids`, `history`. They stay empty until a verified source exists; nothing is invented. `squad_id` of the brief is `squad_ids` (the list itself).

## Derived at load (never overwrite an existing value)
- `country_id` from `country` via `countries.json` (`TeamDB.link_team`), also applied when a save is restored.
- `crest_id = "crest_" + id` for clubs (the crest itself arrives in phase 4).
- `league_id` / `division` from the loaded pack's leagues (`TeamDB.link_leagues`).
- `club_type`: stored value, else REAL when `real` is true, else FICTIONAL; `ClubCreator` sets CUSTOM.

## Countries (`data/countries.json`)
Fields: `country_id`, `country_name`, `country_code` (3 letters, unique), `nationality_name`, `flag_asset` ("" = none yet), `region`, `database_status` (REAL_VERIFIED / REAL_PARTIAL / FICTIONAL / PLANNED). Shipped: England, Spain, Germany, Italy, France (REAL_VERIFIED) and the 4 fictional regions. Adding a country = one JSON record.

## Validation
- `TeamData.validate()`: ids, names, ranges, money, stadium, rival not self, kits, duplicate squad entries.
- `TeamDB.validate_relations()`: club country known and consistent with `country_id`; `league_id` agrees with the loaded leagues; rivals exist; squad players exist and carry the squad's `team_id` (loaned players excepted).
- Tests: `tests/db_clubs_validation.tscn` (35 checks), in `tests/run_all.sh`.

## Compatibility
All new keys are optional on load; `to_dict`/`from_dict` round-trip is identical; ids unchanged. Save format change (v3) is planned for phase 9 (`DATABASE_MIGRATION_PLAN.md`); until then the new keys are simply saved and old saves are linked on restore.
