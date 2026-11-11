class_name LobPassSystem
extends Node

## Elevated passing mechanic (Phase 4, plan §8). Kick computation only.
##
## Design rules honoured here:
##   - Horizontal movement toward the intended direction
##     (`lob_direction_adjustment` blend toward the ball, same as passing).
##   - A fixed configurable vertical impulse (`config.lob_lift`, upward m/s)
##     produces a natural airborne arc — gravity, ground collision and
##     bouncing stay entirely with the Phase 3 ball physics.
##   - No teleporting, no fake trajectories: a single wake-safe kick impulse.
##   - Vertical velocity is bounded by the `lob_lift` config (avoids excessive
##     height) and the overall speed by the ball's configured ceiling.

@export var config: BallActionConfig


## Executes a lob pass. Returns the applied power (m/s) or -1.0 when rejected.
func execute_lob(ball: BallController, intent: Vector3, power: float,
		ball_direction: Vector3) -> float:
	if ball == null or not is_instance_valid(ball) or config == null:
		return -1.0
	var flat_intent := Vector3(intent.x, 0.0, intent.z)
	var to_ball := Vector3(ball_direction.x, 0.0, ball_direction.z)
	var direction: Vector3
	if flat_intent.length_squared() > 0.0001 and to_ball.length_squared() > 0.0001:
		direction = (flat_intent.normalized() * (1.0 - config.lob_direction_adjustment)
				+ to_ball.normalized() * config.lob_direction_adjustment).normalized()
	elif flat_intent.length_squared() > 0.0001:
		direction = flat_intent.normalized()
	elif to_ball.length_squared() > 0.0001:
		direction = to_ball.normalized()
	else:
		return -1.0
	var applied := clampf(power, config.min_lob_power, config.max_lob_power)
	ball.apply_kick(direction, applied, config.lob_lift)
	return applied
