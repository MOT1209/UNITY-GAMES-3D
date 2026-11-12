# Phase 7 — Repository Audit (7.1)

Base: `main` at `6f7af93` plus PR #4 (`ccaa743`, long-career fixes). Godot 4.7.2. Baseline before any Phase 7 change:
`tests/run_all.sh` → **2238 passed, 0 failed, 24 suites**. Findings below come from reading the code, not the old docs.

## Current architecture (verified in code)

| Layer | Where | Notes |
|---|---|---|
| Autoloads | `Loc`, `GameManager`, `TeamDB`, `AppHub` | Only four; `GameManager` = scene flow, `AppHub` = management state (career, squads, academies), `TeamDB` = teams/players/leagues. |
| Data | `scripts/data/` | `PlayerData` (+`appearance`), `TeamData`, `LeagueDef`, formations, tactics. |
| Systems | `scripts/systems/` | academy, career (+`PlayerLifecycle`), competitions (+`LeaguePyramid`, `MatchSimulator`), finance, match, promotion, scouting, squads, teams, training, transfers. |
| Match engine | `scripts/systems/match/match_manager.gd` | One `MatchManager` builds arena, ball, 22 players (+`TeamGoalkeeper`), three AI layers, HUD, goals, clock, half-time, full time, `MatchResult`. `MatchState` is the pure bookkeeping object. |
| Gameplay | `scripts/gameplay/`, `scripts/player/`, `scripts/teams/` | `FootballActions` (pass/shot/lob/dribble, emits signals), `PlayerController`, `TeamGoalkeeper` (dive/catch/throw, emits signals). |
| UI | `scripts/ui/` | Hub (`HubRoot`) + 22 screens built in code from `UIKit`; main menu; card/portrait system. |
| Player visuals | `scripts/players/`, `scripts/ui/cards/` | Appearance, faces, animation library, cards, portrait renderer. |
| Saves | `SaveManager` (career/world, v2), `AppHub.save_game` | Atomic write, versioned, migration. **No match save.** |

## Verified completed (TESTED-OK by a run in this container)

Gameplay phases 1–5, arena, career T1–T12, localization (en/de/ar), player visuals/cards/portraits (also under xvfb with real
rendering), real data pack (5 countries, 198 clubs), league pyramid (promotion/relegation, play-offs, cups), 12-season career
longevity. 2238 checks.

## Documentation vs code (reconciliation)

| Claim in old docs | Actual |
|---|---|
| `FINAL_INTEGRATION_AUDIT`: "Main-menu Play opens a stadium prototype" | **Outdated** — Play opens `match_setup` in the hub (`main_menu.gd`). |
| `FINAL_INTEGRATION_AUDIT`: "Settings button disabled (placeholder)" | **Outdated** — a settings panel exists (language + game world). |
| `FINAL_INTEGRATION_AUDIT`: "Real teams NOT IMPLEMENTED" | **Outdated** — implemented (data pack). |
| `STABILIZATION_REPORT`: "match results screen, pause menu NOT IMPLEMENTED" | **Correct** — see below. |
| `STABILIZATION_REPORT`: "in-progress match save NOT IMPLEMENTED" | **Correct**. |
| `plan.md`: "kit patterns not rendered" | **Correct**. |
| README: "many system error messages are still English" | **Correct**: 129 `return "…"` error strings in `scripts/systems`/`scripts/core`. |

## Incomplete / missing (confirmed)

1. **Post-match experience:** after full time the engine emits `match_finished`, shows only the HUD text and returns to the menu
   after a fixed 5 s timer. No results screen. `GameManager` documents "Not implemented: pause systems".
2. **Pause menu:** none. `pause` input action exists but only the dev test scenes use it.
3. **Match statistics:** `MatchState.events` records only `goal` and `full_time`. There are no shots, passes, saves, possession,
   assists or substitutions in the match record. `FootballActions` already emits `pass_started`, `shot_started`, `lob_started` and
   `TeamGoalkeeper` emits `ball_caught` / `dived`, but `MatchManager` does not listen. **No fouls or cards exist in gameplay**, so
   they cannot be measured (and must not be displayed).
4. **Match save/recovery:** none. `MatchSetup` and `Squad.to_dict` exist; `MatchSetup` has no serialiser.
5. **Career records of matches:** `CareerState` stores competition results only (score), no per-match report or player stats.
6. **Quick simulation** (`MatchSimulator`) produces scores only; it has no events, so no statistics exist for simulated matches
   (the UI must say so, not invent numbers).
7. **Kit patterns** stored (`TeamData.kits[slot].pattern`) and previewed in UI but not rendered on the 3D model; `TeamKit.from_dict`
   ignores the pattern.
8. **Visuals still missing:** rotating 3D preview, club badges (no licensed art; see blockers), extra hairstyles (needs meshes),
   accessories (needs meshes), training kits.
9. **Localization:** system-layer errors are English strings; hard-coded display strings remain in a few places (listed in the
   Phase 7 localization audit).

## Bugs / technical debt found

- `PlayerAI._keeper` is dead code (the match uses `TeamGoalkeeper`) but still covered by T11 — duplicate keeper implementation.
- `MatchManager` returns to the menu on a timer even when the result was never shown (data is correct, UX is not).
- `GameManager.last_match_result` and `AppHub._on_match_finished` both react to the match end: result recording is protected by
  `Competition.submit_result` (a fixture can be recorded once), but there is no guard for friendlies/duplicates beyond that.
- Face system costs ~350 ms for 22 players at match start (14 nodes per face) — to be profiled and reduced (7.6).
- `MatchSetup` ids for fixtures: `match_id` empty for friendlies (fine), required for competition matches (validated).

## Performance risks

22 players × (model + ~14 face nodes) at match start; portrait renderer fine (bounded cache); collection screen builds all cards
at once. No GPU available in the container → frame-time/GPU numbers can only come from software rendering (llvmpipe) and are
**not representative**; real-GPU performance remains NOT TESTED.

## Test coverage gaps

No test opens a real match and plays it through; `phase6` / `T12` cover pieces (goal detection, half-time, keeper, kits). No test of
results screen, pause, match save/load, per-match statistics, or the complete flow (menu → setup → match → results → career → save).
No test measures performance.

## Blockers recorded up front

- **Club/national badges:** real badges are trademarks and no licensed art is available; only procedurally generated crests are
  possible. Real badges: **NOT IMPLEMENTED (blocked: licensing/assets)**.
- **Extra hairstyles and accessories** require new meshes (no DCC tool in this environment).
- **Real-GPU profiling:** no GPU in the container.
- **Fouls/cards:** no gameplay mechanic exists.

## Recommended order (followed)

7.3 events/statistics → 7.2 results screen + pause → 7.4 match save/load → 7.5 flow/career integration → 7.6 profiling →
7.7 visuals + localization → 7.8 end-to-end test → 7.9 docs and final stabilisation.
