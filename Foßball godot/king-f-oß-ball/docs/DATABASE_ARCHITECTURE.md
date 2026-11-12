# Database architecture (KING FOOTBALL)

Status: Phase 1 design. Nothing here is implemented yet unless marked EXISTS.
Principle: **extend, never replace.** `TeamDB` (autoload), `TeamData`, `PlayerData`, data packs and `SaveManager` stay the backbone.

## 1. Entities and stable IDs
| Entity | Id format | Where it lives | Status |
|---|---|---|---|
| Club / national team | `eng_arsenal`, `club_sunvale`, `fic_<cc>_<slug>` (new fictional) | `TeamData`, JSON in `data/packs/<pack>/clubs/` | EXISTS (fictional prefix new) |
| Player | `tm_<n>` (real), `gen_<...>` (generated), `youth_<...>` (academy) | `PlayerData` in `TeamDB.players` | EXISTS |
| Country | `eng`, `esp`, `ger`, `ita`, `fra` | `data/countries.json` -> `CountryData` | NEW (phase 2) |
| League / division | `england` / `eng_d1` | `LeagueDef` | EXISTS (+ tier 3 new) |
| Crest | `crest_<club_id>` | `data/packs/<pack>/crests/` -> `CrestData` | NEW (phase 4) |
| Kit | slot name inside `TeamData.kits` | `TeamData.kits` | EXISTS (extended phase 5) |

Rules: ids are permanent, lowercase ASCII, never derived from a display name after creation; every reference between entities uses ids; a duplicate id is rejected by `TeamDB.register_team` / `register_player` (EXISTS).

## 2. Data flow
```
data/countries.json ─┐
data/packs/<pack>/   │        ┌─> LeagueDef / LeaguePyramid -> CareerState, competitions
  pack.json          ├─> TeamDB ├─> Squad, MatchSetup -> MatchManager (same PlayerData objects)
  clubs/*.json       │  (teams, │─> PlayerCardData -> cards, portraits (LRU)
  leagues/*.json     │  players,├─> TransferMarket (changes team_id only, id kept)
  crests/*.json (new)┘  leagues)└─> Academy / YouthGenerator -> register_player
                                 └─> SaveManager (v3) <-> user://saves
```
One `PlayerData` instance per player lives in `TeamDB.players`; screens and the match engine hold references, never copies of identity.

## 3. Attribute model (conflict resolution)
The brief lists ~22 attributes. The game's match engine, card stats, overall formula and training all use **7 core attributes** (`pace, shooting, passing, dribbling, defending, physical, goalkeeping`). Introducing a second rating system would conflict, so:
- The 7 core attributes stay the source of truth and `get_overall()` is untouched.
- Detailed attributes (acceleration, sprint_speed, finishing, vision, ball_control, tackling, agility, balance, reactions, positioning, composure ...) are **derived** by `AttributeDetail` (new, phase 3): parent attribute + deterministic offset (within +-6) from the player's seed. Read-only, not saved, so they cannot drift and cannot change match results.

## 4. Extensions per record (all optional, with defaults, so old data and saves load)
- `TeamData`: full_name, nickname, city, region, founding_year, club_type (REAL/FICTIONAL/CUSTOM), country_id, league_id, division, rival_club_ids, finance block (transfer_budget, wage_budget, balance, weekly_expenses, sponsorship_income), stadium_name/capacity/level, crest_id, accent_color, history.
- `PlayerData`: first_name, last_name, nationality_id, birth_year (birth_date only when sourced), height_cm, weight_kg, secondary_positions, player_type, contract_id, per-season/competition stats.
- Real data is never invented: fields without a verified source stay empty and are shown as unknown.

## 5. Crest system (phase 4)
- `CrestData`: crest_id, club_id, asset_path, asset_type (OFFICIAL_LICENSED / ORIGINAL_ALTERNATIVE / FICTIONAL / USER_CUSTOM), version, shape_style, symbol, primary/secondary/accent colours, transparent_background, license_status, source, created_at.
- `CrestService` renders the original crest procedurally from (club_id, colours, shape, symbol, division pattern); extends `LogoService` (EXISTS: templates + validated image import).
- Variants (full, icon, monochrome, kit, card) are render sizes/modes of ONE crest id.
- `CrestCache`: LRU of textures keyed (crest_id, variant, size). No crest is loaded unless a screen shows it.
- No official crest is shipped. Per-club forbidden-symbol list guards against imitating protected logos. Provenance recorded per crest.

## 6. Generation (phase 6)
Deterministic from `(world_seed, id)`: same input -> same club/player. Generated once into the pack JSON (committed), never at screen open. Reuses `SquadGenerator`, `YouthGenerator.pool_for`, `PlayerAppearance.generate`.

## 7. Performance
Dictionary id index (EXISTS). Added in phase 9 only if measured to be needed: per-club and per-country indexes, lazy portraits/crests (portrait LRU EXISTS), validation outside gameplay paths.

## 8. Localization
Names stay as stored (never auto-translated). UI strings via `Loc` keys in `translations/` (ar/de/en). Arabic is RTL (see ARABIC_RTL_SUPPORT.md).
