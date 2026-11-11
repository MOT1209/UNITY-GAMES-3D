## Screenshot runner (visual validation, non-headless).
## Usage:
##   godot --path . res://tests/screenshot_runner.tscn -- menu
##   godot --path . res://tests/screenshot_runner.tscn -- stadium
##   godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
##   godot --path . res://tests/screenshot_runner.tscn -- arena
##   godot --path . res://tests/screenshot_runner.tscn -- arena_follow
##   godot --path . res://tests/screenshot_runner.tscn -- ball
##   godot --path . res://tests/screenshot_runner.tscn -- mechanics
## Saves PNG into res://assets/placeholders/validation/ and quits.
extends Node

const STABILIZE_FRAMES := 45
const FOLLOW_FRAMES := 150


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "menu"

	var scene_path := "res://ui/main_menu/main_menu.tscn"
	if mode.begins_with("arena"):
		scene_path = "res://scenes/stadium/stadium_arena.tscn"
	elif mode == "ball":
		scene_path = "res://scenes/development/ball_physics_test.tscn"
	elif mode == "mechanics":
		scene_path = "res://scenes/development/football_mechanics_test.tscn"
	elif mode != "menu":
		scene_path = "res://scenes/stadium/stadium_prototype.tscn"

	var scene: Node = load(scene_path).instantiate()

	# Deterministic capture: pin the orbiting test target at (0, 0, 14) BEFORE
	# it enters the tree, so captures are comparable between runs.
	if scene.has_node("TestTarget"):
		var target: Node3D = scene.get_node("TestTarget")
		target.start_angle = PI / 2.0
		target.orbit_speed_radians = 0.0

	add_child(scene)

	if mode == "stadium_follow" or mode == "arena_follow":
		var camera: GameCamera = scene.get_node("%GameCamera")
		camera.set_mode(GameCamera.Mode.FOLLOW)
		for i in FOLLOW_FRAMES:
			await get_tree().process_frame

	if mode == "stadium" or mode == "arena":
		await get_tree().create_timer(1.0).timeout

	if mode == "ball":
		# Phase 3: let the scene settle, then fire a power shot so the capture
		# shows the ball in motion with HUD status live.
		await get_tree().create_timer(1.0).timeout
		var test_scene: Node = scene
		if test_scene.get("ball") != null:
			var ball: BallController = test_scene.get("ball")
			ball.apply_kick(Vector3(1.0, 0.0, -0.4), 18.0, 2.0)
			for i in 25:
				await get_tree().physics_frame

	if mode == "mechanics":
		# Phase 4: settle, then dribble + pass so the capture shows gameplay
		# HUD feedback (charge bars, cooldown marks, last event).
		await get_tree().create_timer(1.0).timeout
		Input.action_press("dribble")
		Input.action_press("move_forward")
		for i in 45:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		Input.action_release("dribble")
		Input.action_press("pass")
		for i in 3:
			await get_tree().physics_frame
		Input.action_release("pass")
		for i in 10:
			await get_tree().physics_frame

	for i in STABILIZE_FRAMES:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var prefix := "arena_" if mode.begins_with("arena") else "phase1_"
	var out_path := "res://assets/placeholders/validation/%s%s.png" % [prefix, mode.trim_prefix("arena_").trim_prefix("arena")]
	if mode == "arena":
		out_path = "res://assets/placeholders/validation/arena_broadcast.png"
	if mode == "ball":
		prefix = "phase3_"
		out_path = "res://assets/placeholders/validation/phase3_ball_test.png"
	if mode == "mechanics":
		prefix = "phase4_"
		out_path = "res://assets/placeholders/validation/phase4_mechanics_test.png"
	image.save_png(out_path)
	print("[SCREENSHOT] saved %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit()
