# Long Careers — Player Lifecycle, AI Squads and the Season Calendar

Added after the game review (2026-11-12). The review found that long careers broke: nobody retired, so after about
10 seasons a player passed the age limit of 50 and **saves refused to load**. AI clubs never signed anyone, so their
squads aged and the leagues lost their meaning.

## Between two seasons (`CareerState.end_season` → `PlayerLifecycle.run`)

1. **Contracts (AI clubs):** an expiring contract is renewed when the player is ≤ 29, or ≤ 32 and within 4 points of
   the club's level (`PlayerLifecycle.ai_renews`). Otherwise he is released. The user's club is never decided
   automatically.
2. **Ageing:** squad players age in the rollover. Free agents age in the lifecycle (never twice). Retired players
   never age again.
3. **Retirement:** the chance starts at 33 (35 for keepers) and rises steeply. Retirement is certain at 40 (keepers 42).
   The draw is deterministic per player and season. Retired players leave their club and any lineup and get status
   `RETIRED`. The season summary reports the user's retirements (`retired_mine`).
4. **Development outside the academy:**
   - up to 23: +0..3 per season toward potential, never past it
   - 31–33: −0..2
   - 34+: −1..3

   Potential always stays ≥ overall. The user's academy still develops through `TrainingSystem`.
5. **AI squad upkeep**, for every club except the user's:
   - **Minimums:** 22 players, ≥ 2 GK, 6 DEF, 6 MID, 4 FWD. Short lines are filled first with the best suitable free
     agent (at most club level + 6, age ≤ 33, normal market rules). Otherwise the club brings in a young player
     (18–22) at about its *base level* − 3, whose potential peaks around the base level.
   - **Quality:** if the club's XI falls more than 2 points below its base level, it brings in up to 3 ready players
     (23–27, about base level). A full squad releases its weakest outfield veteran first.
   - **Base level:** `CareerState.club_levels`, recorded at career start and saved. Anchoring new players to it, and not
     to the current XI, prevents feedback loops: every division stays within ±2.5 of its starting average over
     12 seasons (measured).

## Season calendar

- `advance_week()` stops at week 46: nothing is played and no wages are paid until the season is ended.
- **Career dashboard:** at week 46 "Advance week" is disabled, "End season" is highlighted and a hint is shown. Ending
  earlier warns how many weeks are left and that all remaining matches will be simulated.
- **Standings of a league-pyramid competition:** no "simulate round / all" buttons, because they would put rounds and
  weeks out of step. There is a calendar hint, and only the user's due fixtures can be played or simulated.
  Hand-made competitions from the Competitions screen keep the old buttons.

## Localization fixes from the review

- **Result message after a 3D match:** `HUB_RESULT_*`.
- **Pyramid competition names:** play-off and relegation play-off names are built in the UI through `Loc`
  (`AppHub.competition_title`, `LeaguePyramid.display_name_of`).
- **Finance:** ledger entries carry an optional `key` + `args`, and the finance screen prefers them. Wages, matchday
  income, league prize money and parachute payments use them. Old saves show the stored text.
- **Game-world picker:** it is now a shared control (`WorldPicker`), so it appears in the hub's Settings and in the
  main-menu Settings panel.

## Tests

`tests/career_longevity_validation.gd` runs 12 seasons with the real pack (about 2 minutes). Every season it saves,
JSON-round-trips and validates. It checks:

- no active player is over 45, and retired players hold no club;
- every AI club has 22–30 players and ≥ 2 keepers;
- no player is in two squads;
- more than 200 retirements and replacements happen;
- division sizes stay constant;
- the per-division average stays within ±5;
- the calendar blocks at week 46;
- the long career loads.

Last run: 3,521 retirements and 5,244 players brought in over 12 seasons. Every division ended within 2.5 points of
its start; e.g. the Premier League went from 82.8 to 80.9.

## Known limits

- AI clubs do not buy players from other clubs. Their signings are free agents or generated players
  ("transfer-window abstraction").
- Injuries, suspensions and form are still not simulated.
- Reputation is static.
