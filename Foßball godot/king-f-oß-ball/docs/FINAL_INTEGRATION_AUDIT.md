# KING FOOTBALL — Final Integration Audit

Engine: Godot 4.7.2 (`C:\tools\godot\Godot_v4.7.2-stable_win64_console.exe`), headless.
Legend: **TESTED-OK** = implemented and verified by a real headless run ·
**IMPLEMENTED** = in code, only partly or not covered by a run ·
**NOT TESTED** · **NOT IMPLEMENTED**.

## 1. Executive summary

The project was two merged tracks (gameplay phases 1–5, career T1–T12) that did not work as one game.
The baseline run showed 9 of 17 suites broken (parse errors that also hung headless runs), and the
audit found that **no goal could ever be scored in a real match** (the arena goal trigger did not see
the real ball). This pass fixed the test infrastructure, linked academy training to the career calendar,
added Over-Age Prospects, made club ids Unicode-safe, switched ends at half-time, put the real
goalkeeper and real kit data into `MatchManager`, and fixed goal detection.
**Not finished** (see §9/§10): real-team data import, main-menu "Play" flow, a scripted 23-step end-to-end
test, and several UI controls that are only checked at system level.

## 2. Systems audited
CareerState, TrainingSystem, ScoutingSystem, Academy, PromotionSystem, SaveManager, TeamDatabase,
ClubCreator, KitEditor/TeamKit, MatchManager, PitchSpace, TeamAI, PlayerAI, ManagerAI, TeamGoalkeeper,
StadiumArena goal triggers, hub screens (academy/training/scouting/career), tests/run_all.sh.

## 3. Bugs discovered
1. 9 suites failed to compile ("cannot infer type") — `db: Node` typing; T4 invalid cast (B1).
2. `register_team` did not link roster to `squad_ids` → `remove_team` leaked players (B2).
3. `JSON.stringify` truncated floats to 14 digits and turned ints into floats → saves lost growth progress and results not identical after reload.
4. `MatchManager._place_team` crashed on human-controlled slots.
5. Stray root `main.tscn`.
6. Career `advance_week` did not drive training/scouting; training could be run without limit.
7. Players older than the oldest age group disappeared from the Academy screen and were never handled.
8. `slugify` dropped non-ASCII → Arabic names rejected, "A.B"/"A B" collided.
9. No side switch at half-time.
10. Real match keeper = lateral-only PlayerAI keeper (no dive/save); real `TeamGoalkeeper` only in the demo scene.
11. Flat single-colour tint instead of kit data.
12. **Arena goal trigger watched layer 1, real ball is layer 4 → real shots never scored.**
13. `get_current_ball()` could hand out a freed ball (teardown error).
14. Stale test assumptions (T6 budget/capacity, T10 keeper slot, T11 chaser distance).

## 4. Bugs fixed
All of §3 (1–14). Details in the git log (commits f6891ed … 14d9149).

## 5. Files changed (main)
`scripts/core/{team_database,save_manager}.gd`, `scripts/data/player_data.gd`,
`scripts/systems/{career/career_state,training/training_system,scouting/scouting_system,academy/academy,academy/academy_config,promotion/promotion_system,competitions/competition,teams/club_creator,match/match_manager}.gd`,
`scripts/teams/team_goalkeeper.gd`, `scripts/player/team_kit.gd`, `scripts/environment/stadium_arena.gd`,
`scripts/ball/ball_proximity_detector.gd`, `scripts/ui/app_hub.gd`,
`scripts/ui/screens/{academy,career,training,scouting}_screen.gd`,
`tests/run_all.sh`, `tests/phaseT*_validation.gd`, new `tests/phase6_integration_validation.{gd,tscn}`; `main.tscn` (root) removed.

## 6. Tests executed
`tests/run_all.sh <godot>`: 18 suites incl. new `phase6_integration_validation`; guards: every
`*_validation.tscn` must be listed, no duplicate `class_name`, per-suite timeout (300 s).

## 7. Actual results (headless, Godot 4.7.2)
Baseline before fixes: phase1–5/arena green; T1 2 fails; T4–T9 not compiling; T10 2 fails; T11 1 fail; T12 not compiling.
After fixes (last full run): phase1 49, phase2 57, phase3 103, phase4 159, phase5 219, arena 29, T1 74, T3 95,
T4 41, T5 69, T6 68, T7 79, T8 130, T9 125, T10 107, T11 131, T12 58 (one T12 failure seen once was a stray
`main.tscn` recreated by a killed run; passes after cleanup), **phase6 105** — all 0 failed.
Mutation checks (break the fix → test fails → restore): calendar sync, extension expiry, half-time frame swap,
keeper shot reading, goal trigger mask.

## 8. End-to-end workflow (23 steps) — status
| Step(s) | Status |
|---|---|
| 1–2 launch/main menu | NOT TESTED (T10 builds hub screens headless; menu "Play" still opens a prototype, not the real match) |
| 3–4 select team, start career | TESTED-OK (T10 UI) |
| 5–6 squad / formation | TESTED-OK (T10 UI; slot assignment) |
| 7–8 academy, scout, generate | TESTED-OK (T5/T10/phase6) |
| 9–11 train, advance calendar, development | TESTED-OK (phase6: calendar-driven, no duplicate/free weeks) |
| 12–14 over-age, promote, verify in squad | TESTED-OK at system level (phase6); **UI buttons NOT TESTED** |
| 15–17 match, AI, keeper reactions/saves | TESTED-OK (T11/T12/phase6: real keeper dives, catches, concedes) |
| 18 half-time side switch | TESTED-OK (phase6) |
| 19–20 finish, result → career | TESTED-OK in T11/T12 (result → competition, revenue) |
| 21–23 save, restart, load | TESTED-OK for career/academy/training/over-age (phase6/T6/T12); **match-in-progress save NOT IMPLEMENTED** |
No single scripted 23-step run exists yet.

## 9. Remaining limitations / not implemented
- **Real teams (D): NOT IMPLEMENTED.** Seed data is fictional; no importer (`tools/`), no import docs yet. No real logos/photos may be used.
- Main menu "Play" still starts a stadium prototype; Settings button disabled (placeholder). Dead-control audit only done for the screens above.
- Kit `pattern` (stripes/hoops…) is stored but not rendered (models expose flat colour slots only).
- `PlayerAI._keeper` remains in code (covered by T11) but the match no longer uses it → a leftover duplicate to delete once T11 is updated.
- Match save/load (in-progress match) not implemented.
- Over-age "Keep" is a simple extension up to age 21; adjust if a different pathway is wanted.

## 10. Needs manual testing
Visual check of kits/numbers on the models, keeper animation feel, camera at half-time, UI click-through of the
Over-Age section and the new "Next week" buttons, full-length match, Arabic text rendering/RTL in the UI.
