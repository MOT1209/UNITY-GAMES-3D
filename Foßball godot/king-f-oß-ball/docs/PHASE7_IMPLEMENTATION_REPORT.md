# Phase 7 — Implementation report

Status labels: **IMPLEMENTED** (code exists), **TESTED-OK** (automated test passes), **TESTED-WITH-FAILURES**,
**NOT TESTED**, **NOT IMPLEMENTED** (with the reason). Nothing below is claimed without a test or a measurement.
Audit: [PHASE7_AUDIT_REPORT.md](PHASE7_AUDIT_REPORT.md). Performance: [PHASE7_PERFORMANCE_REPORT.md](PHASE7_PERFORMANCE_REPORT.md).

## Test result (Godot 4.7.2, headless, `tests/run_all.sh`)

2437 checks passed, 0 failed, 0 suites failed. Importer unit tests: 14 OK.
New suites: `match_stats_validation` 37, `match_flow_validation` 77, `phase7_localization_validation` 19,
`phase7_end_to_end_validation` 35. Extended: `player_visual_validation` 137, `player_visual_integration_validation` 72.
`player_card_validation`: 82 passed, 1 skipped (portrait rendering is skipped without a window; run under xvfb for the real portraits).

## Workstreams

| # | Item | Status |
|---|------|--------|
| A | Results screen (score, scorers, stats, ratings, MVP, continue/rematch/menu), pause menu (resume/settings/controls/save/restart/quit with confirmations), Esc handling, match flow | IMPLEMENTED, TESTED-OK |
| B | In-progress match save/restore (`MatchSave`, versioned, `.bak` recovery, validation, "Resume saved match"), exactly-once result handling | IMPLEMENTED, TESTED-OK |
| C | `MatchStats` event pipeline: passes, shots, on target, saves, goals, assists, possession, substitutions; deterministic ratings; `MatchReport`; career `match_log` / `player_stats` | IMPLEMENTED, TESTED-OK |
| C | Fouls, cards | IMPLEMENTED later, see FEATURE_STATUS.md (`MatchRules`) |
| C | Offsides, corners | NOT IMPLEMENTED — no such mechanic; no number is invented |
| C | Reports for quick-simulated matches | NOT IMPLEMENTED — only the score is produced |
| D | Profiling (`tools/profile_match.gd`) and fixes: 22 players 403 → ~66 ms, match start-up 382 → ~104–149 ms, face nodes 220 → 44 | IMPLEMENTED, MEASURED (software renderer) |
| D | FPS / draw calls on a real GPU | NOT TESTED — no GPU here; llvmpipe 5.1 FPS is not representative |
| E | Kit patterns on the 3D jersey, rotating 3D preview on the profile, captain's armband | IMPLEMENTED, TESTED-OK |
| E | Club / national badges | NOT IMPLEMENTED — licensing, no assets |
| E | Extra hairstyles and accessories | NOT IMPLEMENTED — need authored meshes |
| E | Training kits | NOT IMPLEMENTED — no consumer in the game |
| F | `ErrorText` layer: 86 rules map internal error strings to translation keys (ar/de/en); 100 % of the 123 error literals in systems/core mapped; results/pause/HUD localized; Arabic score kept LTR | IMPLEMENTED, TESTED-OK |
| G | Career integrity: match report recorded once, lineups never rewritten by matches (matches use `duplicate_for_match`), season/finance/save round trip covered by the end-to-end test | PARTLY TESTED — Friendly/Tournament/Training modes rely on earlier suites, not on new dedicated tests |
| H | `phase7_end_to_end_validation`: real engine, real input actions, pass, shot, goal, half-time with side switch, full time, result, competition, finance, results screen, save/load | IMPLEMENTED, TESTED-OK (35/35) |

## Bugs found and fixed

- Esc during a real match returned to the menu (arena also handled `pause`).
- Manager-AI substitutions rewrote the career lineup; matches now play on copies.
- `initial_setup_dict` aliased live squads (deep copy).
- Pause sub-menu button name collision.
- Arabic score displayed "0 - 1" for a 1-0 win (label forced LTR).
- Arena HUD text bled through the results screen and was English-only.
- 350 ms start-up cost was the animation library regenerated per player.
- Face merge produced an empty mesh (packed arrays inside a dictionary).

## Known limitations / risks

- Possession is "side that last controlled the ball", not time-on-ball physics.
- Ratings are a deterministic function of the measured events, not a real rating model.
- Check 12b of the end-to-end test first looked like an engine bug; it was the test moving the keeper. The test now reads the keeper's post.
- Real-GPU performance and visuals on device are unverified.
