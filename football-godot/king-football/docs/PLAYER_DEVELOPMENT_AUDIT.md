# Player Development — audit and implementation status

Scope of the request: a complete player development ecosystem (plans, coaching staff, training, academy 2.0, analytics, UI,
persistence, tests). This document records what existed, what was found, what was built in this pass and what is still open.
It does not claim more than the code and tests show.

## 1. What existed (audited)

| Area | Files | State |
|---|---|---|
| Player model | `scripts/data/player_data.gd` | 7 attributes only (pace, shooting, passing, dribbling, defending, physical, goalkeeping), `potential`, `fitness`, `growth_progress`, `development_history`, `secondary_positions`. No fine-grained skills (tackling, vision, ...). |
| Academy | `systems/academy/*` | U15/U17/U19 groups, yearly intake, budget, upkeep, over-age handling, promotion screen. |
| Youth development | `academy/youth_development.gd` | Weekly U19 league (simulated), cup, loans, mentors, potential knowledge range, 2 staff roles. |
| Academy training | `training/training_system.gd`, `progression_model.gd` | Group / individual attribute focus, deterministic weekly points. |
| First-team training | `career/training_plan.gd` | Daily intensity / focus plan around fixtures; scales weekly development factor and recovery. |
| First-team growth | `career/player_lifecycle.gd::develop` | Once per season, age based. No weekly growth, no plans. |
| Staff | `career/staff_team.gd` | 7 roles (assistant, first-team coach, GK coach, fitness coach, doctor, chief scout, youth coach), deterministic market, hire / fire. Roles are not the six requested departments; no contracts per date, no negotiation, no progression, no screen. |
| Scouting | `scouting/scouting_system.gd` | Scouts, regional missions, pool, reports with estimate margin. |
| Calendar | `career_state.gd::_run_step("academy")` | Academy training, scouting and `YouthDevelopment.sync` run each career week. |
| Save | `career_state.to_dict/from_dict`, `save_manager.gd` | Versioned dict, per-system `from_dict` with defaults; JSON turns ints into floats (handled by `_restore_ints`). |

## 2. Findings

Bugs (fixed in this pass):
1. `YouthDevelopment.sync` processed at most the **last 4** owed weeks and silently discarded the rest (`mini(owed, 4)`); `TrainingSystem.sync_to_calendar` had the same cap (`MAX_CATCH_UP := 4`). A calendar jump of more than 4 weeks lost development.
2. The youth league lineup used `available()` = the whole academy sorted by rating: **U15 players played the U19 league**, no goalkeeper was guaranteed, injured prospects were not excluded.
3. `loan_out` picked a random club from all clubs, **including the player's own club**, and the loan result ignored club quality / playing time.

Gaps (partly or not addressed, see section 4):
- Two overlapping staff concepts: `StaffTeam` (legacy: assistant, doctor, chief scout, youth coach, plus `fitness_coach` and `goalkeeping_coach`) and the new `CoachingStaff` (six departments). Fitness and goalkeeping exist in both. Legacy injury / goalkeeper effects still read `StaffTeam`; the new development effects read `CoachingStaff`. Unifying them was not done (it would change saved data and `club_ops_validation`).
- Two training concepts: `TrainingPlan` (daily, first team) and `TrainingSystem` (weekly, academy). Plans now sit on top of both without replacing either.
- `PlayerLifecycle.develop` still grows first-team players once a year; the new weekly engine adds capped growth for the managed club in addition (damped by `DevConfig.ENGINE_SCALE`, capped per attribute and season).
- Real minutes played are not tracked anywhere; match experience uses **appearances and average rating** from `world_stats`.

## 3. What was built

New module `scripts/systems/development/` (all numbers in `dev_config.gd`):
- `DevConfig` - every balance value and the 1..20 coach rating scale, five star bands (1-4 / 5-8 / 9-12 / 13-16 / 17-20).
- `CoachingStaff` - six departments (attacking, midfield, defensive, goalkeeping, fitness, tactical), coach records (id, name, age, nationality, department, specialisation, overall / technical / tactical / youth / professional ratings, experience, reputation, salary, contract years and expiry season, history), recruitment market that refreshes with the calendar, search / filter, negotiation (salary and length), hire, reject, renew, dismiss with compensation, wage bookkeeping through the ledger, wage budget and slot limits tied to the training facility level, yearly progression at individual rates, contract expiry, starter staff for careers that have none.
- `DevelopmentPlans` - plan types balanced / position / attribute / role / long-term / custom / conversion; focus items per position group mapped onto the seven real attributes; switching keeps history and costs an adaptation period; progress view with an **estimated** weeks-per-point (explicitly an estimate).
- `DevelopmentEngine` - weekly calculation: `ProgressionModel.weekly_points` (age, headroom, traits, fitness, facility, personality) x coach multiplier x plan consistency x focus spread x `ENGINE_SCALE`, seasonal per-attribute cap by age, potential cap, match experience from appearances / rating, individual workload -> fitness, overload injury risk on top of the existing baseline, notifications (attribute gains, milestones, plan completed, conversion done, fatigue, no playing time, academy player ready), monthly / seasonal reports, 4-weekly snapshots, **catch-up of every owed week with an idempotent `last_week` marker**.
- `DevelopmentState` - everything saved under the career key `development`, with validation, safe defaults and integer restoration.
- Integration: `CareerState.development`, weekly step in the existing `academy` step, season-end hook (coach progression / expiry, seasonal report), academy training reads the plan focus and the coaching multiplier (`TrainingSystem.plan_focus`, `dev_bonus`).
- Youth fixes: catch-up in `YouthDevelopment.sync` and `TrainingSystem`, eligible lineup (ages 16-19, 1 GK + 4-4-2 shape, injured excluded), ranked loan options that never include the own club and drive loan appearances.
- Screens (registered in `ScreenRegistry`, tab group under the Team section): Player Development (`dev_hub`), Coaching Staff (`coaching_staff`), Coach Recruitment (`coach_recruitment`). All strings in `translations/screens.csv` (en / de / ar).
- Tests: `tests/player_development_validation` (116 checks) and an updated expectation in `phaseT9_validation` (coaching wages are now part of the weekly bill).

### Balance notes
Coach multiplier: vacant 0.85, rating 1 = 0.92, rating 20 = 1.12, department cap 1.15, tactical coach contributes 25 % of his deviation to every attribute. Elite vs. no coaching is about +40 % on the trained attribute (test asserts 1.25x-1.5x). Intensity above 0.6 adds up to ~1.2 % weekly injury risk; fitness below 55 adds more; fitness below 40 stops training gains.

### Migration
Old saves have no `development` key: they load with an empty state, and on the first career week a starter staff (one modest coach per department, 2-year contracts, wages by the same formula as the market) is created. This adds roughly 6 x 1-2k weekly wages to existing careers. Nothing else in the save changes; the save validator and the JSON round-trip tests pass.

## 4. Not done / open (honest list)

- Fine-grained attributes (the player model has seven); focus items are labels mapped onto them.
- Youth Academy Hub merge (a Training Center screen now exists: weekly schedule, coach per focus, squad workload; the Development Analytics screen exists: team overview, player comparison, attribute charts, reports).
- Custom plan editor exists in the Player Development screen (up to 3 attributes with weights); role / attribute / conversion target of the dropdown plans are still chosen automatically.
- Scouting: missions now take a preferred position and an objective (balanced / potential / ready) and better scouts see more players per slot; the 4-week scouting catch-up cap is fixed. Still open: per-group academy coaches, youth competitions beyond the existing U19 league and cup (U15 / U17 leagues do not exist).
- StaffTeam and CoachingStaff are bridged, not merged: fitness and goalkeeping coaches are hired only in the coaching staff screen, legacy members are imported once, and the legacy injury / goalkeeper effects read the better of both. Assistant, doctor, chief scout and youth coach stay in StaffTeam.
- Training schedules per session type (technical / tactical / physical / goalkeeping sessions with assigned players): the existing daily `TrainingPlan` remains the schedule.
- Only the full headless suite (`tests/run_all.sh`) can confirm no other regressions; the suites listed in the PR / commit message were run.
