## Screenshot runner (visual validation, non-headless).
## Usage:
##   godot --path . res://tests/screenshot_runner.tscn -- menu
##   godot --path . res://tests/screenshot_runner.tscn -- stadium
##   godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
## Saves PNG into res://assets/placeholders/validation/ and quits.
extends Node

const STABILIZE_FRAMES := 45
const FOLLOW_FRAMES := 150


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "menu"

	var scene_path := "res://ui/main_menu/main_menu.tscn"
	if mode != "menu":
		scene_path = "res://scenes/stadium/stadium_prototype.tscn"

	var scene: Node = load(scene_path).instantiate()

	# Deterministic capture: pin the orbiting test target at (0, 0, 14) BEFORE
	# it enters the tree, so captures are comparable between runs.
	if scene.has_node("TestTarget"):
		var target: Node3D = scene.get_node("TestTarget")
		target.start_angle = PI / 2.0
		target.orbit_speed_radians = 0.0

	add_child(scene)

	if mode == "stadium_follow":
		var camera: GameCamera = scene.get_node("%GameCamera")
		camera.set_mode(GameCamera.Mode.FOLLOW)
		for i in FOLLOW_FRAMES:
			await get_tree().process_frame

	if mode == "stadium":
		await get_tree().create_timer(1.0).timeout

	for i in STABILIZE_FRAMES:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var out_path := "res://assets/placeholders/validation/phase1_%s.png" % mode
	image.save_png(out_path)
	print("[SCREENSHOT] saved %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	get_tree().quit()
