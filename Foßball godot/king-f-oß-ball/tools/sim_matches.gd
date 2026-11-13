## Developer tool: plays full matches in the real engine with the AI on both sides and prints the statistics (plausibility check).
##   godot --headless --path . res://tools/sim_matches.tscn -- <seeds> <difficulty> <minutes> [notackle|-] [trace]
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var seeds := int(a[0]) if a.size() > 0 else 3
	var difficulty := int(a[1]) if a.size() > 1 else 1
	var minutes := int(a[2]) if a.size() > 2 else 2
	var no_tackle := a.size() > 3 and a[3] == "notackle"      # switch the AI tackles off (to see what the rest of the game does)
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var totals := {"goals": 0, "fouls": 0, "yellows": 0, "reds": 0, "corners": 0, "throw_ins": 0, "goal_kicks": 0, "offsides": 0, "shots": 0, "passes": 0, "ended": 0}
	for s in range(seeds):
		var setup := MatchSetup.new()
		setup.home_id = "club_royal_harbor"
		setup.away_id = "club_northgate_utd"
		setup.duration_minutes = minutes
		setup.human_side = "none"
		setup.difficulty = difficulty
		setup.rng_seed = 100 + s + (int(a[5]) if a.size() > 5 else 0)
		var m := MatchManager.new()
		m.return_to_menu_on_finish = false
		add_child(m)
		m.begin(setup, db)
		if no_tackle:
			m.rules.team_cooldown = {"home": 1.0e9, "away": 1.0e9}
		var t0 := Time.get_ticks_msec()
		var frames := 0
		var dead := 0
		var shoot_presses := 0
		var was_charging := {}
		var slow := 0
		var owner_changes := 0
		var last_side := ""
		var min_goal_dist := 1000.0
		var in_range := 0
		var carrier_frames := 0
		var chasers_close := 0
		while m.state.phase != MatchState.Phase.FINISHED and frames < 60 * 60 * (minutes + 3):
			await get_tree().physics_frame
			frames += 1
			if a.size() > 4 and a[4] == "trace" and frames % 180 == 0:
				var near := 0
				for sd in ["home", "away"]:
					for e in m.entries[sd]:
						if ((e["node"] as Node3D).global_position - m.ball.global_position).length() < 6.0:
							near += 1
				var o2 := m._owner_entry()
				print("TRACE t=%ds ball=(%.0f,%.0f) v=%.1f owner=%s near6m=%d phase=%d" % [frames / 60, m.ball.global_position.x, m.ball.global_position.z, m.ball.linear_velocity.length(), (o2["side"] + str(o2["slot"])) if not o2.is_empty() else "-", near, m.state.phase])
			for sd in ["home", "away"]:
				for e in m.entries[sd]:
					var ch: bool = e["charging"] == &"shoot"
					if ch and not was_charging.get(e["player_id"], false):
						shoot_presses += 1
					was_charging[e["player_id"]] = ch
			if m.state.phase != MatchState.Phase.PLAYING:
				dead += 1
				continue
			if m.ball.linear_velocity.length() < 0.4:
				slow += 1
			var own := m._owner_entry()
			if not own.is_empty():
				carrier_frames += 1
				if own["side"] != last_side:
					owner_changes += 1
					last_side = own["side"]
				var goal := PitchSpace.opponent_goal(m.frame_side(own["side"]))
				var d := Vector2((own["node"] as Node3D).global_position.x - goal.x, (own["node"] as Node3D).global_position.z - goal.z).length()
				min_goal_dist = minf(min_goal_dist, d)
				if d <= 24.0:
					in_range += 1
		var st := m.state.stats
		var line := {"goals": m.state.score["home"] + m.state.score["away"]}
		for k in ["fouls", "yellows", "reds", "corners", "throw_ins", "goal_kicks", "offsides", "shots", "passes"]:
			line[k] = int(st.teams["home"][k]) + int(st.teams["away"][k])
		line["ended"] = 1 if m.state.phase == MatchState.Phase.FINISHED else 0
		for k in totals:
			totals[k] += int(line[k])
		line["ai_shoot_attempts"] = shoot_presses
		line["dead_s"] = int(dead / 60.0)
		line["ball_slow_s"] = int(slow / 60.0)
		line["carrier_s"] = int(carrier_frames / 60.0)
		line["owner_changes"] = owner_changes
		line["closest_to_goal_m"] = int(min_goal_dist)
		line["carrier_in_range_s"] = snappedf(in_range / 60.0, 0.1)
		print("MATCH seed=%d diff=%d score=%d-%d frames=%d wall=%.0fs %s" % [100 + s, difficulty, m.state.score["home"], m.state.score["away"], frames, (Time.get_ticks_msec() - t0) / 1000.0, str(line)])
		m.process_mode = Node.PROCESS_MODE_DISABLED
		m.queue_free()
		await get_tree().process_frame
	print("TOTAL over %d matches (%d min each): %s" % [seeds, minutes, str(totals)])
	get_tree().quit()
