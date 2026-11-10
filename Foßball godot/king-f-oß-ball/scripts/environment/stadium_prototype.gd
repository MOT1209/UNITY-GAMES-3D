class_name StadiumPrototype
extends Node3D

## Stadium prototype controller:
##   - pause action  → clean return to the main menu (via GameManager)
##   - camera_toggle → switches the reusable GameCamera between modes
##   - HUD keeps showing the active camera mode
## Gameplay systems (match logic, players, ball) intentionally absent in Phase 1.

@onready var game_camera: GameCamera = %GameCamera
@onready var camera_mode_label: Label = %CameraModeLabel


func _ready() -> void:
	game_camera.mode_changed.connect(_on_camera_mode_changed)
	_on_camera_mode_changed(game_camera.mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.return_to_menu()
	elif event.is_action_pressed("camera_toggle"):
		game_camera.switch_mode()


func _on_camera_mode_changed(mode: GameCamera.Mode) -> void:
	camera_mode_label.text = "Camera: %s (V to toggle)" % game_camera.get_mode_name()
