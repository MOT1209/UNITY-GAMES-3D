## Match statistics pipeline: pure unit tests (no scene) + the engine wiring in a real match.
##   godot --headless --path . res://tests/match_stats_validation.tscn
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
	print("=== KING FOOTBALL — Match statistics validation ===")
	_test_passes()
	_test_shots_saves_goals()
	_test_assists_and_own_goals()
	_test_possession_and_ratings()
	_test_report_and_persistence()
	await _test_in_real_match()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _state() -> MatchState:
	var s := MatchState.create("h", "a", 10, "m1")
	s.register_players("home", ["h1", "h2", "h3", "hgk"])
	s.register_players("away", ["a1", "a2", "agk"])
	s.init_stamina(["h1", "h2", "h3", "hgk", "a1", "a2", "agk"])
	s.kick_off()
	return s


func _test_passes() -> void:
	var s := _state()
	s.record_pass("home", "h1")
	s.record_owner("home", "h2")
	_check(s.stats.teams["home"]["passes"] == 1 and s.stats.teams["home"]["passes_ok"] == 1, "pass to a team-mate is successful")
	s.record_pass("home", "h2")
	s.record_owner("away", "a1")
	_check(s.stats.teams["home"]["passes"] == 2 and s.stats.teams["home"]["passes_ok"] == 1, "pass intercepted by an opponent fails")
	s.record_pass("home", "h1")
	s.record_owner("home", "h1")
	_check(s.stats.teams["home"]["passes_ok"] == 1, "the passer touching the ball again is not a completed pass")
	s.tick(s.elapsed + 10.0)
	_check(s.stats.pass_accuracy("home") == 100.0 * 1.0 / 3.0 and s.stats.players["h1"]["passes"] == 2, "unreceived pass expires as incomplete; accuracy derived (1/3)")
	var before: int = s.stats.teams["home"]["passes"]
	s.phase = MatchState.Phase.HALF_TIME
	s.record_pass("home", "h1")
	_check(s.stats.teams["home"]["passes"] == before, "events outside play are ignored")


func _test_shots_saves_goals() -> void:
	var s := _state()
	s.record_shot("home", "h1")
	s.record_keeper_hold("away", "agk")
	_check(s.stats.teams["home"]["shots"] == 1 and s.stats.teams["home"]["on_target"] == 1 and s.stats.teams["away"]["saves"] == 1
			and s.stats.players["agk"]["saves"] == 1, "a held shot = shot on target + save")
	_check(s.events.any(func(e: Dictionary) -> bool: return e["type"] == "save" and e["shooter_id"] == "h1"), "save event recorded with the shooter")
	s.record_keeper_hold("away", "agk")
	_check(s.stats.teams["away"]["saves"] == 1, "a catch without a pending shot is not a save (counted once)")
	s.record_shot("home", "h2")
	s.tick(s.elapsed + 10.0)
	_check(s.stats.teams["home"]["shots"] == 2 and s.stats.teams["home"]["on_target"] == 1, "a shot that ends nowhere stays off target")
	s.record_shot("home", "h2")
	s.record_owner("away", "a1")
	_check(s.stats.teams["home"]["on_target"] == 1, "a blocked shot is off target")
	s.record_shot("home", "h3")
	_check(s.goal_difference("home") == 0, "no goal yet")
	s.goal("home", "h3")
	_check(s.score["home"] == 1 and s.stats.teams["home"]["on_target"] == 2 and s.stats.players["h3"]["goals"] == 1, "goal after a shot: on target, scorer credited")
	var goals: Array = s.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal")
	_check(goals.size() == 1, "exactly one goal event")
	_check(not s.goal("home", "h3"), "a second goal while play is stopped is ignored (no duplicates)")
	s.kick_off()
	s.goal("home", "h1")
	_check(s.stats.teams["home"]["shots"] == 5 and s.stats.teams["home"]["on_target"] == 3, "a goal without a registered shot still counts as a shot on target")


func _test_assists_and_own_goals() -> void:
	var s := _state()
	s.record_pass("home", "h1")
	s.record_owner("home", "h2")
	s.record_shot("home", "h2")
	s.goal("home", "h2")
	_check(s.stats.players["h1"]["assists"] == 1 and s.events.back()["assist_id"] == "h1", "completed pass + goal = assist")
	s.kick_off()
	s.record_pass("home", "h1")
	s.record_owner("home", "h2")
	s.record_owner("home", "h3")
	s.goal("home", "h3")
	_check(s.stats.players["h2"]["assists"] == 0 and s.stats.players["h1"]["assists"] == 1, "no assist when the scorer did not receive the pass")
	s.kick_off()
	s.goal("home", "a1")
	var last: Dictionary = s.events.back()
	_check(last["own_goal"] and s.stats.players["a1"]["own_goals"] == 1 and s.stats.players["a1"]["goals"] == 0 and s.score["home"] == 3,
			"an own goal counts for the other side and not as the player's goal")


func _test_possession_and_ratings() -> void:
	var s := _state()
	s.record_possession("home", 30.0)
	s.record_possession("away", 10.0)
	_check(is_equal_approx(s.stats.possession_pct("home"), 75.0) and is_equal_approx(s.stats.possession_pct("away"), 25.0), "possession is derived from owned time")
	_check(MatchState.create("h", "a", 5).stats.possession_pct("home") == 50.0, "no data -> 50/50, not a fake number")
	s.record_shot("home", "h1")
	s.goal("home", "h1")
	s.kick_off()
	s.record_substitution("home", "h3", "h4")
	_check(s.subs_used["home"] == 1 and s.events.any(func(e: Dictionary) -> bool: return e["type"] == "substitution" and e["out_id"] == "h3"), "substitution counted and recorded once")
	_check(s.stats.rating("h1", 1) > s.stats.rating("h2", 1) and s.stats.rating("h1", 1) <= 10.0 and s.stats.rating("a1", -1) >= 3.0, "ratings rise with goals, stay in 3..10")
	_check(s.stats.rating("h1", 1) == s.stats.rating("h1", 1), "ratings are deterministic")


func _test_report_and_persistence() -> void:
	var s := _state()
	s.record_pass("home", "h1")
	s.record_owner("home", "h2")
	s.record_shot("home", "h2")
	s.goal("home", "h2")
	s.kick_off()
	s.elapsed = s.duration_seconds
	s.phase = MatchState.Phase.FINISHED
	var rep := MatchReport.build(s, null, "home")
	_check(rep["home_goals"] == 1 and rep["away_goals"] == 0 and rep["outcome_human"] == "win", "report: score and outcome for the human side")
	_check(rep["scorers"].size() == 1 and rep["scorers"][0]["player_id"] == "h2" and rep["scorers"][0]["assist_id"] == "h1", "report: scorer, assist, minute")
	_check(rep["motm"] == "h2", "man of the match = best measured rating")
	_check(rep["team_stats"]["home"]["shots"] == 1 and rep["team_stats"]["home"]["passes_ok"] == 1 and rep["measured"].has("possession"), "report carries measured team stats")
	_check(rep["measured"].has("fouls") and rep["measured"].has("cards") and not rep["measured"].has("offsides") and rep["team_stats"]["home"]["fouls"] == 0, "fouls/cards are measured (zero here: none happened); offsides are still not claimed")
	_check(JSON.stringify(rep) != "" and MatchReport.from_result(MatchResult.make("x", "h", "a", 2, 2, 4, 3), "away")["outcome_human"] == "loss",
			"simulated results produce a score-only report")
	_check(MatchReport.from_result(MatchResult.make("x", "h", "a", 1, 0))["measured"] == ["score"], "a simulated report says only the score is known")
	var back := MatchStats.from_dict(JSON.parse_string(JSON.stringify(s.stats.to_dict())))
	_check(JSON.stringify(back.to_dict()) == JSON.stringify(s.stats.to_dict()), "statistics survive JSON save/load exactly")


func _test_in_real_match() -> void:
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
	_check(m.state.stats.players.size() == 22, "all 22 players registered in the statistics")
	# drive the real gameplay signals of one outfield player
	var e: Dictionary = m.entries["home"][5]
	var actions := e["actions"] as FootballActions
	m.state.phase = MatchState.Phase.PLAYING
	actions.pass_started.emit(10.0)
	_check(m.state.stats.teams["home"]["passes"] == 1 and m.state.stats.players[e["player_id"]]["passes"] == 1, "FootballActions.pass_started feeds the statistics")
	actions.shot_started.emit(20.0, 0.1)
	_check(m.state.stats.teams["home"]["shots"] == 1 and m.state.events.any(func(ev: Dictionary) -> bool: return ev["type"] == "shot"), "FootballActions.shot_started feeds the statistics")
	(m.entries["away"][0]["node"] as TeamGoalkeeper).ball_caught.emit()
	_check(m.state.stats.teams["away"]["saves"] == 1 and m.state.stats.players[m.entries["away"][0]["player_id"]]["saves"] == 1, "TeamGoalkeeper.ball_caught after a shot = a save")
	var before: int = m.state.stats.teams["home"]["passes"]
	for i in 3:
		await get_tree().physics_frame
	_check(m.state.stats.teams["home"]["passes"] == before, "the pipeline does not invent events while the game runs")
	m.queue_free()
	await get_tree().process_frame
