# Player Portrait Rendering (Phase V6)

`scripts/players/player_portrait_renderer.gd` (`PlayerPortraitRenderer`, a `Node` obtained with `PlayerPortraitRenderer.shared(tree)`).

- Renders **the real gameplay model**: same GLB scene (`player_model.tscn` / `goalkeeper_model.tscn`), `TeamKit` of the player's club (goalkeeper slot for keepers), shirt number, stored appearance (`PlayerAppearance.to_look`). So the card shows exactly what the match shows.
- **One** shared `SubViewport` (300×360, `own_world_3d = true`, transparent background, 4× MSAA) with its own camera, key + rim directional light and ambient. It never touches the match scene/world.
- Camera: 24° FOV at −Z (the model faces −Z), look target scales with the player's height so framing stays consistent for tall/short players. Pose: first frame of `Idle`/`Ready`, animation paused (deterministic).
- Lifecycle: viewport created lazily, `UPDATE_ONCE` per portrait (idle otherwise), requests are serialised, models are reused (one outfield + one keeper instance), `release(drop_cache)` frees everything.
- **Cache**: `ImageTexture` per `PlayerCardData.portrait_key()` = player id + appearance signature + kit colours + number + role; LRU, max 96 entries; nothing written to disk or saves. A kit or appearance change changes the key → fresh portrait.
- No device (headless/dummy driver): `can_render()` is false, `request()` returns `null`, the card keeps its silhouette. No crash.
- `PlayerCard` loads portraits asynchronously, tolerates being set up before entering the tree (deferred to `NOTIFICATION_ENTER_TREE` — a bug found by the integration test) and ignores results for a card that was reused/freed meanwhile.

Verified under `xvfb-run` + Mesa llvmpipe (see QA report): portraits are non-empty, transparent at the corners, differ per player, are cached, a kit change re-renders once, 12 portraits create no extra viewport, `release()` leaves 0 viewports. Developer tool: `tools/card_gallery.tscn` renders all five categories to a PNG.

Not done: live rotating 3D preview on the profile screen (the profile shows the static portrait card); other poses/expressions; per-card portrait zoom.
