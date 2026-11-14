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
## Key-hint chips of an embedded match (null in the stand-alone prototype).
var control_hints: ControlHints = null

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
	var old_hints := get_node_or_null("HUD/HintsLabel") as Label
	if old_hints != null:
		old_hints.visible = false          # replaced by per-key chips (bidi-safe in Arabic)
	control_hints = ControlHints.new()
	control_hints.anchor_top = 1.0
	control_hints.anchor_right = 1.0
	control_hints.anchor_bottom = 1.0
	control_hints.offset_left = 16.0
	control_hints.offset_right = -16.0
	control_hints.offset_top = -64.0
	control_hints.offset_bottom = -10.0
	control_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hud := get_node_or_null("HUD")
	if hud != null:
		hud.add_child(control_hints)
		control_hints.show_for(ControlHints.SHOW_SECONDS)
	Loc.language_changed.connect(func(_c: String) -> void: _refresh_embedded_texts())
	_refresh_embedded_texts()


func _refresh_embedded_texts() -> void:
	_on_camera_mode_changed(game_camera.mode)


func _on_camera_mode_changed(mode: GameCamera.Mode) -> void:
	if not handle_pause:      # embedded in a match: localized
		camera_mode_label.text = Loc.f("HUD_CAMERA_MODE", Loc.t("HUD_CAMERA_BROADCAST" if mode == GameCamera.Mode.BROADCAST else "HUD_CAMERA_DYNAMIC"))
	else:
		camera_mode_label.text = "Camera: %s (V to toggle)" % game_camera.get_mode_name()
