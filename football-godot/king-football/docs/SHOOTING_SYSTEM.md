# Shooting System (Phase 4)

Shots are directional physics kicks with charge-scaled elevation. No
goalkeeper, no shot curves, no rule logic (plan §7 boundary).

## Where it lives

- `scripts/gameplay/shooting_system.gd` — `ShootingSystem` (`Node`), built
  by `FootballActions._build_subsystems()`.
- Input/charging/cooldowns/state in `football_actions.gd`; the shoot charge
  controller is named `ShootCharge`.

## How a shot happens

1. Player presses `shoot` (E / gamepad B) while the interaction window is
   open → `ShootCharge.start()`.
2. While held: charge ratio ramps 0→1 over `charge_time` (0.9 s) after the
   quick-tap threshold. UI reads `get_charge_ratio(&"shoot")` (also
   broadcast via `charge_changed`).
3. On release:
   - Power: quick tap → `default_shoot_power` (16 m/s); charged → lerp
     default → `max_shoot_power` (26 m/s) by the ratio, clamped to
     `[min_shoot_power (10), max_shoot_power]`.
   - Lift: `lerpf(min_shot_lift, max_shot_lift, charge_ratio)` — a tap is a
     near-ground drive (0.3 m/s up), a full charge is an elevated shot
     (3.0 m/s up).
   - Direction: same intent↔to-ball blend as passing
     (`shoot_direction_adjustment` 0.3).
   - Kick: `BallController.apply_kick(direction, power, lift)`.
4. `shot_started(power, lift)` fires (tests must sample the lift here — by
   the time `linear_velocity.y` is read, gravity has eaten small lifts),
   transient `SHOOTING` state (0.3 s) + `shoot_cooldown` (0.5 s), then
   `shot_completed`.

## Guarantees

- Elevation is bounded by config (`max_shot_lift`) and horizontal speed by
  the ball's ceiling; stacked kicks cannot exceed `max_ball_speed`.
- Charging requires the ball in range at press **and** keeps a guard: the
  charge cancels if the window is lost mid-hold.
- Elevated shots are physics-true — the arc comes from the initial
  velocity + gravity, nothing scripted.

## Tuning knobs (`BallActionConfig` → Shooting group)

| Knob | Default | Meaning |
|---|---|---|
| `min_shoot_power` | 10 m/s | Power floor |
| `max_shoot_power` | 26 m/s | Fully charged |
| `default_shoot_power` | 16 m/s | Quick tap |
| `min_shot_lift` | 0.3 m/s | Tap elevation |
| `max_shot_lift` | 3.0 m/s | Charged elevation |
| `shoot_direction_adjustment` | 0.3 | intent↔to-ball blend |
| `shoot_cooldown` | 0.5 s | Re-trigger block |

## Validation coverage

`tests/phase4_validation.tscn` asserts: tap power/trajectory/elevation,
charge ratio 0 before the threshold and ramping during hold, charged power
> default, elevated trajectory (vertical velocity from the signal),
no charging/shooting out of range.

## Notes for Phase 5+

- `shot_started(power, lift)` + `get_kick_direction()` give a goalkeeper AI
  exactly the shot state it needs to react.
- Finesse/curve is intentionally absent; adding spin would be a
  `BallController.apply_kick(spin)` extension (the parameter already
  exists).
