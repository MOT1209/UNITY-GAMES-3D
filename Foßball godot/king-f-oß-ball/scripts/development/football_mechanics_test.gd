extends Node3D

## Dedicated Phase 4 football mechanics test environment (plan §16).
## Launch from the command line:
##   godot --path . res://scenes/development/football_mechanics_test.tscn
## or open the scene in the editor and press F6.
##
## Contains: football pitch, player (with the real BallActions/BallDetector
## gameplay node), football, existing camera system, obstacles, and a
## development HUD that mirrors the plan §15 feedback list. The real gameplay
## actions come from the InputMap (pass/shoot/lob_pass/dribble); the raw dev
## keys (1–4, R, T, B) are development-only helpers that collide with no
## InputMap action.

const CRATE_COUNT := 4

@onready var ball: BallController = $Ball
@onready var player: PlayerController = $Player
@onready var actions: FootballActions = $Player/BallActions
@onready var game_camera: GameCamera = $GameCamera
@onready var action_label: Label = %ActionLabel
@onready var ball_status_label: Label = %BallStatusLabel
@onready var power_label: Label = %PowerLabel
@onready var cooldown_label: Label = %CooldownLabel
@onready var event_label: Label = %EventLabel
@onready var camera_mode_label: Label = %CameraModeLabel

var _event_text := "—"


func _ready() -> void:
	game_camera.mode_changed.connect(_on_camera_mode_changed)
	_build_obstacles()
	actions.ball_received.connect(func(speed: float) -> void:
		_push_event("BALL RECEIVED (touch at %.1f m/s)" % speed))
	actions.pass_started.connect(func(power: float) -> void:
		_push_event("PASS %.1f m/s" % power))
	actions.shot_started.connect(func(power: float, lift: float) -> void:
		_push_event("SHOT %.1f m/s (lift %.1f)" % [power, lift]))
	actions.lob_started.connect(func(power: float, lift: float) -> void:
		_push_event("LOB PASS %.1f m/s (lift %.1f)" % [power, lift]))
	actions.dribble_started.connect(func() -> void:
		_push_event("Dribble control engaged"))
	actions.dribble_stopped.connect(func() -> void:
		_push_event("Dribble control released"))
	actions.pass_completed.connect(func() -> void: _push_event("Pass action complete"))
	_on_camera_mode_changed(game_camera.mode)


func _process(_delta: float) -> void:
	var avail: Dictionary = actions.get_action_availability()
	action_label.text = "Action: %s  ·  Ball: %.1f m/s  ·  Distance: %.1f m  ·  Interaction: %s" % [
		actions.get_action_state_name(),
		ball.get_ball_speed(),
		actions.get_ball_distance(),
		"YES" if avail[&"interact"] else "no",
	]
	cooldown_label.text = "Pass %s  ·  Shoot %s  ·  Lob %s  ·  Dribble %s" % [
		_mark(avail[&"pass"]),
		_mark(avail[&"shoot"]),
		_mark(avail[&"lob"]),
		_mark(avail[&"dribble"]),
	]
	power_label.text = "Charge — Pass %s  Shot %s  Lob %s" % [
		_bar(actions.get_charge_ratio(&"pass")),
		_bar(actions.get_charge_ratio(&"shoot")),
		_bar(actions.get_charge_ratio(&"lob")),
	]
	event_label.text = "Last event: %s" % _event_text


func _mark(value: bool) -> String:
	return "✓" if value else "✗"


func _bar(ratio: float) -> String:
	var level := int(round(clampf(ratio, 0.0, 1.0) * 8.0))
	return "█".repeat(level) + "░".repeat(8 - level)


func _push_event(text: String) -> void:
	_event_text = text


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
	# Development-only direct kick (camera forward). Deliberately not part of
	# the gameplay interface — real kicks go through FootballActions.
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


## Crates + a thin wall near the centre for gameplay-around-obstacle checks.
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

	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	wall.position = Vector3(0.0, 0.9, -7.0)
	var wall_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(4.0, 1.8, 0.2)
	wall_shape.shape = box_shape
	wall.add_child(wall_shape)
	var wall_mesh := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(4.0, 1.8, 0.2)
	wall_mesh.mesh = wall_box
	wall_mesh.material_override = StandardMaterial3D.new()
	(wall_mesh.material_override as StandardMaterial3D).albedo_color = Color(0.55, 0.58, 0.62)
	wall.add_child(wall_mesh)
	crates_root.add_child(wall)
