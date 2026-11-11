class_name DribblingSystem
extends Node

## Basic physics-based dribbling (Phase 4, plan §9). The orchestrator calls
## `physics_tick()` every physics tick while the dribble action is held.
##
## Design rules honoured here (plan §9 "Important"):
##   - NO artificial ball-following: the ball is never attached, positioned or
##     teleported. Control is a per-tick capped `apply_force()` spring toward
##     the follow spot ahead of the player (the phase-3 handoff contract).
##   - The follow spot sits `dribble_follow_distance` metres in front of the
##     player along the movement direction; the applied force is the spring
##     `dribble_control_strength` (N per metre) times the planar error between
##     ball and spot. Far from the spot it pushes, close to it it gently
##     self-corrects — no constant blind shove.
##   - `apply_force()` is one-step in Godot 4.7 → re-applied every tick by the
##     caller; the ball is woken first (forces do not wake sleeping bodies).
##   - A brake component limits ball speed to the player's speed + slack so
##     pushes never run away; the force total is capped for solver stability.
##   - Standing still (no movement input): there is no follow spot to aim at, so
##     the system switches to holding mode and damps the ball's planar
##     velocity — the ball is kept under the player's control instead of being
##     shoved along the last aim direction.
##   - When the ball leaves the dribble range (or control is released), the
##     function returns false and the ball moves freely — no recovery snap,
##     the player simply has to run onto it again.
##
## Config: all numbers live in `BallActionConfig` (dribbling group).

## Squared-length epsilon for degenerate directions (matches Phase 2 style).
const DEGENERATE_DIR_EPSILON := 0.0004


## One dribble control step. Returns true while the ball is in range (under
## control), false once it leaves the range. `carry_dir` is the planar
## movement-input direction (ZERO when standing still), `player_speed` the
## player's planar speed, `sprinting` whether the sprint action is held.
func physics_tick(ball: BallController, host: Node3D, carry_dir: Vector3,
		player_speed: float, sprinting: bool, config: BallActionConfig) -> bool:
	if ball == null or not is_instance_valid(ball) or config == null:
		return false

	var offset := ball.global_position - host.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	var distance := planar.length()
	if distance > config.dribble_distance or offset.y > config.max_control_height:
		return false

	var force := Vector3.ZERO
	var carry := Vector3(carry_dir.x, 0.0, carry_dir.z)
	if carry.length_squared() > DEGENERATE_DIR_EPSILON:
		# Spring toward the follow spot ahead of the player.
		var target := host.global_position + carry.normalized() * config.dribble_follow_distance
		var error := Vector3(target.x - ball.global_position.x, 0.0,
				target.z - ball.global_position.z)
		var strength := config.dribble_control_strength
		if sprinting:
			strength *= config.dribble_sprint_boost
		force = error * strength

		# Brake: bleed ball speed that overshoots the player's speed + slack.
		var ball_vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		var ball_speed := ball_vel.length()
		var allowed := maxf(player_speed, 1.0) + config.dribble_speed_slack
		if ball_speed > allowed:
			force -= ball_vel.normalized() * (ball_speed - allowed) * config.dribble_brake_strength
	else:
		# Standing still: hold the ball close — damp its planar velocity.
		var vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		force = vel * -config.dribble_brake_strength

	force = force.limit_length(config.dribble_max_force)
	ball.sleeping = false  # apply_force does not wake a sleeping ball
	ball.apply_force(force)
	return true
