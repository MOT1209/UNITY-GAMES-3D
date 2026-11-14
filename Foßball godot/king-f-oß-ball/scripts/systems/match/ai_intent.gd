class_name AIIntent
extends IntentProvider

## Scripted intent used by player AI. The AI sets `move` and calls `press()` /
## `release()`; the shared player scripts read it like real input.
## `begin_tick()` clears one-shot edges (call once per physics tick, before
## setting new intent) — inherited from `IntentProvider`, which now owns the
## shared state (`move`, `_held`, the edge dictionaries) so that a driven
## provider (touch UI / remote controller) can reuse the very same API.

func _init() -> void:
	world_space = true


func set_move_world(direction: Vector3) -> void:
	var flat := Vector2(direction.x, direction.z)
	move = flat.limit_length(1.0)


## Releases every action AND stops the movement (the base class only clears the
## buttons, because a driven provider may still be steered by the driver).
func release_all() -> void:
	super.release_all()
	move = Vector2.ZERO
