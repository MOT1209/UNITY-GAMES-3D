class_name PlayerController
extends CharacterBody3D

## Reusable football player controller (Phase 2).
##
## Responsibilities, kept deliberately small:
##   - 8-direction movement via InputMap actions (digital normalized, analog
##     magnitude preserved).
##   - Camera-relative movement with a world-axis fallback when no camera
##     exists in the viewport.
##   - Acceleration / deceleration + a sprint system (no stamina — later phase).
##   - Smoothed yaw rotation toward the movement direction, last facing kept
##     while idle.
##   - Lightweight IDLE / MOVING / SPRINTING state machine with clean signals.
##
## Deliberately NOT implemented here: passing, shooting, dribbling (see
## `FootballActions`), tackling, team/AI logic (see `scripts/systems/match/`).
## Control comes from `intent` (default: the global Input; AI players use an
## `AIIntent`) and speed/acceleration can be scaled by `attribute_modifiers`.

signal movement_state_changed(new_state: MovementState)
## Emitted when the measured horizontal speed changes by more than
## [member SPEED_SIGNAL_DELTA] m/s since the last emission — meaningful
## changes only, not every physics frame.
signal speed_changed(speed: float)
## Emitted when the facing *target* direction rotates by more than ~15°.
signal facing_direction_changed(direction: Vector3)

enum MovementState { IDLE, MOVING, SPRINTING }

const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_MOVE_FORWARD := "move_forward"
const ACTION_MOVE_BACKWARD := "move_backward"
const ACTION_SPRINT := "sprint"

## Below this horizontal speed (m/s) the player counts as stopped (IDLE).
const IDLE_SPEED_EPSILON := 0.35
## Δm/s threshold above which `speed_changed` fires again.
const SPEED_SIGNAL_DELTA := 0.25
## Δangle threshold (radians) above which `facing_direction_changed` fires.
const FACING_SIGNAL_DELTA := 0.26  # ≈ 15°
## Squared-length epsilon for treating a flattened direction as degenerate.
const DEGENERATE_DIR_EPSILON := 0.0004
const SHARP_TURN_DEGREES := 45.0
const SHARP_TURN_SPEED := 0.45

@export var config: PlayerConfig

## Current discrete movement state; future animation systems read this.
var movement_state: MovementState = MovementState.IDLE

var _horizontal_velocity := Vector3.ZERO
var _vertical_velocity := 0.0
var _last_signal_speed := 0.0
var _last_signal_facing := Vector3.ZERO
var _has_facing := false


## Optional per-player attribute modifiers (Phase T2). Null = Phase 2 defaults.
var attribute_modifiers: AttributeModifiers = null

## Control source (Phase T11). Default reads the global Input (unchanged
## behaviour); AI players get an `AIIntent`.
var intent: IntentProvider = IntentProvider.new()

## Set by `FootballActions` while the ball is at the player's feet (dribbling): he turns slower with it (Phase M4).
var with_ball := false

# --- Phase 2 advanced mechanics: short, bounded body effects (all inactive by default) ----------------------------
## Skill-move body motion: while `_override_left` > 0 the horizontal target velocity is `_override_vel` (world) instead
## of the stick, reached with `_override_accel` x the normal acceleration. Never a position change.
var _override_vel := Vector3.ZERO
var _override_left := 0.0
var _override_accel := 1.0
## Balance loss after contact (physical duels, a lost shoulder challenge): top speed x `_balance_mult` while it lasts.
var _balance_left := 0.0
var _balance_mult := 1.0
## Shielding / protecting the ball: top speed x this (1.0 = off).
var speed_cap := 1.0
## Facing request (world, planar) that wins over the movement direction while set: shielding turns the back to the
## opponent. ZERO = face the movement as before.
var facing_override := Vector3.ZERO
var _jump_request := 0.0
## Largest planar velocity change a contact nudge may add (m/s): physical contact never launches a player.
const MAX_NUDGE := 2.0


func _ready() -> void:
	if config == null:
		config = PlayerConfig.new()
	_apply_physics_params()


## Runs every fixed physics tick. Separates the horizontal planar velocity
## from the vertical (gravity) component before move_and_slide().
func _physics_process(delta: float) -> void:
	var input := intent.move_vector()
	var world_dir := _input_to_world_dir(input)

	# Target velocity keeps the input magnitude (≤ 1) — analog sticks keep
	# partial speed, keyboard is normalized by Input.get_vector().
	var target_velocity := world_dir * _resolve_max_speed(input) * speed_cap
	# Phase M3: a sharp turn with the ball at the feet slows the player down (the ball has to come round with him).
	if with_ball and world_dir != Vector3.ZERO and _horizontal_velocity.length() > 1.0 \
			and rad_to_deg(_horizontal_velocity.angle_to(world_dir)) > SHARP_TURN_DEGREES:
		target_velocity *= SHARP_TURN_SPEED
	var rate := config.acceleration if world_dir != Vector3.ZERO else config.deceleration
	if attribute_modifiers != null and world_dir != Vector3.ZERO:
		rate *= attribute_modifiers.acceleration_multiplier()
	if _override_left > 0.0:
		_override_left -= delta
		target_velocity = _override_vel
		rate = config.acceleration * _override_accel
	if _balance_left > 0.0:
		_balance_left -= delta
		target_velocity *= _balance_mult
	_horizontal_velocity = _horizontal_velocity.move_toward(target_velocity, rate * delta)

	_apply_gravity(delta, world_dir != Vector3.ZERO)
	if _jump_request > 0.0:
		if is_on_floor():
			_vertical_velocity = _jump_request
		_jump_request = 0.0
	velocity = _horizontal_velocity + Vector3(0.0, _vertical_velocity, 0.0)
	move_and_slide()

	_update_facing(facing_override if facing_override != Vector3.ZERO else world_dir, delta)
	_update_state()
	_report_speed()


## Current planar speed in m/s (useful for HUD/tests/future animation).
func get_current_speed() -> float:
	return _horizontal_velocity.length()


func get_state_name() -> String:
	match movement_state:
		MovementState.IDLE:
			return "IDLE"
		MovementState.MOVING:
			return "MOVING"
		MovementState.SPRINTING:
			return "SPRINTING"
	return "UNKNOWN"


# --- Phase 2 body effects (skill moves, contact, jumps) ----------------------------------------------------------

## Drives the body at `world_velocity` (planar) for `duration` s, accelerating `accel_mult` x as hard as normal.
## Used by skill moves (a side-step, a stop, a burst out of a feint). The stick takes over again afterwards.
func set_motion_override(world_velocity: Vector3, duration: float, accel_mult: float = 1.0) -> void:
	_override_vel = Vector3(world_velocity.x, 0.0, world_velocity.z)
	_override_left = maxf(duration, 0.0)
	_override_accel = clampf(accel_mult, 0.2, 3.0)


func clear_motion_override() -> void:
	_override_left = 0.0


func has_motion_override() -> bool:
	return _override_left > 0.0


## Contact nudge: adds a planar velocity change of at most MAX_NUDGE m/s (a shoulder, a lost duel).
func nudge(world_dv: Vector3) -> void:
	var dv := Vector3(world_dv.x, 0.0, world_dv.z).limit_length(MAX_NUDGE)
	_horizontal_velocity += dv


## Off balance for `duration` s: top speed x `mult` (0.3..1).
func lose_balance(duration: float, mult: float) -> void:
	_balance_left = maxf(_balance_left, duration)
	_balance_mult = clampf(mult, 0.3, 1.0)


func is_off_balance() -> bool:
	return _balance_left > 0.0


## Jumps with take-off speed `v0` m/s (applied next tick, only from the ground). Reach = v0^2 / 2g.
func jump(v0: float) -> void:
	_jump_request = clampf(v0, 0.0, 5.5)          # 5.5 m/s at 18 m/s2 gravity = 0.84 m, above any real jump


## Height of the body above the ground (m): 0 standing, > 0 in a jump.
func get_jump_height() -> float:
	return maxf(global_position.y - _ground_y, 0.0) if not is_on_floor() else 0.0


var _ground_y := 0.0


# --- Movement core -------------------------------------------------------

## Maps the 2D action vector into a world-space horizontal direction:
##   • WORLD reference  → forward is −Z, right is +X.
##   • CAMERA_RELATIVE  → forward/right follow the active camera's basis,
##     flattened onto the ground plane (vertical pitch ignored so movement
##     never gains vertical velocity from the camera angle).
## No camera (or a completely vertical one) falls back to world axes.
func _input_to_world_dir(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	if intent.world_space:
		return Vector3(input.x, 0.0, input.y)
	if config.movement_reference == PlayerConfig.MovementReference.CAMERA_RELATIVE:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var cam_dir := _camera_relative_dir(input, camera)
			if cam_dir.length_squared() > 0.0:
				return cam_dir
			# Fully vertical camera basis — degenerate, use world fallback.
	return _world_relative_dir(input)


func _camera_relative_dir(input: Vector2, camera: Camera3D) -> Vector3:
	# Godot stores axis directions in basis rows-as-columns: basis.x = right,
	# basis.z = backward. Property access avoids Basis method-call variance.
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < DEGENERATE_DIR_EPSILON \
			or right.length_squared() < DEGENERATE_DIR_EPSILON:
		return Vector3.ZERO
	forward = forward.normalized()
	right = right.normalized()
	# input.y = −1 when pressing up/forward → add +forward (dot maps it back).
	return right * input.x - forward * input.y


func _world_relative_dir(input: Vector2) -> Vector3:
	return Vector3(input.x, 0.0, input.y)


## True max speed for this tick: sprint while the action is held and there is
## movement intent, otherwise the normal run speed.
func _resolve_max_speed(input: Vector2) -> float:
	if config.sprint_enabled and input != Vector2.ZERO \
			and intent.is_pressed(ACTION_SPRINT):
		return config.sprint_speed * _speed_mult()
	return config.normal_speed * _speed_mult()


func _speed_mult() -> float:
	return attribute_modifiers.speed_multiplier() if attribute_modifiers != null else 1.0


func _apply_gravity(delta: float, moving_intent: bool) -> void:
	if is_on_floor():
		_ground_y = global_position.y
		# Small downward bias keeps floor contact stable over seams and
		# grass details; imperceptible as "sinking".
		_vertical_velocity = -config.grounded_downward_bias
	else:
		_vertical_velocity = maxf(
			_vertical_velocity - config.gravity * delta,
			-config.max_fall_speed
		)


# --- Facing / rotation ----------------------------------------------------

## Smoothly rotates the whole body (root) toward the movement direction so the
## character's logical -Z forward stays consistent; any model-specific offset
## belongs inside VisualRoot. Idle keeps the last facing.
func _update_facing(world_dir: Vector3, delta: float) -> void:
	if world_dir != Vector3.ZERO:
		# Emit once per meaningful change of the directional intent (~15°),
		# not per frame — matches the "meaningful changes only" requirement.
		if not _has_facing or absf(_last_signal_facing.normalized().dot(
				world_dir.normalized()) - 1.0) > FACING_SIGNAL_DELTA * 0.5:
			_last_signal_facing = world_dir
			_has_facing = true
			facing_direction_changed.emit(_last_signal_facing)
		var target_yaw := atan2(-world_dir.x, -world_dir.z)
		var t := 1.0 - exp(-config.rotation_speed * delta)
		var step := angle_difference(rotation.y, target_yaw) * t
		var cap := deg_to_rad(config.max_turn_rate_degrees) * delta * (config.dribble_turn_factor if with_ball else 1.0)
		rotation.y += clampf(step, -cap, cap)


# --- States / signals -------------------------------------------------------

func _update_state() -> void:
	var speed := get_current_speed()
	var new_state := MovementState.MOVING
	if speed < IDLE_SPEED_EPSILON:
		new_state = MovementState.IDLE
	elif config.sprint_enabled and intent.is_pressed(ACTION_SPRINT):
		new_state = MovementState.SPRINTING
	if new_state != movement_state:
		movement_state = new_state
		movement_state_changed.emit(new_state)


func _report_speed() -> void:
	var speed := get_current_speed()
	# Only re-emit after a meaningful step so animation systems don't drown.
	if absf(speed - _last_signal_speed) >= SPEED_SIGNAL_DELTA:
		_last_signal_speed = speed
		speed_changed.emit(speed)


# --- Setup helpers -----------------------------------------------------------

func _apply_physics_params() -> void:
	floor_snap_length = config.floor_snap_length
	floor_max_angle = deg_to_rad(config.floor_max_angle_degrees)
	# Prevent the physics body from sliding sideways on slopes forever.
	wall_min_slide_angle = 0.0
