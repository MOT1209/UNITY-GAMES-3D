# Master roadmap

Status per phase is in FEATURE_STATUS.md. Order and acceptance criteria:

1. **Core stabilization** — done (Phase 7 of the earlier numbering). Open: migration-chain audit, quick-sim reports.
2. **Advanced gameplay** — next. Done: tackle, fouls, free kicks, penalties, cards, corners, throw-ins, goal kicks, offside. Left: injuries, adjustable assists, referee model/advantage. Each changes MatchState and MatchStats and has a test. Prerequisite: split `match_manager.gd` (TECHNICAL_DEBT 1).
3. **Tactics and AI** — instructions that change behaviour only; opponent analysis; difficulty scaling.
4. **Career / manager** — manager profile, board objectives, reputation, job offers.
5. **Development** — mentoring, position changes.
6. **Transfers and finance** — negotiations, agents, sponsors, matchday revenue.
7. **World simulation** — news from real events, records, injuries/suspensions.
8. **Atmosphere** — crowd reactions tied to match events, weather, day/night.
9. **Visuals** — badges (need assets and licences), hairstyles/accessories (need meshes), AnimationTree, LOD, GPU profiling.
10. **Competitions** — continental cups, national teams, World Cup, awards; respect licensing.
11. **Replay and presentation** — event-based replay, cameras, commentary architecture.
12. **Multiplayer architecture** — design only until approved.

Rule: start the next phase only when the previous one's suites are green. Items blocked by assets or licences stay NOT IMPLEMENTED with the reason.
