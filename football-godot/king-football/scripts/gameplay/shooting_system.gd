class_name ShootingSystem
extends Node

## Shooting mechanic (Phase 4, plan §7). Kick computation only — input,
## charging, cooldowns and state live in `FootballActions`.
##
## Design rules honoured here:
##   - Directional aiming with a `shoot_direction_adjustment` blend toward the
##     ball (same contract as passing).
##   - Variable power through the shared kick-power charge; quick tap = default
##     power, full charge = `max_shoot_power`.
##   - Ground shots (`min_shot_lift`) and slightly elevated charged shots
##     (lift scales linearly with the charge ratio up to `max_shot_lift`).
##   - Uses `BallController.apply_kick()` — respects the ball's physical state,
##     its existing velocity, and the configured speed ceiling. No goalkeeper
##     behaviour and no shot curves in this phase (plan §7 boundary).


## Executes a shot. `charge_ratio` is the 0..1 kick-power charge used to scale
## the elevation. Returns the applied power (m/s) or -1.0 when rejected.
func execute_shot(ball: BallController, intent: Vector3, power: float,
		charge_ratio: float, ball_direction: Vector3,
		config: BallActionConfig) -> float:
	if ball == null or not is_instance_valid(ball):
		return -1.0
	var direction := _adjusted_direction(intent, ball_direction,
			config.shoot_direction_adjustment)
	if direction == Vector3.ZERO:
		return -1.0
	var applied := clampf(power, config.min_shoot_power, config.max_shoot_power)
	var lift := lerpf(config.min_shot_lift, config.max_shot_lift,
			clampf(charge_ratio, 0.0, 1.0))
	ball.apply_kick(direction, applied, lift)
	return applied


func _adjusted_direction(intent: Vector3, ball_direction: Vector3,
		adjustment: float) -> Vector3:
	var flat_intent := Vector3(intent.x, 0.0, intent.z)
	var to_ball := Vector3(ball_direction.x, 0.0, ball_direction.z)
	if flat_intent.length_squared() > 0.0001 and to_ball.length_squared() > 0.0001:
		return (flat_intent.normalized() * (1.0 - adjustment)
				+ to_ball.normalized() * adjustment).normalized()
	if flat_intent.length_squared() > 0.0001:
		return flat_intent.normalized()
	if to_ball.length_squared() > 0.0001:
		return to_ball.normalized()
	return Vector3.ZERO
