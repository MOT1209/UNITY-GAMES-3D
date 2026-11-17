extends Node
func _ready() -> void:
	var db: Node = get_node("/root/TeamDB"); db.reload()
	var setup := MatchSetup.new(); setup.home_id = "club_royal_harbor"; setup.away_id = "club_northgate_utd"; setup.duration_minutes = 5; setup.human_side = "none"; setup.rng_seed = 9
	var m := MatchManager.new(); m.return_to_menu_on_finish = false; add_child(m); m.begin(setup, db)
	m._needs_reset = false; m._pause_left = 0.0; m.state.kick_off()
	var rng := RandomNumberGenerator.new(); rng.seed = 4
	var goal := PitchSpace.opponent_goal("home")       # home attacks this goal; the away keeper defends it
	var gk := m.entries["away"][0]["node"] as TeamGoalkeeper
	var speed := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 23.0
	var saved := 0
	var scored := 0
	var wide := 0
	for i in 60:
		for side in ["home", "away"]:
			for e in m.entries[side]:
				if int(e["slot"]) != 0:
					(e["node"] as Node3D).global_position = Vector3(-30 + int(e["slot"]) * 2, 0.05, 30 if side == "home" else 25)
		gk.reset_to(Vector3(0, 0.05, goal.z - signf(goal.z) * 2.5), -signf(goal.z))
		m.state.phase = MatchState.Phase.PLAYING
		var score_before: int = m.state.score["home"]
		var start := Vector3(rng.randf_range(-6, 6), 0.12, goal.z - signf(goal.z) * 16.0)
		m.ball.freeze = true; m.ball.global_position = start; m.ball.freeze = false
		for f in 20: await get_tree().physics_frame
		var aim := Vector3(rng.randf_range(-3.4, 3.4), 0, goal.z)
		m.ball.strike(aim - start, speed, 0.6)
		var outcome := "none"
		for f in 90:
			await get_tree().physics_frame
			if m.state.score["home"] > score_before: outcome = "goal"; break
			if gk.state == TeamGoalkeeper.State.HOLD: outcome = "save"; break
			if absf(m.ball.global_position.z) > absf(goal.z) + 0.5: outcome = "wide"; break
			if m.state.phase != MatchState.Phase.PLAYING: outcome = "out"; break
		match outcome:
			"goal": scored += 1
			"save": saved += 1
			_: wide += 1
	print("speed %.0f: goals %d saves(held) %d other %d of 60" % [speed, scored, saved, wide])
	get_tree().quit()
