# Lob Passing System (Phase 4)

The lob is the aerial pass: a fixed configurable vertical impulse plus a
modest horizontal kick, producing a natural gravity-driven arc. No scripted
trajectory, no teleport (plan §8).

## Where it lives

- `scripts/gameplay/lob_pass_system.gd` — `LobPassSystem` (`Node`), built by
  `FootballActions._build_subsystems()`. Unlike the other subsystems it
  reads the config itself (it carries a `config` export set at build time).
- Input/charging/cooldowns/state in `football_actions.gd` (charge
  controller `LobCharge`).

## How a lob happens

1. Player presses `lob_pass` (Q / gamepad Y) in the interaction window →
   `LobCharge.start()`.
2. On release:
   - Power: quick tap → `default_lob_power` (7 m/s); charged → ramp to
     `max_lob_power` (12 m/s), clamped to `[min_lob_power (3), max]`.
   - Vertical: fixed `lob_lift` (6.5 m/s up) — the arc knob. Deliberately
     not charge-scaled: the height stays predictable regardless of distance.
   - Direction: intent↔to-ball blend (`lob_direction_adjustment` 0.35).
   - Kick: `BallController.apply_kick(direction, power, lob_lift)`.
3. `lob_started(power, lift)` fires, transient `LOB_PASSING` state (0.3 s) +
   `lob_cooldown` (0.6 s). Per plan §14 there is no `lob_completed` signal.

## Guarantees

- The arc is real physics: gravity, ground bounce and settling come from
  the Phase 3 ball. The suite verifies the ball actually gains ≥ 0.3 m
  height after the kick.
- Vertical velocity bounded by `lob_lift`; horizontal by the ball ceiling.
- Same cooldown/cancel guards as pass/shoot.

## Tuning knobs (`BallActionConfig` → Lob group)

| Knob | Default | Meaning |
|---|---|---|
| `min_lob_power` | 3 m/s | Power floor |
| `max_lob_power` | 12 m/s | Fully charged |
| `default_lob_power` | 7 m/s | Quick tap |
| `lob_lift` | 6.5 m/s | Vertical impulse (arc height) |
| `lob_direction_adjustment` | 0.35 | intent↔to-ball blend |
| `lob_cooldown` | 0.6 s | Re-trigger block |

## Validation coverage

`tests/phase4_validation.tscn` asserts: tap power, strong upward impulse
(vel.y > 4), horizontal speed kept (5–10 m/s), direction follows facing,
airborne arc measured (height gain), transient state + no-lockup recovery,
cooldown expiry with the ball re-placed in range.

## Notes for Phase 5+

- A goalkeeper AI reading `lob_started` knows a high ball is incoming; pair
  with `shot_started` to distinguish shots from lobs.
- If per-distance arcs are wanted later, replace the fixed `lob_lift` with
  a charge-ratio lerp (same pattern as shooting).
