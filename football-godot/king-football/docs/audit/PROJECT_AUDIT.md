# KING FOOTBALL — Project Audit (Phase 0)

Audit date: 2026-11-17 · Branch: `main` · HEAD: `9fdb5bb` (merge of PR #42) · Engine: Godot 4.7.2 · Host: Windows (this session)

Evidence labels: **[RAN]** executed this session · **[READ]** source read/grep'd this session · **[DOC]** from existing docs only.

This file is the master audit for the current repair programme. The deep-dive from the previous session lives in
`docs/audits/MASTER_AUDIT_2026-11-16.md` (revised 2026-11-17); per-feature detail is in `docs/FEATURE_STATUS.md`.
This audit does not repeat them — it records the current repo state, what was verified this session, and what is open.

## 1. Repository state [RAN]

- `main` was 4 commits behind `origin/main`; fast-forwarded to `9fdb5bb` before any work. Local "changes" to three
  commentary `.translation` files were verified byte-identical to upstream (`git hash-object` vs `git cat-file`)
  and discarded as re-import churn. Working tree clean afterwards.
- PR #42 renamed the project to ASCII paths: `football-godot/king-football` (this directory). CI workflow paths
  updated in the same commit and re-verified this session [READ].
- 230 GDScript files / ~40.9k lines under `scripts/` [DOC, prev audit]; 99 validation suites registered in
  `tests/run_all.sh` [READ].

## 2. Recent PRs re-verified in source (not trusted from documentation)

| PR | Claim | Verified where | Verdict |
|----|-------|----------------|---------|
| #40 | Advantage rule (play on / call back) | `match_rules.gd:28-219` (`ADVANTAGE_SECONDS`, `_advantage_applies`, `_update_advantage`, `end_advantage`); `match_manager.gd:417-418`; 15 dedicated checks in `tests/match_rules_validation.gd:176-248` incl. commentary/HUD translations | Implemented + tested **[READ]** |
| #41 | Match analytics: xG, shot-map xG, heatmaps | `expected_goals.gd` (documented location-only model); `match_state.gd:141-151` (shot map with xG); `match_report.gd:34-68` (`heatmaps`, `ESTIMATED` label); `scripts/ui/match/match_results_view.gd:97-192` (heatmap + shot-map views, xG row gated on the report declaring the estimate); `match_stats.gd:25-27` (`ESTIMATED = ["xg"]`) | Implemented + tested **[READ]** |
| #42 | ASCII paths + CI paths + root README | Directory layout on disk; `.github/workflows/king-football-tests.yml` points at `football-godot/king-football` | Verified **[RAN]/[READ]** |

## 3. Architecture summary [READ]/[DOC]

Autoloads `Loc`, `GameManager`, `TeamDB`, `AppHub`. Match core `MatchManager` (924 lines, was 1064) delegates to
`MatchRules`, `MatchRestarts`, `MatchReferee`, `MatchStats`, `MatchReport`, `MatchSnapshot`, `MatchAIDriver`,
`TeamAI`, `PlayerAI`, `ManagerAI`, `Replay*`, `MatchSave`. Save `SAVE_VERSION = 3`, step-wise migration, newer
saves refused (`save_manager.gd:15,91-113`) [READ]. Controller protocol v3. Renderer `gl_compatibility` (Windows
D3D12 driver, mobile GL), physics Jolt (`project.godot:140-149`) [READ].

## 4. Test baseline

- Previous [DOC]: quick 5518/0; full 5841/3 (`career_p1_long_validation`: save size, advance_week 645 ms vs
  350 ms budget, 46-week season 29.7 s vs 18 s budget — timing measured on shared software-rendered CI).
- Current Windows run: **in progress this session** — see `docs/audit/BUG_REPORT.md` and
  `STABILIZATION_REPORT.md` for the recorded result once it completes.

## 5. Feature classification (top-level, per master prompt)

| System | Status |
|--------|--------|
| Match loop, rules, restarts (fouls, cards, FKs, pens + shoot-out, throw-ins, corners, goal kicks, offside, advantage) | Complete and verified (suites green; advantage verified this session) |
| Match analytics (xG, shot map, heatmaps, timeline, commentary) | Complete and verified this session (PR #41) |
| Team tactics + individual instructions | Implemented, needs improvement (difficulty depth — F3) |
| Handball rule | **Missing** — no ball-contact body-part data exists; a dice-roll handball is forbidden (F1) |
| Transfers v2, contracts, loans, clauses | Implemented and tested; agent fees missing (F5) |
| Finance ledger, economy v2 | Implemented, tested |
| Career mode (manager profile, board, news, awards, national breaks, youth academy, scouting) | Implemented, tested; isolated-menu risk → needs cross-system interaction audit |
| Competitions (league pyramid, promotion/relegation, continental) | Implemented, tested |
| Save system v3 + migrations | Implemented, tested; size/load-time risk (F11) |
| KING Controller (pairing, sessions, live data v3) | Implemented; custom layouts/profiles missing (F7); no-TLS transport documented |
| Localization ar/de/en + RTL | Implemented, tested |
| Android presets (min 24 / target 36, Gradle build on, arm64+v7) | Present [DOC]; **no real-device or real-Gradle verification** (F8) |
| Windows runtime | Builds/runs headless; device-level input/perf verification limited to CI software rendering |

## 6. Open findings (carried from MASTER_AUDIT 2026-11-17, re-checked this session)

F1 handball (H, blocked on contact data) · F3 difficulty decision-depth (M) · F5 agent fees (M) ·
F6 MatchManager debt hotspot (M, 924 lines now) · F7 controller layouts/profiles/haptics (M) ·
F8 real-device Android verification (H, needs hardware) · F9 Windows two-human pause flake (L, no trace) ·
F10 documentation drift (L) · F11 save size/structure (M) · F12 sparse error logging (L).

Full table with repairs: `docs/audits/MASTER_AUDIT_2026-11-16.md` §3.

## 7. Phase-0 verdict

No failing evidence for the master prompt's Phase 1 premise ("fix runtime errors, broken references") exists at
this commit: guards for duplicate `class_name` and suite registration are in place, all suites green at the
previous audit. The programme proceeds to stability verification (current test run), then the prioritised repairs
in `docs/audit/DEVELOPMENT_ROADMAP.md`.
