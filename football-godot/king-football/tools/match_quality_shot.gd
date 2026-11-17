## Developer tool (Phase M): screenshot of a live AI-vs-AI 3D match after `seconds` of play, optionally with the F9 debug
## view (intents, velocity arrows, owner ring, pass target). Same seed + second = the same moment before and after a change.
##   xvfb-run -a -s "-screen 0 2400x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       res://tools/match_quality_shot.tscn -- out.png en 20 debug
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "user://match_shot.png"
	Loc.set_language(a[1] if a.size() > 1 else "en", false)
	var seconds := float(a[2]) if a.size() > 2 else 20.0
	var debug := a.has("debug")
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 5
	setup.human_side = "none"
	setup.rng_seed = 100
	seed(100)
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	var frames := 0
	while m._clock < seconds and frames < 60 * 120:
		await get_tree().physics_frame
		frames += 1
	if debug and m.get("debug_tools") != null:
		m.debug_tools.set_debug_visible(true)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size(), " clock %.1f" % m._clock)
	get_tree().quit(0)
