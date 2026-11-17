# Player Visual System — Phase 0 Audit

Audited before any change (repo state: commit `b2e61fa`, Godot 4.7.2, GL Compatibility renderer).
Baseline: `tests/run_all.sh` = **1807 checks passed, 0 failed, 19 suites** (run in this container
before the first edit).

## Existing architecture (what was found)

| Area | Where | Notes |
|---|---|---|
| Player record | `scripts/data/player_data.gd` (`PlayerData`, a `Resource`) | Stable string `id`; 7 attributes (`pace, shooting, passing, dribbling, defending, physical, goalkeeping`); `get_overall()` is derived per position; `to_dict/from_dict` JSON. No appearance data. |
| Database | `scripts/core/team_database.gd` (autoload `TeamDB`) | `players{id→PlayerData}`, `teams`. Players come only from team JSON (`data/clubs`, `data/national_teams`) or the academy. |
| Academy | `scripts/systems/academy/{academy,youth_generator,academy_config}.gd` | Deterministic `(academy_seed, index)` → `PlayerData` (`yth_<team>_<n>`). Promotion (`promotion_system.gd`) **mutates the same `PlayerData`** (id, history stay). |
| Squad | `scripts/systems/squads/squad.gd` | Starting XI / bench / reserves hold player **ids**. |
| Match | `scripts/systems/match/match_manager.gd` | `_spawn_team`/`_dress` dress a `PlayerController` or `TeamGoalkeeper` from real `PlayerData` + `TeamData.kits`; `_swap_player` re-dresses on substitutions. |
| Character model | `assets/models/characters/player.glb`, `goalkeeper.glb`; scenes `scenes/player/{player,goalkeeper}_model.tscn` | Stylized low-poly body with **face** (eyes/brows/mouth modelled in the head), one `Skeleton3D` (18 bones), clips `Idle Walk Run Kick` (+ `Ready DiveLeft DiveRight CatchHigh CatchLow Throw` for the keeper). Hair styles are separate meshes (`Short Buzz Afro Long`) + `Beard`; materials are named `P_/G_` + `Jersey Trim Shorts Socks Boots Skin Hair Number`. |
| Dressing | `scripts/player/{player_character_visual,team_kit,player_look,goalkeeper_visual}.gd` | `TeamKit` recolours materials, `PlayerLook` = skin/hair/boots/hair style/beard/height/build, applied by `PlayerCharacterVisual`. Number via shared atlas. |
| Kits data | `TeamData.kits` (`home/away/third/goalkeeper` dicts), `systems/teams/kit_editor.gd`, UI `kit_editor_screen.gd` | Centralised, per-team, saved with the team. `pattern` is stored but **not rendered** (flat colour slots only). |
| Save/load | `scripts/core/save_manager.gd` + `AppHub.save_game/load_game` | JSON, versioned (`SAVE_VERSION`), `migrate()` chain, atomic write, all-or-nothing `restore()`. |
| UI | `scripts/ui/**` | Screens are built in code (`HubScreen` + `UIKit`), registered in `ui/hub/screen_registry.gd`; navigation via `HubRoot.navigate`. Localization via autoload `Loc` + `translations/*.csv` (en/de/ar, RTL switch on the root window). |
| Tests | `tests/*_validation.{gd,tscn}`, `tests/run_all.sh` | Headless suites with a guard that every `*_validation.tscn` is listed. |

## Reusable (reused, not rebuilt)

- The GLB character + skeleton + clips, `PlayerCharacterVisual`, `TeamKit`, `PlayerLook`.
- Kit data model and editor, Squad/Academy/Promotion/Transfer systems, `SaveManager`, `UIKit`, `HubScreen`, `Loc`.
- The `hash(player.id)`-seeded look that `MatchManager` already used — the new system **reproduces it exactly** so no existing player changes face.

## Missing (gaps found)

1. Appearance was **not data**: derived on the fly from the id, never saved, only used in the match. Cards/profile could not show it.
2. No card concept, no portrait renderer, no collection screen; squad/academy/profile were text/tables only.
3. `PlayerCharacterVisual` and `TeamPlayer.setup` (demo scene) still use ad-hoc seeds (`team_idx*1000 + n*17`) — only the demo scene.
4. No sprint/turn/pass/shoot/tackle/header/celebration/injury clips; no `AnimationTree`.
5. No training kit, no rendered kit patterns, no accessories.
6. No separate face parts (eyes/nose/mouth are baked into the one head mesh), no curly/wavy hair meshes beyond `Afro`.

## Technical limitations

- **No Blender / DCC tool in this environment**, and no licensed external character pack in the repo. New meshes and animation clips therefore could **not** be authored here (see asset policy in the character doc). Everything shipped is built on existing assets.
- GL Compatibility renderer: no SSS/advanced shaders; kept materials as flat `StandardMaterial3D`.
- Headless Godot has no GPU: portrait rendering is verified under `xvfb-run` + Mesa llvmpipe (software GL), not on real GPUs.
- `JSON` in Godot 4.7 does not round-trip every `float` exactly → appearance stores integers (per-mille) only.

## Integration risks (and how they were handled)

| Risk | Handling |
|---|---|
| Changing `PlayerData` breaks saves/tests | One optional `appearance: Dictionary` field, absent → `{}`; `SaveManager` v1→v2 migration backfills; old files load (tested). |
| Looks of existing players change | Generation sequence is bit-identical to `PlayerLook.random(hash(id))`; test compares 300 seeds. |
| Cards go stale | Card data is a view-model rebuilt from live `PlayerData` (`PlayerCardData`), category derived from OVR on each read, `PlayerCard.refresh()`. |
| Portrait viewports leak / slow the match | One shared `SubViewport` with its own `World3D`, `UPDATE_ONCE`, bounded LRU cache, `release()`; tested. |
| Concurrent work | `git status` was clean at start; only small, additive edits to existing files (listed in the final report). |

## Recommended implementation order (followed)

Audit → appearance data + persistence → card data/category → portrait renderer → card UI → screens (squad, academy, profile, collection, detail) → save migration → tests → docs. Asset-dependent phases (new character/face/animations) are specified, not faked — see the other docs.
