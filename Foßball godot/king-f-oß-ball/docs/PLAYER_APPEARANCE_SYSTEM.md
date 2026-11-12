# Player Appearance System (Phase V2)

## Data model — `PlayerData.appearance` (Dictionary, saved with the player)

| Key | Type | Meaning |
|---|---|---|
| `v` | int | record version (2; v1 records are upgraded in place by `PlayerAppearance.upgrade`, keeping every existing field) |
| `seed` | int | `hash(player.id) & 0x7fffffff` — the stable appearance seed |
| `skin` / `hair` / `boots` | int | index into `PlayerLook.SKINS` (6) / `HAIRS` (6) / `BOOTS` (6) |
| `hair_style` | String | `Short`, `Buzz`, `Afro`, `Long`, `Bald` |
| `beard` | bool | |
| `height_pm`, `build_pm` | int | per-mille scale of the rig (900–1120 / 900–1150) |
| `face`, `eyes`, `brows`, `nose`, `mouth`, `eye_color` | int | (record v2) indices into the `FaceBuilder` tables: 5 head shapes, 5 eyes, 5 brows, 4 noses, 5 mouths, 5 eye colours |

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
| Face shapes, eye/eyebrow/nose/mouth shapes | ✅ **Implemented procedurally** (`scripts/players/face_builder.gd`), see below. 5×5×5×4×5×5 combinations; 200 players gave ≥ 150 distinct faces in tests |

## Tests

`tests/player_visual_validation.gd` (determinism, distinctness of 200 players, legacy equivalence, JSON round trip, repair, migration) and `player_visual_integration_validation.gd` (academy, promotion, save/load, match).


## Face system (`FaceBuilder`)

The model's head is one mesh whose eyes/brows/mouth are boxes in the body's `*_Dark` surface (that surface contains
only facial geometry in both models — checked). Without a DCC tool the mesh cannot be edited, so:

1. the baked features are hidden (surface override with a fully transparent material),
2. eyes (dot, round, almond, wide, close; optional sclera + 5 iris colours), eyebrows (thin, thick, angry, raised, short;
   in the hair colour), a nose (4 sizes) and a mouth (flat, wide, small, smile, frown) are built from cached primitive meshes
   on a `BoneAttachment3D` at the `Head` bone, so they follow every animation,
3. head shape = scale of the `Head` bone (skin, hair and beard are skinned to it and scale together; no clip animates bone scale).

A `PlayerLook` with `face_shape = -1` (any look that carries no face data, e.g. the demo scene) keeps the original face.
Meshes/materials are shared between players. Verified on close-up renders (`tools/model_view.tscn -- out.png face`) and on cards.

Limits: stylised geometric features (no skin-texture detail, no expressions/lip shapes beyond the listed ones, no ears/cheek
variation); readability is tuned for card/portrait distance (features are ×1.25 of the natural size). Wavy/straight hair still
needs new hair meshes.
