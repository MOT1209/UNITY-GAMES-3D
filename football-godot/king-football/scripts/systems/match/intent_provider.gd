class_name IntentProvider
extends RefCounted

## Source of a player's control intent (Phase T11). The default (raw) instance
## reads the global `Input` exactly like Phases 2–4 did, so human control is
## unchanged. `AIIntent` replaces it for computer-controlled players.
## A `driven` provider (set_driven(true)) is fed programmatically — by a touch
## UI or a remote controller (KING CONTROLLER) — through the same
## press()/release()/set_move() API `AIIntent` uses, so gameplay code never
## needs to know where the input came from. The driver owns the edge timing:
## call begin_tick() once per tick before applying new state (same contract as
## AIIntent), typically once per _process frame that applies fresh input.
## `world_space` = true means `move_vector()` is already a world XZ direction
## (no camera transform): used by AI. A world-space provider also READS its own
## stored state (move / pressed actions) instead of the global `Input` — the AI
## scripts it like a player, so the shared player scripts can treat both the
## human and the AI the same way.

var world_space: bool = false
var driven: bool = false

var move: Vector2 = Vector2.ZERO
## Explicit kick aim (Phase M1), in the same space as `move`. While it is non-zero `FootballActions` kicks along it,
## so a player can stand still (plant his foot) while charging and still kick where he aimed. ZERO = use `move`.
var aim: Vector2 = Vector2.ZERO
## Kick power override in m/s (Phase M1; 0 = use the charged power). The AI sets the power a pass needs for its length
## directly instead of holding the button for it — the long wind-up was where pressing opponents won the ball.
var kick_power: float = 0.0
## Phase 2: a skill move asked for by the AI (or a remote driver): the move id (`SkillMoveCatalog`) and its exit side
## (+1 right / -1 left of the player, 0 = pick). `FootballActions` consumes it on the next tick. &"" = none.
## Humans use the `skill_move` action instead.
var skill_request: StringName = &""
var skill_side: float = 0.0
## Phase 2: the shooting technique of the next shot (`ShotTechnique`), set by the AI. &"" = read the human modifiers
## (`skill_move` / `shield` held when the shot is released).
var shot_technique: StringName = &""
var _held: Dictionary = {}
var _pressed_edge: Dictionary = {}
var _released_edge: Dictionary = {}


func move_vector() -> Vector2:
	if driven or world_space:
		return move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func is_pressed(action: StringName) -> bool:
	if driven or world_space:
		return _held.get(action, false)
	return Input.is_action_pressed(action)


func just_pressed(action: StringName) -> bool:
	if driven or world_space:
		return _pressed_edge.get(action, false)
	return Input.is_action_just_pressed(action)


func just_released(action: StringName) -> bool:
	if driven or world_space:
		return _released_edge.get(action, false)
	return Input.is_action_just_released(action)


# --- driven mode feeding (mirrors the AIIntent API) ----------------------------------

func set_driven(value: bool) -> void:
	driven = value
	if not value:
		release_all()
		move = Vector2.ZERO
		aim = Vector2.ZERO
		kick_power = 0.0
		skill_request = &""
		shot_technique = &""


func begin_tick() -> void:
	_pressed_edge.clear()
	_released_edge.clear()


## Camera-space movement request for a driven provider (length is clamped to 1).
func set_move(direction: Vector2) -> void:
	move = direction.limit_length(1.0)


func set_aim(direction: Vector2) -> void:
	aim = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO


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
