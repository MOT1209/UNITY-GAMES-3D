## QA tool: plays a real match with AI on both sides and captures gameplay
## screenshots at fixed times plus on every goal. Saves PNGs to a folder.
##   godot --path . --rendering-driver opengl3 res://tools/qa_match_capture.tscn -- <outdir> [minutes] [shots]
extends Node

var captures := 0
var out_dir := "user://qa"
var goals_seen := {}

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "user://qa"
	var minutes := int(a[1]) if a.size() > 1 else 5
	if not minutes in MatchSetup.ALLOWED_DURATIONS:
		minutes = 5
	var shot_at := [3.0, 10.0, 20.0, 40.0, 70.0, 100.0]   # in-game seconds
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	var clubs: Array = []
	for id in db.teams.keys():
		var t: TeamData = db.get_team(id)
		if t.league_id != "" and t.league_id == (db.get_team(clubs[0]).league_id if clubs.size() > 0 else ""):
			clubs.append(id)
		if clubs.size() >= 2:
			break
	if clubs.size() < 2:
		clubs = ["eng_arsenal", "eng_aston_villa"]
	setup.home_id = clubs[0]
	setup.away_id = clubs[1]
	setup.duration_minutes = minutes
	setup.human_side = "none"
	setup.difficulty = 1
	setup.rng_seed = 42
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err: String = m.begin(setup, db)
	if err != "":
		print("QA capture: begin failed: ", err)
		get_tree().quit()
		return
	var t0 := Time.get_ticks_msec()
	var frame_i := 0
	while m.state.phase != MatchState.Phase.FINISHED and frame_i < 60 * 60 * (minutes + 3):
		await get_tree().physics_frame
		frame_i += 1
		var in_game := m.state.elapsed
		for st in shot_at:
			if st <= in_game and not goals_seen.has("t" + str(st)):
				goals_seen["t" + str(st)] = true
				await _shot(out_dir + "/play_t%03ds.png" % int(st))
		var gh: int = m.state.score["home"]
		var ga: int = m.state.score["away"]
		var key := "g%d_%d" % [gh, ga]
		if not goals_seen.has(key):
			goals_seen[key] = true
			await _shot(out_dir + "/goal_%d-%d.png" % [gh, ga])
	await _shot(out_dir + "/full_time.png")
	print("QA capture done: %d images" % captures)
	get_tree().quit()

func _shot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	captures += 1
	print("captured ", path, " (%dx%d)" % [img.get_width(), img.get_height()])
