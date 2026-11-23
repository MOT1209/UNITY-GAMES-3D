class_name ShieldingSystem
extends Node

## Ball shielding / protection (Phase 2 advanced mechanics). Mounted by `FootballActions`; ticked while the `shield`
## action is held (human) or the AI asks for it, and the ball is close.
##
## Physics only, like the dribble: the ball is kept on the far side of the body from the nearest opponent by a capped
## per-tick spring force (`apply_force`), never attached; the body turns its back / side to the opponent
## (`PlayerController.facing_override`) and moves at SHIELD_SPEED of its pace (`speed_cap`). Moving the stick carries the
## shielded ball along (a turn while protecting it). Near a line, `let_run` stops touching the ball: the player only
## keeps his body between the opponent and a ball that is running out of play.
##
## `protection()` (0..1) says how well the ball is covered right now: body orientation (back or side to the opponent),
## the ball on the far side, and strength / balance. The tackle rules and the physical-duel contest read it.

const SHIELD_SPEED := 0.55
const RANGE := 1.45
const MAX_HEIGHT := 0.6
## Distance (m) of the ball's spot behind the body, away from the opponent.
const SPOT_DISTANCE := 0.55
const SPRING := 9.0
const DAMP := 4.0
const MAX_FORCE := 15.0

var _active := false
var _protection := 0.0
var _player: PlayerController


func is_active() -> bool:
	return _active


func protection() -> float:
	return _protection if _active else 0.0


## One shielding step. Returns true while the ball is within shielding range. `threat` = nearest opponent (world,
## INF = none), `carry` = planar movement direction (ZERO = standing).
func physics_tick(ball: BallController, host: PlayerController, threat: Vector3, carry: Vector3,
		mods: AttributeModifiers, let_run: bool = false) -> bool:
	_player = host
	if ball == null or not is_instance_valid(ball) or host == null:
		release()
		return false
	var offset := ball.global_position - host.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	if planar.length() > RANGE or offset.y > MAX_HEIGHT:
		release()
		return false
	_active = true
	var away := Vector3.ZERO
	if threat != Vector3.INF:
		away = host.global_position - threat
		away.y = 0.0
	if away.length_squared() < 0.01:
		away = -host.global_transform.basis.z
		away.y = 0.0
	away = away.normalized()
	host.speed_cap = SHIELD_SPEED
	host.facing_override = away
	if not let_run:
		var spot := host.global_position + away * SPOT_DISTANCE
		# A ball still on the opponent's side is rolled round the body (via the side it is on), not pulled through it.
		var to_ball := Vector3(offset.x, 0.0, offset.z)
		if to_ball.length_squared() > 0.0001 and to_ball.normalized().dot(away) < 0.2:
			var side := away.cross(Vector3.UP)
			var s := signf(to_ball.dot(side))
			if s == 0.0:
				s = 1.0
			spot = host.global_position + (side * s * 0.6 + away * 0.4)      # its own dot is ~0.55: it hands over to the back spot
		var c := Vector3(carry.x, 0.0, carry.z)
		if c.length_squared() > 0.01:
			spot += c.normalized() * 0.3
		var err := Vector3(spot.x - ball.global_position.x, 0.0, spot.z - ball.global_position.z)
		var vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		var hv := Vector3(host.velocity.x, 0.0, host.velocity.z)
		var force := (err * SPRING - (vel - hv) * DAMP) * ball.mass / 0.43
		force = force.limit_length(MAX_FORCE)
		ball.sleeping = false
		ball.apply_force(force)
	_protection = cover(host, ball.global_position, threat, mods)
	return true


## Ends shielding: the body faces its movement again at full pace.
func release() -> void:
	if _active and _player != null and is_instance_valid(_player):
		_player.speed_cap = 1.0
		_player.facing_override = Vector3.ZERO
	_active = false
	_protection = 0.0


## How well `host` covers a ball at `ball_pos` from an opponent at `threat` (0..1). Pure, for tests and the rules:
## ball on the far side (0.45), body facing away / side-on (0.25), strength + balance (0.3).
static func cover(host: Node3D, ball_pos: Vector3, threat: Vector3, mods: AttributeModifiers) -> float:
	if threat == Vector3.INF:
		return 1.0
	var away := host.global_position - threat
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return 0.0
	away = away.normalized()
	var to_ball := ball_pos - host.global_position
	to_ball.y = 0.0
	var far_side := clampf(to_ball.normalized().dot(away), 0.0, 1.0) if to_ball.length_squared() > 0.0001 else 0.5
	var facing := -host.global_transform.basis.z
	facing.y = 0.0
	var body := clampf(facing.normalized().dot(away) * 0.5 + 0.5, 0.0, 1.0) if facing.length_squared() > 0.0001 else 0.5
	var phys := 0.5
	if mods != null:
		phys = mods.detail("strength") * 0.65 + mods.detail("balance") * 0.35
	return clampf(far_side * 0.45 + body * 0.25 + phys * 0.3, 0.0, 1.0)
