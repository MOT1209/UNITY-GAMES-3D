# Phase 7.6 — Performance profiling and optimisation

Tool: `tools/profile_match.tscn` (`godot --headless --path . res://tools/profile_match.tscn`; add `-- frames` under a
display for frame statistics). Machine: 4-core Intel Xeon 2.1 GHz, **no GPU** (Mesa llvmpipe software renderer for the
frame numbers). CPU timings are medians of 5 runs; they vary ±20 % between runs on this shared machine.

## The "350 ms for 22 players" investigation

The earlier report attributed the 350 ms to the face system. **Profiling showed that was wrong.**

| Measurement (headless CPU) | Before | After | Change |
|---|---|---|---|
| 22 players instantiated + dressed (median) | **403 ms** | **66 ms** | −84 % |
| of which the face system (`FaceBuilder.apply` ×22) | 2.8 ms | 0.8 ms | −71 % |
| 22 players without any face | 328 ms | 63 ms | −81 % |
| Match start-up `MatchManager.begin()` (median) | **382 ms** | **104–149 ms** (124 ms in the final run) | ≈ −68 % |
| Nodes for 22 dressed players | 463 | 287 | −38 % |
| Face nodes for 22 players | 220 | 44 | −80 % |
| Ball instantiate | 52 ms | 1.0 ms | −98 % |

Causes and fixes, each found by measurement:

1. **`PlayerAnimationLibrary.install` regenerated the 8 generated clips for every player (~10 ms each) and threw them
   away because the shared library already had them.** This was the real cost (introduced with the animation work, not the
   faces). Fix: return early when all clips exist. First instance 21 ms (one-off), later instances 0.17 ms.
2. **Face parts were ~10 separate `MeshInstance3D`s per player.** Building them cost almost nothing, but they multiplied
   nodes and draw calls. Fix: one merged, vertex-coloured mesh per distinct face (cached), one node per player. The
   appearance is unchanged (same geometry and colours; asserted by the existing face tests and the portrait diff test).
3. **The football's pattern texture (256×128 pixels, per-pixel GDScript) was rebuilt for every ball, ~50 ms.**
   Fix: cache by parameters.

What is left of the ~125 ms start-up: arena scene ≈ 35–45 ms, 22 player scenes ≈ 45 ms, dressing 22 players ≈ 65 ms
(of which material duplication in `apply_kit`/`apply_look`), ball ≈ 1 ms. Further saving possible (not done): share the
duplicated skin/jersey materials between players of the same team and look.

## Memory (22 players)

Second batch of 22 dressed players (one-off shared resources excluded): **+1,970 KB static memory, +638 objects**.
Whole match scene: 617 nodes, ≈ 3,190 objects, ≈ 87 MB static memory (before the merge: 3,370 objects).

## Frames — NOT representative

Under Mesa llvmpipe (CPU rasteriser, 1280×720): **5.1 FPS average, 3.9 FPS 1 % low, 194 ms/frame**, of which physics ≈ 4.1 ms
(median) — the frame time is the software rasteriser. **668 draw calls** per frame, 45.8 MB video memory. These numbers say
nothing about a real GPU. **Real-GPU FPS, GPU frame time and 1 % lows: NOT MEASURED (no GPU available).**
The draw-call count is a real risk indicator: the body mesh has 9 surfaces (9 draw calls) × 22 players ≈ 200 of the 668.
Merging surfaces by vertex colour would roughly halve that (not done; needs a re-export or runtime mesh merge).

## Portrait rendering (software GL)

Median 12 ms per portrait on llvmpipe (cached portraits cost 0). 12 portraits including cache hits: ~115–150 ms.

## Not measured / limits

- GPU time, real-GPU FPS and 1 % lows; UI-transition frame drops; long-match memory growth (a 90-minute run).
- The headless run prints `material_get_instance_shader_parameters` errors from the dummy renderer when nodes are freed in
  bulk by the profiler; they also appear with the pre-change code and are harmless noise of the dummy driver.
