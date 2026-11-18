# KING FOOTBALL — P1 Career Mode: stability, data integrity, save migration, performance

Godot 4.7.2 headless, Linux, 4 vCPU. Branch `claude/king-football-career-repair-qexzwz`. Raw outputs: `docs/p1/`.

## 1. Executive summary
Nothing was rebuilt; targeted repairs only. Real pack (298 clubs, 8,013 players): a 46-week season went **26.5 s → ~5.3–6.3 s**
(avg week 577 → 115–138 ms). Pure-performance changes were proven **byte-identical** to the old build (`docs/p1/fingerprint_*`).
Real bugs found and fixed (below), statistics split into real vs estimated, a career validator added, UI week made non-blocking.
Full suite: **4,335 checks passed, 0 failed** (baseline: 4,019 passed; its 1 failure was an artifact of running from a copied folder).

## 2. Architecture assessment
PlayerData/TeamData are the sources of truth (kept; only never-saved lookup indexes added). Calendar design sound. The career block
of a save was never validated; three stats stores mixed real and model data; several O(F²) scans; unbounded lists.

## 3. Problems, root causes, repairs
| Sev | Problem | Root cause | Repair |
|---|---|---|---|
| H | Season 26.5 s (22 s in leagues) | `Competition` linear scans per fixture; `get_overall()` in sort comparators; ratings per match | Fixture index + counters + cursor; per-week rating cache; XI from precomputed overalls; cached/memoised `get_overall` (invalidated by setters); native-sorted AI pool |
| H | +36 MB memory per season, growing saves | Ledgers 2 entries/club/week forever | `FinanceLedger.compact` (balance/totals/audit unchanged) |
| C/H | Old continental cups stayed in the career forever | never erased on rollover | erased; validator flags stale competitions |
| H | Play-off final (3-round play-off) not played in week 46 | loop only reran when a competition, not a round, appeared | loop while matches appear |
| H | Reloaded career diverged from an uninterrupted one | saves sort keys → iteration order changed | canonical order (`roles()`, `pyramid_keys()`) |
| M | ints became floats after load (rules, history, reports, ledger args) | raw JSON copied | restored |
| M/H | Estimates shown as real stats | `world_stats` mixed both | `est_*` split; awards `basis`/`estimated_percent`; `world_stats_legacy` flag |
| M | uid-less report double counted; 200-entry lambda scan per result | — | index; keyed by match id |
| H | Career block unvalidated; bad types crash | — | `CareerValidator` (shape + semantic), run on a staging DB inside `SaveManager.validate` (all-or-nothing); `save_game` refuses failing careers |
| M | Unbounded histories | — | caps: ledgers, transfer log 2000, summaries 50, club/award history, released 1500, per-player history ≤80, retired players purged after 3 seasons if unreferenced |
| M | UI froze per week | sync | `advance_week_async`, busy guards |

## 4. Files
Created: `career_validator.gd`, `tests/career_p1_validation`, `tests/career_p1_long_validation`, `tools/profile_season`, `tools/profile_save`, `tools/sim_fingerprint`, `docs/p1/*`.
Modified: career_state, season_stats, competition, league_pyramid, match_simulator, finance_ledger, transfer_market, ai_transfers, availability, player_lifecycle, player_data, training_system, save_manager, app_hub, career_screen, translations/leagues.csv, run_all.sh, CAREER_LONGEVITY.md; tests phaseT10, league_pyramid, phase12_awards, db_integration adjusted. Removed: nothing.

## 5. Performance (same machine, real pack)
| | Before | After |
|---|---|---|
| 46 weeks | 26,541–26,659 ms | 5,314–6,347 ms |
| avg / worst week | 577 / 889–967 ms | 115–138 / 220–640 ms (noisy) |
| leagues phase | 22.1 s | ~2.5 s |
| longest uninterrupted block (async) | whole week | 67–103 ms |
| memory per season | +36 MB | ~+4 MB (retiree pool filling) |
| 12-season longevity suite | 422 s | 132 s |
| end_season | 530 ms | 440–990 ms (unchanged class; lifecycle + ledgers) |
Save of a real career: 17 MB; load validation 1.0 s (career audit ≈ 0.6 s).

## 6. Tests executed
`tests/run_all.sh --full <godot>` → 4,335 passed / 0 failed. New: `career_p1_validation` (255), `career_p1_long_validation` (59 + 10 seasons × 2 worlds:
clean audit each season, stats recorded exactly once, no repeated match ids, promotion/relegation, save round trips, performance budgets).
Fault-injection tests prove the validator detects 20+ corruptions. Resume determinism and async == sync are tested byte-for-byte.

## 7. Save migration
v0, v1, v2 → v3 (synthesised from a v3 save by stripping fields), plus an "ancient" career block; each: values unchanged, validates, restores,
plays a season. Newer versions refused. 16 corrupt-save cases refused with the database untouched; 14 missing-optional-field cases load with defaults.
Limit: no real historical save files exist in the repo, so old formats are reconstructions.

## 8. Remaining issues
- Memory still creeps a few % per season (retired players kept 3 seasons); plateau not demonstrated beyond 10 seasons.
- `end_season` (~0.5–1 s) is synchronous; only the weekly path is async. Worst sync week still up to ~0.6 s.
- Timings are on one noisy 4-vCPU container; budgets are generous. No real-GPU/Android measurements.
- A ledger/stat mismatch is a warning, not a load blocker, by design.
- Retiree purge and history caps are policy choices; confirm they suit design.

## 9. Next phase
Async `end_season`, a plateau test at 20+ seasons, real-device (Android) timings, a saved-file corpus for migration tests.
