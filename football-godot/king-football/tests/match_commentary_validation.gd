## Commentary + report timeline: event-driven, deterministic, translated, built only from the event log.
##   godot --headless --path . res://tests/match_commentary_validation.tscn
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
	print("=== KING FOOTBALL — Commentary validation ===")
	var names := {"h1": "Ali", "h2": "Omar", "a1": "Max", "agk": "Keeper"}
	_test_keys_translated()
	_test_lines(names)
	_test_consume(names)
	_test_report()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_keys_translated() -> void:
	for lang in ["en", "de", "ar"]:
		Loc.set_language(lang, false)
		var bad: Array = []
		for t in MatchCommentary.VARIANTS:
			for v in range(1, int(MatchCommentary.VARIANTS[t]) + 1):
				var key := MatchCommentary.key_for({"id": v - 1, "type": "goal" if t == "own_goal" else t, "own_goal": t == "own_goal"})
				if t != "own_goal" and t != "goal":
					key = MatchCommentary.key_for({"id": v - 1, "type": t})
				var text := Loc.t(key)
				if text == key or text.strip_edges() == "":
					bad.append(key)
		_check(bad.is_empty(), "%s: every commentary key is translated" % lang, str(bad))
	_check(Loc.t("COMM_GOAL_ASSIST") != "COMM_GOAL_ASSIST", "assist line is translated")


func _test_lines(names: Dictionary) -> void:
	Loc.set_language("en", false)
	var goal := {"id": 3, "type": "goal", "side": "home", "player_id": "h1", "assist_id": "h2", "own_goal": false}
	var l := MatchCommentary.line(goal, names, Loc)
	_check(l.contains("Ali") and l.contains("Omar") and not l.contains("{"), "goal line names the scorer and the assist", l)
	var og := {"id": 4, "type": "goal", "side": "home", "player_id": "a1", "own_goal": true}
	_check(MatchCommentary.line(og, names, Loc).contains("Max"), "own goal has its own wording")
	_check(MatchCommentary.line({"id": 5, "type": "shot", "side": "home", "player_id": "h1"}, names, Loc) == "",
			"a shot (outcome unknown at the time) gets no line")
	_check(MatchCommentary.line({"id": 6, "type": "throw_in", "side": "home"}, names, Loc) == "", "uncommented event types give no line")
	_check(MatchCommentary.line(goal, names, Loc) == l, "same event, same line (deterministic)")
	var sub := {"id": 7, "type": "substitution", "side": "home", "player_id": "h2", "out_id": "h1"}
	var s := MatchCommentary.line(sub, names, Loc)
	_check(s.contains("Omar") and s.contains("Ali"), "substitution names both players", s)
	var unknown := MatchCommentary.line({"id": 1, "type": "red_card", "side": "away", "player_id": "zz"}, names, Loc)
	_check(not unknown.contains("{") and not unknown.contains("zz"), "an unknown player is left blank, never invented", unknown)
	Loc.set_language("ar", false)
	_check(MatchCommentary.line(goal, names, Loc).contains("Ali"), "Arabic line is produced")
	Loc.set_language("de", false)
	_check(MatchCommentary.line({"id": 1, "type": "full_time"}, names, Loc) == "Abpfiff.", "German full time")
	Loc.set_language("en", false)


func _test_consume(names: Dictionary) -> void:
	var c := MatchCommentary.new()
	var ev: Array = [{"id": 1, "type": "shot", "player_id": "h1"}, {"id": 2, "type": "foul", "side": "away", "player_id": "a1", "victim_id": "h1"}]
	var lines := c.consume(ev, names, Loc)
	_check(lines.size() == 1 and c.current == lines[0], "consume yields lines only for commented events")
	_check(c.consume(ev, names, Loc).is_empty(), "an event is never commented twice")
	c.update(MatchCommentary.SHOW_SECONDS + 0.1)
	_check(c.current == "", "the line disappears after its display time")


func _test_report() -> void:
	var s := MatchState.create("h", "a", 10, "m1")
	s.register_players("home", ["h1", "h2"])
	s.register_players("away", ["a1", "agk"])
	s.kick_off()
	s.set_ball_position(3.0, 40.0)
	s.tick(30.0)
	s.record_shot("home", "h1")
	s.record_keeper_hold("away", "agk")
	s.record_foul("away", "a1", "h2", "yellow")
	s.tick(10.0)
	s.record_substitution("home", "h1", "h2")
	var rep := MatchReport.build(s)
	var types: Array = rep["timeline"].map(func(e: Dictionary) -> String: return e["type"])
	_check(types == ["save", "yellow_card", "substitution"], "timeline holds the key events in order", str(types))
	_check(rep["shot_map"].size() == 1 and rep["shot_map"][0]["outcome"] == "saved" and rep["shot_map"][0]["z"] == 40.0,
			"shot map is in the report with the real position and outcome")
	_check("timeline" in rep["measured"] and "shot_map" in rep["measured"], "the report declares both as measured")
	_check(JSON.stringify(rep) != "" and JSON.parse_string(JSON.stringify(rep))["timeline"].size() == 3, "the report stays JSON-safe")
	var sim := MatchReport.from_result(MatchResult.make("x", "h", "a", 1, 0))
	_check(not sim.has("timeline") and not ("timeline" in sim["measured"]), "a simulated result claims no timeline")
