# Player Animation System (Phase V4)

## Source clips (authored, unchanged)

`Idle Walk Run Kick`; goalkeeper also `Ready DiveLeft DiveRight CatchHigh CatchLow Throw`.

## Generated clips (new, built in-engine — no external asset)

`scripts/players/player_animation_library.gd` (`PlayerAnimationLibrary.install`) adds eight clips to the
`AnimationPlayer` of any character with the shared rig (outfield and goalkeeper). Called from
`PlayerCharacterVisual._ready`; idempotent; does nothing if a source clip is missing.

| Clip | How it is made | Triggered by (real gameplay) |
|---|---|---|
| `Sprint` | `Run` re-timed ×0.78 (faster cadence), amplitude ×1.25 around the standing pose, forward spine lean, head compensated | `SPRINTING` state; team players at ≥ 7 m/s |
| `Dribble` | `Run`, amplitude ×0.75, slight lean, head down toward the ball | `FootballActions.dribble_started/stopped` while running |
| `Pass` | `Kick` re-timed ×0.72, amplitude ×0.65 | `pass_started` |
| `Shoot` | `Kick` ×0.9, amplitude ×1.2 | `shot_started` |
| `LongPass` | `Kick`, lean back | `lob_started` |
| `FirstTouch` | keyframed from the standing pose: raised, cushioning right leg, arms out | reception complete (`ball_received`) — only when nearly standing |
| `Celebrate` | keyframed: arms overhead, three hops with knee tuck, lean back (2.3 s) | `MatchManager._goal_reactions`: scoring side's outfield, during the 2.5 s goal pause |
| `Disappointed` | keyframed: head and spine slump, arms hanging forward (2.2 s) | same, conceding side |

Bone offsets are expressed in model axes and converted through the parent's rest rotation (the imported rig has
non-identity rest rotations). Every clip was checked on side-view contact sheets (`tools/model_view.tscn`).

## Behaviour (in `PlayerCharacterVisual`)

Cross-fades 0.18 s (kicks 0.08 s, reactions 0.15 s); playback rate scaled to speed against the authored clip speed
(`walk/run/sprint_clip_speed`) to limit foot sliding; one-shots block locomotion refresh until they end and then
**resume the matching locomotion clip** (before, a finished Kick left the pose frozen until the next speed signal);
a first touch never freezes a running player; `play_kick(kind)` falls back to `Kick` if a generated clip is missing.

## Deliberately NOT created

Tackle, interception, header, injury, turn clips, goalkeeper block/punch/distribution variants and a teammate-interaction
clip: **the game has no such mechanics**, and animations that no gameplay state can trigger would contradict the
"animation must match gameplay" rule. When a mechanic is added, add a derived/keyframed clip to the library and call
`play_reaction`/`play_kick` from that mechanic.

## AnimationTree

Not introduced. Locomotion is a 1-D speed choice plus one-shot overrides, which `AnimationPlayer` with cross-fades and
rate scaling already does; an `AnimationTree` would need the existing tests/gameplay (which read `current_animation`) to be
rewritten for no visible gain. Revisit when blend-space locomotion (turning, strafing) is authored.

## Quality limits (honest)

Generated clips are procedural variations of the existing animation, not hand-animated: stylised and readable, but not
motion-capture quality; hands/fingers and facial animation are not animated; no IK foot locking.

## Tests

`player_visual_validation.gd` (clip installation on both rigs, bone paths / finite normalised keys, loop modes, timing,
kick kinds, speed→Sprint/Dribble, reactions, return to idle) and `player_visual_integration_validation.gd`
(Pass/Shoot/LongPass/dribble reach the visual from real `FootballActions`; goal reactions in a real match; keepers excluded).
