class_name IntentProvider
extends RefCounted

## Source of a player's control intent (Phase T11). The default instance reads
## the global `Input` exactly like Phases 2–4 did, so human control is
## unchanged. `AIIntent` replaces it for computer-controlled players.
## `world_space` = true means `move_vector()` is already a world XZ direction
## (no camera transform): used by AI.

var world_space: bool = false


func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func is_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)


func just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)


func just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)
