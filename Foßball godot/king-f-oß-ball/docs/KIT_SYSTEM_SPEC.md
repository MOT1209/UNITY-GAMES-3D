# Kit system and visual identity spec (database phase 5)

## Data
A club's kits live in `TeamData.kits`: slots `home`, `away`, `third` (optional), `goalkeeper`, each `{main, secondary, accent, shorts, socks, number, pattern}` (hex colours; pattern = solid, stripes, hoops, halves, sash, checks). Edited through `KitEditor` (validates colours and patterns). Not stored in the kit data: the crest, which always comes from the team's current crest record (so it can never disagree with the club).

## Club identity, not KING branding
Home kits keep the club's own colours (test: 198/198 real-pack home kits use the club's primary or secondary colour; none uses the UI gold). The KING colours belong to the game interface only.

## Validation and repair (`KitEditor`, applied by `TeamDB` when clubs are loaded)
- `problems(team)`: shirt number contrast below 3:1 on its shirt; home/away, home/goalkeeper, away/goalkeeper, home/third kits too close (same metric the match uses to pick an away kit).
- `repair(team)`: away/third kit takes the home secondary colour, else white/black; goalkeeper takes the first of green, yellow, orange, black, pink, white that differs from home and away; numbers become white or near-black, whichever reads better. A good kit set is left byte-for-byte unchanged.
- Only data loaded from packs/files is repaired, and what was changed is listed in `TeamDB.kit_repairs`. Source JSON files are untouched. A player's own choices in the kit editor are never overridden (restoring a save does not repair). On the real pack this repaired 31 clashing away kits, 3 goalkeeper clashes and ~390 unreadable numbers that the importer's default colours produced (e.g. white number on a white shirt).
- `TeamDB.validate_kits()` reports remaining problems (none after loading).

## Rendering
- **3D players**: `TeamKit.for_team(db, team, slot)` builds the kit with `crest` = the club's `kit` crest texture. `PlayerCharacterVisual.apply_kit()` colours the materials (and the pattern, existing `KitPattern`) and `apply_crest()` puts the badge on the left chest: a small quad on a `BoneAttachment3D` of the `Chest` bone (follows the animation), idempotent, removed when the kit has no crest. Used for outfield players and goalkeepers, in matches (`MatchManager`) and in card portraits.
- **Portrait cache**: `PlayerCardData.portrait_key` includes the crest design, so a changed crest never shows a stale portrait.
- **2D previews**: `KitRenderer` / `KitService` draw shirt, shorts and socks with the crest (phase 4).
- The badge sits ~1 cm proud of the shirt (a flat quad on a low-poly torso); a real decal/texture on the shirt would need UV art.

## Tests
`tests/db_kits_validation.tscn` (34 checks): repair rules, loaded worlds (valid kits, own colours, readable numbers), user choices kept, `TeamKit.for_team`, badge on outfield/goalkeeper/chest bone/idempotent/removal, portrait key, and a real match scene where all 22+ players wear the crest.

## Not in this phase
Third kits for clubs that do not have one, kit material/crest placement as data fields (`crest_placement`, `material`; the badge position is a constant), sponsor logos.
