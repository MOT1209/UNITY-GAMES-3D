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

# Phase T6 — Promotion & save/load
- `PromotionSystem.promote()` validates first, then mutates: same `player_id`, attributes and history; status YOUTH→ACTIVE; removed from `Academy.roster_ids`, appended to `TeamData.squad_ids`; auto or explicit unique shirt number; contract + salary; "promoted" history entry. Rejections: unknown, already first team, not in this academy, under `AcademyConfig.MIN_PROMOTION_AGE` (16), number taken/out of range. Reversal only via `release_from_squad()` / `release_youth()` (free agent); loans/transfers in Phase T9.
- `SaveManager` (static, `scripts/core/save_manager.gd`): `capture()` → versioned dict (teams, players, academies, scouting, training, squads, extras); `write_file()` atomic via temp + rename; `read_file()`; `migrate()` (v0→v1; newer versions refused); `validate()` (duplicates, dangling references, player in academy and squad, attribute ranges); `restore()` is all-or-nothing.
- Tests: `res://tests/phaseT6_validation.tscn`.

# Phase T7 — Team customization
- `ClubCreator.create_club()` builds a validated fictional club (id `club_<slug>`), generates a believable 23-man squad from a strength level (`SquadGenerator`, deterministic — no manual player editor), registers it in `TeamDB` and persists it to `user://teams/<id>.json` (loaded automatically on start-up). `export_team`/`import_team` use the same JSON format; `delete_user_club` only removes user-created clubs.
- `KitEditor`: home/away/third/goalkeeper kits × main/secondary/accent/shorts/socks/number colors + pattern; validation, `preview()` (reads the saved dictionary), clash detection and away-kit selection.
- `LogoService`: original procedural templates (shield/circle/diamond/stripes), validated import (png/jpg/webp, ≤ 2 MB, 32–4096 px, resized to 256), always-usable `resolve()` fallback. No protected logos shipped.
- Tests: `res://tests/phaseT7_validation.tscn`.

# Phase T8 — Competitions
- `MatchResult` (validated; penalties only for drawn matches), `FixtureGenerator.round_robin()` (circle method, double round robin, byes for odd counts, home/away streaks ≤ 3), `LeagueTable` (points / GD / goals scored / id tie-break, idempotent per `match_id`).
- `Competition`: `create_league`, `create_knockout` (seeded pairing, byes for non power-of-two, optional third-place match), `create_group_knockout` (even group count, top 2 advance, A1–B2 crossover). `submit_result()` only accepts results for its own unplayed fixtures with matching teams; knockout draws need penalties; each knockout round is generated when the previous one completes. `standings()`, `bracket()`, `awards()`, `history`, `promotion_relegation()`, full `to_dict()/from_dict()` (works mid-competition).
- Tests: `res://tests/phaseT8_validation.tscn`.

# Phase T9 — Finance, transfers, career
- `FinanceLedger`: all money moves through entries (category, amount, balance_after); `is_consistent()` audits opening + entries == balance; transfers need balance and transfer budget; only salaries may overdraw.
- `TransferMarket`: `search()`, `asking_price()`, `buy()/sell()` (offer ≥ asking, contract ≥ minimum wage, wage budget, squad 18–30, free agents cost nothing, youth/loaned players excluded), `loan()` (borrower pays fee + wages, `loan_parent`/`loan_weeks_left`, auto-return via `advance_loans()`), `renew_contract()`, `expiring_contracts()`, history. Validate-then-mutate; a player is always in exactly one `squad_ids`.
- `CareerState`: managed club, season/week clock, ledgers for every club, market, competitions (results → match revenue, prize money paid once), `end_season()` (ageing, contract run-down, expiry release with minimum-squad protection), full save/load through `SaveManager` extras["career"]. `PlayerData` gained `loan_parent`, `loan_weeks_left`.
- Tests: `res://tests/phaseT9_validation.tscn`.

# Phase T11 — Match engine integration
- **Intent providers** (`scripts/systems/match/intent_provider.gd`, `ai_intent.gd`): `PlayerController` and `FootballActions` now read control through `intent` (default `IntentProvider` = the same global `Input` calls as Phases 2–4; `AIIntent` for computer players, `world_space` bypasses the camera). The ball/physics/controller code is otherwise untouched.
- `MatchSetup` (teams, squads, stadium, duration, difficulty, conditions, human side, knockout flag; `validate()`, `build_side()` with auto-pick fallback and away-kit selection), `MatchState` (clock/halves/score/events/stamina → `MatchResult`), `PenaltyShootout`, `PitchSpace` (team-relative ↔ world; home attacks goal N/−Z).
- AI layers: `PlayerAI` (chase, dribble, shoot, pass under pressure, keeper positioning/distribution), `TeamAI` (formation shape from `TacticsPreset`, pressing, chaser selection), `ManagerAI` (late-game mentality, protecting a lead, tired-player substitutions with limits).
- `MatchManager` (`scenes/match/match_scene.tscn` via `GameManager.start_configured_match(setup)`): spawns the arena, the real ball and 22 `player.tscn` instances from the lineups, applies `AttributeModifiers`, human control with `switch_player`, goals via `StadiumArena.goal_entered`, half-time, full time, fatigue carry-over, emits `MatchResult` (→ `Competition.submit_result` / `CareerState.submit_result`).
- Known simplifications: players are tinted with one flat kit colour; sides are not swapped at half-time; goalkeepers are AI-only positioning (no dive/save physics yet).
- Tests: `res://tests/phaseT11_validation.tscn`.

# Phase T10 — UI integration
- Entry: main menu → "Management Hub" (`ui/hub/hub.tscn`, `HubRoot`). Navigation bar + content + message bar; `AppHub` autoload holds the live state (selected club, squads, academies, scouting, training, career) and save/load.
- `UIKit` (`scripts/ui/kit/ui_kit.gd`): label/title/button/table/stat bar/option/panel/scroll/empty state/kit preview/confirmation dialog — one look for all screens. `HubScreen` base class; `ScreenRegistry` maps 18 screen ids to scripts (+ the existing main menu = 19 required screens).
- Screens: team selection, team details (+comparison), squad management, tactical formation (+presets), player profile, academy dashboard, scouting, training, promotion, competitions, standings, bracket, career dashboard, transfer market, club finance, team customization, kit editor, match setup. Every control calls the real systems (`Squad`, `TacticsPreset`, `Academy`, `ScoutingSystem`, `TrainingSystem`, `PromotionSystem`, `Competition`, `CareerState`, `TransferMarket`, `ClubCreator`, `KitEditor`, `MatchSetup`); empty states point to the missing prerequisite; destructive actions (end season, delete club, promotion) are confirmed; errors from the systems are shown in the message bar.
- Matches: "Play in 3D" / "Start match" call `AppHub.play_match()` → `GameManager.start_configured_match()`; the result flows back through `GameManager.match_finished` into the competition and finances, and `return_scene_path` returns to the hub. "Simulate" uses `AppHub.simulate_fixture()` (strength-weighted, no 3D).
- Tests: `res://tests/phaseT10_validation.tscn` (builds every screen, drives buttons/dropdowns/sliders, verifies state changes and persistence).

# Phase T12 — Testing, optimisation, documentation
- `tests/phaseT12_validation.tscn`: project integrity (autoloads, input actions, scenes, every script loads), an end-to-end career (create club → scout → train → promote → lineup → transfer → league from engine-style results → finances → save/load → no regenerated academy players), seed-data integrity and a 22-player performance sample.
- `tests/run_all.sh [godot]` runs all suites (phase 1–4, stadium, T1–T12).
- Cleanup: removed the stray root `main.tscn`, updated version and stale header comments.
- IMPORTANT: this whole T-series was written in an environment without a Godot binary. Files were syntax-checked with `gdparse` (gdtoolkit) and seed JSON with Python, but **no suite has been executed**. Run `tests/run_all.sh` first and fix whatever the first real run reports.
