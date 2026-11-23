extends "res://scripts/systems/match/match_manager_part1.gd"

## Match manager, part 2 of 3 (split Nov 2026; the class is `MatchManager` in match_manager. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: begin, simulate_rest, _apply_resume, walkout_active, _step_walkout, end_walkout, _update_presentation,
## _human_kit_color, _entry_id, _dress, _kickoff_position, _place_team, _player_names, switch_player, _auto_switch,
## _step_half_time, _update_pass_marker, _owner_entry, _update_possession, _update_stamina, _update_managers,
## _manager_difficulty, _swap_player, _sample_bodies, switch_player2, _auto_switch2.

## Builds the match. Returns "" or an error text (nothing is spawned on error).
func begin(p_setup: MatchSetup, p_db: Node) -> String:
	var problems := p_setup.validate(p_db)
	if not problems.is_empty():
		return problems[0]
	db = p_db
	# The match plays on its OWN copy of the squads: manager-AI substitutions must never rewrite the
	# career's lineups. `initial_setup_dict` keeps the kick-off state for restarts and saves.
	setup = p_setup.duplicate_for_match(p_db)
	initial_setup_dict = setup.to_dict().duplicate(true)      # deep: the live squads are mutated later
	_rng.seed = setup.rng_seed
	state = MatchState.create(setup.home_id, setup.away_id, setup.duration_minutes, setup.match_id)
	state.uid = "mu_%d_%d" % [int(Time.get_unix_time_from_system()), setup.rng_seed]
	for side in ["home", "away"]:
		sides[side] = setup.build_side(db, side)
	# P3: one aim assist for the human side, fed from the live match state via
	# a bound Callable (dependency injection — the assist never reaches into
	# the manager). AI players keep their own context and are untouched.
	_assist = HumanAimAssist.new()
	_assist.context = _aim_context.bind(setup.human_side)
	rules = MatchRules.new(self)
	advanced = AdvancedPlay.new(self, setup.rng_seed)
	aerial = AerialArbiter.new()
	aerial.name = "AerialArbiter"
	aerial.rng.seed = hash("aerial:%d" % setup.rng_seed)
	add_child(aerial)
	_build_arena()
	MatchEnvironment.apply(arena_root, setup.conditions)
	replay_buffer = ReplayBuffer.new(23, 10.0)
	var home_rep: int = db.get_team(setup.home_id).reputation
	crowd = CrowdSystem.new(clampf(0.55 + float(home_rep) / 250.0, 0.3, 1.0), 1.3 if setup.knockout else 1.0)
	if DisplayServer.get_name() != "headless":
		if MatchSounds.available():
			_sounds = MatchSounds.new()
			_sounds.crowd = crowd
			_sounds.state = state
			add_child(_sounds)
		else:
			_crowd_audio = CrowdAudio.new()             # no recorded files: the synthesized bed
			_crowd_audio.crowd = crowd
			add_child(_crowd_audio)
	_spawn_ball()
	for side in ["home", "away"]:
		_spawn_team(side)
	referee = MatchReferee.new()
	add_child(referee)
	referee.global_position = Vector3(-6.0, 0.0, 8.0)
	stand_crowd = StandCrowd.new()
	add_child(stand_crowd)        # filled on the first physics tick (needs the stadium collision)
	var ids: Array = []
	for side in ["home", "away"]:
		for e in entries[side]:
			ids.append(e["player_id"])
	state.init_stamina(ids)
	for side in ["home", "away"]:
		state.register_players(side, entries[side].map(func(e: Dictionary) -> String: return e["player_id"]))
	_build_hud()
	debug_tools = MatchDebugTools.new(self)
	add_child(debug_tools)
	radar = MatchRadar.new(self)                         # Phase H1
	_hud_layer.add_child(radar)
	if hud != null and setup.competition_id != "":
		var hub := get_node_or_null("/root/AppHub")
		hud.set_competition(str(hub.competition_title(setup.competition_id)) if hub != null and hub.career != null else setup.competition_id)
	aim_assist_enabled = bool(GameSettings.get_value("controls", "aim_assist"))
	if setup.human_side != "none":
		var mode := setup.switch_mode if setup.switch_mode in GameSettings.SWITCH_MODES \
				else str(GameSettings.get_value("match", "switch_mode"))
		switch_policy = AutoSwitchPolicy.new(mode, setup.human_side)
		selection_indicator = SelectionIndicator.new(0, _human_kit_color())
		_select(_closest_to_ball(setup.human_side, -1))
		if camera != null and camera.has_method("set_mode") and str(GameSettings.get_value("match", "camera")) == "follow":
			camera.set_mode(GameCamera.Mode.FOLLOW)
	if camera != null and camera.has_method("track_ball"):
		camera.track_ball(ball)
	if setup.walkout:
		_start_walkout()
	_apply_resume()
	_seat_ready = true
	_sync_seat2()                    # a second phone that paired before the match starts playing at once
	return ""


## Phase S2 (the other direction): "simulate the rest" — the event engine plays the remaining minutes from the current score
## and the match ends at once (goals are logged with their scorers, the normal full-time flow follows).
func simulate_rest() -> void:
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return
	var minute := int(state.display_minute())
	var live := MatchEventEngine.LiveMatch.new(db, setup.home_id, setup.away_id, setup.rng_seed + minute)
	live.minute = minute
	live.weather = str(setup.conditions.get("weather", "clear"))
	live.score = {"home": int(state.score["home"]), "away": int(state.score["away"])}
	var before: Dictionary = live.score.duplicate()
	while not live.finished():
		for ev in live.step():
			if str(ev["type"]) == "goal":
				state.stats.register_player(str(ev["player_id"]), str(ev["side"]))
				state.stats.players[str(ev["player_id"])]["goals"] += 1
				state.stats.teams[str(ev["side"])]["shots"] += 1
				state.stats.teams[str(ev["side"])]["on_target"] += 1
				state.log_event({"minute": float(ev["minute"]), "type": "goal", "side": str(ev["side"]), "player_id": str(ev["player_id"]),
						"assist_id": str(ev["assist_id"]), "own_goal": false})
	state.score = {"home": int(live.score["home"]), "away": int(live.score["away"])}
	state.elapsed = state.duration_seconds
	state.phase = MatchState.Phase.FINISHED
	if get_tree().paused:
		resume_match()


## Phase S2 "play from this minute": takes the minute, score, cards and goals of a live simulation (`AppHub.pending_resume`).
func _apply_resume() -> void:
	var hub := get_node_or_null("/root/AppHub")
	if hub == null or (hub.pending_resume as Dictionary).is_empty():
		return
	var r: Dictionary = hub.pending_resume
	hub.pending_resume = {}
	var minute := clampi(int(r.get("minute", 0)), 0, 89)
	state.elapsed = float(minute) / MatchState.DISPLAY_MINUTES * state.duration_seconds
	for side in ["home", "away"]:
		state.score[side] = int((r.get("score", {}) as Dictionary).get(side, 0))
		for k in ["shots", "on_target", "corners", "fouls", "yellows", "reds"]:
			if state.stats.teams[side].has(k) and (r.get("stats", {}) as Dictionary).has(side):
				state.stats.teams[side][k] = int(r["stats"][side].get(k, 0))
	state.stats.teams["home"]["possession"] = float(r.get("stats", {}).get("home", {}).get("possession", 50))
	state.stats.teams["away"]["possession"] = float(r.get("stats", {}).get("away", {}).get("possession", 50))
	for ev in r.get("events", []):
		if str(ev.get("type", "")) == "goal":
			var sc := str(ev["player_id"])
			state.stats.register_player(sc, str(ev["side"]))
			state.stats.players[sc]["goals"] += 1
			if str(ev.get("assist_id", "")) != "":
				state.stats.register_player(str(ev["assist_id"]), str(ev["side"]))
				state.stats.players[str(ev["assist_id"])]["assists"] += 1
			state.log_event({"minute": float(ev["minute"]), "type": "goal", "side": str(ev["side"]), "player_id": sc, "assist_id": str(ev.get("assist_id", "")), "own_goal": false})
	if minute >= 45:
		state.half = 2
		state.phase = MatchState.Phase.KICKOFF
		_needs_reset = true


func walkout_active() -> bool:
	return walkout_left > 0.0


func _step_walkout(delta: float) -> void:
	MatchWalkout.step(self, delta)


## Ends the walk-out (time up or skipped).
func end_walkout() -> void:
	MatchWalkout.finish(self)


## Referee, spectators (see `MatchPresentation`).
func _update_presentation(delta: float) -> void:
	MatchPresentation.update(self, delta)


func _human_kit_color() -> Color:
	return MatchPresentation.human_kit_color(self)


func _entry_id(side: String, slot: int) -> String:
	return MatchTeamBuilder.entry_id(self, side, slot)


func _dress(node: Node, pdata: PlayerData, kit: TeamKit, slot: int) -> void:
	MatchTeamBuilder.dress(self, node, pdata, kit, slot)


func _kickoff_position(side: String, slot: int) -> Vector3:
	var data: Dictionary = sides[side]
	var rel: Vector2 = (data["tactics"] as TacticsPreset).target_position(data["formation"], slot, 0.5)
	rel.y = minf(rel.y, 0.46)                 # everybody in their own half
	return PitchSpace.to_world(rel, frame_side(side))


func _place_team(side: String, face_forward: bool = false) -> void:
	for e in entries[side]:
		var node: CharacterBody3D = e["node"]
		var pos := _kickoff_position(side, e["slot"]) + Vector3(0.0, 0.05, 0.0)
		var facing_z := 1.0 if frame_side(side) == "away" else -1.0     # direction of attack
		if node is TeamGoalkeeper:
			(node as TeamGoalkeeper).reset_to(pos, facing_z)
			continue
		node.global_position = pos
		node.velocity = Vector3.ZERO
		node.rotation.y = PI if facing_z > 0.0 else 0.0                 # face the opponent's goal
		if e["ai"] != null:               # null = human-controlled slot
			(e["ai"] as AIIntent).release_all()


## player_id -> display name for everyone on the pitch or the bench entries (commentary text).
func _player_names() -> Dictionary:
	var out := {}
	for side in ["home", "away"]:
		for e in entries[side]:
			if e.has("pdata") and e["pdata"] != null:
				out[str(e["player_id"])] = (e["pdata"] as PlayerData).display_name
	return out


## Hands control to the human-side player closest to the ball.
func switch_player() -> void:
	if setup.human_side == "none" or selected.is_empty():
		return
	var cur_acts := selected.get("actions") as FootballActions
	if cur_acts != null and cur_acts.is_charging():
		return                                   # Phase M6: no switch while a pass / shot is being charged
	var next := _closest_to_ball(setup.human_side, selected["slot"])
	if not next.is_empty():
		_select(next)
		if switch_policy != null:
			switch_policy.note_switch(_clock)


## Automatic switch after a change of ball owner (see `AutoSwitchPolicy`).
func _auto_switch(owner: Dictionary) -> void:
	if switch_policy == null or selected.is_empty():
		return
	var acts := selected.get("actions") as FootballActions
	var charging := acts != null and acts.is_charging()
	match switch_policy.on_owner(owner, str(selected["player_id"]), charging, _clock):
		"receiver":
			_select(owner)
		"closest":
			var next := _closest_to_ball(setup.human_side, -1)
			if not next.is_empty() and next != selected:
				_select(next)


func _step_half_time(delta: float) -> void:
	if not _half_handled:
		_half_handled = true
		_pause_left = HALF_TIME_PAUSE
		for side in entries:
			for e in entries[side]:
				if e["ai"] != null:
					(e["ai"] as AIIntent).release_all()
	_pause_left -= delta
	if _pause_left <= 0.0:
		state.start_second_half()
		_half_handled = false
		_needs_reset = true
		_pause_left = 0.5


## While the human holds the pass button, the ring marks the team-mate the pass will go to (Phase M1).
func _update_pass_marker() -> void:
	if selected.is_empty() or _assist == null or not aim_assist_enabled:
		if pass_marker != null:
			pass_marker.show_on(null)
		return
	var acts := selected.get("actions") as FootballActions
	if acts == null or acts.get_charge_ratio(&"pass") <= 0.0 and not human_intent.is_pressed(&"pass"):
		if pass_marker != null:
			pass_marker.show_on(null)
		return
	if pass_marker == null:
		pass_marker = PassTargetMarker.new()
		add_child(pass_marker)
	var stick := human_intent.move_vector()
	var origin := (selected["node"] as Node3D).global_position
	var t := _assist.pass_target(origin, acts._input_to_world_dir(stick) if stick != Vector2.ZERO else Vector3.ZERO)
	var body: Node3D = null
	if not t.is_empty():
		var best_d := 1.0
		for e in entries[setup.human_side]:
			var p := (e["node"] as Node3D).global_position
			var d := Vector2(p.x - (t["pos"] as Vector3).x, p.z - (t["pos"] as Vector3).z).length()
			if d < best_d:
				best_d = d
				body = e["node"]
	pass_marker.show_on(body)


func _owner_entry() -> Dictionary:
	var best: Dictionary = {}
	var best_d := POSSESSION_RADIUS
	var bp := ball.global_position
	var bv := Vector2(ball.linear_velocity.x, ball.linear_velocity.z)
	for side in entries:
		for e in entries[side]:
			var n := e["node"] as CharacterBody3D
			var d := Vector2(n.global_position.x - bp.x, n.global_position.z - bp.z).length()
			if d >= best_d:
				continue
			if d > FAST_BALL_RADIUS and (bv - Vector2(n.velocity.x, n.velocity.z)).length() > FAST_BALL:
				continue
			best_d = d
			best = e
	return best


func _update_possession() -> void:
	var owner := _owner_entry()
	if not owner.is_empty():
		if owner["player_id"] != last_toucher_id:
			state.record_owner(owner["side"], owner["player_id"], int(owner["slot"]) == 0)
			rules.restarts.on_owner(owner)
			_auto_switch(owner)
			_auto_switch2(owner)
		last_toucher_id = owner["player_id"]
		_possession_side = owner["side"]


func _update_stamina(delta: float) -> void:
	for side in entries:
		for e in entries[side]:
			var ratio: float
			if e["node"] is PlayerController:
				var node: PlayerController = e["node"]
				ratio = node.get_current_speed() / maxf(node.config.sprint_speed, 0.1)
			else:
				ratio = (e["node"] as CharacterBody3D).velocity.length() / KEEPER_SPRINT_SPEED
			var pd: PlayerData = e["pdata"]
			state.drain_stamina(e["player_id"], delta, ratio, pd.physical)


func _update_managers(delta: float) -> void:
	_manager_timer += delta
	if _manager_timer < MANAGER_INTERVAL:
		return
	_manager_timer = 0.0
	for side in ["home", "away"]:
		var data: Dictionary = sides[side]
		var orders := ManagerAI.decide(state, side, data["squad"], data["tactics"], db, _manager_difficulty(side))
		if orders.is_empty():
			continue
		var subs := ManagerAI.apply(orders, side, state, data["squad"], data["tactics"], db)
		for o in subs:
			_swap_player(side, o["slot"], o["in_id"])


## The AI manager of the human's opponent plays at the match difficulty; the human's own side is not auto-managed
## beyond what it already did (normal).
func _manager_difficulty(side: String) -> int:
	return setup.difficulty if side != setup.human_side else 1


## Replaces the on-pitch player in `slot` with a new squad member (substitution).
func _swap_player(side: String, slot: int, new_player_id: String) -> void:
	for e in entries[side]:
		if e["slot"] == slot:
			var pdata: PlayerData = db.get_player(new_player_id)
			e["player_id"] = new_player_id
			e["pdata"] = pdata
			e["mods"] = AttributeModifiers.new(pdata)
			_dress(e["node"], pdata, e["kit"], slot)          # new shirt number and look
			if e["node"] is TeamGoalkeeper:
				(e["node"] as TeamGoalkeeper).attribute_modifiers = e["mods"]
			else:
				(e["node"] as PlayerController).attribute_modifiers = e["mods"]
				(e["actions"] as FootballActions).attribute_modifiers = e["mods"]
			return


## Ball first, then the home players, then the away players: x, y, z and facing of each.
func _sample_bodies() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var bp := ball.global_position
	out.append_array(PackedFloat32Array([bp.x, bp.y, bp.z, 0.0]))
	for side in ["home", "away"]:
		for e in entries[side]:
			var n := e["node"] as Node3D
			var p := n.global_position
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, n.global_rotation.y]))
	return out


func switch_player2() -> void:
	if selected2.is_empty():
		return
	var next := _closest_to_ball(seat2_side(), selected2["slot"])
	if not next.is_empty():
		_select2(next)
		if switch_policy2 != null:
			switch_policy2.note_switch(_clock)


func _auto_switch2(owner: Dictionary) -> void:
	if switch_policy2 == null or selected2.is_empty():
		return
	var acts := selected2.get("actions") as FootballActions
	var charging := acts != null and acts.is_charging()
	match switch_policy2.on_owner(owner, str(selected2["player_id"]), charging, _clock):
		"receiver":
			_select2(owner)
		"closest":
			var next := _closest_to_ball(seat2_side(), -1)
			if not next.is_empty() and next != selected2:
				_select2(next)
