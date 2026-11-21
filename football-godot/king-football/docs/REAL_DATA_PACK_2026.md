# Real Data Pack 2026-27 (`data/packs/real_2026`) — the five leagues

Season **2026-27**, added one country at a time:

| Country | Tier 1 | Tier 2 | Cup |
|---|---|---|---|
| Spain | LaLiga: 20 clubs, 511 players | Segunda División: 22 clubs, 571 players | Copa del Rey |
| England | Premier League: 20 clubs, 546 players | Championship: 24 clubs, 646 players | FA Cup |
| Germany | Bundesliga: 18 clubs, 493 players | 2. Bundesliga: 18 clubs, 455 players | DFB-Pokal |
| Italy | Serie A: 20 clubs, 546 players | Serie B: 20 clubs, 427 players | Coppa Italia |
| France | Ligue 1: 18 clubs, 464 players | Ligue 2: 18 clubs, 452 players | Coupe de France |

Italy: players without an English article are accepted when the club's Italian "Rosa 2026-2027" lists them with the
same shirt number AND their Italian article ({{Bio}}) gives the date of birth (19 players). Many Serie B players exist
in both squad lists but have no date of birth anywhere; they are left out rather than given an invented age. Clubs left
short (fewer than 18 players or 2 keepers) are topped up at **career start** by `PlayerLifecycle.ensure_minimum` with the
game's own generated youth players (ids `gen_…`, typed GENERATED, never presented as real). Serie B play-off: 3rd-8th.

Germany: players without an English article are verified on **German Wikipedia** (`fallback_wiki: "de"`), with two
rules: (1) the player's own German footballer article has a date of birth and an open-ended senior station at this
club (62 players); or (2) the club's own German article lists him in its "Kader 2026/27" table with the **same shirt
number** and a date of birth (13 players, two independent squad lists agree). The German club infobox fills a missing
manager / stadium. Relegation: 17th/18th down, top two up, the 16th plays the 2. Bundesliga's 3rd.
Total pack: 122 clubs, 3,222 players, 117 rows excluded.

86 clubs, 2,274 players. Every player is a real, verified player (no generated names). It is a separate pack, chosen
in **Settings → Game world** ("Real leagues 2026-27 (Spain + England)"); `real_2025` (five countries, 2025-26) is
unchanged, so saves made with it keep loading. Germany, Italy and France still come from `real_2025` and follow with
the same tools (see "Adding a league").

England in numbers: Premier League 529 of 546 players matched to transfermarkt (unknown: contract 233, foot 22,
market value 29, height 6); Championship 502 of 646 (the snapshot covers fewer second-tier players). 21 English
rows excluded: 16 without a Wikipedia article, 3 by the nationality rule, 2 whose article names another club (on loan
at Yeovil Town / Woking). New clubs: Bolton Wanderers, Cardiff City, Lincoln City.

Squads over 30 (TransferMarket.MAX_SQUAD) drop the highest shirt numbers first, but never a player worth 3M EUR or
more: in England new signings take high numbers (Hull City lists 33 players).

## Why not transfermarkt-datasets alone

The dataset behind `real_2025` **stopped updating on 2026-07-06** (its README: "2026/27 squads are not covered").
Its squads therefore miss every summer-2026 transfer and contain no players for the promoted clubs. The official
LaLiga / club squad pages render their player tables with JavaScript and cannot be read by a build script.

## Sources and rules (tools/import_real/build_2026.py)

| Data | Source | Rule |
|---|---|---|
| Clubs per division | Wikipedia "2026–27 La Liga" / "2026–27 Segunda División" | Cross-checked with openfootball's 2026-27 LaLiga fixture file (CC0): the build stops unless all 20 clubs agree |
| Squad, shirt numbers, sporting nationality | "Current squad" table of each club's Wikipedia article | Maintained from the club's official site (numbers only once official); the `{{updated}}` date and article revision are kept in each club file (`squad_source`) |
| **Verification** | the player's own Wikipedia article | A squad row is accepted only if the player has a footballer article whose infobox names **this club** (or its reserve side) as current club, with a date of birth. Everything else is excluded and listed in `pack.json → report.excluded` |
| Date of birth, height, positions (incl. secondary) | the player's infobox | |
| Preferred foot, detailed position, market value | transfermarkt-datasets (snapshot 2026-07-06), matched by **exact date of birth + name** | names must be nearly identical, share two parts, or be a one-word name / abbreviation of the full name; a shared surname is not enough (it had matched e.g. Iván Medina to Tobías Medina) |
| Contract end | same | only when the player was already at the same club in the snapshot |
| Manager, stadium, capacity | club infobox | |
| Ratings | **estimates** | the `real_2025` market-value model; players without a market value: club median − 2 (`rating_basis: club_median`) |

Fields no source provides are **not invented**: each player lists them in `unknown_fields`
(LaLiga: contract 221, foot 48, market value 67, height 1; the game needs a foot value and uses RIGHT for those).
Contracts that ended before the season (e.g. 30 June 2026 in the July snapshot) count as unknown.

Excluded at build time (21): 18 rows without a Wikipedia footballer article (11 of them Athletic academy rows,
among them clearly vandalised names), 1 whose own article names another club (José Antonio de la Rosa: Cádiz table
vs. Wieczysta Kraków), and 2 by the project's nationality rule (`build_pack.EXCLUDED_NATIONALITIES`). One duplicate
(Jones El-Abdellaoui, listed by Celta and Celta Fortuna) is kept at Celta; Athletic's 31st verified player (#44) is
dropped by the 30-player squad limit.

## Game integration

- Same JSON format as `real_2025` → TeamDatabase, career, transfer market, search, squads, profiles, standings use it
  unchanged. Club ids of clubs that exist in `real_2025` are kept (`esp_real_madrid_c_f` …); new: `esp_cd_tenerife`,
  `esp_cd_eldense`, `esp_ce_sabadell`, `esp_rc_celta_fortuna`.
- Player ids: `tm_<transfermarkt id>` when matched, else `wp_<article slug>` (typed REAL by `PlayerData.type_for_id`).
- New fields used by the game: `TeamData.manager_name` (team page shows manager + stadium), player `height_cm`,
  `birth_year`, `secondary_positions` (profile shows number, height, birth year, "also plays").
- Extra informational fields (`birth_date`, `contract_end`, `market_value_eur`, `wiki`, `tm_id`, `unknown_fields`,
  `rating_basis`) are ignored by the loader.
- The career starts in 2026-27 (`CareerDate.FIRST_YEAR`). Spain has two tiers in this pack: 3 down from LaLiga,
  2 up + play-off (3rd–6th) from the Segunda; reserve sides never go up.

## Rebuilding

```
python3 tools/import_real/fetch_2026.py
python3 tools/import_real/build_2026.py            # fetches Wikipedia once, cached in cache/2026/wiki/
python3 tools/import_real/build_2026.py --offline  # deterministic rebuild from the cache
godot --headless --path . res://tests/laliga_2026_validation.tscn
```

To refresh squads (January window): delete `cache/2026/wiki/` and rebuild; review `report.excluded`.

## Adding a league

Add its season article(s) and clubs to `DIVISIONS` / `CLUBS` in `build_2026.py` (club article → team id, plus
code/colours for clubs new to the game); a `leagues/<country>.json` is written next to Spain's. Run the validation
suite and review the exclusion report. One country at a time.

## Licences

Wikipedia: CC BY-SA 4.0 (facts only). openfootball: CC0. transfermarkt-datasets: published by its author, data from
Transfermarkt — development / personal use; legal review needed before a public or commercial release. Club names
are trademarks; no badges, kit artwork or photos are included.

## France

Ligue 1 (18 clubs, 464 players) and Ligue 2 (18 clubs, 452 players); Ligue 1 matches openfootball 18/18. The Ligue 1
article's map groups both Paris clubs under one label, so the builder also reads the clubs linked in its "Stadiums and
locations" section (same country only). Players without an English article are accepted when the club's French
article lists them in its "Effectif de la saison 2026-2027" table ({{Feff joueur}}) with the same shirt number and a
date of birth: 166 players, mostly in Ligue 2 (exclusions went from 222 to 56). Relegation: 17th/18th down, top two up,
Ligue 1's 16th plays the winner of Ligue 2's 3rd-5th.

Whole pack: 198 clubs, 5,111 real players, every top division cross-checked with openfootball.
