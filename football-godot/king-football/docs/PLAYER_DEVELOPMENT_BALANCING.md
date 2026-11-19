# Player development balancing

Every number lives in `scripts/systems/development/dev_config.gd` (formulas only read it) and `scripts/systems/training/progression_model.gd`.

## Growth shape (implemented + tested for direction and limits, **not tuned against real football data**)
* Weekly points = `BASE_WEEKLY_POINTS` (0.35) x age factor x headroom (potential - overall) x trait factor x fitness x facility x intensity x diminishing returns (current / 110) x coaching x personality, damped by `ENGINE_SCALE` (0.6).
* Age factor falls with age (floor 0.25); headroom shrinks to 0 as overall approaches potential; potential is a ceiling on the overall, never a guaranteed result.
* Season gain caps per attribute: 6 (age <= 21), 3 (22-29), 1 (>= 30).
* Coach multipliers: vacant 0.85, rating 1 = 0.92, rating 20 = 1.12, department cap 1.15, specialisation +0.02.
* Plans: adaptation after a switch 0.60 for 3 weeks, consistency 0.92..1.06 over 10 weeks, long-term plan x0.85 now and x1.10 after 26 weeks, spreading over targets gives +12 % per extra target up to x1.35.
* Match experience: 0.10 points per full match (x rating factor 0.7..1.3); no minutes, no match growth.
* Sessions: 0.10 points per full-intensity session, 2 fitness per session (x1.5 physical); no training below fitness 40.
* Overload: more than 3 session-intensity points a week, plan intensity above 0.6, or fitness below 55 add injury risk (max 5 % a week).

## Evidence
Directional behaviour is tested: a regular starter develops more than a bench player; elite coaching beats none; every session raises its attribute beyond the plan; overloaded schedules injure players and normal ones do not; season caps hold; potential limits the overall. No simulation compared the resulting rating curves with real-world data, so absolute growth speed is a design value, not a measurement. Players do not develop at identical rates (age, headroom, traits, personality, plan, coaching and match minutes all differ).

## Stages
Youth (<= 21) develops fastest and has the high season cap; prime (22-29) develops slowly; 30+ is capped at one point per attribute and season in the weekly engine, and yearly decline is handled by `PlayerLifecycle`.
