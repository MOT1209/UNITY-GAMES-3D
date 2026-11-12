## Phase 1 validation suite — runs headless:
##   godot --headless --path . res://tests/phase1_validation.tscn
## Asserts: InputMap actions, script parsing, scene loading/structure,
## camera broadcast + follow behavior, UI wiring, config resources.
extends Node

const REQUIRED_ACTIONS: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"sprint", "pass", "shoot", "lob_pass", "dribble", "tackle",
	"switch_player", "camera_toggle", "pause",
]

const SCRIPTS: Array[String] = [
	"res://scripts/core/game_manager.gd",
	"res://scripts/camera/game_camera.gd",
	"res://scripts/camera/camera_config.gd",
	"res://scripts/environment/football_pitch.gd",
	"res://scripts/environment/stadium_stands.gd",
	"res://scripts/environment/stadium_prototype.gd",
	"res://scripts/debug/test_target.gd",
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/menu_button.gd",
]

const SCENES: Array[String] = [
	"res://scenes/main/main.tscn",
	"res://ui/main_menu/main_menu.tscn",
	"res://scenes/stadium/stadium_prototype.tscn",
	"res://scenes/environment/football_pitch.tscn",
	"res://scenes/environment/goal.tscn",
	"res://scenes/camera/game_camera.tscn",
]

var _passed := 0
var _failed := 0


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame

	print("=== KING FOOTBALL — Phase 1 validation ===")
	_test_input_map()
	_test_scripts()
	_test_resources()
	await _test_game_manager()
	await _test_scenes_and_camera()
	await _test_main_menu_ui()          # was not awaited: its checks silently never ran

	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- InputMap -----------------------------------------------------------

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _test_input_map() -> void:
	for action in REQUIRED_ACTIONS:
		var exists := InputMap.has_action(action)
		var event_count := 0
		if exists:
			event_count = InputMap.action_get_events(action).size()
		_check(exists and event_count >= 2, "InputMap action '%s'" % action,
			"exists=%s, events=%d (need key + gamepad binding)" % [exists, event_count])


# --- Scripts parse ---------------------------------------------------------

func _test_scripts() -> void:
	for path in SCRIPTS:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "Script parses: %s" % path)


func _test_resources() -> void:
	var config: Resource = load("res://resources/configurations/game_camera_config.tres")
	var ok: bool = config is CameraConfig
	if ok and config != null:
		ok = config.broadcast_position_offset.y > 20.0 and config.follow_speed > 0.0 and config.follow_distance > 0.0
	_check(ok, "CameraConfig resource loads with defaults", "loaded=%s, is CameraConfig=%s" % [config != null, ok])


# --- GameManager ------------------------------------------------------------

func _test_game_manager() -> void:
	var gm: Node = get_tree().root.get_node_or_null("/root/GameManager")
	_check(gm != null, "GameManager autoload registered")
	if gm == null:
		return
	_check(gm.has_signal("state_changed"), "GameManager exposes 'state_changed' signal")
	_check(gm.state == 1, "GameManager initial state is MAIN_MENU", "state=%s" % gm.state)
	_check(ResourceLoader.exists(gm.SCENE_MAIN) and ResourceLoader.exists(gm.SCENE_STADIUM),
		"GameManager scene paths resolve")
	_check(gm.has_method("start_match") and gm.has_method("return_to_menu") and gm.has_method("quit_game"),
		"GameManager phase-1 interface complete")


# --- Scenes + camera behaviour ----------------------------------------------

func _test_scenes_and_camera() -> void:
	for path in SCENES:
		var packed: PackedScene = load(path)
		_check(packed != null, "Scene loads: %s" % path)

	var stadium: Node3D = load("res://scenes/stadium/stadium_prototype.tscn").instantiate()
	add_child(stadium)
	await get_tree().process_frame
	await get_tree().process_frame

	# Structure.
	_check(stadium.get_node_or_null("Pitch") != null, "Stadium: pitch instance present")
	if stadium.has_node("Pitch"):
		var pitch: Node3D = stadium.get_node("Pitch")
		var collect: Array[MeshInstance3D] = []
		_collect_meshes(pitch, collect)
		_check(collect.size() > 40, "Pitch: procedural markings generated", "meshes=%d" % collect.size())
		_check(pitch.get_node_or_null("GroundCollision") != null, "Pitch: ground collision exists")

	for goal_name in ["GoalA", "GoalB"]:
		var goal: Node3D = stadium.get_node_or_null(goal_name)
		_check(goal != null, "Stadium: %s present" % goal_name)
		if goal:
			_check(goal.get_node_or_null("PostLeft") != null and goal.get_node_or_null("PostRight") != null
				and goal.get_node_or_null("Crossbar") != null and goal.get_node_or_null("NetBack") != null,
				"Goal structure complete (%s)" % goal_name)

	_check(stadium.get_node_or_null("Stands") != null, "Stadium: stands generator present")

	var camera: GameCamera = stadium.get_node("%GameCamera")
	_check(camera != null, "Stadium: reusable GameCamera present")
	var target: Node3D = stadium.get_node("TestTarget")
	_check(target != null and camera.follow_target == target, "Camera: follow target wired (test target)")

	# Broadcast mode: stable, elevated, looking at the configured point.
	camera.set_mode(GameCamera.Mode.BROADCAST)
	await get_tree().process_frame
	var cfg: CameraConfig = camera.config
	var expected_pos: Vector3 = cfg.broadcast_look_target + cfg.broadcast_position_offset
	_check(camera.global_position.distance_to(expected_pos) < 0.1 and camera.fov == cfg.broadcast_fov,
		"Broadcast camera: positioned per config",
		"pos=%s expected=%s" % [camera.global_position, expected_pos])

	# Follow mode: must home in on the moving test target within damping tolerance.
	var initial_pos := camera.global_position
	camera.set_mode(GameCamera.Mode.FOLLOW)
	await get_tree().process_frame
	_check(camera.fov == cfg.follow_fov, "Dynamic camera: applies follow FOV", "fov=%s" % camera.fov)
	var elapsed := 0.0
	while elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	var desired: Vector3 = target.global_position + Vector3(0, cfg.follow_height, cfg.follow_distance)
	var distance := camera.global_position.distance_to(desired)
	_check(distance < 3.0, "Dynamic camera: follows test target with damping",
		"distance-to-desired=%.2f (tolerance 3.0)" % distance)
	_check(camera.global_position.distance_to(initial_pos) > 5.0,
		"Dynamic camera: actually moved to the follow position")

	# Switch interface round-trip.
	camera.switch_mode()
	_check(camera.mode == GameCamera.Mode.BROADCAST, "Camera switching: switch_mode() works")

	stadium.queue_free()
	await get_tree().process_frame


# --- Main menu UI ------------------------------------------------------------

func _test_main_menu_ui() -> void:
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	var play: Button = menu.get_node("%PlayButton")
	var settings: Button = menu.get_node("%SettingsButton")
	var quit: Button = menu.get_node("%QuitButton")
	_check(play != null and quit != null and settings != null, "Main menu: required buttons exist")

	var play_connected: bool = play.pressed.get_connections().size() > 0
	var settings_connected: bool = settings.pressed.get_connections().size() > 0
	var quit_connected: bool = quit.pressed.get_connections().size() > 0
	_check(play_connected and quit_connected, "Main menu: Play/Quit wired to handlers")
	# Settings used to be a disabled placeholder; it is now a real language/settings panel.
	_check(settings != null and not settings.disabled and settings_connected,
		"Main menu: Settings is enabled and wired (opens the language settings)",
		"disabled=%s connected=%s" % [settings.disabled, settings_connected])
	settings.pressed.emit()
	await get_tree().process_frame
	_check(menu.get_node_or_null("SettingsPanel") != null and menu.get_node("SettingsPanel").find_child("Lang_ar", true, false) != null,
		"Main menu: Settings opens a panel with the three language buttons")

	menu.queue_free()
	await get_tree().process_frame
