# Player Character Base (Phase V1)

## Decision

The project already contains a **stylized, rigged, animated, kit-recolourable** character
(`assets/models/characters/player.glb`, `goalkeeper.glb`). It matches the approved
"Stylized Enhanced 3D" direction (rounded stylized body, modelled face with eyes/brows/mouth,
athletic proportions). Per the brief ("do not rebuild / do not duplicate"), **it is the master
character**. No replacement model was created: this environment has no Blender/DCC tool and no
licensed character pack, and the asset policy forbids pretending or shipping unrelated
placeholders.

## What the base provides (verified by `tests/player_visual_validation.gd`)

- One `Skeleton3D`, 18 bones, shared by outfield and goalkeeper models.
- One `AnimationPlayer`. Outfield: `Idle Walk Run Kick`. Keeper adds `Ready DiveLeft DiveRight CatchHigh CatchLow Throw`.
- Height 1.6–2.1 m, feet at y=0, facing **−Z** (the portrait camera therefore sits at −Z).
- Modular parts as separate meshes: `Body` (head+face+arms+legs+kit+boots), `Hair_{Short,Buzz,Afro,Long}`, `Beard`.
- Reusable materials by name suffix: `Jersey Trim Shorts Socks Boots Skin Hair Number Dark` (+ `Glove` on the keeper). `TeamKit.apply_to` / `PlayerLook` duplicate a material per player so nothing leaks between players.
- Instantiable in a match: `MatchManager._dress` → `PlayerCharacterVisual` (unchanged API).

## Scenes / scripts

| File | Role |
|---|---|
| `scenes/player/player_model.tscn`, `goalkeeper_model.tscn` | Character scene = GLB + `PlayerCharacterVisual` / `GoalkeeperVisual` |
| `scripts/player/player_character_visual.gd` | Kit, number, look application, animation driving |
| `scripts/players/player_appearance.gd` | **New**: stored appearance → `PlayerLook` |

## Import configuration

GLBs are imported with Godot defaults (`*.glb.import` in the repo). Required properties for any
replacement/extension of the model so the rest of the pipeline keeps working:

1. Scale 1 unit = 1 m, facing −Z, origin between the feet.
2. A single armature named `*_Rig` (the look code scales it for height/build).
3. Material names must end with the suffixes above; hair/beard meshes must be named `*_Hair_<Style>` / `*_Beard`.
4. Animation names exactly as above (they are looked up by name); loop modes are set in code (`NON_LOOPING`).

## Asset specification for a *new* master model (not delivered here)

If a higher-fidelity model is wanted: Blender 4.x, ≤ 6k tris body + ≤ 1k per hair mesh, 18-bone
humanoid (same bone names as the current rig for retargeting), vertex-colour or ≤ 1024² atlas,
face as separate sub-meshes (`*_Eyes`, `*_Brows`, `*_Mouth`) to allow Phase V2 face variation,
export glTF 2.0 binary (`+Y up`, "Apply Modifiers", "Skinning", "Animation: NLA strips off, one
action per clip"), licence CC0/CC-BY or commissioned work; record source and licence in this file.
No external asset is currently used besides the project's own models.

## Not done (honest list)

- No new body/face model; no LOD meshes; no retargeting to a second rig (only one rig exists).
