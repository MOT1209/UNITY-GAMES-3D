extends Node3D

## Dedicated Phase 2 test environment controller.
## Launch from the command line:
##   godot --path . res://scenes/development/player_controller_test.tscn
## or open the scene in the editor and press F6.
## Wiring only: follow-camera handover, camera-mode HUD, live speed/state HUD,
## and a few collision-test crates built procedurally on the pitch.

const CRATE_COUNT := 4

@onready var player: PlayerController = $Player
@onready var game_camera: GameCamera = $GameCamera
@onready var camera_mode_label: Label = %CameraModeLabel
@onready var speed_label: Label = %SpeedLabel


func _ready() -> void:
	game_camera.mode_changed.connect(_on_camera_mode_changed)
	_build_crates()
	_on_camera_mode_changed(game_camera.mode)


func _process(_delta: float) -> void:
	speed_label.text = "State: %s  ·  Speed: %.1f m/s  (max %.1f)" % [
		player.get_state_name(), player.get_current_speed(), _max_speed_ref()
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.return_to_menu()
	elif event.is_action_pressed("camera_toggle"):
		game_camera.switch_mode()
	elif event.is_action_pressed("switch_player"):
		# Placeholder debug helper: teleport back to the centre spot.
		player.global_position = Vector3(0.0, 0.2, 0.0)


# Sprint speed reference for the HUD (mirrors controller config).
func _max_speed_ref() -> float:
	return player.config.sprint_speed


func _on_camera_mode_changed(_mode: GameCamera.Mode) -> void:
	camera_mode_label.text = "Camera: %s (V to toggle)" % game_camera.get_mode_name()


## Four simple crates near the centre spot for obstacle/collision checks.
func _build_crates() -> void:
	var crate_material := StandardMaterial3D.new()
	crate_material.albedo_color = Color(0.8, 0.45, 0.12)
	crate_material.roughness = 0.8

	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(1.0, 1.0, 1.0)

	var crate_shape := BoxShape3D.new()
	crate_shape.size = Vector3(1.0, 1.0, 1.0)

	var positions: Array[Vector3] = [
		Vector3(8.0, 0.5, 6.0),
		Vector3(-6.0, 0.5, 4.0),
		Vector3(12.0, 0.75, -3.0),
		Vector3(-9.0, 0.6, -8.0),
	]
	var crates_root := Node3D.new()
	crates_root.name = "Obstacles"
	add_child(crates_root)

	for i in CRATE_COUNT:
		var crate := StaticBody3D.new()
		crate.name = "Crate%d" % i
		crate.position = positions[i]

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = crate_mesh
		mesh_instance.material_override = crate_material
		crate.add_child(mesh_instance)

		var collision := CollisionShape3D.new()
		collision.shape = crate_shape
		crate.add_child(collision)

		crates_root.add_child(crate)
