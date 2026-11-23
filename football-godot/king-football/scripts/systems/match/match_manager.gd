class_name MatchManager
extends "res://scripts/systems/match/match_manager_part2.gd"

## Match manager, part 3 of 3. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: _physics_process, _step_kickoff, _reset_ai_commands, note_human_pass, _sample_heat, capture,
## save_match, restore, skip_replay, _start_shootout, _finish, _show_results, _on_results_continue,
## _unhandled_input, is_paused, seat2_active, restart_match, quit_match, controller_side_for_slot,
## controller_side_info, controller_tactical_state, controller_apply_tactic, controller_substitute,
## controller_player_name.

func _physics_process(delta: float) -> void:
	if state == null or ball == null:
		return
	if human_intent.just_pressed(&"switch_player"):
		switch_player()
	if not selected2.is_empty() and human_intent2.just_pressed(&"switch_player"):
		switch_player2()
	_clock += delta
	if state.phase != MatchState.Phase.PLAYING and not rules.advantage.is_empty():
		rules.end_advantage("played_on")           # the ball went dead (goal, out of play, whistle): the advantage is over
	match state.phase:
		MatchState.Phase.KICKOFF:
			if walkout_left > 0.0:
				_step_walkout(delta)
			_step_kickoff(delta)
		MatchState.Phase.PLAYING:
			state.set_ball_position(ball.global_position.x, ball.global_position.z)
			state.tick(delta)
			_update_possession()
			rules.update(delta)
			if state.phase != MatchState.Phase.PLAYING:
				# Phase M4: a restart (ball out, foul, offside) stopped play inside `rules.update`. The AI must not run
				# this frame: it re-applied every player's last move after the restart had released them, and that move
				# then stayed on for the whole pause — players walked off the pitch and the taker pushed the ball out
				# again (measured: endless throw-in loops, up to 223 player-samples off the pitch per match).
				_reset_ai_commands()
			else:
				replay_buffer.tick(delta, _sample_bodies)
				if advanced != null:
					advanced.update(delta)
				if _possession_side != "":
					state.record_possession(_possession_side, delta)
				_update_ai(delta)
				_update_stamina(delta)
				_sample_heat(delta)
				_update_managers(delta)
		MatchState.Phase.HALF_TIME:
			_step_half_time(delta)
		MatchState.Phase.FINISHED:
			_finish()
	crowd.consume(state.events, "home")
	crowd.update(delta)
	if state.events.size() != _commentary_events:
		_commentary_events = state.events.size()
		commentary.consume(state.events, _player_names(), get_node_or_null("/root/Loc"))
	commentary.update(delta)
	_update_presentation(delta)
	_update_pass_marker()
	_update_hud()


func _step_kickoff(delta: float) -> void:
	_pause_left -= delta
	if _pause_left > 0.0:
		return
	if _needs_reset:
		_place_team("home")
		_place_team("away")
		ball.reset_ball(Vector3(0.0, 0.3, 0.0))
		_needs_reset = false
		_pause_left = 1.0
	else:
		state.kick_off()


## Play stopped: every AI player stands still with no pending command or kick, and thinks afresh on the restart.
func _reset_ai_commands() -> void:
	incoming_pass = {}
	for side in entries:
		for e in entries[side]:
			e["cmd"] = {}
			e["charging"] = &""
			e["think"] = 0.0
			if e["ai"] != null:
				(e["ai"] as AIIntent).release_all()


## An assisted human pass was played towards `target`: the team-mate standing there becomes the ball's intended
## receiver, so his AI runs onto it exactly as for an AI pass (Phase M1).
func note_human_pass(side: String, slot: int, target: Vector3) -> void:
	if target == Vector3.INF:
		return
	var passer: Dictionary = {}
	var best: Dictionary = {}
	var best_d := 2.0
	for e in entries[side]:
		if int(e["slot"]) == slot:
			passer = e
			continue
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - target.x, p.z - target.z).length()
		if d < best_d:
			best_d = d
			best = e
	if not best.is_empty() and not passer.is_empty() and passer["ai"] == null:
		incoming_pass = {"receiver_id": best["player_id"], "passer_id": passer["player_id"], "t": _clock}


## Position samples for the heat maps: every MatchStats.HEAT_INTERVAL seconds of play, one sample per player on the pitch.
func _sample_heat(delta: float) -> void:
	_heat_timer += delta
	if _heat_timer < MatchStats.HEAT_INTERVAL:
		return
	_heat_timer = fmod(_heat_timer, MatchStats.HEAT_INTERVAL)
	for side in entries:
		for e in entries[side]:
			if rules.sent_off.has(e["player_id"]):
				continue
			var pos := (e["node"] as Node3D).global_position
			state.stats.add_heat(e["player_id"], side, pos.x, pos.z, state.half)


## Snapshot of the running match (see `MatchSnapshot` and `MatchSave`).
func capture() -> Dictionary:
	return MatchSnapshot.capture(self)


## Saves to `path` (atomic, keeps a .bak). Returns "" or an error text.
func save_match(path: String = MatchSave.DEFAULT_PATH) -> String:
	if state == null or state.phase == MatchState.Phase.FINISHED or state.result_processed:
		return Loc.t("MATCH_SAVE_FINISHED")
	return MatchSave.write(capture(), path)


## Rebuilds the match from a validated save (`MatchSave.read`); call in place of `begin()`.
func restore(data: Dictionary, p_db: Node) -> String:
	return MatchSnapshot.restore(self, data, p_db)


func skip_replay() -> void:
	if replay_player != null and replay_player.playing:
		replay_player.skip()


## A level knockout match: the shoot-out is played on the pitch (`PenaltyDuel`).
func _start_shootout() -> void:
	penalty_duel = PenaltyDuel.new(self)
	add_child(penalty_duel)
	penalty_duel.finished.connect(func(h: int, a: int) -> void:
		state.forced_pens = [h, a]
		_shootout_done = true)
	penalty_duel.begin()
	if camera != null and camera.has_method("set_mode"):
		camera.set_mode(GameCamera.Mode.BROADCAST)    # the TV camera follows the ball to the goal


func _finish() -> void:
	if _finished_emitted:
		return
	if penalty_duel != null and penalty_duel.active():
		return                                    # the shoot-out is still being played
	if not _shootout_done and setup.knockout and int(state.score["home"]) == int(state.score["away"]) \
			and (setup.human_side != "none" or force_3d_shootout):
		_start_shootout()
		return
	_finished_emitted = true
	var home_rating: int = db.get_team_rating(setup.home_id)
	var away_rating: int = db.get_team_rating(setup.away_id)
	var result := state.to_result(setup.knockout, _rng, home_rating, away_rating)
	# Match fatigue carries over to the next game.
	for side in entries:
		for e in entries[side]:
			var pd: PlayerData = e["pdata"]
			var lost := int((100.0 - float(state.stamina.get(e["player_id"], 100.0))) * 0.4)
			pd.fitness = clampi(pd.fitness - lost, 30, 100)
			pd.experience += 1
	state.result_processed = true
	report = MatchReport.build(state, db, setup.human_side, result)
	report["competition_id"] = setup.competition_id
	report["uid"] = state.uid
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set("last_match_report", report)       # BEFORE the signals: listeners read it
	match_finished.emit(result)
	if gm != null:
		gm.set("last_match_result", result)
		if gm.has_signal("match_finished"):
			gm.emit_signal("match_finished", result)
	_show_results()


func _show_results() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if _hud_layer != null:
		_hud_layer.visible = false
	results_view = MatchMenus.show_results(self, report, db)


func _on_results_continue() -> void:
	results_closed.emit()
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.return_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if replay_player != null and replay_player.playing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("pass")):
		skip_replay()
		return
	if walkout_left > 0.0 and (event.is_action_pressed("ui_accept") or event.is_action_pressed("pass")):
		end_walkout()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and pause_menu == null and results_view == null \
			and state != null and state.phase != MatchState.Phase.FINISHED:
		get_viewport().set_input_as_handled()
		pause_match()


func is_paused() -> bool:
	return pause_menu != null


## True while a second human controls a player.
func seat2_active() -> bool:
	return not selected2.is_empty()


## Abandons this run and starts the same match again from kick-off. No result is recorded.
func restart_match() -> void:
	abandoned = true
	var fresh := MatchSetup.from_dict(initial_setup_dict)
	get_tree().paused = false
	restart_requested.emit(fresh)
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.start_configured_match(fresh)


## Leaves the match without a result (a competition fixture stays pending).
func quit_match() -> void:
	abandoned = true
	get_tree().paused = false
	quit_requested.emit()
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.return_to_menu()


## Which side a controller seat drives. Seat 0 = the human side of MatchSetup, seat 1 = its
## opponent (versus play — the same mapping `seat2_side()` uses). "" for an unknown seat.
func controller_side_for_slot(slot: int) -> String:
	if slot == 0 and setup != null and setup.human_side in ["home", "away"]:
		return setup.human_side
	if slot == 1:
		return seat2_side()
	return ""


## Team id + display name per side, read straight from `sides` and the database.
func controller_side_info() -> Dictionary:
	var out: Dictionary = {}
	for side in ["home", "away"]:
		if not sides.has(side):
			continue
		var data: Dictionary = sides[side]
		var info: Dictionary = {"side": side, "id": str(data.get("team_id", "")), "name": ""}
		var team: TeamData = db.get_team(str(data.get("team_id", ""))) \
				if db != null and db.has_method("get_team") else null
		if team != null:
			info["name"] = team.display_name
		out[side] = info
	return out


## Read-only view of a side's live tactics (the values a phone Tactics page would show).
func controller_tactical_state(side: String) -> Dictionary:
	if not sides.has(side):
		return {}
	var preset: TacticsPreset = sides[side].get("tactics")
	if preset == null:
		return {}
	return {"formation": str(sides[side].get("formation", "")), "mentality": preset.mentality,
			"pressing": preset.pressing, "defensive_line": preset.defensive_line,
			"build_up": preset.build_up, "passing_style": preset.passing_style,
			"width": preset.width, "preset_name": preset.preset_name}


## Applies a tactical value from a controller. Returns "" on success, else a reason code.
## Keys: formation, mentality, build_up, passing_style, preset_name (string values);
## pressing, defensive_line, width (0..100 integers). No team name is ever accepted.
func controller_apply_tactic(side: String, key: String, value: Variant) -> String:
	if not sides.has(side):
		return "unknown_side"
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return "finished"
	var preset: TacticsPreset = sides[side].get("tactics")
	if preset == null:
		return "no_tactics"
	match key:
		"formation":
			if typeof(value) != TYPE_STRING or String(value).length() == 0 or String(value).length() > 24:
				return "bad_value"
			sides[side]["formation"] = String(value)
			return ""
		"mentality":
			if typeof(value) != TYPE_STRING or not (String(value) in ["defensive", "balanced", "attacking"]):
				return "bad_value"
			preset.mentality = {"defensive": 0, "balanced": 1, "attacking": 2}[String(value)]
			return ""
		"build_up":
			if typeof(value) != TYPE_STRING or not (String(value) in ["short", "mixed", "long"]):
				return "bad_value"
			preset.build_up = {"short": 0, "mixed": 1, "long": 2}[String(value)]
			return ""
		"passing_style":
			if typeof(value) != TYPE_STRING or not (String(value) in ["safe", "balanced", "risky"]):
				return "bad_value"
			preset.passing_style = {"safe": 0, "balanced": 1, "risky": 2}[String(value)]
			return ""
		"preset_name":
			if typeof(value) != TYPE_STRING or String(value).length() > 24:
				return "bad_value"
			preset.preset_name = String(value)
			return ""
		"pressing", "defensive_line", "width":
			if not (value is int or value is float):
				return "bad_value"
			var iv := clampi(int(value), 0, 100)
			if key == "pressing":
				preset.pressing = iv
			elif key == "defensive_line":
				preset.defensive_line = iv
			else:
				preset.width = iv
			return ""
		_:
			return "unknown_key"


## Substitution from a controller. slot = on-pitch slot, player_id = bench player id.
func controller_substitute(side: String, slot: int, player_id: String) -> String:
	if not sides.has(side):
		return "unknown_side"
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return "finished"
	if state != null and int(state.subs_used[side]) >= ManagerAI.MAX_SUBS:
		return "no_subs_left"
	var squad = sides[side].get("squad")
	if squad == null:
		return "no_squad"
	var out_pid: String = ""
	var entries_side: Array = entries.get(side, [])
	for e in entries_side:
		if int(e.get("slot", -1)) == slot:
			out_pid = str(e.get("player_id", ""))
			break
	if out_pid == "":
		return "no_player_in_slot"
	if out_pid == player_id:
		return "same_player"
	var reason: String = squad.substitute(db, slot, player_id)
	if reason != "":
		return reason
	var pdata: PlayerData = db.get_player(player_id) if db != null and db.has_method("get_player") else null
	_swap_player(side, slot, player_id)
	if pdata != null:
		for e in entries_side:
			if int(e.get("slot", -1)) == slot:
				e["pdata"] = pdata
				e["mods"] = AttributeModifiers.new(pdata)
				break
	state.stamina[player_id] = 100.0
	state.record_substitution(side, out_pid, player_id)
	return ""


## Player display name from the database, or "" when unknown (never a made-up name).
func controller_player_name(player_id: String) -> String:
	if player_id == "" or db == null or not db.has_method("get_player"):
		return ""
	var pdata: PlayerData = db.get_player(player_id)
	return pdata.display_name if pdata != null else ""
