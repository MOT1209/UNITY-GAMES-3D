## Match content validation (UX phase 6): defensive wall at free kicks, the referee on the pitch,
## animated spectators that react to goals.
##   godot --headless --path . res://tests/match_content_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Match content validation ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	var m := _match()
	await _frames(3)
	await _test_wall(m)
	await _test_referee(m)
	await _test_crowd(m)
	await _test_throw_in(m)
	await _test_replay_angles(m)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame
	await _test_walkout()
	_test_shootout_rules()
	await _test_shootout_in_3d()
	await _test_human_penalty()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _match(walkout := false, knockout := false, human := "none") -> MatchManager:
	var setup := MatchSetup.new()
	setup.walkout = walkout
	setup.knockout = knockout
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 10
	setup.human_side = human
	setup.rng_seed = 4
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	if walkout:
		return m
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	return m


func _test_wall(m: MatchManager) -> void:
	var goal := PitchSpace.opponent_goal(m.frame_side("home"))
	var spot := Vector3(4.0, 0.3, goal.z - signf(goal.z) * 22.0)
	m.rules.restart_from(spot, "home", "free_kick")
	var wall: Array = m.rules.last_wall
	_check(wall.size() == 4, "a free kick 22 m out gets a 4-man wall", str(wall.size()))
	var ok := true
	var to_goal := Vector3(goal.x - spot.x, 0.0, goal.z - spot.z).normalized()
	for e in m.entries["away"]:
		if e["player_id"] in wall:
			var p := (e["node"] as Node3D).global_position
			var d := Vector2(p.x - spot.x, p.z - spot.z).length()
			var ahead := Vector3(p.x - spot.x, 0.0, p.z - spot.z).normalized().dot(to_goal)
			ok = ok and d >= MatchRules.WALL_DISTANCE - 0.05 and d <= MatchRules.WALL_DISTANCE + 1.5 and ahead > 0.9
	_check(ok, "the wall stands 9.15 m from the ball, between ball and goal")
	m.rules.restart_from(Vector3(0.0, 0.3, 0.0), "home", "free_kick")
	_check(m.rules.last_wall.is_empty(), "no wall for a free kick in midfield")
	m.rules.restart_from(spot, "home", "corner")
	_check(m.rules.last_wall.is_empty(), "no wall at corners")
	m.state.phase = MatchState.Phase.PLAYING


func _test_referee(m: MatchManager) -> void:
	var ref := m.referee
	_check(ref != null and ref.model != null, "the referee model is on the pitch")
	_check(ref.find_children("*", "CollisionObject3D", true, false).is_empty(), "the referee has no collision (can never block ball or players)")
	var w := MatchReferee.wanted_position(Vector3(30.0, 0.0, 50.0))
	_check(absf(w.x) <= PitchSpace.HALF_WIDTH and absf(w.z) <= PitchSpace.HALF_LENGTH, "the wanted spot stays inside the pitch", str(w))
	m.ball.reset_ball(Vector3(-20.0, 0.3, 30.0))
	var target := MatchReferee.wanted_position(m.ball.global_position)
	var before := ref.global_position.distance_to(target)
	await _frames(40)
	var after := ref.global_position.distance_to(MatchReferee.wanted_position(m.ball.global_position))
	_check(after < before - 3.0, "the referee follows play", "%.1f -> %.1f m" % [before, after])
	_check(ref.current_animation() in ["Run", "Walk"], "and runs / walks while doing so", ref.current_animation())
	ref.gesture("card")
	_check(ref.current_animation() == "ShowCard", "bookings: card gesture")


func _test_crowd(m: MatchManager) -> void:
	var c := m.stand_crowd
	_check(c != null and c.built and c.spectators > 500, "spectators fill the stands", str(c.spectators if c != null else -1))
	var bad: Array = []
	for i in mini(c.spectators, 200):
		var p := c.positions[i]
		if not ((absf(p.x) > StandCrowd.PITCH_KEEP_OUT.x - 0.3 or absf(p.z) > StandCrowd.PITCH_KEEP_OUT.y - 0.3) and p.y > 0.5):
			bad.append(p)
	_check(bad.is_empty(), "nobody stands on the pitch: every spectator is on the stand steps", str(bad.slice(0, 3)))
	m.crowd.mood = "calm"
	m.crowd.excitement = 0.0
	await _frames(2)
	var calm := c.excitement()
	m.state.goal("home", "")
	await _frames(3)
	_check(c.excitement() > calm + 0.3, "the crowd jumps after a home goal", "%.2f -> %.2f" % [calm, c.excitement()])


func _test_throw_in(m: MatchManager) -> void:
	var taker: Dictionary = m.entries["home"][5]
	m.rules.restart_from(Vector3(PitchSpace.HALF_WIDTH, 0.3, 10.0), "home", "throw_in", taker)
	var vis := (taker["node"] as Node).get_node_or_null("VisualRoot") as PlayerCharacterVisual
	var anim := vis.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer if vis != null else null
	_check(m.rules.last_throw_animated and anim != null and anim.current_animation == "ThrowIn",
			"the throw-in taker throws with both hands over the head (ThrowIn clip)", anim.current_animation if anim != null else "")
	var to_pitch := Vector3(-1, 0, 0)
	var facing := -(taker["node"] as Node3D).global_transform.basis.z
	_check(facing.dot(to_pitch) > 0.8, "and faces the pitch")
	m.state.phase = MatchState.Phase.PLAYING
	await _frames(2)


func _test_replay_angles(m: MatchManager) -> void:
	await _frames(40)                       # fill the replay buffer with real play
	var before := get_viewport().get_camera_3d()
	m.ball.reset_ball(Vector3(2.0, 0.3, PitchSpace.HALF_LENGTH - 2.0))
	m._start_goal_replay()
	var d := m.replay_director
	_check(d != null and d.current, "the goal replay takes over the view")
	var seen := {}
	var dur := float(m.replay_player.clip_data.get("duration", 1.0))
	for i in 12:
		m.replay_player.advance(dur / m.replay_player.speed / 12.0 * 0.95)
		d._update()
		seen[d.angle] = true
	_check(seen.size() == 3 and d.cuts >= 2, "it cuts between three angles (TV, behind the goal, close-up)", str(seen.keys()))
	m.replay_player.skip()
	await get_tree().process_frame
	_check(not d.current and (before == null or before.current), "after the replay the match camera is back")


func _test_walkout() -> void:
	var m := _match(true, false, "home")
	await _frames(2)
	var lined := 0
	for side in m.entries:
		for e in m.entries[side]:
			if (e["node"] as Node3D).global_position.x < -PitchSpace.HALF_WIDTH + 16.0:
				lined += 1
	_check(m.walkout_active() and lined >= 20, "the teams line up by the touchline for the walk-out", str(lined))
	var dist_before := _distance_to_spots(m)
	await _frames(120)
	_check(_distance_to_spots(m) < dist_before - 20.0, "they walk towards their kick-off positions",
			"%.0f -> %.0f m (all players)" % [dist_before, _distance_to_spots(m)])
	_check(m.state.phase == MatchState.Phase.KICKOFF, "no kick-off during the walk-out")
	m.end_walkout()
	await _frames(2)
	_check(not m.walkout_active() and m.selected["node"].intent == m.human_intent, "skipping the walk-out gives the player his footballer back")
	await _frames(90)
	_check(m.state.phase == MatchState.Phase.PLAYING, "and the match kicks off")
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _distance_to_spots(m: MatchManager) -> float:
	var total := 0.0
	for side in m.entries:
		for e in m.entries[side]:
			if int(e["slot"]) != 0:
				total += (e["node"] as Node3D).global_position.distance_to(m._kickoff_position(side, int(e["slot"])))
	return total


func _test_shootout_rules() -> void:
	_check(not PenaltyDuel.decided({"home": 3, "away": 2}, {"home": 3, "away": 3}), "3-2 after three kicks each: not decided")
	_check(PenaltyDuel.decided({"home": 3, "away": 0}, {"home": 3, "away": 3}), "3-0 after three each: away cannot catch up")
	_check(PenaltyDuel.decided({"home": 4, "away": 2}, {"home": 5, "away": 4}), "4-2 with one away kick left: decided early")
	_check(not PenaltyDuel.decided({"home": 4, "away": 4}, {"home": 5, "away": 5}), "4-4 after five each: sudden death")
	_check(PenaltyDuel.decided({"home": 5, "away": 4}, {"home": 6, "away": 6}), "sudden death: decided when one misses and the other scores")
	_check(not PenaltyDuel.decided({"home": 5, "away": 4}, {"home": 6, "away": 5}), "sudden death waits for the second kick of the pair")


func _test_shootout_in_3d() -> void:
	var m := _match(false, true, "none")
	m.force_3d_shootout = true
	var results: Array = []
	m.match_finished.connect(func(r: MatchResult) -> void: results.append(r))
	m.state.half = 2
	m.state.elapsed = m.state.duration_seconds - 0.01
	var started := false
	for i in 4000:
		await get_tree().physics_frame
		if m.penalty_duel != null:
			started = true
		if not results.is_empty():
			break
	var duel := m.penalty_duel
	_check(started and duel != null, "a level knockout match goes to a shoot-out on the pitch")
	if duel == null:
		return
	var keepers_apart := (m.entries["home"][0]["node"] as Node3D).global_position.distance_to((m.entries["away"][0]["node"] as Node3D).global_position) > 60.0
	_check(keepers_apart, "the waiting goalkeeper stands in the other goal, not next to the one facing the kick")
	_check(not results.is_empty(), "the shoot-out finishes the match", "kicks %d, score %s" % [duel.kicks.size(), str(duel.score)])
	_check(duel.kicks.size() >= 6 and PenaltyDuel.decided(duel.score, duel.taken), "kicks were taken until the shoot-out was decided",
			"%d kicks, %s" % [duel.kicks.size(), str(duel.score)])
	_check(duel.kicks.any(func(k: Dictionary) -> bool: return k["side"] == "home") and duel.kicks.any(func(k: Dictionary) -> bool: return k["side"] == "away"),
			"both teams kick, alternating")
	if not results.is_empty():
		var r: MatchResult = results[0]
		_check(r.home_pens == int(duel.score["home"]) and r.away_pens == int(duel.score["away"]), "the result carries the shoot-out score",
				"%d-%d vs %s" % [r.home_pens, r.away_pens, str(duel.score)])
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _test_human_penalty() -> void:
	var m := _match(false, true, "home")
	m.state.half = 2
	m.state.elapsed = m.state.duration_seconds - 0.01
	for i in 30:
		await get_tree().physics_frame
		if m.penalty_duel != null:
			break
	var duel := m.penalty_duel
	_check(duel != null and duel.kicker_side == "home" and m.selected == duel._kicker, "the human takes his team's kick with his own player")
	if duel == null:
		return
	for i in 90:                                   # wait for the preparation, then shoot like in play
		await get_tree().physics_frame
		if duel.step == PenaltyDuel.Step.KICK:
			break
	m.human_intent.set_driven(true)
	m.human_intent.begin_tick()
	m.human_intent.set_move(Vector2(0.2, -1.0))
	m.human_intent.press(&"shoot")
	await get_tree().physics_frame
	m.human_intent.begin_tick()
	m.human_intent.set_move(Vector2.ZERO)          # tap-aim: direction on the press, then hold the button
	for i in 18:
		await get_tree().physics_frame
		m.human_intent.begin_tick()
	m.human_intent.release(&"shoot")
	for i in 400:
		await get_tree().physics_frame
		m.human_intent.begin_tick()
		if not duel.kicks.is_empty():
			break
	_check(not duel.kicks.is_empty() and duel.kicks[0]["side"] == "home", "the human's shot is taken and counted", str(duel.kicks))
	m.human_intent.set_driven(false)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame
