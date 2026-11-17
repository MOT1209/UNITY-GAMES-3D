# Crest system spec (implemented in database phase 4)

Code: `scripts/systems/crests/` (`CrestData`, `CrestSymbols`, `CrestRenderer`, `CrestGenerator`, `CrestRegistry`, `CrestCache`, `CrestService`). Data: `data/crests/crests.json` (206 shipped records), `data/crests/blocklist.json`. Tools: `tools/generate_crests.tscn` (regenerate the file), `tools/crest_gallery.tscn` (PNG sheet, CPU only).

## What a crest is
A `CrestData` record: `crest_id` (`crest_<club id>`), `club_id`, `asset_path` ("" = drawn procedurally, a file path, or `template:<id>`), `asset_type`, `version`, `shape_style`, `division`, `symbol`, `primary/secondary/accent_color`, `transparent_background`, `license_status`, `source`, `created_at`. All variants are rendered from this ONE record.

| asset_type | meaning | required license_status |
|---|---|---|
| OFFICIAL_LICENSED | licensed official artwork (none is shipped) | LICENSED |
| ORIGINAL_ALTERNATIVE | independent stand-in for a REAL club | ORIGINAL_NOT_AFFILIATED |
| FICTIONAL | crest of a fictional club | FICTIONAL |
| USER_CUSTOM | user image/template, or crest of a user-made club | USER_SUPPLIED |

## Intellectual property
- No official crest is shipped, read, traced or reconstructed. Real clubs get an **original alternative**: a generic shape (6) x division (5) x pictogram (12) in the club's own colours. The pictograms are plain geometry (star, tower, mountain, crown, ball, tree, sun, arrow, bridge, leaf, gem, castle) built from circles, boxes, triangles and line segments (`CrestSymbols`).
- `blocklist.json` stops the generator from using symbols that appear on the protected crest of specific real clubs (e.g. no tower for Everton). It is a best-effort coincidence guard; the independence of the design is the real safeguard. **The crests are NOT affiliated with or endorsed by any club.** Using real club names, player names and the Transfermarkt-derived data is a separate licensing question (see `DATA_SOURCE_AND_LICENSES.md`).
- Changing colours of an official crest is never used.

## Generation (deterministic)
`CrestGenerator.generate(club_id, colours, ...)`: design index = `hash("crest:" + club_id) % 360`, then stepped by 37 (coprime to 360) until the symbol is not blocked and the design+colours are not already used by another club. `tools/generate_crests.tscn` processes clubs in id order and writes `crests.json`; the test suite regenerates everything and requires the file to match exactly (nothing hand-edited, nothing stale). Clubs without a shipped record (user-made, generated later) get the same kind of design derived on demand and kept stable (`CrestRegistry.derived`).

## Variants (`CrestRenderer`)
`full` 128 px, `icon` 40 px (thick border), `mono` 64 px (white silhouette), `kit` 64 px (no split pattern), `card` 72 px. Any size can be requested. Anti-aliased, transparent outside the shape. Symbol colour is chosen for contrast (club accent preferred) and always gets a thin outline so it stays legible on any fill. Measured: 198 icons in ~0.6 s, 20 full crests in ~0.6 s (CPU, headless).

## Cache and lazy loading
`CrestService.texture(db, team, variant)` -> `CrestCache` (LRU, 256 entries, key = crest id + variant + size + version + design). Nothing is drawn until a screen asks; repeated requests reuse the texture. A changed or reassigned crest has another key, so it shows immediately everywhere.

## Registry (`CrestRegistry`, `TeamDB.crests`)
`for_team(team)`: the team's own image/template (`logo_path`) -> its `crest_id` -> a shipped crest of the club -> derived design. `assign(team, crest_id)` (own crests only), `add_alternative(crest)` (valid, unique design), `import_custom(team, path)` (validated, resized, stored in `user://logos` through `LogoService`), `missing_assets()`, `validate(db)` (valid records, unique designs, no identical image files, no club pointing at another club's crest), `orphan_crests(db)`, `stats()`.

## Where crests appear
Team selection, team details, career dashboard, league table + weekly results (`LeaguesScreen`), competition table (`StandingsScreen`, via `UIKit.team_cell`), transfer market rows, match results screen, in-match HUD (under the scoreboard), player cards (club line; the card shows the player's CURRENT club, so it changes after a transfer). Pitch cards (minimal) and national teams show none. All through `UIKit.crest(db, team, px, variant)`.

## Kit preview (added after review feedback)
The flat colour blocks of the kit preview were replaced by a drawn kit: `KitRenderer` paints shirt (6 patterns, accent collar and cuffs), shorts and socks from the saved kit data with the club crest on the chest; `KitService` caches the textures (key = kit data + crest design). It is a UI preview; rendering the crest on the 3D player shirt is still phase 5. Crests also got depth (soft light/shade, double border, fine inner line, gloss, symbol shadow) at sizes >= 56 px; small icons stay flat so they stay crisp.

## Not in this phase
Crest on the 3D shirt (phase 5), Crest Manager UI and in-game import UI (phase 7; the registry functions exist and are tested), competition-specific and kit-preview crests.
