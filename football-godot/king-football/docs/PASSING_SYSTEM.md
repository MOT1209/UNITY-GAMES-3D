# Passing System — Ground Passing (Phase 4)

Ground passes execute a directional physics kick through the Phase 3 ball
API. Nothing here touches animation or possession.

## Where it lives

- `scripts/gameplay/passing_system.gd` — `PassingSystem` (`Node`), one
  instance per player, built by `FootballActions._build_subsystems()`.
- Input, charging, cooldowns and state live in `scripts/gameplay/
  football_actions.gd` (`FootballActions`) — this node is deliberately pure
  kick computation so it stays trivially testable.

## How a pass happens

1. Player presses `pass` (Space / gamepad A) while `can_interact_with_ball()`
   is true and no cooldown/state-hold is running → `PassCharge.start()`.
2. While held, the charge ramps power from `default_pass_power` (9 m/s) up
   to `max_pass_power` (16 m/s) over `charge_time` (0.9 s). A hold shorter
   than `quick_tap_threshold` (0.12 s) releases the default power.
3. On release, `PassingSystem.execute_pass()` runs:
   - Direction = movement-input direction (camera-relative, world fallback)
     blended with the planar direction toward the ball by
     `pass_direction_adjustment` (0.35). No input → facing; no ball
     direction → pure intent. Degenerate setups are rejected (-1).
   - Power clamped to `[min_pass_power, max_pass_power]`.
   - Kick: `BallController.apply_kick(direction, power, 0.0)` — a
     mass-scaled impulse that adds to the ball's current velocity and
     respects its speed ceiling. No lift: passes stay on the ground.
4. `FootballActions` emits `pass_started(power)`, plays the kick anim hook,
   starts the transient `PASSING` state (`state_hold` 0.3 s) and the
   `pass_cooldown` (0.35 s). `pass_completed` fires when the transient
   state expires.

## Guarantees

- One kick per press: cooldown + transient state block re-trigger; a charge
  started while the interaction window is open is cancelled if the window
  closes before release.
- No teleporting, no velocity writes — one wake-safe impulse per kick.
- Standing-still pass still works (facing / to-ball fallbacks).

## Tuning knobs (`BallActionConfig` → Passing group)

| Knob | Default | Meaning |
|---|---|---|
| `min_pass_power` | 4.0 m/s | Power floor |
| `max_pass_power` | 16.0 m/s | Fully charged power |
| `default_pass_power` | 9.0 m/s | Quick-tap power |
| `pass_direction_adjustment` | 0.35 | intent↔to-ball blend (1 = kick exactly at ball) |
| `pass_cooldown` | 0.35 s | Re-trigger block |

Charge timing (shared): `charge_time` 0.9 s, `quick_tap_threshold` 0.12 s,
`state_hold` 0.3 s.

## Notes for Phase 5+

- `pass_started(power)` + `get_kick_direction()` are enough to spawn a
  pass-target indicator or to feed teammate selection.
- The blend knob doubles as a future "assist strength" per difficulty.
- A charged pass currently has no lift; power-scaled lofting is reserved
  (see the `charge_ratio` parameter kept in `_execute_pass`).
