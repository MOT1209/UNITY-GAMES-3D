class_name AIIntent
extends IntentProvider

## Scripted intent used by player AI. The AI sets `move` and calls `press()` /
## `release()`; the shared player scripts read it like real input.
## `begin_tick()` clears one-shot edges (call once per physics tick, before
## setting new intent).

var move: Vector2 = Vector2.ZERO
var _held: Dictionary = {}
var _pressed_edge: Dictionary = {}
var _released_edge: Dictionary = {}


func _init() -> void:
	world_space = true


func begin_tick() -> void:
	_pressed_edge.clear()
	_released_edge.clear()


func set_move_world(direction: Vector3) -> void:
	var flat := Vector2(direction.x, direction.z)
	move = flat.limit_length(1.0)


func press(action: StringName) -> void:
	if not _held.get(action, false):
		_held[action] = true
		_pressed_edge[action] = true


func release(action: StringName) -> void:
	if _held.get(action, false):
		_held[action] = false
		_released_edge[action] = true


func release_all() -> void:
	for a in _held.keys():
		release(a)
	move = Vector2.ZERO


func move_vector() -> Vector2:
	return move


func is_pressed(action: StringName) -> bool:
	return _held.get(action, false)


func just_pressed(action: StringName) -> bool:
	return _pressed_edge.get(action, false)


func just_released(action: StringName) -> bool:
	return _released_edge.get(action, false)
