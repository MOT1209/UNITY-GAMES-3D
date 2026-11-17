extends Node
func _ready() -> void:
	var db: Node = get_node("/root/TeamDB"); db.reload()
	var setup := MatchSetup.new(); setup.home_id = "club_royal_harbor"; setup.away_id = "club_northgate_utd"; setup.duration_minutes = 5; setup.human_side = "none"; setup.rng_seed = 5
	var m := MatchManager.new(); m.return_to_menu_on_finish = false; add_child(m); m.begin(setup, db)
	m._needs_reset = false; m._pause_left = 0.0; m.state.kick_off()
	for i in 30: await get_tree().physics_frame
	m.ball.freeze = true; m.ball.global_position = Vector3(36.6, 0.2, -50.2); m.ball.freeze = false
	m.last_toucher_id = m.entries["home"][5]["player_id"]
	for f in 400:
		await get_tree().physics_frame
		var b := m.ball.global_position
		if f % 10 == 0 or f < 5:
			var own := m._owner_entry()
			print("f%d phase %d ball (%.1f, %.2f, %.1f) v (%.1f,%.1f) owner %s pause %.2f ev %d" % [f, m.state.phase, b.x, b.y, b.z, m.ball.linear_velocity.x, m.ball.linear_velocity.z, str(own.get("player_id", "-")) + "/" + str(own.get("intent", "")), m._pause_left, m.state.events.size()])
	get_tree().quit()
