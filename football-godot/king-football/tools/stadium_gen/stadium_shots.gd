extends Node

## Screenshots of every stadium (and every ball) for review:
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tools/stadium_gen/stadium_shots.tscn -- <out_dir>
## Writes <id>_overview.png, <id>_broadcast.png, <id>_pitch.png, <id>_night.png and balls.png.

const SCENE := "res://scenes/stadium/stadium_arena.tscn"
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"

var _out := "user://stadium_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1600, 900)
	for id in StadiumCatalog.ids():
		await _shoot(id)
	await _shoot_balls()
	get_tree().quit()


func _shoot(id: String) -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var pl := root.get_node_or_null("Player")
	if pl != null:
		pl.free()
	var hud := root.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	StadiumCatalog.apply_to(root.get_node("Arena"), id)
	add_child(root)
	MatchEnvironment.apply(root, {"weather": "clear", "time_of_day": "day"})
	var gc := root.get_node_or_null("GameCamera")
	if gc != null:
		gc.set_process(false)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	for view: Array in [["overview", Vector3(115, 95, 150), Vector3(0, 0, 0), 50.0],
			["broadcast", Vector3(30, 22, 0), Vector3(0, 0, 0), 44.0],
			["pitch", Vector3(-8, 4.5, 40), Vector3(15, 6, -40), 70.0]]:
		cam.fov = view[3]
		cam.look_at_from_position(view[1], view[2], Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, id, view[0]])
	MatchEnvironment.apply(root, {"weather": "clear", "time_of_day": "night"})
	cam.fov = 70.0
	cam.look_at_from_position(Vector3(-8, 4.5, 40), Vector3(15, 6, -40), Vector3.UP)
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s_night.png" % [_out, id])
	root.queue_free()
	await get_tree().process_frame


func _shoot_balls() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	root.add_child(sun)
	var ids := BallCatalog.ids()
	for i in ids.size():
		var ball := (load(BALL_SCENE) as PackedScene).instantiate() as RigidBody3D
		ball.freeze = true
		root.add_child(ball)
		ball.global_position = Vector3((i - (ids.size() - 1) * 0.5) * 0.3, 0.0, 0.0)
		BallCatalog.apply_to(ball, ids[i])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	cam.look_at_from_position(Vector3(0, 0.35, 1.9), Vector3.ZERO, Vector3.UP)
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/balls.png" % _out)
