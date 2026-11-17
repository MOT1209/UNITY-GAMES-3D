extends Node3D

## Dedicated Phase 3 ball physics test environment.
## Launch from the command line:
##   godot --path . res://scenes/development/ball_physics_test.tscn
## or open the scene in the editor and press F6.
##
## Wiring only: follow camera, HUD, obstacle crates + a thin wall, ball debug
## overlays and a handful of development-only kick helpers. The helpers use raw
## physical keys (digits 1–4, R, T, B) that collide with no InputMap action, so
## no development controls leak into the final gameplay interface.

const CRATE_COUNT := 4

@onready var ball: BallController = $Ball
@onready var player: PlayerController = $Player
@onready var game_camera: GameCamera = $GameCamera
@onready var ball_debug: BallDebug = $Ball/BallDebug
@onready var detector: BallProximityDetector = $Player/BallDetector
@onready var ball_status_label: Label = %BallStatusLabel
@onready var detector_status_label: Label = %DetectorStatusLabel
@onready var player_speed_label: Label = %PlayerSpeedLabel
@onready var camera_mode_label: Label = %CameraModeLabel


func _ready() -> void:
	game_camera.mode_changed.connect(_on_camera_mode_changed)
	_build_obstacles()
	# Development overlays — this is a dev scene, enabling debug here is fine.
	ball.debug_enabled = true
	_on_camera_mode_changed(game_camera.mode)


func _process(_delta: float) -> void:
	ball_status_label.text = "Ball: %.1f m/s  ·  Player-ball: %.1f m  ·  Interaction: %s" % [
		ball.get_ball_speed(),
		player.global_position.distance_to(ball.global_position),
		"YES" if detector.is_interaction_available() else "no",
	]
	detector_status_label.text = "Nearby ball: %s" % (
			str(detector.get_current_ball().name) if detector.is_ball_nearby() else "---")
	player_speed_label.text = "State: %s  ·  Speed: %.1f m/s" % [
		player.get_state_name(), player.get_current_speed(),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.return_to_menu()
	elif event.is_action_pressed("camera_toggle"):
		game_camera.switch_mode()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _dev_kick(6.0, 0.0)   # touch pass
			KEY_2: _dev_kick(14.0, 2.0)  # driven kick
			KEY_3: _dev_kick(7.0, 9.0)   # lob
			KEY_4: _dev_kick(24.0, 0.5)  # power shot
			KEY_R: ball.reset_ball()      # ball back to centre
			KEY_B: ball.reset_ball(Vector3(0.0, 6.0, 0.0))  # drop from height
			KEY_T:                        # full reset (ball + player)
				ball.reset_ball()
				player.global_position = Vector3(0.0, 0.2, 2.5)


func _dev_kick(power: float, lift: float) -> void:
	# Kick direction: flattened forward of the active camera (falls back to the
	# player's facing, then to world −Z). Deliberately *not* wired to the
	# pass/shoot actions — those are Phase 4 gameplay.
	var direction := Vector3(0.0, 0.0, -1.0)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var cam_forward := -camera.global_transform.basis.z
		cam_forward.y = 0.0
		if cam_forward.length_squared() > 0.0001:
			direction = cam_forward.normalized()
	ball.apply_kick(direction, power, lift)


func _on_camera_mode_changed(_mode: GameCamera.Mode) -> void:
	camera_mode_label.text = "Camera: %s (V to toggle)" % game_camera.get_mode_name()


## Crates + a thin wall near the centre for collision/deflection checks.
func _build_obstacles() -> void:
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

	# Thin 4 m wall 6 m ahead of the centre for high-speed rebound checks.
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	wall.position = Vector3(0.0, 0.9, -7.0)
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(4.0, 1.8, 0.3)
	var wall_mesh_instance := MeshInstance3D.new()
	wall_mesh_instance.mesh = wall_mesh
	wall_mesh_instance.material_override = StandardMaterial3D.new()
	(wall_mesh_instance.material_override as StandardMaterial3D).albedo_color = \
			Color(0.55, 0.58, 0.65)
	wall.add_child(wall_mesh_instance)
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	(wall_shape.shape as BoxShape3D).size = Vector3(4.0, 1.8, 0.3)
	wall.add_child(wall_shape)
	crates_root.add_child(wall)
