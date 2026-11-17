## Match analytics (Phase 8): xG model, shot-map xG, heat-map sampling, report fields and their measured / estimated labels.
##   godot --headless --path . res://tests/match_analytics_validation.tscn
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
	print("=== KING FOOTBALL — Match analytics validation ===")
	_test_xg_model()
	_test_attack_direction_and_cells()
	_test_report_xg_and_labels()
	_test_heat_persistence_and_career_strip()
	await _test_real_match_samples()
	await _test_view()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_xg_model() -> void:
	var gz := -52.5
	var six := ExpectedGoals.shot_xg(0.0, gz + 6.0, gz)
	var spot := ExpectedGoals.shot_xg(0.0, gz + 11.0, gz)
	var edge := ExpectedGoals.shot_xg(0.0, gz + 18.0, gz)
	var far := ExpectedGoals.shot_xg(0.0, gz + 30.0, gz)
	_check(six > spot and spot > edge and edge > far, "xG falls with distance (%.3f > %.3f > %.3f > %.3f)" % [six, spot, edge, far])
	_check(absf(six - 0.28) < 0.04 and absf(spot - 0.15) < 0.04 and absf(edge - 0.07) < 0.03 and far < 0.04, "xG matches the documented anchor values", "%s %s %s %s" % [six, spot, edge, far])
	_check(ExpectedGoals.shot_xg(0.0, gz + 12.0, gz) > ExpectedGoals.shot_xg(15.0, gz + 12.0, gz), "a central shot is worth more than the same distance from the wing")
	_check(is_equal_approx(ExpectedGoals.shot_xg(8.0, gz + 12.0, gz), ExpectedGoals.shot_xg(-8.0, gz + 12.0, gz)), "xG is symmetric left / right")
	var ok := true
	for x in [-34.0, -10.0, 0.0, 3.0, 34.0]:
		for z in [-52.5, -50.0, -40.0, 0.0, 52.5]:
			var v := ExpectedGoals.shot_xg(x, z, gz)
			ok = ok and v >= 0.0 and v <= 1.0
	_check(ok, "xG stays inside 0..1 everywhere, also on the goal line")
	_check(is_equal_approx(ExpectedGoals.shot_xg(5.0, 40.0, 52.5), ExpectedGoals.shot_xg(5.0, -40.0, -52.5)), "the same shot at either goal gives the same xG")


func _test_attack_direction_and_cells() -> void:
	_check(ExpectedGoals.attack_goal_z("home", 1) == -52.5 and ExpectedGoals.attack_goal_z("away", 1) == 52.5, "first half: home attacks -Z, away +Z")
	_check(ExpectedGoals.attack_goal_z("home", 2) == 52.5 and ExpectedGoals.attack_goal_z("away", 2) == -52.5, "second half: the ends are swapped")
	var rows := ExpectedGoals.HEAT_ROWS
	var cols := ExpectedGoals.HEAT_COLS
	# home, first half, standing on its own goal line (z = +52) on the centre line: row 0, middle column
	var own := ExpectedGoals.heat_cell(0.0, 52.0, "home", 1)
	_check(own / cols == 0, "own goal line is row 0", str(own))
	var opp := ExpectedGoals.heat_cell(0.0, -52.0, "home", 1)
	_check(opp / cols == rows - 1, "the opponent's goal line is the last row", str(opp))
	# the same real position is the opposite end for the other side, and flips again in the second half
	_check(ExpectedGoals.heat_cell(0.0, -52.0, "away", 1) / cols == 0, "away: that corner is its own goal line")
	_check(ExpectedGoals.heat_cell(0.0, -52.0, "home", 2) / cols == 0, "home, second half: that end is its own goal again")
	# left / right as seen facing the opponent's goal: home attacks -Z, its right hand side is +X
	_check(ExpectedGoals.heat_cell(30.0, 0.0, "home", 1) % cols > cols / 2, "home first half: +X is the right hand side")
	_check(ExpectedGoals.heat_cell(30.0, 0.0, "away", 1) % cols < cols / 2, "away first half: +X is the LEFT hand side (it faces the other way)")
	var in_range := true
	for x in [-80.0, -34.0, 0.0, 34.0, 80.0]:
		for z in [-80.0, -52.5, 0.0, 52.5, 80.0]:
			var c := ExpectedGoals.heat_cell(x, z, "home", 1)
			in_range = in_range and c >= 0 and c < rows * cols
	_check(in_range, "every position, even outside the pitch, maps to a valid cell")


func _state() -> MatchState:
	var s := MatchState.create("h", "a", 10, "m1")
	s.register_players("home", ["h1", "h2", "hgk"])
	s.register_players("away", ["a1", "a2", "agk"])
	s.init_stamina(["h1", "h2", "hgk", "a1", "a2", "agk"])
	s.kick_off()
	return s


func _test_report_xg_and_labels() -> void:
	var s := _state()
	s.set_ball_position(0.0, -46.0)          # home shot, first half, 6.5 m from the goal it attacks
	s.record_shot("home", "h1")
	s.set_ball_position(0.0, 20.0)           # away shot from 32 m
	s.record_shot("away", "a1")
	var sm := s.shot_map()
	_check(sm.size() == 2 and sm[0].has("xg") and sm[0]["half"] == 1, "every shot-map point has xG and its half")
	_check(float(sm[0]["xg"]) > 0.2 and float(sm[1]["xg"]) < 0.04, "a close shot is worth much more than a long shot", "%s %s" % [sm[0]["xg"], sm[1]["xg"]])
	var rep := MatchReport.build(s, null, "none", null)
	var ts: Dictionary = rep["team_stats"]
	_check(is_equal_approx(float(ts["home"]["xg"]), snappedf(float(sm[0]["xg"]), 0.01)) and is_equal_approx(float(ts["away"]["xg"]), snappedf(float(sm[1]["xg"]), 0.01)),
			"team xG is the sum of its own shots", str(ts["home"]["xg"]) + " " + str(ts["away"]["xg"]))
	_check("xg" in (rep["estimated"] as Array) and not ("xg" in (rep["measured"] as Array)), "xG is declared as an estimate, never as measured")
	_check("shot_map" in (rep["measured"] as Array) and rep.has("heatmaps"), "shot positions are measured and the report carries heat maps")
	# second half: the same world position is a shot at the OTHER goal, so xG differs
	var s2 := _state()
	s2.half = 2
	s2.set_ball_position(0.0, -46.0)
	s2.record_shot("home", "h1")
	_check(float(s2.shot_map()[0]["xg"]) < 0.04, "second half: home attacks +Z, so a shot at z = -46 is a 98 m shot (xG ~0)", str(s2.shot_map()[0]["xg"]))
	var empty := MatchReport.build(_state(), null, "none", null)
	_check(float(empty["team_stats"]["home"]["xg"]) == 0.0, "no shots = 0 xG (nothing invented)")


func _test_heat_persistence_and_career_strip() -> void:
	var st := MatchStats.new()
	st.add_heat("h1", "home", 0.0, 52.0, 1)
	st.add_heat("h1", "home", 0.0, 52.0, 1)
	st.add_heat("a1", "away", 0.0, 52.0, 1)
	var g := st.heat_grid("home")
	var total := 0
	for c in g:
		total += c
	_check(total == 2 and st.heat_grid("away").size() == g.size(), "heat samples are counted per side (home 2)")
	var rt := MatchStats.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_check(rt.heat_grid("home") == g and rt.heat_grid("away") == st.heat_grid("away") and rt.heat_grid("home", "h1") == g, "heat survives a JSON round trip (match save)")
	var legacy := MatchStats.from_dict({"teams": {}, "players": {}})
	_check(legacy.heat.is_empty(), "an old match save without heat loads with empty grids")
	var bad := MatchStats.from_dict({"heat": {"h1": [1, 2, 3]}})
	_check(bad.heat.is_empty(), "a grid of the wrong size is dropped, not misread")
	# the career keeps the report WITHOUT the (large) heat grids
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var c := CareerState.start(db, "club_royal_harbor")
	var s := _state()
	s.home_id = "club_royal_harbor"
	s.away_id = "club_northgate_utd"
	var rep := MatchReport.build(s, db, "none", null)
	rep["uid"] = "u1"
	var recorded := c.record_match(rep, "")
	_check(recorded and not c.match_log.is_empty() and not (c.match_log.back() as Dictionary).has("heatmaps"), "the career match log does not store heat maps")
	_check((c.match_log.back() as Dictionary).has("shot_map") and (c.match_log.back() as Dictionary).has("estimated"), "but it keeps the shot map and the estimate labels")
	_check(rep.has("heatmaps"), "the original report still has them for the results screen")


func _test_real_match_samples() -> void:
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 5
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "match builds")
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	for i in 130:                       # about 2 s at 60 physics frames per second
		await get_tree().physics_frame
	var hg := m.state.stats.heat_grid("home")
	var n := 0
	for c in hg:
		n += c
	_check(n >= 11 * 2, "the real match samples every home player at least twice in ~2 s (%d samples)" % n)
	_check(m.state.stats.heat.size() >= 20, "heat exists for the players of both teams (%d)" % m.state.stats.heat.size())
	# sampling stops while the ball is dead
	m.state.phase = MatchState.Phase.KICKOFF
	var before := n
	for i in 40:
		await get_tree().physics_frame
	var after := 0
	for c in m.state.stats.heat_grid("home"):
		after += c
	_check(after == before, "no samples are taken while the ball is not in play")
	m.queue_free()
	await get_tree().process_frame


func _test_view() -> void:
	var counts: Array = []
	counts.resize(ExpectedGoals.HEAT_COLS * ExpectedGoals.HEAT_ROWS)
	counts.fill(0)
	counts[5] = 9
	var hv := PitchAnalyticsView.heat(counts, Vector2(150, 220))
	var sv := PitchAnalyticsView.shot_map([{"x": 0.0, "z": -46.0, "side": "home", "half": 1, "xg": 0.3, "outcome": "goal"}], Vector2(150, 220))
	add_child(hv)
	add_child(sv)
	await get_tree().process_frame
	_check(hv.size.x > 0 and sv.size.y > 0, "the heat and shot views build and draw without error")
	var top := PitchAnalyticsView.to_pixel(Vector2(0.5, 1.0), Rect2(0, 0, 150, 220))
	var bottom := PitchAnalyticsView.to_pixel(Vector2(0.5, 0.0), Rect2(0, 0, 150, 220))
	_check(top.y == 0.0 and bottom.y == 220.0 and top.x == 75.0, "the attack goal is drawn at the TOP of the pitch")
	# results screen: shows xG only because the report declares it, labelled as an estimate
	var s := _state()
	s.set_ball_position(0.0, -46.0)
	s.record_shot("home", "h1")
	s.phase = MatchState.Phase.FINISHED
	var db: Node = get_node("/root/TeamDB")
	var rep := MatchReport.build(s, db, "none", null)
	rep["home_id"] = "club_royal_harbor"
	rep["away_id"] = "club_northgate_utd"
	var view := MatchResultsView.create(rep, db)
	add_child(view)
	await get_tree().process_frame
	_check(view.find_child("Analytics", true, false) != null and view.find_child("Heat_home", true, false) != null and view.find_child("Shots_away", true, false) != null,
			"the results screen shows heat and shot maps of both teams")
	var texts := ""
	for l in view.find_children("*", "Label", true, false):
		texts += (l as Label).text + "|"
	_check(texts.contains(Loc.t("RESULT_XG")) and texts.contains(Loc.t("RESULT_ESTIMATE_NOTE")), "xG appears with an 'estimate' label and a note")
	var plain := rep.duplicate(true)
	plain["estimated"] = []
	var view2 := MatchResultsView.create(plain, db)
	add_child(view2)
	await get_tree().process_frame
	var texts2 := ""
	for l in view2.find_children("*", "Label", true, false):
		texts2 += (l as Label).text + "|"
	_check(not texts2.contains(Loc.t("RESULT_XG")), "without the 'estimated' declaration the results screen shows no xG")
	for n in [hv, sv, view, view2]:
		n.queue_free()
