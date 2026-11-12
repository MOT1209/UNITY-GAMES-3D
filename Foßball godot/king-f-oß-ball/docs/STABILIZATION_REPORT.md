# KING FOOTBALL — Stabilization, Integration & Multilingual Report

Date: 2026-11-12 · Godot 4.7.2 (`C:\tools\godot\Godot_v4.7.2-stable_win64_console.exe`) · branch `main`.
Everything below was executed; nothing is claimed from static reading. Labels: **TESTED-OK**,
**TESTED-WITH-FAILURES**, **IMPLEMENTED (not covered by a run)**, **NOT TESTED**, **NOT IMPLEMENTED**.

## 1. Problems found and 2. root causes

| # | Problem | Root cause |
|---|---|---|
| 1 | 9 of 17 suites did not compile; headless runs hung | `db: Node` typed autoload copies → `:=` could not infer types (`Cannot infer the type`); T4 `x == [..] as Array[String]` cast; no timeout in the runner |
| 2 | T1 `remove team removes its players` | `register_team` never filled `squad_ids`, `remove_team` iterates `squad_ids` → players leaked |
| 3 | T1/T6/T8/T12 round-trip failures | `JSON.stringify` default keeps 14 digits and turns ints into floats; `Competition.from_dict` copied raw JSON |
| 4 | `MatchManager` crash on human-controlled slots | `_place_team` called `release_all()` on a null AI |
| 5 | Academy training could be run without limit; career did not drive it | two independent week counters |
| 6 | Players older than the oldest age group vanished from the Academy screen | `end_season` discarded `TrainingSystem.age_up`'s return value; group lists ignore age > 19 |
| 7 | Arabic / accented club names rejected or colliding | `slugify` kept only ASCII |
| 8 | No side switch at half-time | all geometry hard-wired to the real side |
| 9 | Real match used a lateral-only keeper; real keeper only in the demo | two keeper implementations |
| 10 | Flat one-colour kit tint | kit dictionaries ignored |
| 11 | **No real shot could ever score a goal** | arena goal trigger mask = layer 1, the real ball is on layer 4 |
| 12 | Tests that silently never ran | un-awaited async test functions in phase1 (4 checks), T1 (6 checks) |
| 13 | Game had no localization; Arabic only "worked" by forcing LTR | no translation system, no Arabic font, RTL workaround |
| 14 | Pitch diagram lost its markers in RTL | child-ColorRect positions mirrored under an RTL tree |

## 3. Files changed (main)

Core/data: `scripts/core/{localization(new),team_database,save_manager}.gd`, `scripts/data/player_data.gd`.
Systems: `career_state`, `competition`, `training_system`, `scouting_system`, `academy`, `academy_config`,
`promotion_system`, `club_creator`, `match_manager`, `team_goalkeeper`, `team_kit`, `stadium_arena`,
`ball_proximity_detector`. UI: `app_hub`, `main_menu` (+ scene), `language_picker`(new), `pitch_diagram`(new),
`settings_screen`(new), hub shell (`hub_root`, `hub_screen`, `screen_registry`, `ui_kit`), all 18 screens.
Data/assets: `translations/{screens,shell}.csv`, `assets/fonts/NotoSansArabic.ttf` (+OFL), `project.godot`
(autoload `Loc`, fallback locale). Tests: `run_all.sh`, `phaseT*`, `phase6_integration_validation`,
`localization_validation`, `localization_visual`. Docs: this file, `LOCALIZATION_SYSTEM`, `ARABIC_RTL_SUPPORT`,
`MULTILINGUAL_QA_REPORT`, `FINAL_INTEGRATION_AUDIT`, `ARCHITECTURE`, `TEAM_PLAYER_DATABASE`, `README`, `plan.md`.
`git log` commits: f6891ed, 9365301, 2e41c0e, a022e07, e12996b, 14d9149, 934d290, 852b054 and the final one.

## 4. Fixes implemented

1–4, 12: typed `TeamDatabase` (`class_name`), explicit types, `register_team` links roster ↔ squad, full-precision
JSON + int restore, null guard, awaited tests. 5: `sync_to_calendar` (idempotent, bounded catch-up) driven by
`CareerState.advance_week` through `AppHub.advance_week`. 6: `Academy.over_age_ids/keep_extended/expire_extensions`,
Over-Age Prospects UI. 7: `ClubCreator.make_id` (ASCII legacy ids, `club_<hint>_<sha256-8>` for Unicode, collision
loop, duplicate detection). 8: `MatchManager.frame_side`. 9–10: real `TeamGoalkeeper` + `TeamKit.from_dict` in
`MatchManager`. 11: `trigger_mask = 5`. 13: `Loc` + tables + fonts + UI conversion. 14: `PitchDiagram`.

## 5. Exact commands executed

```
godot_console="C:\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$godot_console --headless --path . --import                         # refresh class cache / resources
bash tests/run_all.sh /c/tools/godot/Godot_v4.7.2-stable_win64_console.exe     # all suites, 300 s timeout each
$godot_console --headless --path . res://tests/<suite>.tscn         # single suite
godot_gui --path . res://tests/localization_visual.tscn --resolution 1280x720 --rendering-driver opengl3   # screenshots
```

## 6. Actual test results

Baseline before this work: phase1–5 and arena green; T1 2 failures; T4–T9 did not compile; T10 2, T11 1 failures;
T12 did not compile.

Last results per suite (headless, Godot 4.7.2; "run" = `tests/run_all.sh`, "rerun" = suite run alone after a later edit):

| Suite | Checks | Source |
|---|---|---|
| phase1 | 53 / 0 fail (4 menu checks had silently never run) | rerun |
| phase2 · phase3 · phase4 · phase5 · arena | 57 · 103 · 159 · 219 · 29 / 0 fail | run |
| T1 | 88 / 0 (6 hook checks had silently never run; +regression tests) | run |
| T3 · T4 · T5 · T6 · T7 | 95 · 41 · 69 · 68 · 79 / 0 fail | run |
| T8 · T9 | 130 · 125 / 0 fail | run |
| T10 · T11 | 108 · 131 / 0 fail | run / rerun |
| T12 | 57 passed, **1 failed** (stray `main.tscn`, see §7) | run |
| phase6_integration | 105 / 0 | run |
| localization | 90 / 0 | run |

Totals: ≈1,810 checks, 1 failure (§7). The last full `run_all.sh` completed with 1,752 passed / 10 failed: T12's stray
`main.tscn` (§7) plus 9 T10 failures caused by a language saved in the developer's user settings by an earlier
test run (T10 looks for English texts). Fixed afterwards: headless runs now always start in English
(`Loc._ready`, override `KING_LANGUAGE=xx`), the stray setting was removed, and T10 (108/0), phase1 (53/0) and
localization (90/0) were re-run alone and pass. A complete `run_all.sh` after that fix was **not** repeated.
Mutation checks (break → fail → restore): calendar sync, extension expiry, half-time swap, keeper shot reading,
goal trigger mask, roster link, int restore, RTL flag, raw-id display.

## 7. Remaining failures

* `phaseT12_validation` → `stray root main.tscn removed` fails **whenever an untracked `main.tscn` exists in the
  project root**. That file (a `StaticBody3D` + `BoxMesh` scene with Godot-4.7-editor `unique_id` fields, mtime
  during this session) is written by a Godot **editor** (a 4.7.1 editor process is running on this machine —
  `plan.md` already warns about 4.7.1). It is not created by any test. It was deliberately **not deleted** because it
  looks like in-progress work; delete it or move it under `scenes/development/` and the suite is green.
* Nothing else fails.

## 8. Phase 5 readiness — verified

| Requirement | Evidence | Result |
|---|---|---|
| 22 players spawn in the real match scene | `phaseT11` (22 spawned, squads, modifiers), `phase6` | TESTED-OK |
| Correct teams and kits (home/away, keeper kit, number, clash-free away) | `phase6` reads jersey/shorts/socks colours from the spawned models | TESTED-OK |
| Human control | `phaseT11` (human selects, switch player), default input unchanged | TESTED-OK |
| AI players / Team AI react to the ball | `phaseT11` (formation targets, chasers, pressers, movement), `phase5` | TESTED-OK |
| Passing/shooting through existing `FootballActions` | `phase4`, `phaseT11` (AI uses actions) | TESTED-OK |
| Goalkeeper dives / catches / concedes in the real match, both halves | `phase6` | TESTED-OK |
| Half-time side switch | `phase6` (keepers, halves, facing, goal attribution, AI) | TESTED-OK |
| Goals count from real shots | `phase6` (after the trigger-mask fix) | TESTED-OK |
| Match result → competition/finance | `phaseT11`, `phaseT12` | TESTED-OK |
| Phases 1–4 unchanged | all four suites green | TESTED-OK |
| **Scripted 23-step end-to-end run** | not written as one test; the steps are covered piecewise | **NOT IMPLEMENTED** |
| In-progress match save/load | — | **NOT IMPLEMENTED** |
| Match-results screen, pause menu | — | **NOT IMPLEMENTED** |

## 9. Localization architecture

`Loc` autoload (`scripts/core/localization.gd`) · CSV tables `translations/*.csv` (`key,en,de,ar`, merged) ·
stable `UPPER_SNAKE` keys · `Loc.t/f/tn/enum_name/num/money/date/iso` · runtime switch with `language_changed` ·
persisted in `user://settings.cfg` · root layout direction · Noto Sans Arabic + system fallbacks · validator.
Full description: `docs/LOCALIZATION_SYSTEM.md`. ~430 keys × 3 languages.

## 10. Arabic RTL verification

TESTED-OK (structure) and verified on real screenshots (shaping, mirroring, bidi). `docs/ARABIC_RTL_SUPPORT.md`,
`docs/MULTILINGUAL_QA_REPORT.md`, `docs/qa/*.png`. One real RTL bug found and fixed (pitch markers).

## 11. German verification

TESTED-OK: `ä ö ü ß` present and exact, umlaut names inserted in dynamic text, German number/currency/date formats,
all screens rendered in German without raw keys or English table text; screenshots `*_de.png`.

## 12. English verification

TESTED-OK: reference language and fallback; all screens rendered; formats; plurals.

## 13. Screens tested in all three languages

Main menu, first-run language dialog, Settings (panel + hub screen), Team Selection, Team Details, Squad,
Tactical Formation, Player Profile, Youth Academy (incl. Over-Age Prospects), Scouting, Training, Promotion,
Competitions, League Standings, Tournament Bracket, Career, Transfers, Finance, Team Customization, Kit Editor,
Match Setup — rendered automatically in ar/de/en; a subset reviewed visually (list in the QA report).
In-game match HUD: keys and LTR scoreboard tested; no windowed match screenshot.

## 14. Remaining localization limitations

System-layer error sentences (~150) are English; names/data defaults are not translated; no tutorials/loading/pause/
results screens exist; Arabic IME input, other OSes, high-DPI and native-speaker proofreading are NOT TESTED; kit
patterns are not rendered. See the "limitations" sections of `LOCALIZATION_SYSTEM.md` and `MULTILINGUAL_QA_REPORT.md`.

## Not done from the brief (explicit)

* **Real-team import architecture / documentation (section D of the earlier brief): NOT IMPLEMENTED.** Seed data is
  fictional only.
* Full "every button verified by clicking" audit: buttons on the screens above are covered by T10/phase6/localization
  rendering and specific press tests; it is not exhaustive. Loading states do not exist yet.
* UI design-system consolidation beyond the existing `UIKit` was not attempted.

## GO / NO-GO

* **GO** for continuing feature development on this base (stable, integrated, multilingual foundation, regression
  suite with timeouts, guards against duplicate classes and un-listed suites).
* **NO-GO** for calling the game "release-ready" or the brief fully complete: real-team import, scripted
  end-to-end test, in-progress match save, results/pause screens, native proofreading of ar/de text and the
  English-only system messages remain.


## Phase 7 update

Full suite: 2437 checks, 0 failed (see PHASE7_IMPLEMENTATION_REPORT.md).
