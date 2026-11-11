class_name PlayerCharacterVisual
extends Node3D

## Drives the real character model's AnimationPlayer from the parent
## `PlayerController`'s state/speed signals. Deliberately decoupled: the
## controller stays visual-agnostic and this node just listens.
##
## Animation mapping (assets/models/characters/player.glb, facing -Z):
##   IDLE      → "Idle"
##   MOVING    → "Walk" below `walk_max_speed`, otherwise "Run"
##   SPRINTING → "Run"
## "Kick" is reserved for Phase 4 — call `play_kick()` from the gameplay layer.

## Planar speed (m/s) at which MOVING switches from Walk to Run.
@export var walk_max_speed: float = 3.2
## Cross-fade time between locomotion clips (s).
@export var anim_fade: float = 0.18

var _anim: AnimationPlayer
var _current_state: PlayerController.MovementState = \
		PlayerController.MovementState.IDLE


func _ready() -> void:
	_anim = _find_anim_player(self)
	var controller := get_parent() as PlayerController
	if controller != null:
		controller.movement_state_changed.connect(_on_state_changed)
		controller.speed_changed.connect(_on_speed_changed)
	if _anim != null:
		_anim.play("Idle")
	else:
		push_warning("PlayerCharacterVisual: no AnimationPlayer found under %s." % name)


func _on_state_changed(new_state: PlayerController.MovementState) -> void:
	_current_state = new_state
	match new_state:
		PlayerController.MovementState.IDLE:
			_play("Idle")
		PlayerController.MovementState.MOVING:
			_play("Walk")  # speed refinement arrives with the next speed signal
		PlayerController.MovementState.SPRINTING:
			_play("Run")


func _on_speed_changed(speed: float) -> void:
	# Only refine while actually moving — IDLE/SPRINTING have their own clips.
	if _current_state != PlayerController.MovementState.MOVING:
		return
	_play("Run" if speed > walk_max_speed else "Walk")


## Phase 4 hook: fire the kick animation once (locomotion resumes automatically
## on the next state/speed change).
func play_kick() -> void:
	_play("Kick")


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip):
		_anim.play(clip, anim_fade)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null
