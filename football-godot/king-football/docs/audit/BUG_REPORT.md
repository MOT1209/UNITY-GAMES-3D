# KING FOOTBALL — Bug Report

Date: 2026-11-17 · HEAD `9fdb5bb` · Status words: OPEN / FIXED / CANNOT-REPRODUCE / WONTFIX / BLOCKED.

## Current test baseline

| Run | Date | Host | Result |
|-----|------|------|--------|
| quick (`tests/run_all.sh --quick`) | 2026-11-17 | Linux CI (prev session) [DOC] | 5518 passed, 0 failed |
| full | 2026-11-17 | Linux CI (prev session) [DOC] | 5841 passed, 3 failed (`career_p1_long_validation`) |
| quick | 2026-11-17 | Windows, Godot 4.7.1 headless, this session | recorded on completion → `STABILIZATION_REPORT.md`; first two attempts invalid (B4: missing `--import`, then B5: overlapping runs); partial clean segment before interruption: 2,219 passed / 0 failed through `player_visual_integration_validation` |

## Open bugs

### B1 — Full-suite `career_p1_long_validation`: 3 failing checks (OPEN, H)
1. Save size at season 10 = 780 KB fails the "stays bounded" assertion (growth is bounded but non-plateauing;
   investigation recorded in commit `65e310d`, no code change made).
2. Real-pack `advance_week()` 645.5 ms vs 350 ms budget.
3. 46-week season 29.7 s vs 18 s budget.
Both timing budgets were measured on a shared software-rendered CI container; budget realism must be re-validated
on the Windows host before changing code (a budget change is a last resort and needs a recorded rationale).

### B2 — Two-human Pause/Resume flake on Windows (OPEN, L, CANNOT-REPRODUCE)
Reported once; not reproduced on Linux (14/14) nor in prior runs. Plan: add targeted logging at
`controller_registry.gd` `apply_input` and `match_manager.toggle_pause_from_controller`, then repeated Windows
runs to capture a trace. No fix justified without a failing trace.

### B3 — Documentation drift (OPEN, L)
README / FEATURE_STATUS / MASTER_ROADMAP / plan.md disagree on counts and dates; `plan.md` is Arabic and dated
2026-11-11. Reconciled incrementally as each repair phase lands (the `docs/audit/` set is the current cycle's
source of truth).

## Fixed in recent history (evidence)

- Advantage rule missing → PR #40 (`b53ea58`), 15 checks in `match_rules_validation` [READ this session].
- No xG/heatmap/shot-map analytics → PR #41 (`112a824`), `expected_goals.gd` + `match_analytics_validation`
  [READ this session].
- Non-ASCII paths broke CI paths → PR #42 (`0081cdb`) [RAN this session].
- Translation-file churn on Windows (`.translation` re-import diffs) → verified content-identical, discarded;
  add to release checklist: commit translation re-imports deliberately after a Godot editor session.

### B4 — Tests on a fresh checkout fail without a prior `--import` (FIXED 2026-11-17)
A fresh clone (or a renamed project directory, as in PR #42) has no `.godot/` global class cache. Running
`tests/run_all.sh` directly then produces dozens of "Identifier X not declared" parse errors and every suite
times out at 1500 s. Reproduced on Windows 2026-11-17; CI already runs `godot --headless --path . --import`
before testing. **Fix implemented**: `tests/run_all.sh` now detects a missing
`.godot/global_script_class_cache.cfg` and runs the import step itself before the first suite, matching CI.

### B5 — Parallel test runs on one project corrupt the baseline (PROCESS RULE, this session)
Two concurrent `run_all.sh` runs (and a single-suite run during a full run) overlapped this session; suites
collided and the baseline became unusable. Rule recorded in `docs/audit/DEVELOPMENT_ROADMAP.md`: exactly one
Godot/test process per project at any time; single-suite checks wait until the batch runner is idle.

### B6 — Unquoted commas in a translation row shift the CSV columns (FIXED 2026-11-18)
`RESULT_PASS_NETWORK_NONE` was added with a comma inside the English and German text but without RFC 4180
quoting. The parser saw 6 fields instead of 4, so the Arabic column held German text and CI
`localization_validation` failed its "every Arabic string actually contains Arabic text (2049 checked)" case.
Fixed by quoting both fields (same convention as `leagues.csv` / `screens.csv`). A full scan of
`translations/*.csv` now reports zero rows whose logical field count differs from 4. Rule: any comma inside a
translation string must be wrapped in double quotes.

### B7 — `arabic_ui_validation` flagged real-pack club names in save slots (FIXED 2026-11-18)
The "no untranslated Latin text on any screen" check treats club names as proper names, but it built that
exception only from the default-world database. A desktop save made with the `real_2025` pack shows its club
(e.g. "Hull City AFC", "Clermont Foot 63") in the save-slot title, so the suite failed locally (42/1) while
CI stayed green (43/0 — no user saves there). The exception now also reads `team.name` / `team.short_name`
from every shipped pack (`data/packs/*/clubs` and `fictional/clubs`). Locally 43/0 again; genuinely
untranslated UI text is still reported.

### B8 — Validation suites deleted the player's real save slots (FIXED 2026-11-18)
`career_flow_validation._test_slots()` removed slots 1–5 and the pre-new-career backup from `user://saves`
— the player's real save folder — wrote test careers into slots 1–3 and removed them again at the end;
`screens_ux_validation` rewrote the manual save `career.json` and restored it from memory. On a desktop
machine that silently destroyed real saves (CI cannot see it: its user folder is empty). `AppHub` now has a
`save_root` (default `user://saves`) with `save_path()` / `autosave_path()` / `backup_path()` / `slot_path()`
following it, and both suites point it at `user://test_saves`. `world_save_consistency_validation` moved its
20 MB scratch file there too. Rule: a validation suite must never write or delete under `user://saves`.

## Not bugs (investigated, by design)

- Sprint gate on difficulty (`player_ai.gd:46`) — intended difficulty scalar, not a bug.
- xG shown only when the report declares `ESTIMATED` (`match_results_view.gd:148-150`) — honesty gate, by design.
- Save refusal for versions > 3 (`save_manager.gd:92-93`) — forward-compat guard, by design.
