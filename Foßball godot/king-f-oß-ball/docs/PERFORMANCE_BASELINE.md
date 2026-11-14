# Performance baseline (P1)

Captured with `tools/profile_match.tscn` on the development machine.
Engine: Godot 4.7.2-stable. Adapter detected: **Intel(R) UHD Graphics 605**
(compatibility renderer, OpenGL 3.3). The measurement below is the **headless
(dummy renderer) run**; the real-GPU `-- frames` run could not be completed in
this automated session (it requires an interactive display). GPU frame-time /
FPS numbers are therefore **not** in this baseline and must be re-measured on a
real display before P8 sign-off. CPU timings, node/object counts and memory are
GPU-independent and are the authoritative numbers below.

## CPU / instantiation timings (ms, median of 5 unless noted)

| Metric | ms |
|---|---|
| 22 player scenes instantiate (median) | 481.996 |
| 22 players with face system (median) | 904.287 |
| 22 players without face system (median) | 684.576 |
| face apply, 22 players (median) | 7.778 |
| arena instantiate (median) | 306.287 |
| ball instantiate (median) | 12.452 |
| match begin (cold) | 1684.913 |
| match begin (median) | 1316.396 |

## Counts

| Metric | value |
|---|---|
| face nodes, 22 players | 44 |
| nodes total, 22 players (with face) | 287 |
| nodes total, 22 players (without face) | 243 |
| object delta, 22 players | 638 |
| static memory delta, 22 players | 1960 KB |

## Match scene (steady state)

| Metric | value |
|---|---|
| match scene nodes | 712 |
| nodes (total) | 741 |
| objects | 3812 |
| static memory | 98.4 MB |

## Notes / debt
- The face system adds ~220 ms to a 22-player instantiate (904 vs 685 ms) and
  44 extra nodes; it is the single largest optional cost. Keep the face system
  on for shipped builds but profile on low-end (Intel UHD 605 class) hardware.
- `match begin` cold is ~1.7 s; median ~1.3 s. Acceptable for a loading screen.
- 13 ObjectDB instances leaked at exit and 2 resources still in use — pre-existing
  noise (also seen on other suites), not introduced by P1.
- Real-GPU FPS / frame-time / draw calls / video memory: **not measured** in
  this run (headless dummy renderer). Re-run `tools/profile_match.tscn -- frames`
  interactively on the Intel UHD 605 before P8 to fill these in, and record
  30/60 FPS budgets for mobile (P4/P8).