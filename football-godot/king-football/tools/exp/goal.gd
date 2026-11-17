extends Node
func _ready() -> void:
	var db: Node = get_node("/root/TeamDB"); db.reload()
	var setup := MatchSetup.new(); setup.home_id = "club_royal_harbor"; setup.away_id = "club_northgate_utd"; setup.duration_minutes = 2; setup.human_side = "none"; setup.rng_seed = 3
	setup.conditions = {"weather": "rain", "time_of_day": "night"}
	var m := MatchManager.new(); m.return_to_menu_on_finish = false; add_child(m); m.begin(setup, db)
	m._needs_reset = false; m._pause_left = 0.0; m.state.kick_off()
	for i in 70: await get_tree().process_frame
	var goal_pos := PitchSpace.opponent_goal(m.frame_side("home"))
	m.last_toucher_id = m.entries["home"][5]["player_id"]
	m.ball.reset_ball(Vector3(goal_pos.x, 0.5, goal_pos.z + (-1.2 if goal_pos.z < 0.0 else 1.2)))
	for f in 25:
		await get_tree().process_frame
		var gk := m.entries["away"][0]["node"] as Node3D
		print("f%d ball (%.2f,%.2f,%.2f) v(%.1f,%.1f,%.1f) gk (%.1f,%.1f) phase %d score %s" % [f, m.ball.global_position.x, m.ball.global_position.y, m.ball.global_position.z, m.ball.linear_velocity.x, m.ball.linear_velocity.y, m.ball.linear_velocity.z, gk.global_position.x, gk.global_position.z, m.state.phase, str(m.state.score)])
	get_tree().quit()
