class_name GameCamera
extends Camera3D

## Reusable camera, independent of any specific player or scene.
##
## Two modes:
##   BROADCAST — stable elevated sideline view of the whole pitch.
##   FOLLOW    — smoothly damped follow of `follow_target`, for gameplay.
##
## Behaviour is configured through a CameraConfig Resource (resources/configurations/).
## Mode switching happens through the clean interface `switch_mode()` /
## `set_mode()` — no gameplay logic is embedded here.

signal mode_changed(mode: Mode)

enum Mode { BROADCAST, FOLLOW }

@export var config: CameraConfig
@export var mode: Mode = Mode.BROADCAST:
	set(value):
		if mode == value and is_inside_tree():
			return
		mode = value
		mode_changed.emit(mode)
		if is_inside_tree():
			_apply_mode()
@export var follow_target: Node3D
## Optional ball: broadcast mode then tracks it (see CameraConfig broadcast_track_*).
var tracked_ball: Node3D

var _warned_no_target := false
var _look := Vector3.ZERO
var _look_ready := false


func _ready() -> void:
	if config == null:
		config = CameraConfig.new()
	_apply_mode()


func _process(delta: float) -> void:
	match mode:
		Mode.BROADCAST:
			if is_instance_valid(tracked_ball):
				_update_broadcast_tracking(delta)
			else:
				_update_broadcast()
		Mode.FOLLOW:
			_update_follow(delta)


## Toggles between BROADCAST and FOLLOW. Clean external interface.
func switch_mode() -> void:
	set_mode(Mode.FOLLOW if mode == Mode.BROADCAST else Mode.BROADCAST)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode


## Broadcast mode follows `ball` along the pitch with smoothing and zooms with the play's speed.
func track_ball(ball: Node3D) -> void:
	tracked_ball = ball
	_look_ready = false


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	_warned_no_target = false


func get_mode_name() -> String:
	return "Broadcast" if mode == Mode.BROADCAST else "Dynamic"


func _apply_mode() -> void:
	if config == null:
		return
	match mode:
		Mode.BROADCAST:
			fov = config.broadcast_fov
			global_position = config.broadcast_look_target + config.broadcast_position_offset
			_update_broadcast()
		Mode.FOLLOW:
			fov = config.follow_fov


func _update_broadcast() -> void:
	if config == null:
		return
	# Keep looking at the configured point; position stays stable.
	look_at_from_position(
		config.broadcast_look_target + config.broadcast_position_offset,
		config.broadcast_look_target,
		Vector3.UP
	)


## Broadcast camera that follows the ball: look point = configured target moved to the ball's z and
## a share of its x, exponentially smoothed (no jumps); the camera keeps its configured offset from
## that point, so the angle stays the same. FOV widens with ball speed (smoothed).
func _update_broadcast_tracking(delta: float) -> void:
	if config == null:
		return
	var b := tracked_ball.global_position
	# Phase M6: look a little ahead of the ball along the play (its velocity, at most `broadcast_lead_max` m), so an
	# attack runs into the picture instead of out of it.
	if tracked_ball is RigidBody3D:
		var v := (tracked_ball as RigidBody3D).linear_velocity
		b += Vector3(v.x, 0.0, v.z * 0.6).limit_length(config.broadcast_lead_max / maxf(config.broadcast_lead_time, 0.01)) * config.broadcast_lead_time
	var wanted := config.broadcast_look_target + Vector3(b.x * config.broadcast_track_x_factor, 0.0, b.z)
	if not _look_ready:
		_look = wanted
		_look_ready = true
	var t := 1.0 - exp(-config.broadcast_track_speed * delta)
	_look = _look.lerp(wanted, t)
	look_at_from_position(_look + config.broadcast_position_offset, _look, Vector3.UP)
	var speed := 0.0
	if tracked_ball is RigidBody3D:
		speed = (tracked_ball as RigidBody3D).linear_velocity.length()
	var zoom := clampf(speed / maxf(config.broadcast_zoom_speed, 0.1), 0.0, 1.0)
	var target_fov := lerpf(config.broadcast_fov, config.broadcast_wide_fov, zoom)
	fov = lerpf(fov, target_fov, 1.0 - exp(-1.5 * delta))


func _update_follow(delta: float) -> void:
	if config == null:
		return
	if not is_instance_valid(follow_target):
		if not _warned_no_target:
			_warned_no_target = true
			push_warning("GameCamera: FOLLOW mode needs a follow_target. Falling back to broadcast view.")
		_update_broadcast()
		return

	var target_pos := follow_target.global_position
	var desired := target_pos + Vector3(0.0, config.follow_height, config.follow_distance)
	# Frame-rate independent exponential damping (no snapped camera moves).
	var t := 1.0 - exp(-config.follow_speed * delta)
	global_position = global_position.lerp(desired, t)

	var look_point := target_pos + Vector3(0.0, config.follow_look_height, 0.0)
	if not look_point.is_equal_approx(global_position):
		look_at(look_point, Vector3.UP)
