# Technical debt

1. `match_manager.gd` (729 lines) mixes placement, pause, save, HUD, possession and results. Split before adding fouls and set pieces.
2. `AppHub` and `GameManager` are large singletons; new systems should take dependencies as arguments.
3. `scripts/player` vs `scripts/players` naming is confusing (controller vs data/visual).
4. No static scan for broken scene/resource references.
5. README still has an old paragraph saying Phase 5+ is "not started".
6. Match statistics for quick-simulated matches only store the score.
7. Performance was measured only on a software renderer.
8. Controller input navigation is not tested.
