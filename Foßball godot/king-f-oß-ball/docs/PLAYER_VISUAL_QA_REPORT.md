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
