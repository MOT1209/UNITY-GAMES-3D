# Real Data Pack (`data/packs/real_2025`)

An **optional** game world with real leagues, clubs and players for England and Spain, season 2025-26.
The fictional world stays the default; the pack is chosen in **Settings → Game world** (switching ends the
running career). Headless runs (tests) always start in the fictional world unless `KING_DATA_PACK=<id>` is set.

## Contents

| | England | Spain |
|---|---|---|
| Tier 1 | Premier League, 20 clubs, **real squads** | LaLiga, 20 clubs, **real squads** |
| Tier 2 | Championship, 24 clubs, generated players | Segunda División, 22 clubs, generated players |
| Cup | FA Cup (44 clubs) | Copa del Rey (42 clubs) |

86 clubs, 2,253 players, of which 1,195 are real players (first tiers, ≤ 30 per club, ≥ 2 goalkeepers).

## Sources and licences

| Source | Used for | Licence / status |
|---|---|---|
| [openfootball](https://github.com/openfootball) season files 2025-26 | which clubs are in which division | CC0 1.0, public domain |
| [transfermarkt-datasets](https://github.com/dcaribou/transfermarkt-datasets), snapshot up to 2026-07-06 | first-tier squads: name, position, date of birth, nationality, foot, market value, contract end | published by its author; the data originates from Transfermarkt. **Fine for development and personal use; get a legal review before any public or commercial release.** |
| `tools/import_real/club_meta.json` (hand-written) | club colours and 3-letter codes | facts, no artwork |

Not used: club badges, sponsor logos, kit designs, player photos (`image_url` in the source is ignored).

**Why tier 2 is generated:** the snapshot only covers first-tier competitions (it has e.g. 6 Leicester players and
no Valladolid players). The clubs and their divisions are real; their players have fictional names (random
English / Spanish first + last name combinations) at a strength suited to the tier. Every club file says where its
players came from (`players_source`: `transfermarkt-datasets` or `generated`).

## Ratings are estimates

No open source of player ratings exists. The importer estimates the overall rating:

- **Market value (log scale):** about 67 at €1M, 77 at €10M, 85 at €50M and 91 at €200M.
- **Age:** −1.5 per year under 22, because young players' value is inflated by potential. +1 per year over 30, because older players' value is deflated.
- **League offset:** LaLiga is 1 point below the Premier League.

The six attributes and goalkeeping are then split from the overall by position, using the same bias table as the
youth generator. They are tuned so the game's own `PlayerData.get_overall()` gives exactly the estimated value.
Potential depends on age and value. Wages use the game's economy formula. Transfer values are the real market values.
Example results: Mbappé and Haaland 90, Salah 85, Lamine Yamal 84 (age 18, potential 92).
They will differ from commercial games.

## Rebuilding / updating

```
python3 tools/import_real/fetch.py          # downloads into tools/import_real/cache/ (gitignored)
python3 tools/import_real/build_pack.py     # writes data/packs/real_2025/ and prints a report
python3 -m unittest discover -s tools/import_real/tests
```

The build is deterministic. Ids are stable: clubs are `eng_<slug>` / `esp_<slug>`, real players `tm_<transfermarkt id>`,
generated players `gen_<club>_<nn>`. This keeps saves compatible across re-imports. The importer stops with a list of
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
