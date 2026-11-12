class_name StadiumPrototype
extends Node3D

## Stadium prototype controller:
##   - pause action  → clean return to the main menu (via GameManager)
##   - camera_toggle → switches the reusable GameCamera between modes
##   - HUD keeps showing the active camera mode
## Gameplay systems (match logic, players, ball) intentionally absent in Phase 1.

## The prototype scene leaves to the menu on `pause`. When the arena is embedded in a real match
## (`MatchManager`), the match owns the pause action (pause menu with confirmation) and this is false.
var handle_pause := true

@onready var game_camera: GameCamera = %GameCamera
@onready var camera_mode_label: Label = %CameraModeLabel


func _ready() -> void:
	game_camera.mode_changed.connect(_on_camera_mode_changed)
	_on_camera_mode_changed(game_camera.mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if handle_pause:
			GameManager.return_to_menu()
	elif event.is_action_pressed("camera_toggle"):
		game_camera.switch_mode()


## Called by `MatchManager` when the arena hosts a real match: the prototype's English-only title and key hints
## are replaced by localized text, and the match owns the pause action.
func embed_in_match() -> void:
	handle_pause = false
	var title := get_node_or_null("HUD/TitleLabel")
	if title != null:
		title.visible = false
	Loc.language_changed.connect(func(_c: String) -> void: _refresh_embedded_texts())
	_refresh_embedded_texts()


func _refresh_embedded_texts() -> void:
	var hints := get_node_or_null("HUD/HintsLabel") as Label
	if hints != null:
		hints.text = Loc.t("HUD_MATCH_HINTS")
	_on_camera_mode_changed(game_camera.mode)


func _on_camera_mode_changed(mode: GameCamera.Mode) -> void:
	if not handle_pause:      # embedded in a match: localized
		camera_mode_label.text = Loc.f("HUD_CAMERA_MODE", Loc.t("HUD_CAMERA_BROADCAST" if mode == GameCamera.Mode.BROADCAST else "HUD_CAMERA_DYNAMIC"))
	else:
		camera_mode_label.text = "Camera: %s (V to toggle)" % game_camera.get_mode_name()
