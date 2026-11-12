# Real Data Pack (`data/packs/real_2025`)

An **optional** game world with real leagues, clubs and players for England, Spain, Germany, Italy and France,
season 2025-26.
The fictional world stays the default; the pack is chosen in **Settings → Game world** (switching ends the
running career). Headless runs (tests) always start in the fictional world unless `KING_DATA_PACK=<id>` is set.

## Contents

| Country | Tier 1 (**real squads**) | Tier 2 (generated players) | Cup | Promotion / relegation |
|---|---|---|---|---|
| England | Premier League, 20 | Championship, 24 | FA Cup | 3 down; 2 up + play-off 3rd–6th |
| Spain | LaLiga, 20 | Segunda División, 22 | Copa del Rey | 3 down; 2 up + play-off 3rd–6th; reserve teams can't go up |
| Germany | Bundesliga, 18 | 2. Bundesliga, 18 | DFB-Pokal | 2 down, 2 up; 16th vs 3rd relegation play-off |
| Italy | Serie A, 20 | Serie B, 20 | Coppa Italia | 3 down; 2 up + play-off 3rd–8th (3rd/4th skip the first round) |
| France | Ligue 1, 18 | Ligue 2, 18 | Coupe de France | 2 down, 2 up; play-off 3rd–5th, winner vs Ligue 1's 16th |

198 clubs, 5,213 players, of which 2,867 are real players (first tiers, ≤ 30 per club, ≥ 2 goalkeepers).

## Sources and licences

| Source | Used for | Licence / status |
|---|---|---|
| [openfootball](https://github.com/openfootball) season files 2025-26 (England, Spain, Germany, Italy `.txt`; France from the `football.json` export, which has no `.txt` for this season) | which clubs are in which division | CC0 1.0, public domain |
| [transfermarkt-datasets](https://github.com/dcaribou/transfermarkt-datasets), snapshot up to 2026-07-06 | first-tier squads: name, position, date of birth, nationality, foot, market value, contract end | published by its author; the data originates from Transfermarkt. **Fine for development and personal use; get a legal review before any public or commercial release.** |
| `tools/import_real/club_meta.json` (hand-written) | club colours and 3-letter codes | facts, no artwork |

Not used: club badges, sponsor logos, kit designs, player photos (`image_url` in the source is ignored).

**Why tier 2 is generated:** the snapshot only covers first-tier competitions (it has e.g. 6 Leicester players and
no Valladolid players). The clubs and their divisions are real; their players have fictional names (random
first + last name combinations from an English / Spanish / German / Italian / French pool) at a strength suited to the tier. Every club file says where its
players came from (`players_source`: `transfermarkt-datasets` or `generated`).

## Ratings are estimates

No open source of player ratings exists. The importer estimates the overall rating:

- **Market value (log scale):** about 67 at €1M, 77 at €10M, 85 at €50M and 91 at €200M.
- **Age:** −1.5 per year under 22, because young players' value is inflated by potential. +1 per year over 30, because older players' value is deflated.
- **League offset:** LaLiga, Serie A and Ligue 1 are 1 point below the Premier League and the Bundesliga.

The six attributes and goalkeeping are then split from the overall by position, using the same bias table as the
youth generator. They are tuned so the game's own `PlayerData.get_overall()` gives exactly the estimated value.
Potential depends on age and value. Wages use the game's economy formula. Transfer values are the real market values.
Example results: Mbappé and Haaland 90, Musiala and Olise 89, Kane 88, Dembélé 87, Lautaro 86, Salah 85,
Lamine Yamal 84 (age 18, potential 92).
They will differ from commercial games.

## Rebuilding / updating

```
python3 tools/import_real/fetch.py          # downloads into tools/import_real/cache/ (gitignored)
python3 tools/import_real/build_pack.py     # writes data/packs/real_2025/ and prints a report
python3 -m unittest discover -s tools/import_real/tests
```

The build is deterministic. Ids are stable: clubs are `eng_<slug>` / `esp_<slug>`, real players `tm_<transfermarkt id>`,
generated players `gen_<club>_<nn>` (prefixes `eng`, `esp`, `ger`, `ita`, `fra`). This keeps saves compatible across re-imports. The importer stops with a list of
clubs it cannot match; add those to `tools/import_real/club_aliases.json`. Clubs without colours are reported too.

### Adding a country

1. Add the openfootball file URLs to `fetch.py`.
2. Add a `COUNTRIES` entry in `build_pack.py`: divisions, sizes, promote/relegate, play-off, cup, transfermarkt
   competition id for real squads, strength range for generated squads, reserve-team links.
3. Add colours and codes to `club_meta.json`, run the build, then the tests (`tests/league_pyramid_validation.gd`
   checks sizes, validity and three simulated seasons).

## Known limits

- The snapshot ends on 6 July 2026, so later transfers are missing. Market values are a snapshot too.
- Second-tier players are not real.
- Club names are trademarks of their clubs. They are used as data only; there are no badges and no affiliation.
