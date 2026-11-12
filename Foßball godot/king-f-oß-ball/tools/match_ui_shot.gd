## Developer tool: screenshot of the results screen or the pause menu (needs a rendering device).
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/match_ui_shot.tscn -- out.png results|pause|controls en|de|ar
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Loc.set_language(a[2] if a.size() > 2 else "en", false)
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.rng_seed = 4
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	var h1: String = m.entries["home"][9]["player_id"]
	var h2: String = m.entries["home"][8]["player_id"]
	var a1: String = m.entries["away"][10]["player_id"]
	m.state.record_pass("home", h2)
	m.state.record_owner("home", h1)
	m.state.record_shot("home", h1)
	m.state.elapsed = 600.0 * 0.0 + 14.0
	m.state.goal("home", h1)
	m.state.kick_off()
	m.state.record_shot("away", a1)
	m.state.record_keeper_hold("home", m.entries["home"][0]["player_id"])
	for i in 7:
		m.state.record_pass("home", h2)
		m.state.record_owner("home", h1 if i % 2 == 0 else h2)
	m.state.record_possession("home", 61.0)
	m.state.record_possession("away", 39.0)
	m.state.half = 2
	m.state.elapsed = m.state.duration_seconds - 0.01
	for i in 10:
		await get_tree().physics_frame
	if a[1] == "pause" or a[1] == "controls":
		if m.results_view != null:
			m.results_view.get_parent().queue_free()
			m.results_view = null
		var fresh := MatchManager.new()
		fresh.return_to_menu_on_finish = false
		add_child(fresh)
		fresh.begin(setup, db)
		fresh.pause_match()
		await get_tree().process_frame
		if a[1] == "controls":
			(fresh.pause_menu.find_child("ControlsButton", true, false) as Button).pressed.emit()
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[0])
	print("saved ", a[0])
	get_tree().paused = false
	get_tree().quit()
