# Player Appearance System (Phase V2)

## Data model — `PlayerData.appearance` (Dictionary, saved with the player)

| Key | Type | Meaning |
|---|---|---|
| `v` | int | record version (1) |
| `seed` | int | `hash(player.id) & 0x7fffffff` — the stable appearance seed |
| `skin` / `hair` / `boots` | int | index into `PlayerLook.SKINS` (6) / `HAIRS` (6) / `BOOTS` (6) |
| `hair_style` | String | `Short`, `Buzz`, `Afro`, `Long`, `Bald` |
| `beard` | bool | |
| `height_pm`, `build_pm` | int | per-mille scale of the rig (900–1120 / 900–1150) |

Height/build are **integers** because Godot's JSON parser does not round-trip every double
(found by test: 5403 / 20000 random floats came back different). Integers always round-trip.

## Code

`scripts/players/player_appearance.gd` (`PlayerAppearance`, static):

- `generate(seed, goalkeeper)` — deterministic; the RNG call order is identical to `PlayerLook.random`, so
  **every player keeps the face he already had** (tested for 300 seeds; heights match to < 0.0006).
- `ensure(player)` — *the only writer*: generates from the id when empty; repairs invalid/partial data
  while keeping valid fields; a stored valid value always wins over regeneration.
- `sanitize(dict)` — type-safe clamping (strings/nulls/arrays in a damaged save cannot crash).
- `to_look(dict)` / `look_for(player)` — runtime `PlayerLook` used by `PlayerCharacterVisual`.
- `signature(dict)` — compact string, part of the portrait cache key.

## Stable identity rules

- Created at the moment a player is registered (`TeamDatabase.register_team/register_player`) and at academy intake (`Academy.generate_intake`), and lazily by `ensure` anywhere else.
- Never re-rolled on load, promotion, transfer, kit change or match start.
- Saved in `players[].appearance`; `SaveManager` v1→v2 migration backfills old saves deterministically; `restore()` repairs damaged records.
- Match (`MatchManager._dress`) and cards/portraits/profile all read the same stored record.

## Academy

Intake gets a stored appearance immediately. Test: the 12 prospects of a fresh intake have 12 distinct appearances; generating
more never changes existing ones; promotion keeps the identical record (same `PlayerData` object, same id).
There is no manual "create player" feature.

## Variation that exists today vs. requested

| Requested | Status |
|---|---|
| Skin tones | ✅ 6 |
| Hairstyles: short / long / curly / wavy / straight / bald | ⚠️ Short, Buzz, Afro (curly), Long, Bald. **No wavy/straight variants** — each style is a mesh in the GLB, new ones need new meshes |
| Hair colour, beard, boots | ✅ |
| Height / build / silhouette | ✅ rig scaling (height, build). Per-limb proportions not done (bone scale tracks in the clips would fight it) |
| Face shapes, eye/eyebrow/nose/mouth shapes | ❌ **Not implemented**: the face is baked into the single head mesh. Needs new art — spec: separate `*_Eyes/_Brows/_Nose/_Mouth` sub-meshes or a face texture atlas with ≥ 4 variants each, same UVs; then add integer index fields to the appearance record (the sanitiser/migration pattern is already in place) |

## Tests

`tests/player_visual_validation.gd` (determinism, distinctness of 200 players, legacy equivalence, JSON round trip, repair, migration) and `player_visual_integration_validation.gd` (academy, promotion, save/load, match).
