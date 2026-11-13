## Developer tool: plays full matches in the real engine with the AI on both sides and prints the statistics (plausibility check).
##   godot --headless --path . res://tools/sim_matches.tscn -- <seeds> <difficulty> <minutes>
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var seeds := int(a[0]) if a.size() > 0 else 3
	var difficulty := int(a[1]) if a.size() > 1 else 1
	var minutes := int(a[2]) if a.size() > 2 else 2
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var totals := {"goals": 0, "fouls": 0, "yellows": 0, "reds": 0, "corners": 0, "throw_ins": 0, "goal_kicks": 0, "offsides": 0, "shots": 0, "passes": 0, "ended": 0}
	for s in seeds:
		var setup := MatchSetup.new()
		setup.home_id = "club_royal_harbor"
		setup.away_id = "club_northgate_utd"
		setup.duration_minutes = minutes
		setup.human_side = "none"
		setup.difficulty = difficulty
		setup.rng_seed = 100 + s
		var m := MatchManager.new()
		m.return_to_menu_on_finish = false
		add_child(m)
		m.begin(setup, db)
		var t0 := Time.get_ticks_msec()
		var frames := 0
		while m.state.phase != MatchState.Phase.FINISHED and frames < 60 * 60 * (minutes + 3):
			await get_tree().physics_frame
			frames += 1
			Engine.time_scale = 1.0
		var st := m.state.stats
		var line := {"goals": m.state.score["home"] + m.state.score["away"]}
		for k in ["fouls", "yellows", "reds", "corners", "throw_ins", "goal_kicks", "offsides", "shots", "passes"]:
			line[k] = int(st.teams["home"][k]) + int(st.teams["away"][k])
		line["ended"] = 1 if m.state.phase == MatchState.Phase.FINISHED else 0
		for k in totals:
			totals[k] += int(line[k])
		print("MATCH seed=%d diff=%d score=%d-%d frames=%d wall=%.0fs %s" % [100 + s, difficulty, m.state.score["home"], m.state.score["away"], frames, (Time.get_ticks_msec() - t0) / 1000.0, str(line)])
		m.process_mode = Node.PROCESS_MODE_DISABLED
		m.queue_free()
		await get_tree().process_frame
	print("TOTAL over %d matches (%d min each): %s" % [seeds, minutes, str(totals)])
	get_tree().quit()
