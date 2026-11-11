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

# Phase T4 — Youth Academy foundation
- `AcademyConfig`: age groups U15 (14–15), U17 (16–17), U19 (18–19), capacity 20 each, traits list. The only place age rules live.
- `YouthGenerator.generate(seed, index, ...)`: deterministic per (seed, index). Current ability rises with age; potential is drawn independently (gap shrinks with age) so high potential ≠ high current; facilities `quality` nudges potential only slightly. Position biases, goalkeepers, 1–2 development traits, initial history entry.
- `Academy`: `generate_intake()` registers prospects in `TeamDB` as `YOUTH` (not in first-team `squad_ids`), enforces group capacity, rejects clones. Saved state = seed + next_index + roster ids, so loading never regenerates players. `PlayerData` gained `traits`; `TeamDB.register_player()` added.
- Tests: `res://tests/phaseT4_validation.tscn`.

# Phase T5 — Scouting, training, progression
- `ProgressionModel` (pure, deterministic): weekly fractional points = base × age × headroom-to-potential × traits × fitness × facilities × intensity × diminishing returns. A point is granted only if overall stays ≤ potential and attribute ≤ 99. History entries per gain; `development_report()`.
- `TrainingSystem`: 7 categories (one per attribute), group focus + individual override, intensity (also drives fitness cost/recovery), `advance_week()`, `age_up()` (returns over-age ids for the Phase T6 decision), save/load.
- `ScoutingSystem`: scouts (quality, weekly cost), regional missions (cost charged from `Academy.budget`), discoveries into an unowned pool, reports with potential estimate + margin (reliability = 70 % scout quality + 30 % facilities), discovery history, `sign_prospect()` (budget + capacity checks), save/load.
- Tests: `res://tests/phaseT5_validation.tscn`. Budgets are plain academy numbers now; Phase T9 moves them to the club ledger.
