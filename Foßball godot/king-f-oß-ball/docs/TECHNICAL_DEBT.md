# Technical debt

1. `match_manager.gd` was split: save/restore moved to `MatchSnapshot`, rules to `MatchRules` / `MatchRestarts`. It is again ~720 lines (replay, crowd and environment wiring were added) (placement, pause, HUD, possession, results); next extraction candidates: pause/results flow.
2. `AppHub` and `GameManager` are large singletons; new systems should take dependencies as arguments.
3. `scripts/player` vs `scripts/players` naming is confusing (controller vs data/visual).
4. No static scan for broken scene/resource references.
5. README still has an old paragraph saying Phase 5+ is "not started".
6. Matches simulated without the engine have no real statistics; season awards use a documented statistical model for them (`SeasonStats`).
7. Performance was measured only on a software renderer.
8. Controller input navigation is not tested.
9. The full suite takes about 13 minutes (the 12-season test is the bottleneck, ~15 s of league simulation per season).
10. The transfer history stores only the week, so old transfers appear in the current season in the news.
11. Crowd audio and the rain / floodlight visuals are verified by state only (no listening, no screenshot of the effects).
12. The negotiation API has no screen; the financial report has no screen.
13. A career save in the real data pack is about 8 MB of JSON (measured after one season); season statistics are part of it until the season ends.
14. AI attack (partly fixed in the review): before, 18 full AI-vs-AI matches (2 minutes, three difficulties) gave 0-3 shots, 0-34 passes and 2 goals in total, with the tackle system on or off. Causes found by tracing the ball: the two strikers duelled at the centre circle for the whole match (no forward pass target at kick-off, no way round a blocker). Fixes: early pass when blocked, sideways / back pass when pressed with nothing ahead, a run that bends round the blocker, shooting from 1.3 x the shoot range with an open lane, the team pushing up with the ball (forwards run ahead through `support_offset`). Measured with `tools/sim_matches.tscn` (3 matches x 2 min, normal / hard): passes 42 / 19 -> 132 / 100, shots 3 / 1 -> 5 / 7, goals 0 / 0 -> 1 / 1, 0 red cards, no stalemate (closest carrier to goal <= 29 m in every match). Second round: tracing the AI's shoot presses showed that only about one in five became a real shot (the press was sent when the ball was not within reach, or the player ran on and the charge was cancelled). `_can_start_kick` now checks the ball is in reach and the player stands still while a kick charges: conversion of attempts to shots rose to about 40 %, passes 127-223 per 3 matches, goals 1. Still low: 0-4 shots per match (target 5-12) and one hard match with 0 shots; more work: crosses, through balls, finishing quality, a goalkeeper that does not always clear to the middle. The sample is small (6 matches per setting).
15. The first foul system (before the tuning in the review) gave 3 red cards per hard match; the tackle rate, foul share and card severity were reduced (see `MatchRules`); re-check with `tools/sim_matches.tscn` after any AI change.
