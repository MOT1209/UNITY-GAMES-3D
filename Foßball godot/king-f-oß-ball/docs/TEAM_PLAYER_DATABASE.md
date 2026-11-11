# Phase T1/T2 — Team & Player Database

- `scripts/data/team_data.gd` (`TeamData`), `scripts/data/player_data.gd` (`PlayerData`): Resources with `validate()`, `to_dict()`, `from_dict()`. IDs are stable strings; names are display-only.
- `scripts/core/team_database.gd` (autoload `TeamDB`): loads `res://data/clubs`, `res://data/national_teams`, `user://teams` JSON files (`{"team":{...},"players":[...]}`). Invalid records and duplicate ids are rejected atomically and reported in `TeamDB.errors`. Adding a team = adding a JSON file.
- Seed data: 8 fictional clubs + 4 fictional national teams, 23 players each (no real names/logos shipped).
- There is intentionally no manual player creator: players come from team data or the Youth Academy (Phase T4+).
- `scripts/data/attribute_modifiers.gd` (`AttributeModifiers`): attribute → multiplier mapping, neutral (1.0) at rating 50.
  Wired now: `PlayerController.attribute_modifiers` (pace → speed/acceleration), `FootballActions.attribute_modifiers` (shooting/passing → power and aim error, fitness increases error). Both default to `null` = unchanged Phase 2–4 behaviour.
  Defined for later phases (T11): reception radius, duel strength, defending, goalkeeping.
- Tests: `godot --headless --path . res://tests/phaseT1_validation.tscn` (plus phase1–4 suites for regression).

# Phase T3 — Squad & Tactics
- `FormationData` (6 formations, slot = position + team-relative x/y, position-fit table), `TacticsPreset` (mentality, pressing, defensive line, build-up, passing style; `target_position()` and `press_distance()` are the pure functions the Phase T11 team AI will consume), `Squad` (`scripts/systems/squads/squad.gd`).
- `Squad` mutators move a player out of any previous place, so duplicates cannot occur; they return an error string. `validate(db)` checks 11 starters, GK slot, ownership, availability, bench ≤ 7, captain/set-piece takers in the XI.
- Tests: `res://tests/phaseT3_validation.tscn`.
