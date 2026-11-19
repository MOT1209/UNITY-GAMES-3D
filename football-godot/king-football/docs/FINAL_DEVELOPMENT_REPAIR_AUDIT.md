# Final development repair audit

Base: `origin/main` @ `c22ec6c` (PR #77), branch `repair/development-ecosystem`.
Method: source read in this session, plus the existing suites run headless (Godot 4.7.1). Old audit documents were not used as evidence.
Status legend: **FIXED** (code + test in this branch) / **OPEN** (confirmed, not fixed yet) / **UNVERIFIED** (suspected, not yet proven) / **NOT AUDITED**.

## Confirmed findings

### F1 — Calendar catch-up silently dropped weeks — Critical — FIXED
* `DevelopmentEngine.sync` jumped `first` forward and counted `skipped_weeks` when `owed > 60`, then set `last_week = absolute_week` (old `development_engine.gd:44-49`).
* `TrainingSystem.sync_to_calendar` set `calendar_week = absolute_week` *before* processing only `min(owed, 60)` weeks (old `training_system.gd:37-38`): the remainder was lost without any record.
* `YouthDevelopment.sync` and `ScoutingSystem.sync_to_calendar` had the same cap-and-forget pattern.
* Fix: the persisted "last processed week" now advances one week at a time, only over weeks really processed. `DevConfig.CATCH_UP_BATCH_WEEKS` (60) bounds the work of ONE call; the remainder stays queued (`pending_weeks(...)`) and the next call resumes it. `last_week` / `calendar_week` are already saved, so a queue survives save / load. `skipped_weeks` is kept only as a legacy field from old saves and is never increased.
* Test: `player_development_validation` `_test_catch_up_queue` — 10 / 60 / 100 / 200-week jumps (first batch size, queued remainder, exactly-once totals, repeated sync adds nothing), save / load in the middle of a queue, training and youth 200-week jumps. The previous assertion that *pinned the dropping behaviour* (`skipped_weeks == 140`) was replaced, not weakened.
* Remaining caveat: after a jump larger than one batch the queue drains over the following sync calls (each career tick), not inside one call.

### F2 — No stored detailed attributes — High — OPEN
* `PlayerData.ATTRIBUTES` has seven broad attributes (`player_data.gd:16`). They feed `get_overall`, the match engine, training, plans and saves.
* `AttributeDetail` (`attribute_detail.gd`) exposes 18 "detailed" names, but they are **derived** from the seven (parent average + a fixed per-player offset), are not stored, cannot be trained, and are not the requested list (no Finishing/Shot Power/Long Shots/Volleys/Penalties/Heading, Short/Long Passing, Crossing, Curve, Marking, Interceptions, Jumping, Strength, Concentration, Anticipation, Decisions, Work Rate, Aggression, Teamwork, keeper Reflexes/Diving/Handling/Kicking/1v1 ...).
* Consequence: development plans and training sessions can only target the seven broad attributes (`DevelopmentEngine._first_team_week` iterates `plan["weights"]` over `PlayerData.ATTRIBUTES`; `get_attribute` returns 0 for anything else).
* Needs a design decision before code (affects saves, data packs, match engine, nearly all suites) — see "Proposed approach".

### F3 — Several coaching factors multiply into the academy `dev_bonus` — High — UNVERIFIED (needs a decision)
`career_state.gd:123` multiplies, for the managed club's academy: manager style x facilities x `staff.youth_factor()` (old `StaffTeam`) x progress x `training.development_factor()` x `YouthDevelopment.coach_factor` (academy's own coach quality) x `coaching.academy_factor()` (new `CoachingStaff`). `group_bonus` (`:126`) then multiplies the group's share again inside `TrainingSystem`.
Three different "coach quality" sources are stacked. Whether that is intended compounding or double counting has not been measured; the requirement forbids duplicate bonuses, so it must be resolved (one source of truth per effect) and covered by a test.

### F4 — Two staff systems still coexist — Medium — OPEN
`StaffTeam.BRIDGED` bridges only `fitness_coach` and `goalkeeping_coach` into `CoachingStaff` (`staff_team.gd:16`, `DevelopmentEngine._import_legacy`). `StaffTeam.youth_factor()` and the academy's own `staff` dictionary remain independent sources (see F3).

## Not yet audited (no claim made)
Youth match path coaching quality; youth eligibility / lineup / goalkeeper / injured / loan rules; training effects on detailed attributes (blocked by F2); every UI screen's data binding; save migration of future fields; coach contracts / recruitment edge cases; fatigue / injury balancing; performance and the full multi-season suites on this branch.

## Test evidence in this branch
Run headless on the branch after F1: `player_development_validation` 201 passed / 0 failed; `phase6_integration_validation` 105 / 0; `phaseT5` 69 / 0; `phaseT6` 67 / 0; `phaseT10` 127 / 0; `phaseT12` 58 / 0. The full suite (`tests/run_all.sh --full`) has **not** been run on this branch yet.

## Proposed approach for F2 (to be confirmed)
Keep the seven broad attributes as the match-engine inputs. Store detailed attributes per player as a dictionary of *trained deltas* on top of the existing deterministic derived base (so old players start with identical values and the match engine is unchanged at migration time). Training a detailed attribute adds weighted fractional progress to its parent broad attribute(s) once (no double counting). Plans / sessions target detailed names; the seven broad names stay valid for old plans.
