class_name TeamGoalkeeper
extends TeamPlayer

## Goalkeeper AI: guards the line, reads shots, dives, catches and throws the
## ball back out.
##
## Adapted to the project's ball contract (Phase 3 / 4):
##   - the ball is found through the `BallController.BALL_GROUP` group, so the
##     keeper works with the real match ball,
##   - a caught ball is HELD with forces only — it is never frozen, never
##     teleported and its velocity is never written; the hands absorb it with
##     one mass-scaled impulse and a spring keeps it there,
##   - a release is a normal `apply_kick()` impulse.
##
## States: GUARD → DIVE / HOLD → RECOVER.

signal dived(side: int)
signal ball_caught
signal ball_released

enum State { GUARD, DIVE, HOLD, RECOVER }

## Half of the goal width the keeper stays inside (m).
@export var goal_half_width := 3.66
## How far in front of the goal line the keeper stands at rest (m). The goal
## structure itself reaches ~2 m in front of the line, so the keeper has to
## stay clear of it.
@export var guard_depth := 2.6
## Walking speed of the keeper (m/s).
@export var move_speed := 5.5
## Maximum dive length (m).
@export var dive_distance := 2.6
## Faster balls are parried by the physics instead of being caught.
@export var catch_speed_limit := 22.0
## How long the keeper holds the ball before throwing it out (s).
@export var hold_time := 1.0
## Speed of the throw (m/s).
@export var throw_speed := 15.0
## Catching reach around the keeper (m).
@export var catch_reach := 0.8
## Ball height above the ground that counts as a high catch (m).
@export var catch_high_height := 1.3
## Hold spring: pull toward the hands (N per metre) and damping (N per m/s).
@export var hold_pull := 40.0
@export var hold_damping := 8.0
@export var hold_max_force := 40.0
## Where the hands are, relative to the keeper.
@export var hold_height := 1.0
@export var hold_forward := 0.55

var state := State.GUARD
var ball: BallController
var _timer := 0.0
var _dive_from := Vector3.ZERO
var _dive_to := Vector3.ZERO
var _dive_t := 0.0
var _react_cooldown := 0.0
var gk_visual: GoalkeeperVisual


func _ready() -> void:
	gk_visual = visual as GoalkeeperVisual
	if gk_visual != null:
		gk_visual.action_finished.connect(_on_action_finished)


## +1 when the keeper's own goal is at +Z, -1 when it is at -Z.
func _goal_sign() -> float:
	if is_zero_approx(home.z):
		return 1.0
	return signf(home.z)


func _physics_process(delta: float) -> void:
	_find_ball()
	if ball == null:
		return
	_react_cooldown = maxf(0.0, _react_cooldown - delta)
	match state:
		State.GUARD:
			_guard(delta)
		State.DIVE:
			_dive_step(delta)
		State.HOLD:
			_hold(delta)
		State.RECOVER:
			pass


## Caches the match ball (the project's `BallController`, group
## `football_ball`).
func _find_ball() -> void:
	if ball != null and is_instance_valid(ball):
		return
	var found := get_tree().get_nodes_in_group(&"football_ball")
	ball = found[0] as BallController if found.size() > 0 else null


# --- GUARD --------------------------------------------------------------------

func _guard(delta: float) -> void:
	var gs := _goal_sign()
	var goal_z := gs * FootballPitch.PITCH_LENGTH * 0.5
	var bp := ball.global_position
	# The closer the ball is to the goal, the further the keeper comes out.
	var closeness := clampf(1.0 - absf(bp.z - goal_z) / (FootballPitch.PITCH_LENGTH * 0.5),
			0.0, 1.0)
	var tx := clampf(bp.x * 0.22, -goal_half_width + 0.5, goal_half_width - 0.5)
	var tz := goal_z - gs * (guard_depth + closeness * 2.5)
	var to := Vector3(tx, 0.0, tz) - position
	to.y = 0.0
	velocity = Vector3.ZERO
	if to.length() > 0.05:
		velocity = to.normalized() * move_speed
		move_and_slide()
	if gk_visual != null:
		gk_visual.set_speed(velocity.length())

	# Face the ball (smoothly — a dive must not snap the body around).
	var look := bp - global_position
	look.y = 0.0
	if look.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), 1.0 - exp(-8.0 * delta))

	_check_catch()
	_read_shot()


## Reads the shot and decides whether to dive.
func _read_shot() -> void:
	if _react_cooldown > 0.0:
		return
	var gs := _goal_sign()
	var v := ball.linear_velocity
	if v.z * gs < 7.0:
		return          # not a shot towards this goal
	var plane_z := position.z
	var t := (plane_z - ball.global_position.z) / v.z
	if t < 0.03 or t > 1.1:
		return          # too late or too far away to react
	var px := ball.global_position.x + v.x * t
	var py := ball.global_position.y + v.y * t - 0.5 * 9.8 * t * t
	py = maxf(py, 0.11)    # the ball rolls / bounces on the grass instead of sinking
	if absf(px) > goal_half_width + 1.0 or py > 2.7:
		return          # wide or over the bar
	_react_cooldown = 1.2
	var dx := px - position.x
	if absf(dx) < 0.55:
		return          # straight at the keeper: stand and block
	var dist := clampf(dx, -dive_distance, dive_distance)
	_start_dive(signf(dx), dist, clampf(t, 0.25, 0.6), px, plane_z)


## Starts the dive towards the predicted intercept point.
##
## The keeper dives ALONG his line (sideways), which is what a real keeper
## does: the shot is read where it crosses his plane, and he moves sideways
## to meet it there. He never lunges forward into his own goal.
func _start_dive(dir_world_x: float, dist: float, dur: float,
		target_x: float, target_z: float) -> void:
	state = State.DIVE
	_dive_from = position
	var dx := clampf(target_x - position.x, -dive_distance, dive_distance)
	_dive_to = position + Vector3(dx, 0.0, 0.0)
	_dive_t = 0.0
	_timer = dur
	# The keeper's right is +X when facing -Z (goal at +Z).
	var keeper_right := dir_world_x * (1.0 if _goal_sign() > 0.0 else -1.0)
	var side := 1 if keeper_right > 0.0 else -1
	if gk_visual != null:
		gk_visual.dive(side)
	dived.emit(side)


func _dive_step(delta: float) -> void:
	_dive_t += delta
	var k := clampf(_dive_t / _timer, 0.0, 1.0)
	position = _dive_from.lerp(_dive_to, 1.0 - pow(1.0 - k, 2.0))
	_check_catch()
	if state == State.DIVE and gk_visual != null and not gk_visual.is_acting():
		state = State.GUARD


# --- Catching & holding -------------------------------------------------------

func _check_catch() -> void:
	if ball == null or state == State.HOLD:
		return
	var d := ball.global_position - global_position
	if Vector2(d.x, d.z).length() > catch_reach or d.y > 2.2:
		return
	if ball.linear_velocity.length() > catch_speed_limit:
		return          # too fast to hold — the physics parries it
	var v := ball.linear_velocity
	if v.length() > 0.5 and v.z * _goal_sign() <= 0.0:
		return          # travelling away from this goal: not ours to catch
	_catch(ball.global_position.y)


## Puts the ball into the keeper's hands. The ball keeps simulating — it is
## only slowed down by forces, never frozen and never moved by script.
func _catch(by: float) -> void:
	state = State.HOLD
	_timer = hold_time
	# The hands absorb the ball: one mass-scaled impulse cancels its motion
	# (a physical impulse, not a velocity write).
	ball.apply_impulse(-ball.linear_velocity * ball.mass)
	if gk_visual != null:
		if by > catch_high_height:
			gk_visual.catch_high()
		else:
			gk_visual.catch_low()
	ball_caught.emit()


## Holds the ball at the hands with a spring + damper.
func _hold(delta: float) -> void:
	var hands := global_position + Vector3.UP * hold_height \
		+ (-global_transform.basis.z) * hold_forward
	var to_hands := hands - ball.global_position
	var force := to_hands * hold_pull - ball.linear_velocity * hold_damping
	force = force.limit_length(hold_max_force)
	ball.sleeping = false
	ball.apply_force(force)
	_timer -= delta
	if _timer <= 0.0:
		_release()


## Throws the ball back into play.
func _release() -> void:
	if gk_visual != null:
		gk_visual.throw_ball()
	state = State.RECOVER
	_react_cooldown = 1.5
	var out := Vector3(0.35 * signf(-global_position.x), 0.0, -_goal_sign()).normalized()
	ball.apply_kick(out, throw_speed, 3.0)
	ball_released.emit()


func _on_action_finished() -> void:
	if state == State.RECOVER:
		state = State.GUARD
