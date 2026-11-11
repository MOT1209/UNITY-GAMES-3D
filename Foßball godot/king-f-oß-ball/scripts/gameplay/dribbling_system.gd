class_name DribblingSystem
extends Node

## Basic physics-based dribbling (Phase 4, plan §9). The orchestrator calls
## `physics_tick()` every physics tick while the dribble action is held.
##
## Design rules honoured here (plan §9 "Important"):
##   - NO artificial ball-following: the ball is never attached, positioned or
##     teleported. Control is a per-tick capped `apply_force()` push toward a
##     spot just ahead of the player (the phase-3 handoff contract).
##   - `apply_force()` is one-step in Godot 4.7 → re-applied every tick by the
##     caller; the ball is woken first (forces do not wake sleeping bodies).
##   - A brake component limits ball speed to the player's speed + slack so
##     pushes never run away; the force total is capped for solver stability.
##   - When the ball leaves the dribble range (or control is released), the
##     function returns false and the ball moves freely — no recovery snap,
##     the player simply has to run onto it again.
##
## Config: all numbers live in `BallActionConfig` (dribbling group).


## One dribble control step. Returns true when control was applied this tick.
## `carry_dir` is the planar direction the ball should be pushed toward (the
## player's movement/facing intent), `player_speed` the player's planar speed,
## `sprinting` whether the sprint action is held.
func physics_tick(ball: BallController, host: Node3D, carry_dir: Vector3,
		player_speed: float, sprinting: bool, config: BallActionConfig) -> bool:
	if ball == null or not is_instance_valid(ball) or config == null:
		return false

	var offset := ball.global_position - host.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	var distance := planar.length()
	if distance > config.dribble_distance or offset.y > config.max_control_height:
		return false

	# Push direction: toward the follow spot ahead of the player along the
	# carry direction. Without a carry direction (standing still) hold the
	# ball close instead of pushing it away.
	var push_dir := carry_dir
	if push_dir.length_squared() < 0.0001:
		push_dir = planar.normalized() if distance > 0.05 else Vector3.ZERO
	if push_dir == Vector3.ZERO:
		return false

	var strength := config.dribble_control_strength
	if sprinting:
		strength *= config.dribble_sprint_boost
	var force := push_dir.normalized() * strength

	# Brake: bleed ball speed that overshoots the player's speed + slack.
	var ball_vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
	var ball_speed := ball_vel.length()
	var allowed := maxf(player_speed, 1.0) + config.dribble_speed_slack
	if ball_speed > allowed:
		force -= ball_vel.normalized() * (ball_speed - allowed) * config.dribble_brake_strength

	force = force.limit_length(config.dribble_max_force)
	if force.length_squared() < 0.0001:
		return false

	ball.sleeping = false  # apply_force does not wake a sleeping ball
	ball.apply_force(force)
	return true
