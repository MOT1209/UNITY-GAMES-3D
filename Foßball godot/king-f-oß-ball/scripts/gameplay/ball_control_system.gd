class_name BallControlSystem
extends Node

## Basic ball reception / control (Phase 4, plan §10). The orchestrator calls
## `physics_tick()` every physics tick while the RECEIVING state is active.
##
## Design rules honoured here:
##   - Pure controlled physics: an exponential damping force bleeds the ball's
##     planar velocity (≈ `reception_damping` per second), never an instant
##     velocity reset and never a teleport. Collision behaviour is preserved.
##   - A small capped pull toward the player's feet "takes the ball in" while
##     it still decelerates naturally — the ball ends near the player's feet
##     because it lost speed there, not because anything snapped it there.
##   - Force is capped (`reception_max_force`) so a fast incoming ball is
##     slowed over a few ticks, not stopped dead in one (avoids absurd
##     accelerations and keeps the touch realistic for both slow and fast
##     arrivals, front or side).
##
## Triggering / state handling lives in `FootballActions`; this node only
## applies per-tick control while reception is active.


## One reception control step. Returns the ball's planar speed after the
## control decision (callers use it to detect reception completion).
func physics_tick(ball: BallController, host: Node3D,
		config: BallActionConfig) -> float:
	if ball == null or not is_instance_valid(ball) or config == null:
		return 0.0

	var vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
	var speed := vel.length()
	if speed < 0.05:
		return speed

	# Exponential damping through a capped force: F = m · a with a = −k·v.
	var force := vel * -config.reception_damping * ball.mass

	# Gentle pull toward the host's feet (planar) so receptions end at the
	# player rather than a metre to the side.
	var offset := host.global_position - ball.global_position
	var to_host := Vector3(offset.x, 0.0, offset.z)
	if to_host.length() > 0.25:
		force += to_host.normalized() * config.reception_pull

	force = force.limit_length(config.reception_max_force)
	ball.sleeping = false  # apply_force does not wake a sleeping ball
	ball.apply_force(force)
	return Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).length()
