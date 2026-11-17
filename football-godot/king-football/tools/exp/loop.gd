extends Node
func _ready() -> void:
	var db: Node = get_node("/root/TeamDB"); db.reload()
	var setup := MatchSetup.new(); setup.home_id = "club_royal_harbor"; setup.away_id = "club_northgate_utd"; setup.duration_minutes = 5; setup.human_side = "none"; setup.difficulty = 1; setup.rng_seed = 103
	seed(103)
	var m := MatchManager.new(); m.return_to_menu_on_finish = false; add_child(m); m.begin(setup, db)
	m.state.duration_seconds = 300.0
	var probe := MatchQualityProbe.new(); add_child(probe); probe.attach(m)
	var printed := 0
	var last_ev := 0
	while m.state.phase != MatchState.Phase.FINISHED and m._clock < 330.0:
		await get_tree().physics_frame
		if m.state.events.size() != last_ev:
			for i in range(last_ev, m.state.events.size()):
				var ev: Dictionary = m.state.events[i]
				if m._clock > 280.0: print("EV %s t %.1f clock %.1f side %s ball (%.1f, %.1f)" % [ev["type"], ev["t"], m._clock, ev["side"], m.ball.global_position.x, m.ball.global_position.z])
			last_ev = m.state.events.size()
		if m._clock > 290.0 and printed < 200 and Engine.get_physics_frames() % 5 == 0:
			printed += 1
			var b := m.ball.global_position
			var near := ""
			for sd in ["home", "away"]:
				for e in m.entries[sd]:
					var p := (e["node"] as Node3D).global_position
					if p.distance_to(b) < 3.0:
						near += " %s%d(%.1f,%.1f)%s/%s" % [sd.substr(0,1), int(e["slot"]), p.x, p.z, str(e.get("intent","")), (e["actions"] as FootballActions).get_action_state_name() if e["actions"] else "GK"]
			print("c %.2f ph %d ball (%.2f,%.2f,%.2f) v(%.1f,%.1f)%s" % [m._clock, m.state.phase, b.x, b.y, b.z, m.ball.linear_velocity.x, m.ball.linear_velocity.z, near])
	get_tree().quit()
