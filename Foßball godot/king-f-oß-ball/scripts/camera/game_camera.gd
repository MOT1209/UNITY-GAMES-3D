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

var _warned_no_target := false


func _ready() -> void:
	if config == null:
		config = CameraConfig.new()
	_apply_mode()


func _process(delta: float) -> void:
	match mode:
		Mode.BROADCAST:
			_update_broadcast()
		Mode.FOLLOW:
			_update_follow(delta)


## Toggles between BROADCAST and FOLLOW. Clean external interface.
func switch_mode() -> void:
	set_mode(Mode.FOLLOW if mode == Mode.BROADCAST else Mode.BROADCAST)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode


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
