# Player Character v2 — Blender → GLB → Godot pipeline

Built entirely by `tools/blender/build_player_v2.py` (Blender 5.2, headless):

```
blender -b --factory-startup --python tools/blender/build_player_v2.py -- assets/models/characters/v2
```

Outputs `player_v2.glb`, `goalkeeper_v2.glb`, `clips.json` (locomotion clip speeds) and the editable sources
`src/player_v2.blend`, `src/goalkeeper_v2.blend` (`src/.gdignore` keeps Godot from importing them).

**Status: opt-in.** Settings → Graphics → *Player model*: **Classic** (v1, default) or **Detailed (new rig)**. With v2
selected, `PlayerCharacterVisual` swaps the v1 GLB of any scene (match players, keepers, portraits, team view) for
its v2 counterpart before it starts; nothing else in the game changes.

## Model

- One body mesh (~4,900 triangles: skin-modifier sculpt of torso, arms, legs and boots + head, ears, nose, eyes,
  mouth, brows, palms and 5 fingers per hand, shirt-number patch), plus hair meshes `*_Hair_{Short,Buzz,Afro,Long}`
  and `*_Beard`. Smart-UV unwrapped; the number patch keeps exact 0..1 UVs for the number atlas.
- Kit regions as separate materials with the v1 suffixes: Skin Hair Jersey Trim Shorts Socks Boots Dark Number
  (+ Glove on the keeper, who also has long sleeves and long shorts). `TeamKit`, `PlayerLook`, `FaceBuilder`,
  `HairBuilder` work unchanged; no image textures are needed (colours come from the kit).
- 1.80 m, feet on y = 0, facing −Z in Godot.

## Skeleton (50 deform bones)

v1's 18 bones keep their names and joint positions (verified < 1 cm), so face/hair offsets and the generated
reaction clips stay valid. Added: `Shoulder_L/R`, `Toes_L/R`, and per hand `Thumb1-2`, `Index1-3`, `Middle1-3`,
`Ring1-3`, `Pinky1-3`. Authoring-only controls (not exported): `IK_Foot_L/R` targets and `Pole_Knee_L/R`; leg IK is
baked into the deform bones on export. The pole angle is calibrated on a bent leg so knees point forward.

Weights: Blender bone-heat for the body, then region clean-up (no arm bones on torso/legs and vice versa, no
cross-leg weights, crotch shared by both thighs + hips, nothing bound to the static `Root`); distance weights for
hands/fingers and the number patch; head parts rigid to `Head`. Max 4 influences, normalised.

## Animation library

| Loops | One-shots | Keeper |
|---|---|---|
| Idle, Walk (1.45 m/s), Jog (3.2), Run (5.0), Sprint (7.4), Dribble (4.0) | Pass, Shoot, LongPass, Kick, FirstTouch, BallControl, Tackle, SlideTackle, Jump, Header, TurnLeft, TurnRight, Accelerate, Decelerate | Ready (loop), DiveLeft, DiveRight, CatchHigh, CatchLow, Throw |

Celebrate, Disappointed, ThrowIn and PortraitIdle are generated in-engine by `PlayerAnimationLibrary` from v2's Idle,
as for v1.

**No foot sliding by construction:** in each gait the planted foot moves backwards at exactly the clip's speed
(IK), so with playback rate = player speed / clip speed the foot stays on the grass. The visual uses the v2 speeds,
picks Jog between 2.1 m/s and the run threshold, and scales Dribble by its own speed.
`tests/player_v2_validation.gd` measures it.

## Honest limits

- Procedurally modelled and key-framed by script: stylised, readable, game-ready — not sculpted, not motion
  capture. Faces come from `FaceBuilder` as in v1; no facial animation; fingers are posed, not animated per action.
- Tackle / SlideTackle / Jump / Header / Turn / Accelerate / Decelerate exist in the GLB, but the match code does not
  trigger them yet (the game has no tackle/header mechanics wired to the visual). Hooking them up = calling
  `play_reaction("<clip>")` from those mechanics.
- Extreme hip angles (highest kick follow-through) show a small crease at the crotch.
- Body proportion variety uses the existing `PlayerLook` rig scaling (height/build); no blend shapes.

## Changing it

Edit the script and re-run it; re-import in Godot; run `player_v2_validation`. During development every clip was
checked on Workbench renders (front / side / back / three-quarter contact sheets of the `.blend`).
