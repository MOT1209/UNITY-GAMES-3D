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
14. AI attack is weak: in 18 full AI-vs-AI matches (2 minutes, three difficulties) there were 0-1 shots and 0-34 passes per match and only 2 goals in total, with the tackle system on or off (so it is not caused by fouls). Needs a dedicated AI pass: carriers dribble towards goal and shoot only inside 24 m; they rarely pass or cross; defenders and chasers crowd the ball.
15. The first foul system (before the tuning in the review) gave 3 red cards per hard match; the tackle rate, foul share and card severity were reduced (see `MatchRules`); re-check with `tools/sim_matches.tscn` after any AI change.
