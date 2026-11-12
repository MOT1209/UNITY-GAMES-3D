# Player Animation System (Phase V4) — status: NOT extended

## What exists and works (unchanged)

`PlayerCharacterVisual` drives the GLB's `AnimationPlayer`: `Idle`, `Walk`, `Run`, `Kick`;
goalkeeper `Ready`, `DiveLeft/Right`, `CatchHigh/Low`, `Throw`. Speed-based clip choice,
playback-rate scaling against the authored clip speeds (`walk_clip_speed`, `run_clip_speed` → reduces
foot sliding), 0.18 s cross-fades, one-shot clips are not interrupted by locomotion updates.
Verified in `player_visual_validation.gd` (Idle→Walk→Run→Idle by speed, Kick not interrupted, fade ≥ 0.1 s).
Portraits freeze `Idle` at t=0 for a deterministic pose.

## What was requested but is not delivered

Sprint, turn, accelerate/decelerate, dribble, short/long pass, first touch, tackle, interception,
header, celebration, disappointment, injury, teammate interaction, goalkeeper block/punch/distribution
variants, and an `AnimationTree` state machine.

**Why:** these are new *clips* (authored in a DCC tool and exported with the rig). None exist in the repo,
none can be authored here, and creating fake/empty clips would violate "do not create animations that
contradict gameplay". Wiring a `AnimationTree` without clips would add risk and no visible value.

## Clip specification for the animator

- Same 18-bone rig, 30 fps, names exactly as below, root motion off, feet-locked loops.
- Loops: `Sprint` (6.5–9 m/s), `Jog`, `Dribble` (ball-close run), `TurnLeft/Right` (one-shots, 0.4 s).
- One-shots: `Pass`, `LongPass`, `Shoot`, `FirstTouch`, `Tackle`, `Intercept`, `Header`, `Celebrate1-3`, `Disappointed`, `Injured`,
  keeper `Punch`, `BlockLow`, `Distribute`.
- Integration plan: add the names to `NON_LOOPING`, call from the existing `FootballActions` signals (`play_kick()` is the pattern), then move locomotion into an `AnimationTree` blend space (speed) + one-shot nodes. Retargeting works by bone name as long as the rig is the shared one.
