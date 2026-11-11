class_name PassingSystem
extends Node

## Ground-passing mechanic (Phase 4, plan §6). Pure kick computation — the
## orchestrator (`FootballActions`) owns input, charging, cooldowns and state.
##
## Design rules honoured here:
##   - Directional: the kick direction is the player's intended direction
##     (movement input / facing), blended toward the ball's actual position by
##     `config.pass_direction_adjustment` so a pass can be aimed at a moving
##     ball but still reach the teammate the player faces.
##   - Physics only: the kick is applied through `BallController.apply_kick()`
##     (a mass-scaled impulse that adds to the ball's existing velocity and
##     respects the speed ceiling). No animation fakery, no teleporting.
##   - Responsive and predictable: powers are clamped to config limits.

## Executes a ground pass. `intent` is the player's kick direction (any
## length), `power` the charged power in m/s, `ball_direction` the planar
## direction from the player toward the ball (ZERO if unknown). Returns the
## applied power (m/s) or -1.0 when the kick was rejected.
func execute_pass(ball: BallController, intent: Vector3, power: float,
		ball_direction: Vector3, config: BallActionConfig) -> float:
	if ball == null or not is_instance_valid(ball):
		return -1.0
	var direction := _adjusted_direction(intent, ball_direction,
			config.pass_direction_adjustment)
	if direction == Vector3.ZERO:
		return -1.0
	var applied := clampf(power, config.min_pass_power, config.max_pass_power)
	ball.apply_kick(direction, applied, 0.0)
	return applied


## Blends the intended direction with the direction toward the ball and
## flattens the result. Falls back to the ball direction when no intent is
## available (e.g. passing while standing still with an unknown facing).
func _adjusted_direction(intent: Vector3, ball_direction: Vector3,
		adjustment: float) -> Vector3:
	var flat_intent := Vector3(intent.x, 0.0, intent.z)
	var to_ball := Vector3(ball_direction.x, 0.0, ball_direction.z)
	var result: Vector3
	if flat_intent.length_squared() > 0.0001 and to_ball.length_squared() > 0.0001:
		result = (flat_intent.normalized() * (1.0 - adjustment)
				+ to_ball.normalized() * adjustment).normalized()
	elif flat_intent.length_squared() > 0.0001:
		result = flat_intent.normalized()
	elif to_ball.length_squared() > 0.0001:
		result = to_ball.normalized()
	else:
		result = Vector3.ZERO
	return result
