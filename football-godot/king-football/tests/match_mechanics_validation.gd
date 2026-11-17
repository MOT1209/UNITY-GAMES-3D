## Phase M (match repair) regression checks — each one pins a measured bug of the 3D match:
##   kick aim while planted, kicks adding the dribble velocity, the 47 rad/s spin ceiling (balls could not roll faster
##   than 5.2 m/s), the kicker's body blocking his own pass, fast balls "owned" by whoever they pass, the pass lane,
##   the human pass receiver (stick cone), pass pace, shot power / spread, ball tunnelling, dribbling, turn rate,
##   first-time passes in the statistics, the shape shuffle, targets on the pitch, F8 bug report / F9 debug view.
##   godot --headless --fixed-fps 60 --path . res://tests/match_mechanics_validation.tscn
extends Node

const BALL_SCENE := "res://scenes/ball/football_ball.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _passed := 0
var _failed := 0
var _env: Node3D


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s%s" % [name, (" — " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — match mechanics validation (Phase M) ===")
	_test_pure()
	await _test_strike_and_roll()
	await _test_kick_aim_and_self_block()
	await _test_shot_power()
	await _test_no_tunnelling()
	await _test_dribble()
	await _test_turn_rate()
	await _test_engine_hooks()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- helpers ----------------------------------------------------------------------------------------

func _new_env() -> void:
	if _env != null:
		_env.free()
	_env = Node3D.new()
	add_child(_env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	_env.add_child(ground)


func _ball(at: Vector3) -> BallController:
	var b: BallController = (load(BALL_SCENE) as PackedScene).instantiate()
	b.position = at
	_env.add_child(b)
	return b


func _player(at: Vector3) -> PlayerController:
	var p: PlayerController = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.position = at
	_env.add_child(p)
	var ai := AIIntent.new()
	p.intent = ai
	(p.get_node("BallActions") as FootballActions).intent = ai
	return p


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- pure functions ---------------------------------------------------------------------------------

func _test_pure() -> void:
	# pass lane (M1): an opponent on the line closes it, one well to the side does not
	var from := Vector3.ZERO
	var to := Vector3(0, 0, -20)
	_check(not PlayerAI.pass_lane_open(from, to, [Vector3(0.5, 0, -10)]), "pass lane: an opponent on the line blocks the pass")
	_check(PlayerAI.pass_lane_open(from, to, [Vector3(5.0, 0, -10)]), "pass lane: an opponent 5 m to the side does not")
	_check(not PlayerAI.pass_lane_open(from, to, [Vector3(0.6, 0, -0.5)]), "pass lane: a presser right at the ball blocks it (measured from the ball)")
	var ctx := {"pos": Vector3.ZERO, "ball": Vector3(0, 0, -0.5), "goal": Vector3(0, 0, -52.5), "teammates": [Vector3(0, 0, -18)],
			"opponents": [Vector3(0.4, 0, -9)], "profile": TacticsPreset.new().pass_profile()}
	_check(PlayerAI._best_pass_target(ctx) == Vector3.INF, "the AI does not pick a team-mate whose lane is blocked")
	ctx["opponents"] = [Vector3(6, 0, -9)]
	_check(PlayerAI._best_pass_target(ctx) == Vector3(0, 0, -18), "the AI picks him once the lane is open")
	# human pass receiver (M1): stick at a mate 20 m away at 25 degrees picks him, not a closer mate behind
	var assist := HumanAimAssist.new()
	var far_mate := Vector3(sin(deg_to_rad(25.0)) * 20.0, 0, -cos(deg_to_rad(25.0)) * 20.0)
	var near_behind := Vector3(2, 0, 6)
	assist.context = func() -> Dictionary: return {"teammates": [near_behind, far_mate], "opponents": [], "goal": Vector3(0, 0, -52.5)}
	var pick := assist.pass_target(Vector3.ZERO, Vector3(0, 0, -1))
	_check(not pick.is_empty() and int(pick["index"]) == 1, "human pass: stick ahead, mate 20 m at 25 deg is the receiver (not the closer one behind)", str(pick))
	var pick2 := assist.pass_target(Vector3.ZERO, near_behind.normalized())
	_check(not pick2.is_empty() and int(pick2["index"]) == 0, "human pass: stick towards the mate behind picks him")
	var near_ahead := Vector3(-3, 0, -8)
	assist.context = func() -> Dictionary: return {"teammates": [near_behind, near_ahead], "opponents": [Vector3(-3.5, 0, -8.5)], "goal": Vector3(0, 0, -52.5)}
	var free_pick := assist.pass_target(Vector3.ZERO, Vector3.ZERO)
	_check(free_pick.is_empty() or int(free_pick["index"]) != 1, "human pass without a direction: a tightly marked mate is not the first choice", str(free_pick))
	assist.context = func() -> Dictionary: return {"teammates": [near_behind, Vector3(4, 0, -15)], "opponents": [], "goal": Vector3(0, 0, -52.5)}
	var fwd := assist.pass_target(Vector3.ZERO, Vector3.ZERO)
	_check(not fwd.is_empty() and int(fwd["index"]) == 1, "human pass without a direction: the free option ahead")
	# pass pace fits the distance (M1)
	_check(FootballActions.assisted_pass_power(20.0) > FootballActions.assisted_pass_power(8.0) + 2.0, "pass pace grows with the distance")
	_check(absf(MatchAIDriver.pass_power_for(20.0) - FootballActions.assisted_pass_power(20.0)) < 0.01, "AI and human passes use the same pace rule")
	# receiver runs to the ball's line (M1)
	var mv := MatchAIDriver.receive_move(Vector3(3, 0, -10), Vector3(0, 0, 0), Vector3(0, 0, -10))
	_check(mv.x < -0.3, "the receiver steps across onto the ball's line", str(mv))
	# intents for the debug view
	_check(MatchAIDriver.intent_name(false, false, true, false, {}) == "CLOSE_DOWN" and MatchAIDriver.intent_name(false, false, false, true, {}) == "SUPPORT",
			"AI intent names (debug view)")
	# shape shuffle (M4): a player on his spot keeps moving slowly
	var sh := PlayerAI.shape_shuffle(Vector3(0, 0, 0), Vector3(0, 0, -20), Vector3(0, 0, 0), 1.0, 4)
	_check(sh.length() > 0.08 and sh.length() <= 0.2, "a player on his spot shuffles (no dead stop)", "%.2f" % sh.length())
	var d := PlayerAI.decide({"pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, -20), "target": Vector3(0.2, 0, 0), "time": 0.5, "slot": 3,
			"goal": Vector3(0, 0, -52.5), "own_goal": Vector3(0, 0, 52.5)})
	_check((d["move"] as Vector3).length() > 0.05, "decide(): arrived players get the shuffle")
	# formation targets stay on the pitch (M4)
	var t := TacticsPreset.new()
	t.mentality = TacticsPreset.Mentality.ULTRA_ATTACKING
	var inside := true
	for ball_z in [-50.0, 0.0, 50.0]:
		for has in [true, false]:
			for p in TeamAI.formation_targets("home", "4-3-3", t, Vector3(30, 0, ball_z), has):
				inside = inside and absf(p.x) <= PitchSpace.HALF_WIDTH - 0.99 and absf(p.z) <= PitchSpace.HALF_LENGTH - 0.99
	_check(inside, "every formation target lies on the pitch")
	# statistics: a first-time pass by the receiver completes the pass (M1)
	var st := MatchStats.new()
	st.pass_started("home", "a", 1.0)
	st.pass_started("home", "b", 1.5)                  # b played it on without ever counting as the owner
	_check(int(st.teams["home"]["passes_ok"]) == 1, "statistics: a first-time pass by the receiver counts the first pass as completed")
	st.owner_changed("away", "x", 2.0)
	_check(int(st.teams["home"]["passes_ok"]) == 1 and int(st.teams["home"]["passes"]) == 2, "statistics: the intercepted second pass is a failure")
	# the spin ceiling (project setting) — a ball must be able to roll at pass speed
	_check(float(ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_angular_velocity", 47.12)) >= 300.0,
			"Jolt max angular velocity raised (47 rad/s capped a rolling ball at 5.2 m/s)")


# --- ball ---------------------------------------------------------------------------------------------

func _test_strike_and_roll() -> void:
	_new_env()
	var b := _ball(Vector3(0, 0.12, 0))
	await _ticks(20)
	b.linear_velocity = Vector3(6, 0, 0)                  # a dribbled ball
	await _ticks(1)
	b.strike(Vector3(0, 0, -1), 10.0)
	await _ticks(3)
	var dir := _planar(b.linear_velocity).normalized()
	var err := rad_to_deg(dir.angle_to(Vector3(0, 0, -1)))
	_check(err < 8.0, "a strike replaces the dribble velocity (apply_kick added it: 31 deg off)", "%.1f deg" % err)
	# rolling distance: a 10 m/s pass rolls 17+ m in 3 s (13.8 m before: spin ceiling + sliding)
	b.free()
	var r := _ball(Vector3(0, 0.12, 10))
	await _ticks(20)
	var x0 := r.global_position.x
	r.strike(Vector3(1, 0, 0), 10.0)
	await _ticks(180)
	var dist := r.global_position.x - x0
	_check(dist > 17.0, "a 10 m/s ground pass rolls more than 17 m in 3 s", "%.1f m" % dist)
	_check(_planar(r.linear_velocity).length() > 2.5, "it is still rolling (no grass brake to 5 m/s)", "%.1f m/s" % _planar(r.linear_velocity).length())


func _test_kick_aim_and_self_block() -> void:
	# the AI plants (move = 0) while charging: the kick goes along the aim, not a stale direction / facing
	_new_env()
	var p := _player(Vector3(0, 0.05, 0))
	var b := _ball(Vector3(0, 0.12, -0.55))
	await _ticks(10)
	var ai := p.intent as AIIntent
	var acts := p.get_node("BallActions") as FootballActions
	ai.begin_tick()
	ai.set_aim_world(Vector3(1, 0, 0))
	ai.press(&"pass")
	await _ticks(1)
	ai.begin_tick()
	ai.release(&"pass")
	await _ticks(1)
	ai.begin_tick()
	await _ticks(4)
	var dir := _planar(b.linear_velocity).normalized()
	_check(_planar(b.linear_velocity).length() > 3.0 and dir.x > 0.6, "a planted kick goes along the intent's aim (was facing / stale)", str(dir))
	_check(acts.get_kick_direction().x > 0.9, "get_kick_direction() reads the aim")
	# a pass played behind the kicker: his body does not stop it
	_new_env()
	var k := _player(Vector3(0, 0.05, 0))
	var b2 := _ball(Vector3(0.3, 0.12, -0.5))
	await _ticks(10)
	var ai2 := k.intent as AIIntent
	ai2.begin_tick()
	ai2.set_aim_world(Vector3(-0.2, 0, 1).normalized())     # backwards, through the body
	ai2.kick_power = 10.0
	ai2.press(&"pass")
	await _ticks(1)
	ai2.begin_tick()
	ai2.release(&"pass")
	await _ticks(1)
	ai2.begin_tick()
	await _ticks(20)
	_check(b2.global_position.z > 2.0 and _planar(b2.linear_velocity).length() > 6.0,
			"a pass across / behind the kicker is not blocked by his own body", "z %.1f, %.1f m/s" % [b2.global_position.z, _planar(b2.linear_velocity).length()])


func _shot_speed(hold_frames: int) -> float:
	_new_env()
	var p := _player(Vector3(0, 0.05, 0))
	var b := _ball(Vector3(0, 0.12, -0.55))
	await _ticks(10)
	var ai := p.intent as AIIntent
	ai.begin_tick()
	ai.set_aim_world(Vector3(0, 0, -1))
	ai.press(&"shoot")
	await _ticks(1)
	for i in hold_frames:
		ai.begin_tick()
		await _ticks(1)
	ai.begin_tick()
	ai.release(&"shoot")
	await _ticks(1)
	ai.begin_tick()
	var z0 := b.global_position.z
	for i in 120:
		await _ticks(1)
		if z0 - b.global_position.z >= 16.0:
			break
	return b.linear_velocity.length()


func _test_shot_power() -> void:
	var tap := await _shot_speed(2)
	_check(tap >= 18.0 and tap <= 24.0, "an unpressed (tapped) shot reaches 16 m at 18-24 m/s", "%.1f m/s" % tap)
	var full := await _shot_speed(70)
	_check(full >= 28.0 and full <= 34.0, "a fully charged shot reaches 16 m at 28-34 m/s", "%.1f m/s" % full)
	var acts := FootballActions.new()
	acts.config = BallActionConfig.new()
	_check(acts.shot_spread_degrees(1.0) > acts.shot_spread_degrees(0.0) and acts.shot_spread_degrees(0.0) >= 4.0,
			"shots have a spread, wider with a full charge", "%.1f / %.1f deg" % [acts.shot_spread_degrees(0.0), acts.shot_spread_degrees(1.0)])
	acts.free()


func _test_no_tunnelling() -> void:
	_new_env()
	var p := _player(Vector3(0, 0.05, 0))
	await _ticks(10)
	var b := _ball(Vector3(0, 0.3, 6))
	var through := 0
	for i in 200:
		b.freeze = true
		b.global_position = Vector3(randf_range(-0.15, 0.15), randf_range(0.2, 1.2), 6.0)
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.freeze = false
		await _ticks(1)
		b.linear_velocity = Vector3(0, 0, -30)
		for f in 25:
			await _ticks(1)
		if b.global_position.z < -1.0:
			through += 1
	_check(through == 0, "200 shots at 30 m/s into a standing player: none goes through him", "%d through" % through)
	p.free()


func _dribble_run(turn: bool) -> bool:
	_new_env()
	var p := _player(Vector3(0, 0.05, 0))
	var b := _ball(Vector3(0, 0.12, -0.6))
	await _ticks(10)
	var ai := p.intent as AIIntent
	var start := p.global_position
	var frames := 0
	while frames < 600:
		ai.begin_tick()
		ai.press(&"dribble")
		var walked := start.distance_to(p.global_position)
		var dir := Vector3(0, 0, -1)
		if turn and p.global_position.z <= -5.0:
			dir = Vector3(1, 0, 0)
		ai.set_move_world(dir)
		await _ticks(1)
		frames += 1
		if _planar(b.global_position - p.global_position).length() > 2.0:
			return false
		if not turn and walked >= 10.0:
			return true
		if turn and p.global_position.x >= 5.0:
			return true
	return false


func _test_dribble() -> void:
	_check(await _dribble_run(false), "dribbling 10 m straight keeps the ball (no pressure)")
	_check(await _dribble_run(true), "dribbling 5 m, a 90 degree turn and 5 m more keeps the ball")


func _test_turn_rate() -> void:
	_new_env()
	var p := _player(Vector3(0, 0.05, 0))
	await _ticks(5)
	var ai := p.intent as AIIntent
	for i in 30:
		ai.set_move_world(Vector3(0, 0, -1))
		await _ticks(1)
	var yaw0 := p.rotation.y
	var frames := 0
	while frames < 120:
		ai.set_move_world(Vector3(0, 0, 1))
		await _ticks(1)
		frames += 1
		if absf(angle_difference(yaw0, p.rotation.y)) > deg_to_rad(170.0):
			break
	_check(frames >= 18, "a 180 degree turn takes at least 0.3 s (max 540 deg/s)", "%d frames" % frames)


# --- engine hooks: ownership, F8 / F9 --------------------------------------------------------------

func _test_engine_hooks() -> void:
	if _env != null:
		_env.free()
		_env = null
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.rng_seed = 7
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	await _ticks(5)
	# a fast ball 1.2 m from a player is not his
	var e: Dictionary = m.entries["away"][5]
	var n := e["node"] as CharacterBody3D
	m.ball.freeze = true
	m.ball.global_position = n.global_position + Vector3(1.2, 0.0, 0.0)
	m.ball.freeze = false
	m.ball.linear_velocity = Vector3(0, 0, 12)
	m._owner_cache_frame = -1
	var owner := m._owner_entry()
	_check(owner.is_empty() or owner["player_id"] != e["player_id"], "a 12 m/s ball 1.2 m from a player does not belong to him")
	m.ball.linear_velocity = Vector3.ZERO
	m._owner_cache_frame = -1
	_check(m._owner_entry().get("player_id", "") == e["player_id"], "a slow ball 1.2 m from him does")
	_check(m.debug_tools != null, "the match has the F8 / F9 debug tools")
	var path := m.debug_tools.save_report()
	_check(path != "" and FileAccess.file_exists(path), "F8 writes a bug report", path)
	var rep := MatchBugReport.load_report(path)
	_check(not rep.is_empty() and (rep["players"] as Array).size() == 22 and rep.has("snapshot") and rep.has("replay"),
			"the report holds the 22 players' state, the snapshot and the replay")
	var clip := MatchBugReport.replay_clip(rep)
	_check(int(clip["body_count"]) == 23, "the report's replay is a ReplayBuffer clip (ball + 22 bodies)")
	_check(m.rules.notice.find(Loc.t("HUD_BUG_REPORT_SAVED")) >= 0, "the HUD notice says the report was saved")
	DirAccess.remove_absolute(path)
	m.debug_tools.set_debug_visible(true)
	await _ticks(2)
	_check(m.debug_tools.debug_visible and m.debug_tools._labels.size() == 22, "F9 shows one intent label per player")
	m.debug_tools.set_debug_visible(false)
	# a restart stops everybody (the AI used to re-apply its last move after the restart and walk on for the pause)
	m.setup.human_side = "none"
	m._select({})
	for i in 90:
		await _ticks(1)
		if m.state.phase != MatchState.Phase.PLAYING:
			m.state.phase = MatchState.Phase.PLAYING
	m.ball.freeze = true
	m.ball.global_position = Vector3(PitchSpace.HALF_WIDTH + 2.0, 0.2, -10.0)
	m.ball.freeze = false
	var stopped_frame := -1
	for i in 30:
		await _ticks(1)
		if m.state.phase == MatchState.Phase.KICKOFF:
			stopped_frame = i
			break
	await _ticks(60)                                       # 1 s into the 1.5 s restart pause
	var fastest := 0.0
	for side in ["home", "away"]:
		for en in m.entries[side]:
			if en["ai"] != null:
				fastest = maxf(fastest, Vector2((en["node"] as CharacterBody3D).velocity.x, (en["node"] as CharacterBody3D).velocity.z).length())
	_check(stopped_frame >= 0 and m.state.phase == MatchState.Phase.KICKOFF, "the ball over the touchline starts a restart")
	_check(fastest < 0.5, "during the restart pause no AI player keeps walking", "fastest %.2f m/s" % fastest)
	var inside := absf(m.ball.global_position.x) < PitchSpace.HALF_WIDTH
	_check(inside, "the restart ball stays on the pitch during the pause", str(m.ball.global_position))
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame
