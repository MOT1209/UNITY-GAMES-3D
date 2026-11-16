# KING FOOTBALL — Master development audit (Phase 0)

Date: 2026-11-16 · Repo HEAD at audit: `1ec4565` (merge of PR #32, Transfers v2) · Engine: Godot 4.7.2 (downloaded and
used headless on Linux for this audit) · Size: 321 GDScript files, ~60k lines, 228 `*_validation` scripts in `tests/`.

How to read this: every row says what was **verified** (file read, grep, or test run in this session) versus
**inferred from existing docs**. Nothing here changed game code. Classification follows the master prompt:
A = COMPLETE (preserve), B = PARTIAL (improve), C = MISSING (build).

> **Update 2026-11-16:** an event log already existed (`MatchState.events`, readers: crowd, sounds, report). It lacked
> ids, exact time, position and shot outcome; these were added (see `docs/MATCH_EVENT_LOG.md`). Roadmap item 1 is done.

## 1. Architecture (verified)
Autoloads `Loc`, `GameManager`, `TeamDB`, `AppHub`. `scripts/systems/*` holds the domain systems (academy, career,
competitions, controller, crests, finance, flags, generation, input, match, promotion, scouting, squads, teams, tools,
training, transfers). `scripts/ball`, `scripts/gameplay` (kick/pass/shoot/dribble), `scripts/player`
(controller + visual) and `scripts/players` (data) are the on-pitch layer. Match core: `MatchManager` (900 lines,
the main debt item) delegating to `MatchRules`, `MatchRestarts`, `MatchReferee`, `MatchStats`, `MatchReport`,
`MatchSnapshot`, `TeamAI`, `PlayerAI`, `ManagerAI`, `Replay*`. Sources of truth: `PlayerData`, `MatchState`,
`CareerState`. Controller: protocol/registry/session/server/hub + `assets/controller/controller_page.html`.

## 2. Feature inventory

| Area | Class | Evidence |
|---|---|---|
| Core match loop, restarts, cards, fouls, penalties, shoot-out, offside, corners, throw-ins, goal kicks | A | `match_rules.gd`, `match_restarts.gd`, `match_flow_validation`; MASTER_ROADMAP |
| Advantage rule | B/C | one grep hit in `scripts`; roadmap lists "referee model/advantage" as open |
| Handball | C | 0 hits |
| Team-level tactics (mentality, pressing, support offset) | B | `team_ai.gd` (90 lines) uses `tactics.pressing/mentality`; presets in `data/tactics_preset.gd` |
| Individual player instructions (Stay Back, Cut Inside, marking...) | C | no instruction data type or AI use found; roadmap says "still to build" |
| Adaptive opponent AI / meaningful difficulty | C/B | `setup.difficulty` exists and is selectable; `CURRENT_PROJECT_AUDIT` #9 says no opponent analysis. **What difficulty actually changes is not yet checked** — first task of Phase 1 |
| Player AI decisions (pass, shoot, cross, through ball) | B | `player_ai.gd` 280 lines; TECHNICAL_DEBT #14 documents measured, still-low goal rates and pass variance |
| Goalkeeper AI | B | exists; "keeper does not always clear to the middle" listed as open |
| Ball physics | A/B | `ball_controller.gd` 180 lines + `BALL_PHYSICS.md`; spin / air resistance not verified |
| Animation | B | cross-fading locomotion clips; AnimationTree deliberately not introduced; reaction clips exist |
| Replay | B | `replay_buffer/director/player` (~290 lines): goal replay with angles; no foul/save/chance selection, no timeline UI. Whether it records real positions is expected (buffer) but unverified |
| Commentary | C | no implementation; `crowd_audio.gd` states no audio assets exist |
| Weather / lighting | B | rain + floodlights in `match_environment.gd` (state-verified only, TECHNICAL_DEBT #11); no snow/fog/wind gameplay effect found |
| Crowd | B | `crowd_system`, `stand_crowd`, synthesized `crowd_audio` |
| Stadium variety | B | `stadium_arena`, `stadium_prototype`, `stadium_stands` |
| Match stats | A/B | `match_stats.gd` 271 lines; saves / shots on target fixed |
| Heatmaps, shot maps, xG/xA, timeline, rich post-match report | C | 0 hits; `match_report.gd` is 89 lines |
| Career, board objectives, manager profile, news, awards | A/B | `career_state`, `board_objectives`, `manager_profile`, `news_feed`, `season_awards`; `career_p1_validation` |
| Finance | B | `finance_ledger.gd` 108 lines; financial report has no screen (TECHNICAL_DEBT #12) |
| Transfers v2 (offers, negotiation, loans, instalments, release clauses, signing bonus, AI offers) | A | `transfer_market.gd` 1697 lines, `transfers_v2_validation`. Agents / commission / performance bonuses: 2 `agent_` hits only — treat as C until checked |
| Youth Academy, scouting, promotion | A | `systems/academy`, `scouting`, `promotion` |
| Injuries | A/B | 10 files reference injuries (not audited in depth) |
| Localization ar/de/en + RTL | A | `localization_validation` 90 checks, screenshots |
| KING CONTROLLER protocol v2, pairing, sessions, 2 phones, pause, hardening | A | architecture doc read in full |
| Controller: custom layouts/profiles, tactics, live dashboard, haptics, tutorial, analytics, mini-map | C | none present |
| Real-device controller QA | C | "NOT TESTED" in `qa/KING_CONTROLLER_QA.md`; impossible from this container |
| Save system | B/A | versioned `save_manager`, autosave slot; 8 MB career JSON (TECHNICAL_DEBT #13) |
| Performance on real hardware | C | only llvmpipe numbers; 60/30 FPS unverified on a device |

## 3. Bugs and stability
1. **Two-human Pause/Resume flake** (reported on Windows: 40/1, 41/0, 40/1). **Not reproduced here**: 14/14 runs
   passed (6 idle, 8 with 8 busy-loop processes on 4 cores; Linux headless, Godot 4.7.2). Code path read:
   `ControllerRegistry.apply_input` (rising edge + 500 ms debounce) -> hub `_on_pause` ->
   `MatchManager.toggle_pause_from_controller`, which toggles on `pause_menu != null`. The test resumes 0.7 s after
   a clean packet, so a miss needs a dropped / reordered packet or a timing difference specific to the Windows host.
   No fix was made, because none can be justified without a failing run. Next step: run the suite repeatedly on the
   Windows host with logging of `pause_down`, `last_pause_ms` and `get_tree().paused` at the failing check.
2. Matches simulated without the engine have no real statistics (TECHNICAL_DEBT #6).
3. Transfer history stores only the week (TECHNICAL_DEBT #10).
4. Goals are rare in AI-vs-AI (TECHNICAL_DEBT #14); measure with `tools/sim_matches.tscn`.

## 4. Technical debt
`match_manager.gd` is 900 lines (docs say 758 and ~720 in different places: doc drift); `AppHub` / `GameManager`
singletons; `player` vs `players` naming; no static broken-reference scan; README has a stale "Phase 5+ not started"
paragraph; `FEATURE_STATUS.md` / `MASTER_ROADMAP.md` still list release clauses and replay as unbuilt although code
exists.

## 5. Performance
Only software-renderer numbers exist; known cost centre is the 9-surface player body mesh. Real-pack world load was
cut 11.8 s -> 5.4 s. No profiling-driven work is justified without a device / GPU measurement.

## 6. Dependency map (build order)
1. Typed, timestamped match event log with positions in `MatchState` / `MatchStats` -> needed by replay selection,
   commentary, shot maps / xG, heatmaps, controller dashboard and mini-map.
2. Player-instruction data type on the tactics model -> `PlayerAI` / `TeamAI` behaviour -> controller tactics page.
3. Commentary needs the event log plus text keys in `Loc` (audio later).
4. Controller dashboard / mini-map / tactics add PC->phone state frames; frames are capped at 1024 bytes, so they
   need compact snapshots or a protocol bump.

## 7. Roadmap (smallest verified steps first)
1. Event-log audit and typed match events.
2. Post-match analytics from real events: shot map, timeline, heatmap; xG only if shot position / type is recorded.
3. Player instructions (3-4 that genuinely change `PlayerAI` / `TeamAI`) with tests; difficulty as decision quality.
4. Rules: advantage and handball with `match_rules_validation` cases.
5. Event-driven commentary text (ar / de / en) as subtitles.
6. Controller: custom layouts / profiles (client-side, no protocol change), then haptics, then dashboard / mini-map.
7. Documentation drift cleanup.

## 8. Limits of this audit
No phones, Android device or GPU here: real-device QA, camera QR scanning, ten-minute Wi-Fi sessions and performance
claims are NOT TESTED and cannot be verified from this container. The Phase 11 (save system) text of the master prompt
was cut off in the message, so that phase is only partly covered.
