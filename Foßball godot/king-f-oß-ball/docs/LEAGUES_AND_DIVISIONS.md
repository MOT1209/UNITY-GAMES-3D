# Leagues, Divisions and the Season Calendar

## Pieces

| File | Role |
|---|---|
| `scripts/data/league_def.gd` (`LeagueDef`) | A country's league system as shipped in a pack (`leagues/<key>.json`), plus validation: tiers 1..n, every club known and in exactly one division, relegation spots of tier *n* = promotion + play-off spots of tier *n+1*, valid play-off places, valid reserve links. Invalid leagues are not loaded (reported in `TeamDB.errors`). |
| `scripts/core/team_database.gd` | `load_world(pack_id)`, `load_pack`, `available_packs`, the saved pack choice (`user://settings.cfg [data] pack`), `leagues`. A pack replaces the default world. |
| `scripts/systems/competitions/league_pyramid.gd` (`LeaguePyramid`) | The live, season-by-season state of one country: current memberships, the season's competitions, the calendar, play-offs, cup, rollover. |
| `scripts/systems/competitions/match_simulator.gd` (`MatchSimulator`) | Engine-free result model (moved out of `AppHub`, identical numbers). |
| `scripts/systems/career/career_state.gd` | Creates one pyramid per country at career start, plays the week in `advance_week()`, runs the rollover in `end_season()`, saves pyramids with the career. |

## Season (46 career weeks)

- **League:** a double round robin per division (the existing `Competition.create_league`). Rounds are spread over weeks
  1–44. A 24-club division has 46 rounds, so a few weeks have a midweek double round.
- **Cup:** a knockout of every club in the country (`Competition.create_knockout`). The strongest clubs (tier 1 first, then
  reputation) get the first-round byes. Rounds are played in weeks 5, 11, 17, 23, 29, 35, 41, 43.
- **Play-offs:** when a division with play-off places has finished its league, the eligible clubs from those places
  (3rd–6th) play a knockout: 3rd vs 6th and 4th vs 5th in week 45, then the final in week 46.
- **Every week:** all fixtures that are due and do not involve the managed club are simulated. The manager's fixture
  appears on the Career dashboard ("Your matches this week"), where it can be played in 3D or quick-simulated. If the
  week passes without it, it is simulated, so the season can never stall.

## Rollover (`end_season`)

1. Any open fixture is simulated, including play-offs and the cup.
2. Prize money for every club by final position: tier 1 starts at €40M and drops €1.5M per place. Tier 2 starts at €6M
   and drops €0.2M per place, with a €0.5M minimum. Clubs relegated from tier 1 also get a €20M parachute.
3. For every pair of adjacent tiers, the bottom *relegate* clubs go down. The top *promote* clubs plus the play-off
   winner go up. Sizes never change.
4. **Reserve teams** (e.g. Real Sociedad B) can't go up into their parent's division. They are skipped for direct
   promotion and for the play-offs, and the next eligible club moves up.
5. The season summary (tables, champions, promoted/relegated, play-off winners, cup winner) goes into
   `LeaguePyramid.history`. Old competitions are removed from the career and the next season's are created.

## UI

- **Team Selection:** in a pack world, pick country → division → club.
- **Leagues** (new screen):
  - country and division pickers
  - table with zones: green = promotion, gold = play-off, red = relegation, ● = your club
  - this week's results
  - cup bracket button
  - last season's champions and movements

  The screen opens on the manager's own division.
- **Career dashboard:** division and position, plus your matches this week (Play in 3D / Simulate). The end-of-season
  message says if your club went up or down.
- **Settings:** Game world (fictional / real pack), with the source and estimate notes.

All new text is in `translations/leagues.csv` (en/de/ar). Club and player names are data and are not translated.
Numbers in tables are bidi-isolated so negative goal differences read correctly in Arabic.

## Tests

`tests/league_pyramid_validation.gd` covers:

- **Pack:** loads and is valid, the default world is untouched in headless runs, and broken league files are rejected.
- **Calendar:** every fixture falls inside the 46-week season, a 20-club division has no double weeks, and cup byes are correct.
- **Weekly play:** the user's fixture is left to the user, then auto-simulated once its week passes.
- **Three full seasons:** the right clubs go up and down, including the play-off winner; sizes stay constant; no club is
  lost or duplicated; every fixture is played exactly once.
- **Save/load:** works mid-season and after a rollover, and the results are deterministic.
- **Reserve-team rule.**
- **UI flows** in en/de/ar.

Importer: `tools/import_real/tests/test_import.py`.

## Not done yet

More countries, continental cups, national teams from real data, two-legged play-offs/cup ties, a real fixture date
calendar (weeks are abstract), player loans between pyramid clubs by AI, top-scorer tables.
