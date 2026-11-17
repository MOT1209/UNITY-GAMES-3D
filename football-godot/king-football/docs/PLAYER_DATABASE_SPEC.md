# Player database spec (implemented in database phase 3)

Source of truth: `PlayerData` (`scripts/data/player_data.gd`), indexed by id in `TeamDB.players`. Every system (match engine, squads, cards, transfers, academy, career) holds the SAME object; identity is the permanent `id`, never the name.

## Fields
| Group | Fields |
|---|---|
| Pre-existing | `id`, `display_name`, `age`, `nationality` (text), `shirt_number`, `position`, `preferred_foot`, 7 core attributes, `potential`, `experience`, `fitness`, `stamina`, `morale`, `development_history`, `growth_progress`, `traits`, `appearance`, `team_id`, `contract_years`, `salary`, `transfer_value`, `status`, `loan_parent`, `loan_weeks_left` |
| New identity (all optional) | `first_name`, `last_name` (derived from `display_name` when not stored; `display_name` stays the full display name), `nationality_id`, `birth_year` (0 = unknown), `height_cm`, `weight_kg` (0 = unknown), `secondary_positions`, `player_type` (REAL / GENERATED / YOUTH), `contract_id` |

`player_type` follows the id prefix: `tm_*` REAL (real-world data pack), `yth_*` YOUTH (academy; stays YOUTH after promotion, it describes origin), everything else GENERATED.

## Rules for real data
Nothing is invented: no birth year, height, weight or secondary position is generated for real players. `get_height_cm()` / `get_weight_kg()` return the stored value, otherwise a deterministic estimate from the stored appearance (`AttributeDetail.estimated_*`), clearly an estimate. `nationality_id` is set only when the nationality is in `data/countries.json` (9 countries today; the other nationalities keep an empty id).

## Attribute model
The 7 core attributes (`pace, shooting, passing, dribbling, defending, physical, goalkeeping`) remain the only stored ratings and the only input of `get_overall()`, the match engine, cards and training. `AttributeDetail.for_player(p)` returns the 18 attributes of the specification (pace, acceleration, sprint_speed, shooting, finishing, passing, vision, dribbling, ball_control, defending, tackling, physicality, stamina, agility, balance, reactions, positioning, composure): core ones pass through, the rest are parent attribute(s) averaged + a stable offset of +-6 from `hash(player_id:attribute)`, clamped 1..99. Derived, never stored, never fed back into the game.

## Season- and competition-aware statistics
`CareerState.season_stats`: `player_id -> {"<season>:<competition_id>": {apps, goals, assists, saves, rating_sum, motm, yellow, red, clean_sheets}}`, friendlies under `friendly`. Updated in `record_match(report, competition_id)` (idempotent by match uid) next to the unchanged all-time `player_stats`; `stats_for(player_id, season, competition_id = "")` sums per season or competition. Saved in the career dictionary; older careers load with empty season stats (history before this change is only in the all-time counters). Yellow/red cards come from the per-player report entries; a clean sheet is counted for a goalkeeper or defender (GK, CB, LB, RB) who played when their side conceded nothing. Counters missing in older saves read as 0 (the migrated `legacy` bucket has no cards or clean sheets).

## Linking and validation
- `TeamDB.link_player(p)`: fills `nationality_id`, names and the id-based type without overwriting stored values; called on register and on save restore.
- `PlayerData.validate()`: adds birth year (1950-2100), height (140-220), weight (40-130) and secondary-position checks (valid, not the primary).
- `TeamDB.validate_relations()` (phase 2) covers squad/player consistency.
- Tests: `tests/db_players_validation.tscn` (50 checks): JSON round trip, validation, detailed attributes (deterministic, bounds, no overall change), real pack (5213 players, 2867 REAL), transfer keeps object/id/appearance and updates the card's club, academy intake + promotion keep identity, season stats, old-record and old-save compatibility.

## Not done in this phase (documented, not skipped silently)
`appearance_version` already exists (`PlayerAppearance.VERSION`); `face_id`/`facial_features` are the existing face index fields. Per-competition cards/clean sheets (above). Save format v3 migration is phase 9.
