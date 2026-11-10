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
## Deliberately NOT implemented here: passing, shooting, dribbling, tackling,
## player switching, team/AI logic, stamina. Access points exist (states +
## signals) so later phases can hook in without touching this file's core.

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

@export var config: PlayerConfig

## Current discrete movement state; future animation systems read this.
var movement_state: MovementState = MovementState.IDLE

var _horizontal_velocity := Vector3.ZERO
var _vertical_velocity := 0.0
var _last_signal_speed := 0.0
var _last_signal_facing := Vector3.ZERO
var _has_facing := false


func _ready() -> void:
	if config == null:
		config = PlayerConfig.new()
	_apply_physics_params()


## Runs every fixed physics tick. Separates the horizontal planar velocity
## from the vertical (gravity) component before move_and_slide().
func _physics_process(delta: float) -> void:
	var input := Input.get_vector(ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT,
			ACTION_MOVE_FORWARD, ACTION_MOVE_BACKWARD)
	var world_dir := _input_to_world_dir(input)

	# Target velocity keeps the input magnitude (≤ 1) — analog sticks keep
	# partial speed, keyboard is normalized by Input.get_vector().
	var target_velocity := world_dir * _resolve_max_speed(input)
	var rate := config.acceleration if world_dir != Vector3.ZERO else config.deceleration
	_horizontal_velocity = _horizontal_velocity.move_toward(target_velocity, rate * delta)

	_apply_gravity(delta, world_dir != Vector3.ZERO)
	velocity = _horizontal_velocity + Vector3(0.0, _vertical_velocity, 0.0)
	move_and_slide()

	_update_facing(world_dir, delta)
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
			and Input.is_action_pressed(ACTION_SPRINT):
		return config.sprint_speed
	return config.normal_speed


func _apply_gravity(delta: float, moving_intent: bool) -> void:
	if is_on_floor():
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
		rotation.y = lerp_angle(rotation.y, target_yaw, t)


# --- States / signals -------------------------------------------------------

func _update_state() -> void:
	var speed := get_current_speed()
	var new_state := MovementState.MOVING
	if speed < IDLE_SPEED_EPSILON:
		new_state = MovementState.IDLE
	elif config.sprint_enabled and Input.is_action_pressed(ACTION_SPRINT):
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
