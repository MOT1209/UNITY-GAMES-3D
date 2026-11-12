# Save & Load (Phase V9)

## Format change

`SaveManager.SAVE_VERSION` 1 → **2**. The only difference: `players[].appearance` (see appearance doc).
Kit data was already saved inside `teams[].kits`; card classes are derived (not saved); portraits are
regenerated/cached (no image data in saves — asserted by test).

## Migration (`SaveManager.migrate`)

- v0 → v1 unchanged. **v1 → v2**: every player without `appearance` gets `PlayerAppearance.generate(seed_for(id), is_gk)` → identical to the look the player already had in matches; deterministic; the input dictionary is not mutated (tested).
- Newer-than-known versions are still refused.

## Restore

`restore()` validates, then builds `PlayerData.from_dict` (integers restored from JSON floats) and calls `PlayerAppearance.ensure`, which repairs damaged records and **never regenerates a valid one**. Missing/invalid references: unknown hair style → `Short`, out-of-range palette index → clamped, wrong types ignored, empty record → regenerated from the id; a missing asset (hair mesh etc.) simply leaves the default look (`apply_look` skips absent meshes/materials).

## Guarantees tested (`player_visual_integration_validation.gd`)

Save file is v2 and every player has an appearance; wiping all appearances in memory then loading restores all of them exactly (same player count, no duplicates); a v1 file loads and gets valid appearances; a damaged record in a v2 file is repaired; promotion keeps the record.

## Known limitation

In-progress match state is still not saved (pre-existing, see `docs/STABILIZATION_REPORT.md`).
