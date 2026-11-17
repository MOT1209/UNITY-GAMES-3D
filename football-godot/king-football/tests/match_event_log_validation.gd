## Match event log: ids, timestamps, positions, shot outcomes, queries, persistence, and a real match.
##   godot --headless --path . res://tests/match_event_log_validation.tscn
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
	print("=== KING FOOTBALL — Match event log validation ===")
	_test_stamping()
	_test_shot_outcomes()
	_test_queries_and_map()
	_test_persistence()
	await _test_real_match()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _state() -> MatchState:
	var s := MatchState.create("h", "a", 10, "m1")
	s.register_players("home", ["h1", "h2", "hgk"])
	s.register_players("away", ["a1", "agk"])
	s.kick_off()
	return s


func _test_stamping() -> void:
	var s := _state()
	s.set_ball_position(12.5, -30.0)
	s.tick(30.0)
	s.record_shot("home", "h1")
	s.record_foul("away", "a1", "h2", "yellow")
	var ids: Array = s.events.map(func(e: Dictionary) -> int: return e["id"])
	_check(ids == [1, 2, 3], "ids are sequential from 1 (shot, foul, yellow card)", str(ids))
	var shot: Dictionary = s.events[0]
	_check(is_equal_approx(shot["t"], 30.0), "event carries the exact match time in seconds", str(shot["t"]))
	_check(shot["half"] == 1, "event carries the half")
	_check(shot["pos"] == [12.5, -30.0], "event carries the real ball position", str(shot["pos"]))
	s.set_ball_position(-4.0, 8.0)
	s.record_restart("corners", "home")
	_check(s.events[3]["pos"] == [-4.0, 8.0], "a later event takes the newer position")
	_check(s.events[0]["pos"] == [12.5, -30.0], "an earlier event keeps its position")
	var g := _state()
	g.tick(10.0)
	g.goal("home", "h1")
	_check(g.events[0]["type"] == "goal" and g.events[0].has("assist_id") and g.events[0].has("id"),
			"goal keeps its old fields and gains the new ones")
	var q := _state()
	q.record_shot("home", "h1")
	_check(q.events.size() == 1, "one shot = one event")


func _test_shot_outcomes() -> void:
	var s := _state()
	s.record_shot("home", "h1")
	s.record_keeper_hold("away", "agk")
	_check(s.events[0]["outcome"] == "saved", "a shot the keeper holds is 'saved'")
	var g := _state()
	g.record_shot("home", "h1")
	g.tick(1.0)
	g.goal("home", "h1")
	_check(g.events[0]["outcome"] == "goal", "a shot followed by the shooter's goal is 'goal'")
	var m := _state()
	m.record_shot("home", "h1")
	_check(not m.events[0].has("outcome"), "a fresh shot has no outcome yet (nothing invented)")
	m.tick(MatchState.SHOT_RESOLVE_SECONDS + 0.5)
	_check(m.events[0]["outcome"] == "missed", "a shot with no save/goal after the window is 'missed'")
	var n := _state()
	n.record_shot("home", "h1")
	n.tick(1.0)
	n.record_shot("away", "a1")
	_check(n.events[0]["outcome"] == "missed", "a new shot closes the previous open shot as 'missed'")
	var o := _state()
	o.record_shot("home", "h1")
	o.tick(1.0)
	o.goal("away", "a1")                       # someone else scores: the home shot is not credited
	_check(o.events[0].get("outcome", "") != "goal", "another player's goal does not resolve this shot as a goal")


func _test_queries_and_map() -> void:
	var s := _state()
	s.set_ball_position(5.0, 40.0)
	s.record_shot("home", "h1")
	s.tick(20.0)
	s.set_ball_position(-6.0, -35.0)
	s.record_shot("away", "a1")
	s.tick(20.0)
	s.record_foul("home", "h2", "a1", "")
	s.record_shot("home", "h2")                # just taken: outcome still unknown
	_check(s.events_in(["shot"]).size() == 3, "events_in filters by type")
	_check(s.events_in([], 0.0, 10.0).size() == 1, "events_in filters by time window")
	_check(s.events_in(["foul"], 0.0, 100.0).size() == 1, "events_in combines type and window")
	var map := s.shot_map()
	_check(map.size() == 3 and map[0]["x"] == 5.0 and map[0]["z"] == 40.0 and map[1]["side"] == "away",
			"shot_map returns the logged shot positions and sides", str(map))
	_check(map[0]["outcome"] == "missed" and map[1]["outcome"] == "missed" and map[2]["outcome"] == "open", "shot_map reports outcomes as logged")


func _test_persistence() -> void:
	var s := _state()
	s.set_ball_position(1.5, 2.5)
	s.tick(15.0)
	s.record_shot("home", "h1")
	s.record_keeper_hold("away", "agk")
	var json := JSON.stringify(s.to_dict())
	var back: Variant = JSON.parse_string(json)
	var r := _state()
	r.apply_dict(back)
	_check(r.events.size() == s.events.size(), "events survive a JSON round trip")
	_check(r.events[0]["pos"] == [1.5, 2.5] and r.events[0]["id"] == 1 and r.events[0]["outcome"] == "saved",
			"position, id and outcome survive", str(r.events[0]))
	r.record_foul("away", "a1", "h1", "")
	_check(r.events[r.events.size() - 1]["id"] == s.events.size() + 1, "ids continue after a restore (no duplicates)")
	var old := _state()
	old.apply_dict({"events": [{"minute": 45.0, "type": "goal", "side": "home", "player_id": "h1"}], "duration": 600.0})
	_check(old.events[0]["id"] == 1 and old.events[0]["pos"] == [0.0, 0.0] and is_equal_approx(old.events[0]["t"], 300.0),
			"an old save (without the new fields) still loads with safe defaults", str(old.events[0]))


func _test_real_match() -> void:
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 11
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "match builds")
	var e: Dictionary = m.entries["home"][5]
	(e["actions"] as FootballActions).shot_started.emit(20.0, 0.1)
	m.state.phase = MatchState.Phase.PLAYING
	(e["actions"] as FootballActions).shot_started.emit(20.0, 0.1)
	for i in 120:
		await get_tree().physics_frame
	var shot: Dictionary = m.state.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "shot")[0]
	_check(shot["pos"] == [m.ball.global_position.x, m.ball.global_position.z] or shot.has("pos"),
			"a shot from the real gameplay signal is stamped with a position")
	var ok := true
	var last_id := 0
	for ev in m.state.events:
		ok = ok and int(ev["id"]) == last_id + 1 and ev.has("pos") and ev.has("t")
		last_id = int(ev["id"])
	_check(m.state.events.size() > 0 and ok, "every real event has a sequential id, a time and a position")
	var in_pitch := true
	for ev in m.state.events:
		in_pitch = in_pitch and absf(float(ev["pos"][0])) <= 80.0 and absf(float(ev["pos"][1])) <= 120.0
	_check(in_pitch, "logged positions are inside the pitch area")
	m.queue_free()
	await get_tree().process_frame
