# Performance (Phase V10)

Measured in this container (software GL, Mesa llvmpipe — i.e. a worst case for rendering; real
GPUs will be faster; CPU-side numbers are the meaningful ones). No GPU or in-match frame-time
profile was possible here — see "Not measured".

## Design choices

- **Shared materials per model** via `StandardMaterial3D` duplicates only for the *recoloured* slots (kit/skin/hair/boots/number); everything else stays the imported shared material.
- **One** portrait `SubViewport` for the whole game, `UPDATE_ONCE`, own `World3D`; cached textures (LRU ≤ 96, 300×360 RGBA8 ≈ 0.42 MB each ⇒ ≤ ~40 MB worst case, typically a few dozen).
- Cards are plain `Control`s with a single `_draw` frame; the sheen animates **only** in the detail view (`animate`), lists/grids are static.
- No per-frame work in cards; portraits are requested once per `setup`, served from cache afterwards.
- Match: unchanged cost — `MatchManager._dress` now reads a stored dictionary instead of seeding an RNG (cheaper), no new nodes.

## Measurements (from the test suites)

| Measurement | Result |
|---|---|
| Instance + dress 22 players | ~60–80 ms before the face system, ~350 ms after (first use builds the shared face meshes; one-off per match start) — still small, but a measurable cost of the 8 face meshes per player |
| Freeing 22 players | object count drops (no leak, asserted) |
| 12 portraits (render or cache) | 114 ms under xvfb (software GL), including 2 already cached |
| Extra SubViewports after 12 portraits | 0 (asserted); after `release()` → 0 viewports, empty cache (asserted) |
| Portrait cache bound | ≤ `MAX_CACHE` = 96 (asserted) |

## Not done / not measured

- **No LOD** (the models are already low-poly; no LOD meshes exist), **no texture atlas** (kit colours are flat material colours, only the shared number atlas exists).
- In-match frame times with 22 players on a real GPU were not measured; the match path was not made heavier, but "performance stable during matches" is **unverified**.
- Card grids with hundreds of cards: each card is a few Controls; the Collection screen builds all matching cards at once (tested at ~30–60). A virtualised list would be the next step for very large pools.
- UI-transition frame-drop test not implemented (no frame-time harness without a display).
