# Phase 4 Report — Football Gameplay Mechanics

**Status: COMPLETE** — validated headlessly, all suites green.

## Scope (per `المرحلة_الرابعة.txt`)

Complete Phase 4 gameplay mechanics inside the existing project on top of the
Phase 2 player and Phase 3 ball: a central player↔ball interaction layer,
passing / shooting / lob passing / dribbling / ball reception, kick-power
charging, action states, cooldowns, a gameplay test scene with dev HUD, and a
fourth validation suite. **Out of scope** (plan §20): team AI, opponent /
goalkeeper AI, formations, match rules, scoreboard/timer, fouls, offside, full
animation system, multiplayer, career/tournament, advanced skill moves. The
`tackle` action stays unconsumed.

## Delivered

| File | Role |
|---|---|
| `scripts/gameplay/football_actions.gd` | `FootballActions` — central interaction layer (`Node3D`), input integration, cooldowns, derived action-state machine, plan §5 queries, signal surface (§14) |
| `scripts/gameplay/ball_action_config.gd` (+ `resources/configurations/ball_action_config.tres`) | All tunable gameplay numbers, `BallActionConfig` resource |
| `scripts/gameplay/kick_power_controller.gd` | Per-action power charge (quick tap / ramp to max / cancel guard) |
| `scripts/gameplay/passing_system.gd` | Ground pass kick computation (directional blend) |
| `scripts/gameplay/shooting_system.gd` | Shot kick computation + charge-scaled elevation |
| `scripts/gameplay/lob_pass_system.gd` | Lob kick computation + fixed vertical impulse |
| `scripts/gameplay/dribbling_system.gd` | Per-tick follow-spot push + overshoot brake |
| `scripts/gameplay/ball_control_system.gd` | Reception: capped exponential damping + feet pull |
| `scenes/player/player.tscn` (modified) | Added `BallActions` (gameplay node) + `BallDetector` child — controller script untouched |
| `scenes/development/football_mechanics_test.tscn` + script | Interactive gameplay test scene (pitch, player, ball, camera, obstacles+wall, KING-styled HUD) |
| `tests/phase4_validation.tscn` + script | Headless validation suite (122 checks) |
| `tests/screenshot_runner.gd` (modified) | `-- mechanics` capture mode → `phase4_mechanics_test.png` |
| `docs/PHASE_4_AUDIT.md` | Mandatory pre-implementation audit |

Design details: `PASSING_SYSTEM.md`, `SHOOTING_SYSTEM.md`,
`LOB_PASSING_SYSTEM.md`, `DRIBBLING_SYSTEM.md`, `BALL_CONTROL_SYSTEM.md`.

## Architecture in one paragraph

`FootballActions` is mounted as `BallActions` under the player with a
`BallProximityDetector` child (`BallDetector`). It builds its subsystem nodes
programmatically in `_ready()` (PassingSystem, ShootingSystem, LobPassSystem,
DribblingSystem, BallControlSystem and three KickPowerControllers named
PassCharge/ShootCharge/LobCharge). It consumes the existing InputMap actions
`pass`/`shoot`/`lob_pass`/`dribble` (+ `sprint` for the dribble boost) — no
movement action changed. Every kick goes through the Phase 3
`BallController.apply_kick()`; dribble and reception control are per-tick
capped `apply_force()` pushes that wake the ball first; the ball is never
attached or teleported. The action state (IDLE / RECEIVING / PASSING /
SHOOTING / LOB_PASSING / DRIBBLING) is derived fresh every physics tick from
small flags, so a locked-up state is structurally impossible. Animation hooks
(`play_kick()`) are guarded by `has_method` — gameplay works with or without
the character visual.

## Validation results

```
=== Validation summary: 122 passed, 0 failed ===      # phase4 (exit 0)
=== Validation summary: 49 passed, 0 failed ===       # phase1 regression
=== Validation summary: 57 passed, 0 failed ===       # phase2 regression
=== Validation summary: 103 passed, 0 failed ===      # phase3 regression
=== Validation summary: 29 passed, 0 failed ===       # stadium arena regression
```

Coverage highlights (122 checks):

- **Assets & structure** — all 8 gameplay scripts parse, config resource
  loads, test scene loads, InputMap `pass`/`shoot`/`lob_pass`/`dribble`/
  `tackle` and movement actions intact.
- **Scene wiring** — player scene carries `BallActions` + `BallDetector`;
  at runtime (post-`_ready`) all five subsystems + three charge controllers
  exist with the right scripts.
- **Query API** — `can_interact_with_ball`, `get_ball_relative_position`,
  `get_ball_distance`, `get_kick_direction`, `get_action_availability` +
  the ten plan §14 signals exist.
- **Subsystem contracts** — no `apply_force`/`apply_impulse` overrides
  (Godot 4.7 native-method rule); test scene contains
  Pitch/Player+gameplay/Ball/GameCamera/HUD.
- **Config sanity** — min < default < max for all three kick types, positive
  cooldowns, dribble/reception forces sane, lob lift positive.
- **Runtime physics + input** (simulated via `Input.action_press/release`):
  - Ground pass: interaction window at 0.5 m, relative position (−Z ahead),
    default kick direction = facing, quick tap = exactly one kick at 9 m/s,
    ball speed ≈ power, direction follows facing, stays low,
    `pass_completed` after the transient state, state back to IDLE.
  - Cooldown/repeat: second tap during the cooldown neither kicks again nor
    adds a second impulse; `pass` flagged unavailable during cooldown.
  - Ground shot: default 16 m/s, slight lift, along facing.
  - Charged shot: charge ratio 0 before the quick-tap threshold, ramps
    during hold, charged power > default, elevated trajectory (lift read
    from `shot_started`).
  - Lob: default 7 m/s + 6.5 m/s upward impulse, horizontal speed kept,
    along facing, real airborne arc (ball gains ≥ 0.3 m height).
  - Charge guard: no charging / no shot with the ball out of the 0.9 m
    interaction window.
  - Dribbling: ball 1.2 m ahead (outside interaction, inside dribble range)
    is gathered, carried with the player (≤ 1.6 m behind the follow spot),
    no teleport (max per-tick move < 0.4 m), free settle after release,
    `dribble_started`/`dribble_stopped` emitted.
  - Reception: an 8 m/s ball is automatically damped under control
    (`RECEIVING` state entered), `ball_received` under the completion speed,
    ball ends near the player, no teleport (max per-tick move < 0.35 m).
  - State recovery: transient `LOB_PASSING` resolves to IDLE (no lockup),
    lob available again after its 0.6 s cooldown (ball re-placed in range so
    availability reflects the cooldown itself).
  - Movement regression: Phase 2 run speed unaffected with the gameplay node
    mounted (≈ 5.5 m/s).
  - Phase integration: Phase 1–3 assets + the Phase 4 script/resource still
    load on top.
- **Visual capture** — windowed run of the mechanics scene shows the real
  character, the live HUD (action state, ball speed/distance, interaction,
  cooldown marks, charge bars, last event) and a completed dribble→pass
  cycle ("Pass action complete").

## Issues fixed during implementation

1. **Static-structure test corrupted runtime tests** — an early version
   added a second player to the tree in a static test; the two overlapping
   capsules depenetrated (~0.5 m push), which silently moved the *next*
   runtime scenario's player out of interaction range and broke 6+ checks.
   Fix: static tests never add the player to the tree; subsystem wiring is
   checked on the runtime scenario player instead. (Cost: 2 debug
   iterations — the diagnostic print that exposed it is now documented in
   `tests/phase4_validation.gd` comments.)
2. **Shot lift read too late** — reading `linear_velocity.y` ~3 ticks after
   release lost the 0.3 m/s lift to gravity (measured negative). Fix: sample
   the lift from the `shot_started` signal payload instead.
3. **Cooldown-availability check needed ball context** — after a kick the
   ball is far outside the interaction window, so availability is false for
   a reason unrelated to the cooldown. Fix: `reset_ball()` the ball back
   into range before asserting the cooldown has elapsed.
4. Godot 4.7 gotchas honoured (from the Phase 3/4 audits): `_ready()` does
   not run on non-tree instances; forces are one-step (re-applied per tick
   by design); native `RigidBody3D.apply_impulse/apply_force` are never
   overridden in GDScript.

## Launching the test scene

```text
godot --path . res://scenes/development/football_mechanics_test.tscn
# or open the scene in the Godot editor and press F6.
```

Controls: `WASD`/arrows move · `Shift` sprint · `V` camera · `Space` pass
(hold to charge) · `E` shoot (hold = power + elevation) · `Q` lob ·
`C` dribble (hold) · `Esc` menu. Dev-only raw keys: `1/2/3/4` direct kicks,
`R` ball to centre, `T` full reset, `B` drop from 6 m. Scripted capture:
`godot --path . res://tests/screenshot_runner.tscn -- mechanics` (output:
`assets/placeholders/validation/phase4_mechanics_test.png`).

## Unverified / not covered

- **Gamepad play-testing** — the InputMap joypad bindings exist and the
  suites simulate actions (which exercise the shared action path), but no
  human has played this with a physical gamepad yet.
- **Animation** — `play_kick()` is called via a guarded hook but the visual
  behaviour was not judged visually beyond the screenshot; no dedicated
  kick/tackle animations exist (later phase).
- **Camera-relative aim in the arena scene** — the suite validates aim logic
  headlessly (world-axis fallback path); the broadcast-camera interplay was
  only spot-checked in the mechanics capture.
- **Long sessions / edge physics** — dribbling a ball against walls at full
  sprint, receptions off bounces, and very high charge rates are tuned but
  not exhaustively stress-tested.

## Known limitations (accepted for Phase 4)

- Direction "aiming" blends intent with the to-ball direction; there is no
  explicit pass-target/assist system yet.
- Reception engages only for balls inside 1.4 m planar distance moving
  toward the player; a receiver cannot "call" a far pass yet.
- Dribble control releases entirely when the ball leaves 1.6 m (by design —
  no magnet/recovery snap).
- No pass/shoot animation blending, no foot placement accuracy (possession
  is power-based, not foot-position-based).
- Player walks through the ball when not dribbling (player body mask is
  world-only, layer 1) — accepted arcade behaviour, documented in the audit.
- `tackle` remains unmapped to gameplay (future phase).

## What is next

See `PHASE_5_HANDOFF.md` — everything Phase 5 (AI/rules) needs is exposed
through `FootballActions` signals/queries and the `BallActionConfig`
resource, and the interaction contract Phase 3 handed to Phase 4
(`apply_kick` + detector) is unchanged.
