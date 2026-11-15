# Player Visual QA Report

Godot 4.7.2 stable (Linux), project imported with `--import`. Date: 2026-11-12.

## Executed and passing

| Run | Result |
|---|---|
| Baseline before any change: `tests/run_all.sh` (19 suites) | 1807 passed, 0 failed |
| After the work: `tests/run_all.sh` (22 suites, headless) | **1993 passed, 0 failed**, 0 suites failed |
| `player_visual_validation` (headless) | 49 / 49 |
| `player_card_validation` (headless) | 82 passed, **1 skipped** (portrait block needs a GPU; the headless fallback check passed) |
| `player_card_validation` under `xvfb-run` + Mesa llvmpipe (`--rendering-driver opengl3`) | **91 / 91**, 0 skipped (real portrait rendering) |
| `player_visual_integration_validation` (headless and xvfb) | 54 / 54 |
| Screenshots reviewed (`tools/card_gallery.tscn`, en and ar) | five categories + goalkeeper + small card; layout fixed after review |

`tests/phaseT10_validation.gd` was edited (19 → 20 registered screens) because a screen was added.

## What the tests cover

Character: scenes load, one 18-bone skeleton, required clips, height/feet-on-ground, kit colours applied and isolated per player, skin/hair/height applied, goalkeeper kit/model, speed→clip transitions, 22-player instancing and cleanup.
Appearance: determinism, 200 distinct players, bit-compatibility with the old look, JSON round trip, repair of damaged records, v1→v2 migration.
Cards: five categories and thresholds, brand colours, card data == live player data (120 players), name/OVR/position/six attributes on rendered cards, long Latin/Arabic names in en/de/ar, no stale copy after growth/position/rename/transfer, collection filters and sorting.
Portraits (xvfb only): render, transparent background, differ per player, cache hit, kit change re-renders, no extra viewports, bounded cache, release.
Integration: squad cards = starting XI, academy cards = roster, profile card, collection screen and its UI filter, detail view, three languages, academy distinct/persistent identities, promotion keeps id/appearance/history, kit edit reaches the match player, match uses stored appearance incl. substitutions, save/load exact restore, v1 save loads, damaged record repaired, missing club / damaged look do not crash.

## Bugs found by the tests/screenshots and fixed

- `sanitize` crashed on non-numeric values in a damaged save.
- Floats in the appearance did not survive JSON (Godot parser) → integer per-mille.
- Cards crashed when `setup()` ran before entering the tree.
- Portraits showed the model's back (model faces −Z); first requests failed before the renderer entered the tree.
- RTL root mirrored the card's absolute layout → card pinned to LTR.
- Divider crossed the name, red-on-red keeper line, flow container stretched small cards.

## Not executed / known limitations / remaining issues

- **Not implemented (needs art assets, not faked):** new master character model, face-part variation (eyes/nose/mouth/face shapes), wavy/straight hair, LOD, texture atlas, training kit, rendered kit patterns, accessories, and **all new animation clips + AnimationTree** (Phase V4). See the respective docs for specs.
- Not built: pitch-layout card view in Squad, rotating live 3D preview, team/competition badges and flags on cards.
- **Not measured:** in-match frame time with 22 players on a real GPU; UI-transition frame drops. Rendering was verified only on a software GL driver.
- No `AnimationTree`/animation tests beyond speed→clip switching.
- Arabic checked on a screenshot and by layout tests, not by a native reviewer; the Arabic stat abbreviations (e.g. سرع) are short forms that should be reviewed.
- `TeamPlayer.setup` (demo scene only) still uses its old ad-hoc look seed; the real match path uses the stored appearance.


---

## Update 2 — faces and animation (follow-up)

| Run | Result |
|---|---|
| `tests/run_all.sh`, 22 suites, headless | **2068 passed, 0 failed** (was 1993) |
| `player_visual_validation` | 115 / 115 |
| `player_visual_integration_validation` | 63 / 63 |
| `player_card_validation` headless | 82 passed, 1 skipped (portrait block) |
| `player_card_validation` xvfb + Mesa llvmpipe | **92 / 92**, 0 skipped (adds: players differing only in face parts render different portraits) |
| Screenshots reviewed | face close-ups (6 players), cards in en, side-view contact sheets for Celebrate, Disappointed, FirstTouch, Sprint, Shoot |

Delivered: procedural face system (`FaceBuilder`: 5 head shapes, 5 eyes, 5 brows, 4 noses, 5 mouths, 5 eye colours; appearance record
v2 with in-place upgrade of v1 records) and 8 generated animation clips wired to real gameplay events (Sprint, Dribble, Pass, Shoot,
LongPass, FirstTouch, goal Celebrate / Disappointed). Details: `PLAYER_APPEARANCE_SYSTEM.md`, `PLAYER_ANIMATION_SYSTEM.md`.

Still open (replaces the earlier "not implemented" list where it overlaps):
- Clips for tackle, interception, header, injury, turning, keeper block/punch/distribution are **not generated on purpose** — the game has no such mechanics.
- No `AnimationTree` (see animation doc for why).
- Generated clips/faces are procedural and stylised, not hand-made art; no facial expressions, no foot IK, no wavy/straight hair, no new body model.
- Gameplay feel in a live match (clip timing against real play, foot sliding) was verified by contact sheets and assertions only — not by playing a match on a GPU.
- Face meshes add measurable instancing cost (22 players ≈ 350 ms vs ≈ 70 ms, see performance doc); in-match frame time still not measured.
- The face code relies on the model's `*_Dark` surface containing only facial geometry (asserted by inspection, not by a test) — a re-exported model must keep that.

---

## Update 3 — round 3 (2026-11-15): portrait pose, lighting, faces, hair, beards, kit

| Run | Result |
|---|---|
| `player_visual_validation` (headless) | **171 / 171** (was 139) |
| `player_card_validation` (headless) | 233 passed, 1 skipped (portrait render block needs a GPU) |
| Portrait grids, 6 x 4, same 24 real-pack players | `docs/qa/players/portraits_before.png` / `portraits_after.png` (xvfb + Mesa llvmpipe) |

Delivered (all procedural, in code — no new art asset, no Blender model):
- **Pose**: `PortraitIdle`, a static clip generated from the standing pose (both rigs): arms relaxed beside the body, slight
  elbow bend. Tested: on both rigs each hand is >= 0.35 m below its shoulder and every elbow below the shoulder; the clip is
  a held pose. The keeper's raised arm ("Ready" first frame) is gone from every card.
- **Framing**: the portrait camera follows the Head bone (`PlayerPortraitRenderer.frame_camera`), fov 26, head and shoulders to
  mid-chest. Tested headless for 48 players incl. keepers: crown (real top of hair, bun, mohawk), chin and both ears project
  inside the 300 x 360 portrait.
- **Lighting**: warm key from the camera's left, cool weak fill from the right, rim from behind; ambient 0.28; linear tone
  mapping; auto exposure off — every card is lit the same.
- **Face** (`FaceBuilder`): ears, nose bridge + rounded tip + nostrils, eyelid creases, a lower lip, 4 jaw / chin shapes
  (x 5 head shapes), 12 skin tones (`PlayerLook.SKIN_TONES`: the 6 old tones + an undertone variant each), 5 eye colours.
- **Hair / beard** (`HairBuilder`): 14 haircuts = the model's 5 hair meshes + 9 sculpted cuts (wavy, curly, braids,
  ponytail, man bun, mohawk, dreadlocks, side part, flat top); beard styles: none, full (model mesh), stubble
  (semi-transparent), goatee, moustache, chin strap, moustache + goatee. Every sculpted vertex is shaded from its normal
  (darker underneath / at the edges) and hair materials have a soft rim light — no flat single colour.
- **Body / kit**: real height / weight set the body proportions of a newly generated appearance; fabric-fold normal map
  on shirt and shorts (portraits / preview only); long sleeves on ~20 % of outfield players; the player's name on the back above the number; boots keep
  their per-player colour; keepers keep the model's gloves and long sleeves.
- **Identity / saves**: appearance record v3. New fields come from their own RNG streams, the old fields are drawn exactly as
  before (tested for 300 seeds), golden signatures pin three ids across runs, 200 random players give >= 90 % distinct
  combinations. A stored v1/v2 record upgrades in place to v3 with the SAME look (skin colour, hair mesh, full beard, original
  chin, short sleeves) — tested.
- **LOD**: face within 30 m (`FACE_LOD_END`), sculpted hair / beards within 22 m (`HAIR_LOD_END`), the back name within 18 m, sleeves within 35 m; the model's
  base hair mesh of every cut stays visible further away, so a distant player never turns bald.

Performance: measured on this machine (software GL, llvmpipe — not a phone GPU; numbers are relative). Match, AI vs AI, broadcast view,
300 frames: average frame 172.3 ms over 4 runs vs 172.0 ms baseline over 3 runs (+0.2 %, inside the run-to-run spread of
159-184 ms). A first version cost +15-20 %; the fabric-fold normal map is therefore portraits / 3D preview only
(`PlayerCharacterVisual.fabric_folds`), and sculpted hair (22 m) and the back name (18 m) got tighter near-camera LOD.
`db_performance_validation` 16/16; `load_world` best of 5: 503 ms vs 501 ms (+0.4 %; medians vary +-12 % between runs);
`PlayerAppearance.ensure` over all 8,013 players +20 ms (69.6 -> 89.1 ms); save file 9.9 -> 10.6 MB (+7 %, the five new
appearance fields — the one metric above 5 %).

Not done / limits:
- **No new Blender base model with shape keys** (no Blender in this environment). `PlayerAppearance` / `PlayerLook` are ready
  for one: a model only has to keep the 18-bone rig and the material suffixes.
- Faces and hair stay stylised low-poly primitives; no textures, no facial expressions, no hair cards with alpha strands.
- The sculpted pieces were placed by eye on the shipped head (relative to the Head bone) and checked on the 6 x 4 grid; a
  re-exported head of a different size would need the offsets in `HairBuilder` / `FaceBuilder` adjusted.
- Frame times were measured on a software renderer only (llvmpipe), not on a phone GPU.
