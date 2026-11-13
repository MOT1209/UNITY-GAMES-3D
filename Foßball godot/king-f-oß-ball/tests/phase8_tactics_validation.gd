## Tactics that really change behaviour: width, build-up, passing style, shoot range, AI manager difficulty, opponent analysis.
##   godot --headless --path . res://tests/phase8_tactics_validation.tscn
extends Node

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
	print("=== KING FOOTBALL — Tactics and AI validation ===")
	_test_width()
	_test_profiles()
	_test_pass_choice()
	_test_shoot_range()
	_test_manager_difficulty()
	_test_opponent_analysis()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_width() -> void:
	var t := TacticsPreset.new()
	var narrow := TacticsPreset.new()
	narrow.width = 0
	var wide := TacticsPreset.new()
	wide.width = 100
	var lw := 8      # a winger slot of 4-3-3 (see FormationData)
	var xn := absf(narrow.target_position("4-3-3", lw).x)
	var xb := absf(t.target_position("4-3-3", lw).x)
	var xw := absf(wide.target_position("4-3-3", lw).x)
	_check(xn < xb and xb <= xw, "width moves the wingers inwards / outwards", "%.2f %.2f %.2f" % [xn, xb, xw])
	_check(wide.target_position("4-3-3", lw).x >= -1.0 and wide.target_position("4-3-3", lw).x <= 1.0, "width keeps targets on the pitch")
	var back := TacticsPreset.from_dict(wide.to_dict())
	_check(back.width == 100 and TacticsPreset.from_dict({"name": "old"}).width == 50, "width is saved and old saves default to 50")
	var bad := TacticsPreset.new()
	bad.width = 150
	_check(not bad.validate().is_empty(), "an invalid width is rejected")


func _test_profiles() -> void:
	var short := TacticsPreset.new()
	short.build_up = TacticsPreset.BuildUp.SHORT
	var direct := TacticsPreset.new()
	direct.build_up = TacticsPreset.BuildUp.DIRECT
	_check(short.pass_profile()["max_dist"] < direct.pass_profile()["max_dist"] and short.pass_profile()["min_dist"] < direct.pass_profile()["min_dist"],
			"short build-up uses shorter passes than direct")
	var safe := TacticsPreset.new()
	safe.passing_style = TacticsPreset.PassingStyle.SAFE
	var risky := TacticsPreset.new()
	risky.passing_style = TacticsPreset.PassingStyle.RISKY
	_check(safe.pass_profile()["cover_radius"] > risky.pass_profile()["cover_radius"] and safe.pass_profile()["min_progress"] < risky.pass_profile()["min_progress"],
			"safe passing avoids covered team-mates and accepts sideways passes; risky does not")


func _ctx(profile: Dictionary) -> Dictionary:
	return {"pos": Vector3(0, 0, 0), "ball": Vector3(0, 0, 0), "has_ball": true, "is_chaser": false, "target": Vector3.ZERO,
			"goal": Vector3(0, 0, -100.0), "own_goal": Vector3(0, 0, 52.5),
			"teammates": [Vector3(5, 0, -8), Vector3(0, 0, -40), Vector3(10, 0, 5)], "opponents": [Vector3(0, 0, 3)],
			"is_keeper": false, "difficulty": 1, "attributes": null, "profile": profile, "shoot_range": 10.0}


func _test_pass_choice() -> void:
	var short := TacticsPreset.new()
	short.build_up = TacticsPreset.BuildUp.SHORT
	var direct := TacticsPreset.new()
	direct.build_up = TacticsPreset.BuildUp.DIRECT
	var a := PlayerAI.decide(_ctx(short.pass_profile()))
	var b := PlayerAI.decide(_ctx(direct.pass_profile()))
	_check(a["action"] == &"pass" and b["action"] == &"pass", "a pressured carrier passes")
	_check((a["move"] as Vector3).z < 0.0 and absf((a["move"] as Vector3).x) > 0.3, "short build-up picks the near team-mate (angled pass)", str(a["move"]))
	_check(absf((b["move"] as Vector3).x) < 0.05 and (b["move"] as Vector3).z < -0.9, "direct build-up picks the long forward ball", str(b["move"]))
	var safe := TacticsPreset.new()
	safe.passing_style = TacticsPreset.PassingStyle.SAFE
	var c := _ctx(safe.pass_profile())
	c["teammates"] = [Vector3(10, 0, 5)]                  # only a backward option
	var risky := TacticsPreset.new()
	risky.passing_style = TacticsPreset.PassingStyle.RISKY
	var d := _ctx(risky.pass_profile())
	d["teammates"] = [Vector3(10, 0, 5)]
	_check(PlayerAI.decide(c)["action"] == &"pass" and PlayerAI.decide(d)["action"] != &"pass", "safe style passes backwards under pressure, risky style keeps the ball")


func _test_shoot_range() -> void:
	var att := TacticsPreset.new()
	att.mentality = TacticsPreset.Mentality.ULTRA_ATTACKING
	att.passing_style = TacticsPreset.PassingStyle.RISKY
	var def := TacticsPreset.new()
	def.mentality = TacticsPreset.Mentality.ULTRA_DEFENSIVE
	def.passing_style = TacticsPreset.PassingStyle.SAFE
	_check(att.shoot_range() > TacticsPreset.new().shoot_range() and def.shoot_range() < TacticsPreset.new().shoot_range(), "attacking/risky teams shoot from further, defensive/safe from closer")
	var ctx := _ctx(TacticsPreset.new().pass_profile())
	ctx["opponents"] = []
	ctx["pos"] = Vector3(0, 0, -30.0)                      # 70 m from goal
	ctx["goal"] = Vector3(0, 0, -100.0)
	ctx["shoot_range"] = 80.0
	_check(PlayerAI.decide(ctx)["action"] == &"shoot", "the carrier shoots inside the tactics' shoot range")
	ctx["shoot_range"] = 50.0            # 70 m away, beyond 1.3 x 50 m
	_check(PlayerAI.decide(ctx)["action"] != &"shoot", "and not outside it")


func _state(minute: float, home_goals: int, away_goals: int) -> MatchState:
	var s := MatchState.create("h", "a", 90)
	s.phase = MatchState.Phase.PLAYING
	s.elapsed = minute / 90.0 * s.duration_seconds
	s.score = {"home": home_goals, "away": away_goals}
	return s


func _test_manager_difficulty() -> void:
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var team := "club_royal_harbor"
	var squad := Squad.new(team, "4-4-2")
	squad.auto_pick(db)
	var losing := _state(65.0, 0, 1)
	var t := TacticsPreset.new()
	var easy := ManagerAI.decide(losing, "home", squad, t, db, 0).filter(func(o: Dictionary) -> bool: return o["type"] == "mentality")
	var normal := ManagerAI.decide(losing, "home", squad, t, db, 1).filter(func(o: Dictionary) -> bool: return o["type"] == "mentality")
	var hard := ManagerAI.decide(losing, "home", squad, t, db, 2).filter(func(o: Dictionary) -> bool: return o["type"] == "mentality")
	_check(easy.is_empty() and normal.is_empty() and not hard.is_empty(), "at minute 65 only the hard manager reacts to a deficit")
	var losing75 := _state(75.0, 0, 1)
	_check(ManagerAI.decide(losing75, "home", squad, t, db, 0).filter(func(o: Dictionary) -> bool: return o["type"] == "mentality").is_empty()
			and not ManagerAI.decide(losing75, "home", squad, t, db, 1).filter(func(o: Dictionary) -> bool: return o["type"] == "mentality").is_empty(),
			"at minute 75 normal reacts, easy never does")


func _test_opponent_analysis() -> void:
	var db: Node = get_node("/root/TeamDB")
	var squad := Squad.new("club_royal_harbor", "4-4-2")
	squad.auto_pick(db)
	var s := _state(30.0, 0, 0)
	s.stats.teams["away"]["on_target"] = 4
	s.stats.teams["away"]["shots"] = 5
	s.stats.teams["away"]["passes"] = 20
	s.stats.teams["home"]["on_target"] = 1
	s.stats.teams["away"]["possession"] = 70.0
	s.stats.teams["home"]["possession"] = 30.0
	var seen := TeamAI.analyse_opponent(s, "home")
	_check(seen["dangerous"] and seen["dominant"] and seen["direct"], "analysis reads the opponent's measured dominance, danger and directness", str(seen))
	var t := TacticsPreset.new()
	var orders := ManagerAI.decide(s, "home", squad, t, db, 2)
	_check(orders.any(func(o: Dictionary) -> bool: return o["type"] == "defensive_line" and o["value"] == 35), "hard manager drops the line against a dangerous attack")
	ManagerAI.apply(orders, "home", s, squad, t, db)
	_check(t.defensive_line == 35, "and the order is applied to the tactics")
	_check(ManagerAI.decide(s, "home", squad, TacticsPreset.new(), db, 1).filter(func(o: Dictionary) -> bool: return o["type"] == "defensive_line").is_empty(), "the normal manager does not analyse the opponent")
	var calm := _state(30.0, 0, 0)
	_check(not TeamAI.analyse_opponent(calm, "home")["dangerous"] and not TeamAI.analyse_opponent(calm, "home")["dominant"], "no danger / dominance is claimed without measured numbers")
