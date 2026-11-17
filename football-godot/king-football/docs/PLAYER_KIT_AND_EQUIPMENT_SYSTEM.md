# Kits & Equipment (Phase V3)

## Single source of truth

`TeamData.kits` (dictionary per slot: `main, secondary, shorts, socks, accent, pattern`) is the centralised,
per-team kit configuration — it already existed and is saved with the team. Slots: `home`, `away`, `third`,
`goalkeeper`. Real and fictional clubs keep their own colours; nothing about team colours is hardcoded in
player scripts, and the KING FOOTBALL black/gold palette is used **only for the card UI**.

Flow: `KitEditor.set_field` → `TeamData.kits` → `TeamKit.from_dict` → `PlayerCharacterVisual.apply_kit`.

- **Match**: `MatchManager._spawn_team/_dress` (selected kit slot for outfield, `goalkeeper` slot for the keeper).
- **Cards/portraits**: `PlayerCardData.kit(db)` resolves the same slot (goalkeepers → `goalkeeper`); the portrait cache key contains the kit colours, so editing a kit re-renders the portrait on the next card build.
- Test: editing the home jersey colour appears on the match player, and a second edit changes the portrait key (`player_visual_integration_validation.gd`).

## Equipment present in the model

Shirt (`Jersey`, `Trim`), shorts, socks, boots (colour from the player's appearance), shirt number
(shared atlas), goalkeeper gloves (`G_Glove` material, goalkeeper model only), goalkeeper-specific kit.

## Not implemented (needs art / design decisions)

- **Training kit** slot (would be a 5th entry in `KitEditor.SLOTS`; kit editor, preview and save already iterate slots).
- **Rendered patterns** (stripes/hoops): the model exposes flat colour slots; a `pattern` mask texture or shader on `P_Jersey` is required. Today `pattern` is stored and previewed in the UI but not drawn on the 3D model.
- Accessories (captain armband, undershirt, headband) — no meshes.
- Boot models beyond colour.
