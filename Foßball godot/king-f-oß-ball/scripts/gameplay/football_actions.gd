class_name FootballActions
extends Node3D

## Central player↔ball interaction layer and action-state machine (Phase 4,
## plan §5/§13). Mounted as `BallActions` under the player with a
## `BallDetector` (`BallProximityDetector`) child.
##
## Responsibilities:
##   - The plan §5 reusable queries: `can_interact_with_ball()`,
##     `get_ball_relative_position()`, `get_ball_distance()`,
##     `get_kick_direction()`, `get_action_availability()`.
##   - Input integration for the existing InputMap actions
##     `pass` / `shoot` / `lob_pass` / `dribble` (movement actions untouched).
##   - Kick-power charging (one `KickPowerController` per kick action).
##   - A lightweight, derived action-state machine
##     (IDLE/RECEIVING/PASSING/SHOOTING/LOB_PASSING/DRIBBLING). States are
##     computed from small flags each tick — a locked-up state is impossible.
##   - Delegating the actual physics to the subsystem nodes it creates:
##     PassingSystem, ShootingSystem, LobPassSystem, DribblingSystem,
##     BallControlSystem.
##
## Hard rules (plan §5/§17): the ball is never attached or teleported, every
## kick goes through the Phase 3 `BallController.apply_kick()` API, dribble and
## reception control are per-tick capped `apply_force()` pushes, and gameplay
## works independently of animation availability.

signal action_state_changed(new_state: ActionState)
signal charge_changed(action: StringName, ratio: float)
signal pass_started(power: float)
signal pass_completed
signal shot_started(power: float, lift: float)
signal shot_completed
signal lob_started(power: float, lift: float)
signal dribble_started
signal dribble_stopped
signal ball_received(ball_speed: float)

enum ActionState { IDLE, RECEIVING, PASSING, SHOOTING, LOB_PASSING, DRIBBLING }

const ACTION_PASS := "pass"
const ACTION_SHOOT := "shoot"
const ACTION_LOB := "lob_pass"
const ACTION_DRIBBLE := "dribble"
const ACTION_SPRINT := "sprint"
## Squared-length epsilon for degenerate directions (matches Phase 2 style).
const DEGENERATE_DIR_EPSILON := 0.0004

@export var config: BallActionConfig

## Current derived action state (separate from the player's movement state).
var action_state: ActionState = ActionState.IDLE

@onready var ball_detector: BallProximityDetector = $BallDetector

var _player: PlayerController
var _pass_system: PassingSystem
var _shoot_system: ShootingSystem
var _lob_system: LobPassSystem
var _dribble_system: DribblingSystem
var _control_system: BallControlSystem
var _pass_charge: KickPowerController
var _shoot_charge: KickPowerController
var _lob_charge: KickPowerController

var _pass_cooldown := 0.0
var _shoot_cooldown := 0.0
var _lob_cooldown := 0.0
var _state_hold := 0.0
var _transient_state: ActionState = ActionState.IDLE
var _receiving := false
var _dribbling := false
var _last_aim := Vector3.ZERO
var _charge_ratios := {
	&"pass": 0.0,
	&"shoot": 0.0,
	&"lob": 0.0,
}
## (action, controller) pairs for the per-tick charge loop — built once in
## `_build_subsystems()` so `_physics_process` allocates nothing per tick.
var _charge_pairs: Array = []


func _ready() -> void:
	if config == null:
		config = BallActionConfig.new()
	_player = get_parent() as PlayerController
	_build_subsystems()


func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_reception(delta)
	_handle_kick_input(delta)
	_update_dribbling(delta)
	_update_state_hold(delta)
	_update_action_state()


# --- Plan §5 reusable queries ------------------------------------------------

## True when a clean interaction window exists right now (distance + height +
## ball tracked). The single "can trap / kick / shoot?" boolean.
func can_interact_with_ball() -> bool:
	return ball_detector.is_interaction_available()


## Offset from the player's origin to the ball in the player's LOCAL frame
## (+x = right, −z = forward, +y = up). ZERO when no ball is tracked.
func get_ball_relative_position() -> Vector3:
	var ball := get_tracked_ball()
	if ball == null or _player == null:
		return Vector3.ZERO
	var offset := ball.global_position - _player.global_position
	return _player.global_transform.basis.inverse() * offset


## Distance from the player to the tracked ball's centre (0 when none).
func get_ball_distance() -> float:
	return ball_detector.get_distance_to_ball()


## The player's current kick/aim direction (planar): the active movement input
## direction (camera-relative when a camera exists, world axes otherwise) if
## a direction is held, otherwise the last movement intent, otherwise the
## player's current facing. ZERO only in degenerate setups.
func get_kick_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right",
			"move_forward", "move_backward")
	if input != Vector2.ZERO:
		_last_aim = _input_to_world_dir(input)
	if _last_aim != Vector3.ZERO:
		return _last_aim
	if _player != null:
		var facing := -_player.global_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() > DEGENERATE_DIR_EPSILON:
			return facing.normalized()
	return Vector3.ZERO


## Snapshot of what each action can do right now (UI + tests read this).
func get_action_availability() -> Dictionary:
	return {
		&"ball_nearby": ball_detector.is_ball_nearby(),
		&"interact": can_interact_with_ball(),
		&"pass": _can_execute(ACTION_PASS),
		&"shoot": _can_execute(ACTION_SHOOT),
		&"lob": _can_execute(ACTION_LOB),
		&"dribble": get_tracked_ball() != null and _state_hold <= 0.0,
	}


## The currently tracked (nearest) ball, or null.
func get_tracked_ball() -> BallController:
	return ball_detector.get_current_ball() as BallController


func get_action_state_name() -> String:
	match action_state:
		ActionState.IDLE: return "IDLE"
		ActionState.RECEIVING: return "RECEIVING"
		ActionState.PASSING: return "PASSING"
		ActionState.SHOOTING: return "SHOOTING"
		ActionState.LOB_PASSING: return "LOB_PASSING"
		ActionState.DRIBBLING: return "DRIBBLING"
	return "UNKNOWN"


## Charge ratio (0..1) of an action's power controller, for UI.
func get_charge_ratio(action: StringName) -> float:
	return _charge_ratios.get(action, 0.0)


# --- Input & charging ----------------------------------------------------------

func _handle_kick_input(delta: float) -> void:
	# Start charging (mutually exclusive: one kick action at a time).
	var any_charging := _pass_charge.is_charging() or _shoot_charge.is_charging() \
			or _lob_charge.is_charging()
	if not any_charging:
		if Input.is_action_just_pressed(ACTION_PASS) and _can_execute(ACTION_PASS):
			_pass_charge.start()
		elif Input.is_action_just_pressed(ACTION_SHOOT) and _can_execute(ACTION_SHOOT):
			_shoot_charge.start()
		elif Input.is_action_just_pressed(ACTION_LOB) and _can_execute(ACTION_LOB):
			_lob_charge.start()

	# Drive the charge clocks and publish ratios for the UI.
	for pair in _charge_pairs:
		var charge: KickPowerController = pair[1]
		var ratio: float = charge.update(delta)
		_charge_ratios[pair[0]] = ratio
		if charge.is_charging():
			charge_changed.emit(pair[0], ratio)

	# Guard: a charge whose interaction window disappears is cancelled.
	if _pass_charge.is_charging() and not _can_execute(ACTION_PASS):
		_pass_charge.cancel()
		_emit_charge_zero(&"pass")
	if _shoot_charge.is_charging() and not _can_execute(ACTION_SHOOT):
		_shoot_charge.cancel()
		_emit_charge_zero(&"shoot")
	if _lob_charge.is_charging() and not _can_execute(ACTION_LOB):
		_lob_charge.cancel()
		_emit_charge_zero(&"lob")

	# Release executes the action.
	if _pass_charge.is_charging() and Input.is_action_just_released(ACTION_PASS):
		var ratio := _pass_charge.get_ratio()
		_execute_pass(_pass_charge.release(), ratio)
		_emit_charge_zero(&"pass")
	if _shoot_charge.is_charging() and Input.is_action_just_released(ACTION_SHOOT):
		var ratio := _shoot_charge.get_ratio()
		_execute_shot(_shoot_charge.release(), ratio)
		_emit_charge_zero(&"shoot")
	if _lob_charge.is_charging() and Input.is_action_just_released(ACTION_LOB):
		var ratio := _lob_charge.get_ratio()
		_execute_lob(_lob_charge.release(), ratio)
		_emit_charge_zero(&"lob")


## Publishes the final zero ratio after a release or a cancel so signal-driven
## UI bars don't stay stuck at the last charge value.
func _emit_charge_zero(action: StringName) -> void:
	_charge_ratios[action] = 0.0
	charge_changed.emit(action, 0.0)


func _can_execute(action: String) -> bool:
	if _state_hold > 0.0:  # a kick is currently in its transient state
		return false
	match action:
		ACTION_PASS:
			return can_interact_with_ball() and _pass_cooldown <= 0.0
		ACTION_SHOOT:
			return can_interact_with_ball() and _shoot_cooldown <= 0.0
		ACTION_LOB:
			return can_interact_with_ball() and _lob_cooldown <= 0.0
	return false


# --- Kick execution ------------------------------------------------------------

func _execute_pass(power: float, charge_ratio: float) -> void:
	var applied := _pass_system.execute_pass(get_tracked_ball(), get_kick_direction(),
			power, ball_detector.get_direction_to_ball(), config)
	if applied < 0.0:
		return
	_after_kick(ActionState.PASSING, config.pass_cooldown)
	pass_started.emit(applied)
	_play_kick_anim()
	# charge_ratio kept for future power-scaled pass lift/fakes.


func _execute_shot(power: float, charge_ratio: float) -> void:
	var lift := lerpf(config.min_shot_lift, config.max_shot_lift, charge_ratio)
	var applied := _shoot_system.execute_shot(get_tracked_ball(), get_kick_direction(),
			power, charge_ratio, ball_detector.get_direction_to_ball(), config)
	if applied < 0.0:
		return
	_after_kick(ActionState.SHOOTING, config.shoot_cooldown)
	shot_started.emit(applied, lift)
	_play_kick_anim()


func _execute_lob(power: float, charge_ratio: float) -> void:
	var lift := config.lob_lift
	var applied := _lob_system.execute_lob(get_tracked_ball(), get_kick_direction(),
			power, ball_detector.get_direction_to_ball())
	if applied < 0.0:
		return
	_after_kick(ActionState.LOB_PASSING, config.lob_cooldown)
	lob_started.emit(applied, lift)
	_play_kick_anim()


func _after_kick(state: ActionState, cooldown: float) -> void:
	_transient_state = state
	_state_hold = config.state_hold
	# A kick interrupts reception/dribble control immediately.
	_receiving = false
	_set_dribbling(false)
	match state:
		ActionState.PASSING: _pass_cooldown = cooldown
		ActionState.SHOOTING: _shoot_cooldown = cooldown
		ActionState.LOB_PASSING: _lob_cooldown = cooldown


## Animation integration point (plan §14): the character visual already
## reserves `play_kick()`. Gameplay is fully independent of this succeeding.
func _play_kick_anim() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var visual := _player.get_node_or_null("VisualRoot")
	if visual != null and visual.has_method("play_kick"):
		visual.play_kick()


# --- Dribbling -----------------------------------------------------------------

func _update_dribbling(_delta: float) -> void:
	if _state_hold > 0.0 or _receiving \
			or not Input.is_action_pressed(ACTION_DRIBBLE):
		_set_dribbling(false)
		return
	var ball := get_tracked_ball()
	if ball == null:
		_set_dribbling(false)
		return
	# Raw movement input as the carry direction (ZERO when standing still →
	# the dribbling system holds the ball close instead of shoving it along
	# the last aim). `get_kick_direction()` stays kick-only.
	var carry := _input_to_world_dir(Input.get_vector("move_left", "move_right",
			"move_forward", "move_backward"))
	var engaged := _dribble_system.physics_tick(ball, _player, carry,
			_player.get_current_speed() if _player != null else 0.0,
			Input.is_action_pressed(ACTION_SPRINT), config)
	_set_dribbling(engaged)


func _set_dribbling(value: bool) -> void:
	if _dribbling == value:
		return
	_dribbling = value
	if _dribbling:
		dribble_started.emit()
	else:
		dribble_stopped.emit()


# --- Reception -----------------------------------------------------------------

func _update_reception(_delta: float) -> void:
	var ball := get_tracked_ball()
	if ball == null:
		_set_receiving(false)
		return

	if _receiving:
		var speed := _control_system.physics_tick(ball, _player, config)
		var offset := _player.global_position - ball.global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		if speed < config.reception_complete_speed:
			_set_receiving(false)
			ball_received.emit(speed)
		elif planar.length() > config.reception_escape_distance:
			_set_receiving(false)  # ball escaped the control radius
		return

	# Trigger: an approaching ball near the player while no kick is busy.
	if not (action_state == ActionState.IDLE or action_state == ActionState.DRIBBLING):
		return
	var vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
	var speed := vel.length()
	if speed < config.reception_trigger_speed:
		return
	var offset := _player.global_position - ball.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	if planar.length() > config.reception_distance:
		return
	if offset.y > config.max_control_height:
		return
	if vel.normalized().dot(planar.normalized()) <= 0.0:
		return  # moving away from the player
	_set_receiving(true)


func _set_receiving(value: bool) -> void:
	if _receiving == value:
		return
	_receiving = value


# --- State machine (derived each tick — lockup-proof) ----------------------------

func _update_cooldowns(delta: float) -> void:
	_pass_cooldown = maxf(_pass_cooldown - delta, 0.0)
	_shoot_cooldown = maxf(_shoot_cooldown - delta, 0.0)
	_lob_cooldown = maxf(_lob_cooldown - delta, 0.0)


func _update_state_hold(delta: float) -> void:
	if _state_hold <= 0.0:
		return
	_state_hold = maxf(_state_hold - delta, 0.0)
	if _state_hold == 0.0:
		_emit_transient_completed()


func _emit_transient_completed() -> void:
	match _transient_state:
		ActionState.PASSING:
			pass_completed.emit()
		ActionState.SHOOTING:
			shot_completed.emit()
		ActionState.LOB_PASSING:
			pass  # plan §14 defines no lob_completed
		_:
			pass


func _update_action_state() -> void:
	var new_state := ActionState.IDLE
	if _state_hold > 0.0:
		new_state = _transient_state
	elif _receiving:
		new_state = ActionState.RECEIVING
	elif _dribbling:
		new_state = ActionState.DRIBBLING
	if new_state != action_state:
		action_state = new_state
		action_state_changed.emit(new_state)


# --- Aim helper (mirrors the Phase 2 controller's mapping) ----------------------

func _input_to_world_dir(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var basis := camera.global_transform.basis
		var forward := -basis.z
		var right := basis.x
		forward.y = 0.0
		right.y = 0.0
		if forward.length_squared() > DEGENERATE_DIR_EPSILON \
				and right.length_squared() > DEGENERATE_DIR_EPSILON:
			return (right.normalized() * input.x
					- forward.normalized() * input.y)
	# No camera (or fully vertical basis): world axes — forward is −Z.
	return Vector3(input.x, 0.0, input.y)


# --- Setup ---------------------------------------------------------------------

func _build_subsystems() -> void:
	_pass_system = PassingSystem.new()
	_pass_system.name = "PassingSystem"
	_shoot_system = ShootingSystem.new()
	_shoot_system.name = "ShootingSystem"
	_lob_system = LobPassSystem.new()
	_lob_system.name = "LobPassSystem"
	_lob_system.config = config
	_dribble_system = DribblingSystem.new()
	_dribble_system.name = "DribblingSystem"
	_control_system = BallControlSystem.new()
	_control_system.name = "BallControlSystem"
	for node: Node in [_pass_system, _shoot_system, _lob_system, _dribble_system, _control_system]:
		add_child(node)

	_pass_charge = _make_charge(config.min_pass_power, config.max_pass_power,
			config.default_pass_power)
	_pass_charge.name = "PassCharge"
	_shoot_charge = _make_charge(config.min_shoot_power, config.max_shoot_power,
			config.default_shoot_power)
	_shoot_charge.name = "ShootCharge"
	_lob_charge = _make_charge(config.min_lob_power, config.max_lob_power,
			config.default_lob_power)
	_lob_charge.name = "LobCharge"

	_charge_pairs = [[&"pass", _pass_charge], [&"shoot", _shoot_charge],
			[&"lob", _lob_charge]]


func _make_charge(minimum: float, maximum: float, default_power: float) -> KickPowerController:
	var charge := KickPowerController.new()
	charge.min_power = minimum
	charge.max_power = maximum
	charge.default_power = default_power
	charge.charge_time = config.charge_time
	charge.quick_tap_threshold = config.quick_tap_threshold
	add_child(charge)
	return charge
