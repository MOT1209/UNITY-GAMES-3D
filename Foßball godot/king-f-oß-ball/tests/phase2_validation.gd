## Phase 2 validation suite — runs headless:
##   godot --headless --path . res://tests/phase2_validation.tscn
## Asserts: player scripts/scenes load, player scene structure, InputMap,
## movement directions (world fallback), diagonal normalization, sprint,
## acceleration/deceleration → stop, movement states + signals, camera-relative
## movement, analog magnitude preservation, grounded/gravity stability,
## obstacle collision, and the dedicated test scene integration.

extends Node

const MOVE_ACTIONS: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right", "sprint",
]

const SCRIPTS: Array[String] = [
	"res://scripts/player/player_controller.gd",
	"res://scripts/player/player_config.gd",
	"res://scripts/development/player_controller_test.gd",
]

const SCENES: Array[String] = [
	"res://scenes/player/player.tscn",
	"res://scenes/development/player_controller_test.tscn",
]

const TICKS_PER_SECOND := 60.0

var _passed := 0
var _failed := 0
var _env: Node3D
var _player: PlayerController
var _state_events: Array[int] = []
var _speed_events: Array[float] = []
var _facing_events: Array[Vector3] = []


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase 2 validation ===")
	_test_assets()
	_test_player_scene_structure()
	await _test_grounding_and_gravity()
	await _test_cardinal_directions()
	await _test_diagonal_normalization()
	await _test_sprint_and_states()
	await _test_deceleration_to_idle()
	await _test_signals()
	await _test_analog_magnitude()
	await _test_camera_relative_movement()
	await _test_obstacle_collision()
	await _test_test_scene_integration()

	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Static assets --------------------------------------------------------

func _test_assets() -> void:
	_check(InputMap.has_action("sprint") and
			InputMap.action_get_events("sprint").size() >= 2, "InputMap: sprint reused from Phase 1")
	for action: String in MOVE_ACTIONS.slice(0, 4):
		_check(InputMap.has_action(action) and
				InputMap.action_get_events(action).size() >= 2,
				"InputMap: %s with key + gamepad binding" % action)

	for path: String in SCRIPTS:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "Script parses: %s" % path)
	for path: String in SCENES:
		_check(load(path) != null, "Scene loads: %s" % path)

	_check(load("res://resources/configurations/player_config.tres") is PlayerConfig,
			"PlayerConfig resource loads")


# --- Player scene structure -------------------------------------------------

func _test_player_scene_structure() -> void:
	var player: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	_check(player is PlayerController, "player.tscn: root is PlayerController (CharacterBody3D)")
	var shape_node: CollisionShape3D = player.get_node_or_null("CollisionShape3D")
	_check(shape_node != null and shape_node.shape is CapsuleShape3D,
			"player scene: capsule collision shape present")
	if shape_node != null:
		var capsule: CapsuleShape3D = shape_node.shape
		var bottom := shape_node.position.y - capsule.height * 0.5
		_check(absf(bottom) < 0.001,
				"player origin at ground level (capsule bottom = origin)",
				"bottom=%f" % bottom)
	var visual: Node3D = player.get_node_or_null("VisualRoot")
	var has_body: bool = visual != null and visual.get_node_or_null("Body") != null \
			and visual.get_node_or_null("Head") != null
	_check(has_body, "player scene: VisualRoot with Body + Head")
	var has_marker: bool = visual != null and visual.get_node_or_null("FacingMarker") != null
	_check(has_marker, "player scene: visible -Z facing marker")
	var legs: Node3D = player.get_node_or_null("VisualRoot/PlaceholderVisuals")
	_check(legs != null and legs.get_child_count() >= 2, "player scene: distinct lower body")
	_check(player.config is PlayerConfig, "player scene: PlayerConfig resource assigned")
	player.free()


# --- Test environment helpers -------------------------------------------------

func _spawn_player(start: Vector3) -> void:
	_release_all()
	if _env != null:
		_env.free()
	_env = Node3D.new()
	add_child(_env)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	_env.add_child(ground)

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = start
	_env.add_child(_player)

	_player.movement_state_changed.connect(_on_state_event)
	_player.speed_changed.connect(_on_speed_event)
	_player.facing_direction_changed.connect(_on_facing_event)

	await _settle()


func _release_all() -> void:
	for action: String in MOVE_ACTIONS:
		Input.action_release(action)


func _on_state_event(state: int) -> void:
	_state_events.append(state)


func _on_speed_event(speed: float) -> void:
	_speed_events.append(speed)


func _on_facing_event(direction: Vector3) -> void:
	_facing_events.append(direction)


## Waits until the player stops moving (up to a frame budget).
func _settle(max_ticks := 90) -> void:
	var ticks := 0
	while ticks < max_ticks:
		await get_tree().physics_frame
		ticks += 1
		if _player.get_current_speed() < 0.05:
			break


func _hold(action: String, strength := 1.0) -> void:
	Input.action_press(action, strength)


## Convenience for ending a hold: releases every movement + sprint action.
func _terminal_release() -> void:
	_release_all()


func _await_ticks(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


## Average horizontal speed over a window of physics ticks (m/s).
## Optionally samples a later window so ramp-up phases are excluded.
func _measure_speed(window_ticks := 15, skip_ticks := 0) -> float:
	if skip_ticks > 0:
		await _await_ticks(skip_ticks)
	var begin := _player.global_position
	await _await_ticks(window_ticks)
	# Measure planar displacement only.
	var move := _player.global_position - begin
	move.y = 0.0
	return move.length() * TICKS_PER_SECOND / window_ticks


# --- Behaviour tests -----------------------------------------------------

func _test_grounding_and_gravity() -> void:
	await _spawn_player(Vector3(0.0, 0.05, 0.0))
	await _await_ticks(30)
	_check(_player.is_on_floor(), "Physics: player stays grounded (is_on_floor)")
	_check(absf(_player.global_position.y) < 0.03,
			"Physics: rests on the ground plane (no floating/sinking)",
			"y=%.3f" % _player.global_position.y)
	var y0 := _player.global_position.y
	var speed := await _measure_speed(15)
	_check(speed < 0.05, "Physics: no unwanted drift while idle", "speed=%.3f" % speed)
	_check(_player.movement_state == PlayerController.MovementState.IDLE, "State: starts/ends in IDLE")
	_check(absf(y0 - _player.global_position.y) < 0.005, "Physics: stable vertical position while idle")


func _test_cardinal_directions() -> void:
	# No camera in the validation viewport → documented world-axis fallback.
	_check(_player.get_viewport().get_camera_3d() == null,
			"Fallback precondition: no camera → world-relative movement")

	var expectations: Array = [
		["move_forward", Vector3(0.0, 0.0, -1.0)],
		["move_backward", Vector3(0.0, 0.0, 1.0)],
		["move_left", Vector3(-1.0, 0.0, 0.0)],
		["move_right", Vector3(1.0, 0.0, 0.0)],
	]
	for pair: Array in expectations:
		var action: String = pair[0]
		var expected: Vector3 = pair[1]
		_release_all()
		await _settle()
		_hold(action)
		var begin := _player.global_position
		await _await_ticks(30)
		var move := _player.global_position - begin
		move.y = 0.0
		# 30 ticks include the acceleration ramp → expect ≈1.95 m, keep 1.5 margin.
		var moved: bool = move.length() > 1.5
		var direction_ok: bool = move.length() > 0.0 \
				and absf(move.normalized().dot(expected)) > 0.985
		_check(moved and direction_ok, "Movement: %s → correct direction" % action,
				"move=%s" % move)
	# Release leftovers for later tests.
	_release_all()
	await _settle()


func _test_diagonal_normalization() -> void:
	await _spawn_player(Vector3.ZERO)
	_hold("move_forward")
	# Terminal speed, ramp fully absorbed by the skip window.
	var straight := await _measure_speed(15, 45)
	_terminal_release()
	await _settle()

	_hold("move_forward")
	_hold("move_left")
	await _await_ticks(45)  # diagonal ramp fully absorbed
	var diag_begin := _player.global_position
	await _await_ticks(15)
	var diag_move := _player.global_position - diag_begin
	diag_move.y = 0.0
	var diagonal := diag_move.length() * TICKS_PER_SECOND / 15.0

	# Diagonal movement direction ≈ 45° across -Z/-X.
	var diag_direction_ok: bool = diag_move.length() > 0.0 \
			and absf(diag_move.normalized().dot(Vector3(-1, 0, -1).normalized())) > 0.985
	_check(diag_direction_ok, "Movement: forward-left diagonal direction correct",
			"move=%s dot=%.4f" % [diag_move,
			absf(diag_move.normalized().dot(Vector3(-1, 0, -1).normalized()))])
	_terminal_release()
	await _settle()

	# get_vector() clamps keyboard input to length 1 — diagonal must not be faster.
	_check(absf(diagonal - straight) < 0.15,
			"Movement: diagonal speed equals straight speed (normalized)",
			"straight=%.2f diagonal=%.2f" % [straight, diagonal])


func _test_sprint_and_states() -> void:
	await _spawn_player(Vector3.ZERO)
	_hold("move_forward")
	var normal_speed := await _measure_speed(15, 30)
	_check(absf(normal_speed - 5.5) < 0.4, "Movement: run speed matches config (≈5.5 m/s)",
			"measured=%.2f" % normal_speed)
	_check(_player.movement_state == PlayerController.MovementState.MOVING, "State: MOVING while input held")

	_hold("sprint")
	var sprint_speed := await _measure_speed(15, 30)
	_check(sprint_speed > normal_speed + 1.5, "Sprint: holding sprint raises speed",
			"normal=%.2f sprint=%.2f" % [normal_speed, sprint_speed])
	_check(_player.movement_state == PlayerController.MovementState.SPRINTING, "State: SPRINTING while sprint held")

	Input.action_release("sprint")
	await _await_ticks(30)
	var restored := await _measure_speed(10)
	_check(absf(restored - normal_speed) < 0.5, "Sprint: releasing sprint restores normal speed",
			"restored=%.2f" % restored)
	_check(_player.movement_state == PlayerController.MovementState.MOVING, "State: MOVING after sprint release")
	_terminal_release()
	await _settle()


func _test_deceleration_to_idle() -> void:
	await _spawn_player(Vector3.ZERO)
	_hold("move_forward")
	await _await_ticks(40)
	_terminal_release()
	var brake_ticks := 0
	while brake_ticks < 90:
		await get_tree().physics_frame
		brake_ticks += 1
		if _player.get_current_speed() < 0.05:
			break
	_check(_player.get_current_speed() < 0.05,
			"Deceleration: stops smoothly after release (≤1.5 s)",
			"speed=%.3f ticks=%d" % [_player.get_current_speed(), brake_ticks])
	_check(_player.movement_state == PlayerController.MovementState.IDLE, "Deceleration: state returns to IDLE")
	_check(_player.is_on_floor(), "Deceleration: stays grounded while braking")


func _test_signals() -> void:
	await _spawn_player(Vector3.ZERO)
	_state_events.clear()
	_speed_events.clear()
	_facing_events.clear()

	_hold("move_forward")
	await _await_ticks(30)
	_hold("sprint")
	await _await_ticks(20)
	_terminal_release()
	await _settle()

	_check(_state_events.size() >= 3, "Signals: movement_state_changed emitted on transitions",
			"events=%s" % str(_state_events))
	var expecting_first := PlayerController.MovementState.MOVING
	_check(_state_events.size() > 0 and _state_events[0] == expecting_first,
			"Signals: first state change is MOVING")
	_check(_speed_events.size() >= 2, "Signals: speed_changed emitted during accel/decel",
			"events=%s" % str(_speed_events))
	_check(_facing_events.size() == 1 and _facing_events[0].length() > 0.0,
			"Signals: facing_direction_changed emitted once for straight run (meaningful changes only)",
			"events=%s" % str(_facing_events))
	# Final state restored.
	_check(_player.movement_state == PlayerController.MovementState.IDLE,
			"Signals: final state IDLE after full stop")


func _test_analog_magnitude() -> void:
	await _spawn_player(Vector3.ZERO)
	_hold("move_forward", 0.4)
	var speed := await _measure_speed(15, 30)
	_terminal_release()
	await _settle()
	# Deadzone remap: strength 0.4 with deadzone 0.2 → ≈0.25 of full speed.
	_check(speed > 0.4 and speed < 3.4,
			"Analog: partial stick strength keeps partial speed (not binary)",
			"speed=%.2f (expect ≈%.2f)" % [speed, 0.25 * 5.5])


func _test_camera_relative_movement() -> void:
	await _spawn_player(Vector3.ZERO)
	var camera := Camera3D.new()
	_env.add_child(camera)
	camera.position = Vector3(20.0, 8.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)  # forward ≈ flattened −X
	camera.make_current()
	await get_tree().process_frame
	await get_tree().process_frame

	_hold("move_forward")
	var begin := _player.global_position
	await _await_ticks(30)
	var move := _player.global_position - begin
	move.y = 0.0
	_terminal_release()
	await _settle()
	# "Forward" must follow the camera's flattened forward (−X), not world −Z.
	_check(move.length() > 1.5 and absf(move.normalized().dot(Vector3(-1, 0, 0))) > 0.9,
			"Camera-relative: forward follows flattened camera forward (−X)",
			"move=%s" % move)

	# Fallback: free the camera again.
	camera.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_hold("move_forward")
	var begin2 := _player.global_position
	await _await_ticks(30)
	var move2 := _player.global_position - begin2
	move2.y = 0.0
	_terminal_release()
	await _settle()
	_check(move2.length() > 1.5 and absf(move2.normalized().dot(Vector3(0, 0, -1))) > 0.9,
			"Camera fallback: without a camera, forward reverts to world −Z",
			"move=%s" % move2)


func _test_obstacle_collision() -> void:
	await _spawn_player(Vector3(0.0, 0.05, 0.0))
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4.0, 3.0, 0.6)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.0, 1.5, -6.0)
	_env.add_child(wall)

	_hold("move_forward")
	await _await_ticks(150)
	_terminal_release()
	await _settle()
	# Wall front face sits at z = −5.7; capsule radius 0.3 → must stop before ~ −5.4.
	var final_z: float = _player.global_position.z
	_check(final_z > -5.65,
			"Collision: player cannot pass through a solid wall",
			"final z=%.2f (wall face −5.7)" % final_z)
	_check(absf(_player.global_position.y - 0.03) < 0.08,
			"Collision: stays grounded on impact")
	# Impact must not push the player up or sideways continuously.
	var speed := await _measure_speed(10)
	_check(speed < 0.2, "Collision: velocity fully blocked at the wall", "residual=%.2f" % speed)


func _test_test_scene_integration() -> void:
	var packed: PackedScene = load("res://scenes/development/player_controller_test.tscn")
	var test_scene: Node = packed.instantiate()
	add_child(test_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(test_scene.get_node_or_null("Pitch") != null, "Test scene: existing Phase 1 pitch reused")
	var integrated_player: PlayerController = test_scene.get_node_or_null("Player")
	_check(integrated_player != null, "Test scene: controllable player present")
	var camera: GameCamera = test_scene.get_node_or_null("%GameCamera")
	_check(camera != null and camera.follow_target == integrated_player,
			"Test scene: follow camera wired to the player")
	_check(test_scene.get_node_or_null("Obstacles") != null,
			"Test scene: obstacle crates generated")
	var hud := test_scene.get_node_or_null("HUD")
	_check(hud != null and hud.get_node_or_null("SpeedLabel") != null
			and hud.get_node_or_null("CameraModeLabel") != null,
			"Test scene: HUD labels present")
	_check(integrated_player.config is PlayerConfig, "Test scene: player got its PlayerConfig")

	# The integrated scene must actually drive the player: simulate forward input.
	Input.action_press("move_forward")
	var begin: Vector3 = integrated_player.global_position
	await _await_ticks(30)
	var move: Vector3 = integrated_player.global_position - begin
	move.y = 0.0
	Input.action_release("move_forward")
	_check(move.length() > 1.5, "Test scene: player can be driven on the pitch",
			"move=%s" % move)

	test_scene.queue_free()
	await get_tree().process_frame
