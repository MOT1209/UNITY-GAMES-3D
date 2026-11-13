# Performance report (phase 9)

## Environment and method
Headless Godot 4.7.2 (GL Compatibility, no GPU), 4 CPU cores, Linux container, pack `real_2025` (298 clubs, 8013 players, 306 crests). Tool: `tools/profile_db.tscn` (`DbProfiler.run`). Single runs; differences under ~15 % are noise. Guard: `tests/db_performance_validation` (generous limits; fails only on a catastrophic regression).

**Portrait rendering:** measured with `tools/profile_portraits` under xvfb with the *software* renderer (see the last section); a real GPU has not been used yet. **Not measured:** frame time during a match.

## Results (before -> after the phase 9 optimizations)
| Measurement | Before | After |
|---|---|---|
| Load the real world | 662 ms | ~420-510 ms |
| Memory added by the database | - | ~52.6 MB (about 120 MB static in total) |
| Player lookup by id | ~0.75-1.2 us | ~0.9 us (noise) |
| Club lookup by id | ~0.55 us | ~0.55 us |
| Squads of all 298 clubs | ~10.5 ms | ~10.5 ms |
| Team rating, all clubs | ~36 ms | ~36 ms |
| Text search over all players | ~86-97 ms | ~86-97 ms |
| Club search | ~4.7 ms | ~4.7 ms |
| Full validation (`validate_all`, 0 critical) | ~1.0 s | ~1.0 s |
| Crest icon, first draw | 3.3 ms each (298 = ~990 ms) | unchanged |
| Second pass over all 298 crests | 1029 ms, 0 cache hits | ~4 ms, 298 hits |
| Kit texture (2x) | 268 ms | ~130 ms |
| Save: capture / write / read / restore | 150 / 350 / 415 / 1190 ms | ~140-170 / ~350 / ~430 / ~860-880 ms |
| Save file size | 9.9 MB | 9.9 MB |
| Migrate a v2 save to v3 | - | ~205-265 ms |

## Bottlenecks found and fixed
1. **Crest cache thrash:** the cache held 256 entries but the world has 298 clubs, so scrolling a full table evicted every entry before reuse (0 hits). Now a byte-budget LRU (1024 entries, 24 MB); the second pass is served entirely from cache.
2. **Kit drawing:** every pixel was tested against all parts; now rows are culled per part. Verified pixel-identical against the old renderer over 240 renders. Long lists (team select) use the cheaper 1x drawing.
3. **Save restore:** each record was parsed twice (validate, then restore); now parsed once.

## Findings left as they are
- Id lookups are dictionary hits (~1 us); no extra index was needed.
- Validation takes about 1 s, runs only in tools, never during play.
- 9.9 MB / ~0.9 s for a full save of the world is acceptable; no change.

## Player portraits (software renderer, not a GPU)
`tools/profile_portraits.tscn` renders portraits through `PlayerPortraitRenderer` (SubViewport + 3D model). Run under `xvfb-run` with `--rendering-driver opengl3`; adapter reported: **llvmpipe (LLVM 20.1.2)**, i.e. CPU software rendering in this container, GL Compatibility, 20 players.

| Measurement | Result |
|---|---|
| First render, median | 29.8 ms |
| First render, slowest (loads the 3D model) | 284 ms |
| 20 first renders in total | 829 ms |
| Cached lookup, median | 0.037 ms (20 of 20 hits) |
| Static memory added | 5.7 MB |
| Video memory used | 37.9 MB |
| Cache | 20 entries (limit 96) |

A hardware GPU is expected to be faster than this software run, but that is not measured. Kaggle cannot be reached from this build environment (the proxy blocks it), so `tools/kaggle/portrait_profile.ipynb` is a ready notebook: enable a GPU accelerator and Internet, run all cells, and read the adapter name in the output (llvmpipe means software again). Paste `portrait_report.json` back to record the GPU numbers here.
