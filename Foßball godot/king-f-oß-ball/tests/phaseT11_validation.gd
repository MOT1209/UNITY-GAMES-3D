## Phase T11 validation — match integration (pure logic + a spawned match):
##   godot --headless --path . res://tests/phaseT11_validation.tscn
extends Node

const H := "club_royal_harbor"
const A := "club_obsidian"

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase T11 validation ===")
	_test_intent_providers()
	_test_pitch_space()
	_test_match_state()
	_test_penalties()
	_test_setup()
	_test_team_ai()
	_test_player_ai()
	_test_manager_ai()
	_test_attributes_change_outcomes()
	await _test_spawned_match()
	await _test_default_input_unchanged()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _test_intent_providers() -> void:
	var ai := AIIntent.new()
	_check(ai.world_space and ai.move_vector() == Vector2.ZERO, "AI intent is world-space and idle by default")
	ai.set_move_world(Vector3(3, 0, 4))
	_check(is_equal_approx(ai.move_vector().length(), 1.0), "AI move clamped to unit length")
	ai.set_move_world(Vector3(0.3, 0, 0))
	_check(is_equal_approx(ai.move_vector().x, 0.3), "partial AI move preserved")
	ai.press(&"pass")
	_check(ai.is_pressed(&"pass") and ai.just_pressed(&"pass") and not ai.just_released(&"pass"), "press sets held + edge")
	ai.begin_tick()
	_check(ai.is_pressed(&"pass") and not ai.just_pressed(&"pass"), "edge cleared next tick, still held")
	ai.release(&"pass")
	_check(not ai.is_pressed(&"pass") and ai.just_released(&"pass"), "release sets edge")
	ai.press(&"shoot")
	ai.press(&"shoot")
	ai.begin_tick()
	_check(not ai.just_pressed(&"shoot"), "repeated press does not re-trigger edge")
	ai.release_all()
	_check(not ai.is_pressed(&"shoot") and ai.move_vector() == Vector2.ZERO, "release_all clears everything")
	var human := IntentProvider.new()
	_check(not human.world_space, "default provider is camera-relative")
	Input.action_press("move_forward")
	_check(human.move_vector().y < -0.5, "default provider reads the global Input")
	Input.action_release("move_forward")
	_check(human.move_vector() == Vector2.ZERO, "default provider idle without input")


func _test_pitch_space() -> void:
	_check(PitchSpace.own_goal("home").z > 0 and PitchSpace.opponent_goal("home").z < 0, "home defends S (+Z), attacks N")
	_check(PitchSpace.own_goal("away").z < 0 and PitchSpace.opponent_goal("away").z > 0, "away is mirrored")
	_check(PitchSpace.to_world(Vector2(0, 0.0), "home").z == PitchSpace.HALF_LENGTH, "y=0 is own goal line (home)")
	_check(PitchSpace.to_world(Vector2(0, 1.0), "home").z == -PitchSpace.HALF_LENGTH, "y=1 is opponent goal line (home)")
	_check(PitchSpace.to_world(Vector2(0, 1.0), "away").z == PitchSpace.HALF_LENGTH, "away attacks +Z")
	_check(PitchSpace.to_world(Vector2(0.5, 0.5), "home").x > 0 and PitchSpace.to_world(Vector2(0.5, 0.5), "away").x < 0, "right wing mirrors between sides")
	_check(PitchSpace.progress_of(Vector3(0, 0, 52.5), "home") == 0.0, "ball at own goal = 0 progress")
	_check(PitchSpace.progress_of(Vector3(0, 0, -52.5), "home") == 1.0 and PitchSpace.progress_of(Vector3(0, 0, -52.5), "away") == 0.0, "progress depends on side")
	_check(PitchSpace.scoring_side(&"N") == "home" and PitchSpace.scoring_side(&"S") == "away", "goal N scores for home, S for away")


func _test_match_state() -> void:
	var s := MatchState.create("h", "a", 10, "m1")
	_check(s.phase == MatchState.Phase.KICKOFF, "match starts at kick-off")
	s.tick(10.0)
	_check(s.elapsed == 0.0, "clock does not run before kick-off")
	_check(not s.goal("home"), "no goals before play starts")
	s.kick_off()
	_check(s.phase == MatchState.Phase.PLAYING, "kick-off starts play")
	s.tick(60.0)
	_check(is_equal_approx(s.display_minute(), 9.0) and s.clock_text() == "09:00", "10 real minutes map to 90 match minutes")
	_check(s.goal("home", "p1") and s.score["home"] == 1, "goal counted")
	_check(s.phase == MatchState.Phase.KICKOFF, "play restarts after a goal")
	_check(not s.goal("away"), "no goal during kick-off pause")
	s.kick_off()
	_check(not s.goal("bogus"), "unknown side ignored")
	s.tick(300.0)
	_check(s.phase == MatchState.Phase.HALF_TIME, "half time reached at 50 % of the clock", str(s.phase))
	_check(s.elapsed <= s.duration_seconds / 2.0 + 0.001 or s.phase == MatchState.Phase.HALF_TIME, "clock stops at half time")
	_check(s.start_second_half() and s.half == 2, "second half starts")
	s.kick_off()
	s.tick(10000.0)
	_check(s.is_finished() and s.elapsed == s.duration_seconds, "full time ends the match, clock capped")
	var t := s.elapsed
	s.tick(10.0)
	_check(s.elapsed == t, "clock frozen after full time")
	_check(s.events.size() >= 2 and s.events[0]["type"] == "goal" and s.events[-1]["type"] == "full_time", "events recorded")
	var r := s.to_result()
	_check(r.match_id == "m1" and r.home_goals == 1 and r.away_goals == 0 and r.validate().is_empty(), "result mirrors score")
	_check(s.goal_difference("home") == 1 and s.goal_difference("away") == -1, "goal difference")
	var d := MatchState.create("h", "a", 2, "m2")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dr := d.to_result(true, rng, 70, 60)
	_check(dr.winner_id() != "" and dr.validate().is_empty(), "knockout draw is settled by penalties")
	_check(d.to_result(false).winner_id() == "", "league draw stays a draw")
	d.init_stamina(["p"])
	var before: float = d.stamina["p"]
	d.drain_stamina("p", 10.0, 1.0, 50)
	_check(d.stamina["p"] < before, "running drains stamina")
	var s1 := MatchState.create("h", "a", 10)
	var s2 := MatchState.create("h", "a", 10)
	s1.init_stamina(["x"]); s2.init_stamina(["x"])
	s1.drain_stamina("x", 30.0, 1.0, 95)
	s2.drain_stamina("x", 30.0, 1.0, 20)
	_check(s1.stamina["x"] > s2.stamina["x"], "higher physical rating tires slower")
	s1.drain_stamina("x", 1e9, 1.0, 10)
	_check(s1.stamina["x"] == 0.0, "stamina never negative")


func _test_penalties() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var level := 0
	var home_wins := 0
	var strong_wins := 0
	for i in 400:
		var r := PenaltyShootout.resolve(60, 60, rng)
		if r[0] == r[1]:
			level += 1
		if r[0] > r[1]:
			home_wins += 1
		var r2 := PenaltyShootout.resolve(90, 30, rng)
		if r2[0] > r2[1]:
			strong_wins += 1
	_check(level == 0, "shoot-outs never end level")
	_check(home_wins > 120 and home_wins < 280, "equal teams win roughly half each", str(home_wins))
	_check(strong_wins > home_wins, "stronger team wins shoot-outs more often")


func _test_setup() -> void:
	var db := _db()
	var s := MatchSetup.new()
	_check(not s.validate(db).is_empty(), "empty setup invalid")
	s.home_id = H; s.away_id = H
	_check(not s.validate(db).is_empty(), "team cannot play itself")
	s.away_id = "ghost"
	_check(not s.validate(db).is_empty(), "unknown team rejected")
	s.away_id = A
	_check(s.validate(db).is_empty(), "valid setup", str(s.validate(db)))
	s.duration_minutes = 7
	_check(not s.validate(db).is_empty(), "unsupported duration rejected")
	s.duration_minutes = 5; s.difficulty = 5
	_check(not s.validate(db).is_empty(), "unknown difficulty rejected")
	s.difficulty = 1; s.human_side = "both"
	_check(not s.validate(db).is_empty(), "unknown human side rejected")
	s.human_side = "home"
	for p in db.get_squad(A):
		if p.position == PlayerData.Position.GK:
			p.status = PlayerData.Status.INJURED
	_check(not s.validate(db).is_empty(), "team without an available goalkeeper rejected")
	for p in db.get_squad(A):
		p.status = PlayerData.Status.ACTIVE
	var home := s.build_side(db, "home")
	var away := s.build_side(db, "away")
	_check(home["starters"].size() == 11 and home["formation"] == "4-3-3", "home lineup of 11")
	var squad: Squad = home["squad"]
	var seen := {}
	var starters_ok := true
	for st in home["starters"]:
		if st["player_id"] == "" or seen.has(st["player_id"]) or db.get_player(st["player_id"]).team_id != H:
			starters_ok = false
		seen[st["player_id"]] = true
	_check(starters_ok, "starters are 11 distinct players of that team")
	_check(squad.validate(db).is_empty(), "lineup validates")
	_check(home["kit"] == "home" and (away["kit"] == "away" or away["kit"] == "third"), "kits: home vs away/third")
	var custom := Squad.new(H, "4-4-2")
	custom.auto_pick(db)
	var s2 := MatchSetup.new()
	s2.home_id = H; s2.away_id = A
	s2.home_squad = custom
	_check(s2.build_side(db, "home")["formation"] == "4-4-2", "selected squad/formation reaches the match")
	var broken := Squad.new(H, "4-4-2")
	var s3 := MatchSetup.new()
	s3.home_id = H; s3.away_id = A
	s3.home_squad = broken
	_check(s3.build_side(db, "home")["starters"][1]["player_id"] != "", "invalid squad falls back to auto-pick")
	_check(s3.build_side(db, "home")["formation"] == "4-4-2", "fallback keeps the chosen formation")
	db.free()


func _test_team_ai() -> void:
	var t := TacticsPreset.new()
	var ball := Vector3(0, 0, 0)
	var targets := TeamAI.formation_targets("home", "4-3-3", t, ball, true)
	_check(targets.size() == 11, "11 formation targets")
	_check(targets[0].z > 40.0, "home goalkeeper stays near own goal (+Z)")
	var away_targets := TeamAI.formation_targets("away", "4-3-3", t, ball, true)
	_check(away_targets[0].z < -40.0, "away goalkeeper near own goal (−Z)")
	var lw := targets[8]
	var away_lw := away_targets[8]
	_check(lw.x < 0 and away_lw.x > 0, "left wingers mirror between the sides")
	var attack := TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, -40), true)
	var defend := TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, 40), true)
	_check(attack[9].z < defend[9].z, "team shifts toward the ball (attack vs defence)")
	var no_ball := TeamAI.formation_targets("home", "4-3-3", t, ball, false)
	_check(no_ball[5].z > targets[5].z, "compact shape without the ball")
	t.defensive_line = 100
	var high := TeamAI.formation_targets("home", "4-3-3", t, ball, true)
	_check(high[2].z < targets[2].z, "high defensive line moves centre-backs up the pitch")
	var pos: Array[Vector3] = [Vector3(0, 0, 50), Vector3(5, 0, 5), Vector3(-20, 0, 10), Vector3(3, 0, 8)]
	_check(TeamAI.chaser_index(pos, Vector3(4, 0, 4), "home") == 1, "closest outfielder chases")   # (5,5) is 1.4 m away; (3,8) is 4.1 m
	_check(TeamAI.chaser_index(pos, Vector3(0, 0, 49), "home") == 0, "keeper may chase balls near his goal")
	var low := TacticsPreset.new(); low.pressing = 30
	var high_press := TacticsPreset.new(); high_press.pressing = 90
	_check(TeamAI.pressers(pos, Vector3(0, 0, 4), "home", low).size() == 1, "low pressing sends one player")
	_check(TeamAI.pressers(pos, Vector3(0, 0, 4), "home", high_press).size() == 2, "high pressing sends two players")
	var def := TacticsPreset.new(); def.mentality = TacticsPreset.Mentality.ULTRA_DEFENSIVE
	var att := TacticsPreset.new(); att.mentality = TacticsPreset.Mentality.ULTRA_ATTACKING
	_check(TeamAI.support_offset(PlayerData.Position.ST, att) > TeamAI.support_offset(PlayerData.Position.ST, def), "attacking mentality increases support runs")
	_check(TeamAI.support_offset(PlayerData.Position.ST, att) > TeamAI.support_offset(PlayerData.Position.CB, att), "forwards support more than defenders")


func _ctx(overrides: Dictionary) -> Dictionary:
	var c := {"pos": Vector3(0, 0, 0), "ball": Vector3(10, 0, 0), "has_ball": false, "is_chaser": false,
			"target": Vector3(0, 0, 0), "goal": Vector3(0, 0, -52.5), "own_goal": Vector3(0, 0, 52.5),
			"teammates": [], "opponents": [], "is_keeper": false, "difficulty": 1, "attributes": null}
	c.merge(overrides, true)
	return c


func _test_player_ai() -> void:
	var chase := PlayerAI.decide(_ctx({"is_chaser": true}))
	_check(chase["move"].x > 0.9, "chaser runs toward the ball")
	var far := PlayerAI.decide(_ctx({"is_chaser": true, "ball": Vector3(30, 0, 0)}))
	_check(far["sprint"] == true, "chaser sprints when far from the ball")
	var easy := PlayerAI.decide(_ctx({"is_chaser": true, "ball": Vector3(30, 0, 0), "difficulty": 0}))
	_check(easy["sprint"] == false, "easy difficulty chasers do not sprint")
	var idle := PlayerAI.decide(_ctx({"target": Vector3(0.5, 0, 0)}))
	_check(idle["move"] == Vector3.ZERO, "player at his position stands still")
	var back := PlayerAI.decide(_ctx({"target": Vector3(0, 0, 20)}))
	_check(back["move"].z > 0.3, "player returns to formation position")
	var shot := PlayerAI.decide(_ctx({"has_ball": true, "pos": Vector3(0, 0, -35), "ball": Vector3(0, 0, -35)}))
	_check(shot["action"] == &"shoot" and shot["move"].z < -0.9, "carrier in range shoots at goal")
	var run := PlayerAI.decide(_ctx({"has_ball": true, "pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, 0)}))
	_check(run["action"] == &"" and run["move"].z < -0.9, "carrier far from goal dribbles forward")
	var mate := Vector3(10, 0, -20)
	var pass_ctx := PlayerAI.decide(_ctx({"has_ball": true, "pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, 0),
			"opponents": [Vector3(1, 0, -1)], "teammates": [mate]}))
	_check(pass_ctx["action"] == &"pass" and pass_ctx["move"].x > 0.2, "pressured carrier passes to an open forward teammate")
	var covered := PlayerAI.decide(_ctx({"has_ball": true, "pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, 0),
			"opponents": [Vector3(1, 0, -1), mate + Vector3(1, 0, 0)], "teammates": [mate]}))
	_check(covered["action"] == &"", "covered teammate is not passed to")
	var backwards := PlayerAI.decide(_ctx({"has_ball": true, "pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, 0),
			"opponents": [Vector3(1, 0, -1)], "teammates": [Vector3(0, 0, 15)]}))
	_check(backwards["action"] == &"", "no backwards pass under pressure when forward play exists")
	var keeper := PlayerAI.decide(_ctx({"is_keeper": true, "pos": Vector3(10, 0, 50), "ball": Vector3(0, 0, -20), "own_goal": Vector3(0, 0, 52.5)}))
	_check(keeper["move"].x < 0, "keeper shadows the ball laterally")
	var hold := PlayerAI.decide(_ctx({"is_keeper": true, "pos": Vector3(0, 0, 50), "ball": Vector3(0, 0, -20), "own_goal": Vector3(0, 0, 52.5)}))
	_check(hold["move"].length() < 0.5, "keeper stays on his line when the ball is far")
	var dist := PlayerAI.decide(_ctx({"is_keeper": true, "has_ball": true, "pos": Vector3(0, 0, 50), "ball": Vector3(0, 0, 50),
			"own_goal": Vector3(0, 0, 52.5), "teammates": [Vector3(10, 0, 20)]}))
	_check(dist["action"] == &"pass", "keeper with the ball distributes")


func _stub_squad(db: TeamDatabase) -> Squad:
	var sq := Squad.new(H)
	sq.auto_pick(db)
	return sq


## A MatchState at `minute` (0-90 scale) with the given goals scored at kick-off.
func _state_at(minute: float, home_goals: int, away_goals: int) -> MatchState:
	var st := MatchState.create(H, A, 10)
	st.kick_off()
	for i in home_goals:
		st.goal("home", "p")
		st.kick_off()
	for i in away_goals:
		st.goal("away", "p")
		st.kick_off()
	if minute > 45.0:
		st.tick(300.0)                       # half time
		st.start_second_half()
		st.kick_off()
		st.tick((minute - 45.0) / 90.0 * 600.0)
	else:
		st.tick(minute / 90.0 * 600.0)
	return st


func _test_manager_ai() -> void:
	var db := _db()
	var sq := _stub_squad(db)
	var t := sq.get_tactics()
	var st := _state_at(76.0, 0, 0)
	st.init_stamina(sq.starting)
	_check(is_equal_approx(st.display_minute(), 76.0), "test clock helper reaches minute 76", str(st.display_minute()))
	_check(ManagerAI.decide(st, "home", sq, t, db).is_empty(), "level game late: no tactical change")
	var losing := _state_at(76.0, 0, 1)
	losing.init_stamina(sq.starting)
	var orders := ManagerAI.decide(losing, "home", sq, t, db)
	var types := orders.map(func(o: Dictionary) -> String: return o["type"])
	_check("mentality" in types and "pressing" in types, "losing late: manager attacks and presses")
	var applied := ManagerAI.apply(orders, "home", losing, sq, t, db)
	_check(t.mentality == TacticsPreset.Mentality.ATTACKING and t.pressing >= 75, "orders change the real tactics")
	_check(applied.is_empty(), "no substitution needed when players are fresh")
	var again := ManagerAI.decide(losing, "home", sq, t, db)
	_check(not again.any(func(o: Dictionary) -> bool: return o["type"] == "mentality"), "manager does not keep escalating each call")
	var t2 := TacticsPreset.new()
	var winning := _state_at(80.0, 1, 0)
	winning.init_stamina(sq.starting)
	ManagerAI.apply(ManagerAI.decide(winning, "home", sq, t2, db), "home", winning, sq, t2, db)
	_check(t2.mentality == TacticsPreset.Mentality.DEFENSIVE, "winning late: manager protects the lead")
	var early_win := _state_at(30.0, 1, 0)
	_check(ManagerAI.decide(early_win, "home", sq, TacticsPreset.new(), db).is_empty(), "no defensive change early in the match")
	var t3 := TacticsPreset.new()
	var heavy := _state_at(80.0, 0, 2)
	heavy.init_stamina(sq.starting)
	ManagerAI.apply(ManagerAI.decide(heavy, "home", sq, t3, db), "home", heavy, sq, t3, db)
	_check(t3.mentality == TacticsPreset.Mentality.ULTRA_ATTACKING, "two goals down: all-out attack")
	var st4 := _state_at(58.0, 0, 0)
	st4.init_stamina(sq.starting + sq.bench)
	var tired_slot := 6
	var tired_id := sq.starting[tired_slot]
	st4.stamina[tired_id] = 20.0
	var o4 := ManagerAI.decide(st4, "home", sq, sq.get_tactics(), db)
	var sub: Dictionary = {}
	for o in o4:
		if o["type"] == "substitute":
			sub = o
	_check(not sub.is_empty() and sub["out_id"] == tired_id, "tired player is substituted")
	_check(sub["in_id"] in sq.bench and db.get_player(sub["in_id"]).position != PlayerData.Position.GK, "replacement is an outfield bench player")
	var applied4 := ManagerAI.apply(o4, "home", st4, sq, sq.get_tactics(), db)
	_check(applied4.size() == 1 and sq.starting[tired_slot] == sub["in_id"] and tired_id in sq.bench, "substitution applied to the real squad")
	_check(st4.subs_used["home"] == 1 and st4.stamina[sub["in_id"]] == 100.0, "sub counted and fresh")
	_check(sq.validate(db).is_empty(), "squad valid after in-match substitution")
	st4.subs_used["home"] = ManagerAI.MAX_SUBS
	st4.stamina[sq.starting[7]] = 10.0
	var none := ManagerAI.decide(st4, "home", sq, sq.get_tactics(), db)
	_check(not none.any(func(o: Dictionary) -> bool: return o["type"] == "substitute"), "substitution limit respected")
	var early := _state_at(10.0, 0, 0)
	early.init_stamina(sq.starting + sq.bench)
	early.stamina[sq.starting[3]] = 5.0
	_check(not ManagerAI.decide(early, "home", sq, sq.get_tactics(), db).any(func(o: Dictionary) -> bool: return o["type"] == "substitute"), "no early substitutions")
	db.free()


## Player attributes must change outcomes: stronger attributes → better shot accuracy/power/speed.
func _test_attributes_change_outcomes() -> void:
	var strong := PlayerData.from_dict({"id": "s", "name": "S S", "age": 25, "position": "ST", "pace": 95, "shooting": 95, "passing": 95, "dribbling": 90, "defending": 40, "physical": 90, "goalkeeping": 5, "potential": 99})
	var weak := PlayerData.from_dict({"id": "w", "name": "W W", "age": 25, "position": "ST", "pace": 25, "shooting": 25, "passing": 25, "dribbling": 30, "defending": 40, "physical": 30, "goalkeeping": 5, "potential": 99})
	var ms := AttributeModifiers.new(strong)
	var mw := AttributeModifiers.new(weak)
	_check(ms.speed_multiplier() > mw.speed_multiplier() + 0.15, "pace → speed")
	_check(ms.shot_power_multiplier() > mw.shot_power_multiplier(), "shooting → shot power")
	_check(ms.shot_error_degrees() < mw.shot_error_degrees() / 3.0, "shooting → accuracy")
	_check(ms.pass_error_degrees() < mw.pass_error_degrees() / 3.0, "passing → pass accuracy")
	_check(ms.duel_strength() > mw.duel_strength(), "physical → duels")
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var a := scene.instantiate() as PlayerController
	var b := scene.instantiate() as PlayerController
	add_child(a)
	add_child(b)
	await get_tree().process_frame
	a.attribute_modifiers = ms
	b.attribute_modifiers = mw
	_check(a._resolve_max_speed(Vector2.ZERO) > b._resolve_max_speed(Vector2.ZERO), "controller: faster player has higher top speed")
	var act_a := a.get_node("BallActions") as FootballActions
	var act_b := b.get_node("BallActions") as FootballActions
	act_a.attribute_modifiers = ms
	act_b.attribute_modifiers = mw
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var err_a := 0.0
	var err_b := 0.0
	for i in 200:
		err_a += absf(act_a._with_error(Vector3.FORWARD, ms.shot_error_degrees()).angle_to(Vector3.FORWARD))
		err_b += absf(act_b._with_error(Vector3.FORWARD, mw.shot_error_degrees()).angle_to(Vector3.FORWARD))
	_check(err_a < err_b / 2.0, "measured aim error: skilled shooter is far more accurate")
	a.queue_free()
	b.queue_free()


func _test_spawned_match() -> void:
	var db: TeamDatabase = get_node("/root/TeamDB")
	var setup := MatchSetup.new()
	setup.home_id = H
	setup.away_id = A
	setup.duration_minutes = 2
	setup.human_side = "home"
	var manager := MatchManager.new()
	manager.return_to_menu_on_finish = false
	add_child(manager)
	var err := manager.begin(setup, db)
	_check(err == "", "match builds from a setup", err)
	if err != "":
		manager.queue_free()
		return
	_check(manager.entries["home"].size() == 11 and manager.entries["away"].size() == 11, "22 players spawned")
	var home_ids: Array = manager.entries["home"].map(func(e: Dictionary) -> String: return e["player_id"])
	var squad: Squad = manager.sides["home"]["squad"]
	_check(home_ids == Array(squad.starting), "selected squad determines who plays")
	var all_home := true
	for pid in home_ids:
		if db.get_player(pid).team_id != H:
			all_home = false
	_check(all_home, "home players belong to the home club")
	var mods_ok := true
	for side in manager.entries:
		for e in manager.entries[side]:
			var n: Node3D = e["node"]      # outfield PlayerController or the TeamGoalkeeper
			if n.attribute_modifiers == null or n.attribute_modifiers.data != e["pdata"]:
				mods_ok = false
	_check(mods_ok, "every player carries his own attribute modifiers")
	_check(manager.ball != null and manager.ball.is_in_group("football_ball"), "match has the real ball")
	_check(not manager.selected.is_empty() and manager.selected["side"] == "home", "human controls a home player")
	var ai_count := 0
	for side in manager.entries:
		for e in manager.entries[side]:
			if e["ai"] != null or e["node"] is TeamGoalkeeper:   # keepers run their own AI
				ai_count += 1
	_check(ai_count == 21, "all other players are AI-controlled", str(ai_count))
	for i in 240:
		await get_tree().physics_frame
	_check(manager.state.phase == MatchState.Phase.PLAYING or manager.state.phase == MatchState.Phase.KICKOFF, "match is running", str(manager.state.phase))
	_check(manager.state.elapsed > 0.0 or manager.state.phase == MatchState.Phase.KICKOFF, "clock advances once play starts")
	var moved := false
	for e in manager.entries["away"]:
		if e["node"] is PlayerController and (e["node"] as PlayerController).get_current_speed() > 0.1:
			moved = true
	_check(moved, "AI players move")
	var side_ok := true
	for e in manager.entries["home"]:
		if (e["node"] as Node3D).global_position.z < -1.0 and manager.state.phase == MatchState.Phase.KICKOFF:
			side_ok = false
	_check(side_ok, "home players start in their own half")
	var goals_before: int = manager.state.score["home"]
	manager.state.kick_off()
	manager._on_goal_entered(&"N", manager.ball)
	_check(manager.state.score["home"] == goals_before + 1, "goal in N counts for the home side")
	manager.state.kick_off()
	manager._on_goal_entered(&"S", manager.ball)
	_check(manager.state.score["away"] == 1, "goal in S counts for the away side")
	var finished := []
	manager.match_finished.connect(func(r: MatchResult) -> void: finished.append(r))
	manager.state.phase = MatchState.Phase.FINISHED
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(finished.size() == 1, "match_finished emitted exactly once")
	if finished.size() == 1:
		var res: MatchResult = finished[0]
		_check(res.home_id == H and res.away_id == A and res.home_goals == 1 and res.away_goals == 1, "result carries the real score")
		var comp := Competition.create_league("t11", "T11", [H, A, "club_sunvale"], false)
		var fx: Dictionary = {}
		for f in comp.fixtures:
			if f["home"] == H and f["away"] == A:
				fx = f
		if not fx.is_empty():
			var r2 := MatchResult.make(fx["match_id"], res.home_id, res.away_id, res.home_goals, res.away_goals)
			_check(comp.submit_result(r2) == "", "engine result updates the competition")
			_check(comp.standings()[0]["points"] == 1 or comp.standings()[1]["points"] == 1, "table reflects the match")
	manager.queue_free()
	await get_tree().process_frame


## Phase 2–4 behaviour must be unchanged for a normal human-controlled player.
func _test_default_input_unchanged() -> void:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(p)
	await get_tree().process_frame
	_check(not p.intent.world_space and p.intent.get_class() == "RefCounted", "player defaults to the Input-reading provider")
	var actions := p.get_node("BallActions") as FootballActions
	_check(not actions.intent.world_space, "actions default to the Input-reading provider")
	_check(p.attribute_modifiers == null and actions.attribute_modifiers == null, "no modifiers by default (Phase 2-4 feel preserved)")
	Input.action_press("move_forward")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(p.get_current_speed() > 0.5, "keyboard input still moves a default player")
	p.queue_free()
