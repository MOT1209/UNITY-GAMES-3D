class_name GoalkeeperVisual
extends PlayerCharacterVisual

## Goalkeeper model (assets/models/characters/goalkeeper.glb): a "Ready" stance
## instead of the idle clip, plus the dive / catch / throw actions.
##
## The actions are one-shot clips: while one plays, the locomotion refresh is
## suppressed so the keeper does not snap back to walking mid-dive.

## Emitted when a dive / catch / throw clip has finished.
signal action_finished

var _action := false


func _ready() -> void:
	idle_animation = "Ready"
	super._ready()


## True while a dive / catch / throw clip is playing.
func is_acting() -> bool:
	return _action


## Starts the dive clip. `side` is the keeper's own right (+1) / left (-1).
func dive(side: int) -> void:
	_play_action("DiveRight" if side > 0 else "DiveLeft")


func catch_high() -> void:
	_play_action("CatchHigh")


func catch_low() -> void:
	_play_action("CatchLow")


func throw_ball() -> void:
	_play_action("Throw")


func _play_action(anim: String) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	_action = true
	_action_playing = true   # blocks the locomotion refresh until the clip ends
	_anim.speed_scale = 1.0
	_anim.play(anim, 0.08)


func _on_animation_finished(anim: StringName) -> void:
	super._on_animation_finished(anim)
	if anim in [&"DiveLeft", &"DiveRight", &"CatchHigh", &"CatchLow", &"Throw"]:
		_action = false
		_action_playing = false
		action_finished.emit()
