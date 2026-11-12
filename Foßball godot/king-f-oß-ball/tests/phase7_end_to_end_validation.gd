## Phase 7 end-to-end: one complete playable workflow through the REAL engine and the REAL career layer.
##   godot --headless --path . res://tests/phase7_end_to_end_validation.tscn
## Initialise -> team -> squad -> match -> 22 players + keepers -> kits -> real gameplay actions -> events ->
## goal (real goal trigger) -> half -> side switch -> second half -> result -> competition -> finances ->
## results screen -> save career -> reload -> consistency. Only the clock is advanced by script (a real
## 2-minute match would take 2 minutes); everything else goes through the same code the game uses.
extends Node

const SAVE := "user://test_saves/phase7_e2e.json"
const HOME := "club_royal_harbor"
const AWAY := "club_northgate_utd"

var _passed := 0
var _failed := 0
var db: Node
var app: Node
var gm: Node
var m: MatchManager


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
	print("=== KING FOOTBALL — Phase 7 end-to-end validation ===")
	await _run()
	DirAccess.remove_absolute(SAVE)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	# 1. initialise
	app = get_node("/root/AppHub")
	gm = get_node("/root/GameManager")
	db = get_node("/root/TeamDB")
	db.reload()
	_check(db.teams.size() > 0 and db.players.size() > 0 and gm != null and Loc != null, "1. game initialised: autoloads and data present")
	# 2-3. team and squad
	app.user_team_id = ""
	app.career = null
	app.squads.clear()
	app.academies.clear()
	app.pending_fixture = {}
	_check(app.start_career(HOME) == "", "2. a team is loaded and a career starts")
	var squad: Squad = app.squad()
	_check(squad != null and squad.validate(db).is_empty() and db.get_squad(HOME).size() >= 18, "3. its squad is loaded and valid", str(squad.validate(db) if squad else "no squad"))
	var comp := Competition.create_league("e2e_league", "E2E League", [HOME, AWAY, "club_cedar_city", "club_sunvale"], true)
	app.career.register_competition(comp)
	var fixture: Dictionary = {}
	for f in comp.fixtures:
		if f["home"] == HOME and f["away"] == AWAY:
			fixture = f
			break
	app.pending_fixture = {"competition_id": comp.id, "match_id": fixture["match_id"]}
	var week_before: int = app.career.week
	var revenue_before: int = (app.career.ledger().entries as Array).filter(func(e: Dictionary) -> bool: return e["category"] == "match_revenue").size()
	var balance_before: int = app.career.ledger().balance
	# 4. initialise the match
	var setup := MatchSetup.new()
	setup.home_id = HOME
	setup.away_id = AWAY
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.rng_seed = 77
	setup.competition_id = comp.id
	setup.match_id = fixture["match_id"]
	setup.home_squad = squad
	m = MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "" and m.state.phase == MatchState.Phase.KICKOFF, "4. the match is initialised (kick-off phase)")
	# 5. 22 players
	var ids := {}
	var in_tree := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			ids[e["player_id"]] = true
			in_tree += 1 if (e["node"] as Node).is_inside_tree() else 0
	_check(m.entries["home"].size() == 11 and m.entries["away"].size() == 11 and ids.size() == 22 and in_tree == 22,
			"5. 22 distinct players are spawned in the scene")
	_check(m.entries["home"].map(func(e: Dictionary) -> String: return e["player_id"]) == Array(m.sides["home"]["squad"].starting)
			and (m.sides["home"]["squad"] as Squad).starting == squad.starting, "5b. the home XI is the career squad's XI")
	# 6. goalkeepers
	_check(m.entries["home"][0]["node"] is TeamGoalkeeper and m.entries["away"][0]["node"] is TeamGoalkeeper
			and (m.entries["home"][0]["pdata"] as PlayerData).position == PlayerData.Position.GK, "6. both goalkeepers are real TeamGoalkeepers")
	# 7. kits
	var home_team: TeamData = db.get_team(HOME)
	var away_team: TeamData = db.get_team(AWAY)
	var jersey_h := _jersey(m.entries["home"][5]["node"])
	_check(jersey_h.is_equal_approx(Color.from_string(home_team.kits["home"]["main"], Color.BLACK)) or _jersey_flat(m.entries["home"][5]["node"]),
			"7. the home outfield wears the home kit colour", str(jersey_h))
	var gk_vis: PlayerCharacterVisual = (m.entries["home"][0]["node"] as TeamGoalkeeper).visual
	_check(_jersey(m.entries["home"][0]["node"]).is_equal_approx(Color.from_string(home_team.kits["goalkeeper"]["main"], Color.BLACK)) and gk_vis != null,
			"7b. the goalkeeper wears the goalkeeper kit")
	_check(not _jersey(m.entries["away"][5]["node"]).is_equal_approx(jersey_h), "7c. the two teams are visually distinguishable")
	# kick off and move the clock past the start-up pauses
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	await _frames(10)
	# 8. real gameplay actions through the human's input
	var hum: Dictionary = m.selected
	_check(not hum.is_empty() and hum["ai"] == null, "8. the human controls one player (IntentProvider)")
	var node := hum["node"] as PlayerController
	_isolate(hum)
	node.global_position = Vector3(0.0, 0.0, -4.0)
	node.velocity = Vector3.ZERO                  # no leftover momentum (it used to carry the player 0.4 m away)
	m.ball.reset_ball(Vector3(0.0, 0.2, -4.5))
	await _frames(3)
	var passes_before: int = m.state.stats.teams["home"]["passes"]
	var acts := hum["actions"] as FootballActions
	_check(acts.get_action_availability()[&"pass"] and acts.get_action_availability()[&"shoot"], "8. the ball is at the human player's feet: pass and shoot are available",
			"dist %.2f" % acts.get_ball_distance())
	Input.action_press("pass")
	await _frames(4)
	Input.action_release("pass")
	await _frames(10)
	_check(m.state.stats.teams["home"]["passes"] == passes_before + 1, "8a. a real pass action registers exactly one pass in the statistics", str(m.state.stats.teams["home"]["passes"]))
	await _frames(45)
	_isolate(hum)
	node.global_position = Vector3(0.0, 0.0, -4.0)
	node.velocity = Vector3.ZERO
	m.ball.reset_ball(Vector3(0.0, 0.2, -4.5))
	await _frames(3)
	var shots_before: int = m.state.stats.teams["home"]["shots"]
	Input.action_press("shoot")
	await _frames(4)
	Input.action_release("shoot")
	await _frames(8)
	_check(m.state.stats.teams["home"]["shots"] == shots_before + 1, "8b. a real shot action registers exactly one shot", str(m.state.stats.teams["home"]["shots"]))
	# 9. events
	_check(m.state.events.any(func(e: Dictionary) -> bool: return e["type"] == "shot" and e["side"] == "home"), "9. the shot is in the match event log")
	# 10. goal through the real goal trigger
	var frame := m.frame_side("home")
	var goal_pos: Vector3 = PitchSpace.opponent_goal(frame)
	m.last_toucher_id = hum["player_id"]
	# the goal trigger is the volume of the goal frame/net, i.e. BEHIND the goal line
	m.ball.reset_ball(Vector3(goal_pos.x, 0.5, goal_pos.z + (-1.2 if goal_pos.z < 0.0 else 1.2)))
	await _frames(20)
	_check(m.state.score["home"] == 1 and m.state.score["away"] == 0 and m.state.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal").size() == 1,
			"10. the ball in the away goal scores exactly one goal for home", "%s" % str(m.state.score))
	var goal_ev: Dictionary = m.state.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal")[0]
	_check(goal_ev["player_id"] != "" and m.state.stats.players[goal_ev["player_id"]]["goals"] == 1, "10b. the scorer is credited with the goal")
	# the test moved the keeper away in _isolate(), so the end it defends is read from its post
	var gk_z_first_half: float = (m.entries["home"][0]["node"] as TeamGoalkeeper).home.z
	# 11. complete the first half
	m._pause_left = 0.0
	await _frames(70)                                  # the goal pause ends, the centre restart happens
	m._needs_reset = false
	m.state.kick_off()
	m.state.elapsed = m.state.duration_seconds / 2.0 - 0.02
	await _frames(12)
	_check(m.state.phase == MatchState.Phase.HALF_TIME and m.state.half == 1, "11. the first half ends at half-time")
	# 12. side switching
	m._pause_left = 0.0
	await _frames(8)
	_check(m.state.half == 2 and m.frame_side("home") == "away", "12. the second half starts and the teams have switched ends")
	m._pause_left = 0.0
	await _frames(70)
	var gk_z_second_half: float = (m.entries["home"][0]["node"] as Node3D).global_position.z
	_check(signf(gk_z_second_half) != signf(gk_z_first_half), "12b. the home goalkeeper now stands at the other end", "%.1f -> %.1f" % [gk_z_first_half, gk_z_second_half])
	# 13. complete the second half
	m._needs_reset = false
	if m.state.phase == MatchState.Phase.KICKOFF:
		m.state.kick_off()
	m.state.elapsed = m.state.duration_seconds - 0.02
	var finished := [0]
	m.match_finished.connect(func(_r: MatchResult) -> void: finished[0] += 1)
	await _frames(14)
	_check(m.state.phase == MatchState.Phase.FINISHED and finished[0] == 1, "13. full time: finished once")
	# 14. result
	var result: MatchResult = gm.last_match_result
	_check(result != null and result.home_goals == 1 and result.away_goals == 0 and result.match_id == fixture["match_id"] and result.validate().is_empty(),
			"14. a valid match result is generated from the real match state")
	_check(m.report["home_goals"] == 1 and m.report["outcome_human"] == "win" and m.report["scorers"].size() == 1 and m.report["measured"].has("shots")
			and m.report["team_stats"]["home"]["passes"] >= 1, "14b. the report holds real events, statistics and the human's outcome")
	# 15. competition
	var table: LeagueTable = comp.tables["main"]
	_check(comp.get_fixture(fixture["match_id"])["played"] and table.rows[HOME]["points"] == 3 and table.rows[AWAY]["points"] == 0
			and table.rows[HOME]["gf"] == 1, "15. the competition recorded the result (3 points, 1-0)")
	# 16. finances
	var revenue_after: int = (app.career.ledger().entries as Array).filter(func(e: Dictionary) -> bool: return e["category"] == "match_revenue").size()
	_check(revenue_after == revenue_before + 1 and app.career.ledger().balance > balance_before and app.career.ledger().is_consistent(),
			"16. match revenue was booked exactly once and the ledger is consistent")
	_check(app.career.week == week_before and app.pending_fixture.is_empty(), "16b. the career week is untouched and the fixture is cleared")
	# 17. results screen
	_check(m.results_view != null and (m.results_view.find_child("ScoreLabel", true, false) as Label).text == "1 - 0"
			and m.results_view.find_child("ManOfTheMatch", true, false) != null, "17. the results screen is open with the real score and man of the match")
	# 18-19. save and reload the career
	var snapshot := {"standings": comp.standings(), "log": app.career.match_log.size(), "balance": app.career.ledger().balance,
			"scorer": goal_ev["player_id"], "scorer_look": PlayerAppearance.signature((db.get_player(goal_ev["player_id"]) as PlayerData).appearance),
			"player_count": db.players.size(), "squad": squad.to_dict()}
	_check(app.save_game(SAVE) == "", "18. the career saves")
	m.queue_free()
	await get_tree().process_frame
	db.load_world("")
	app.career = null
	app.squads.clear()
	_check(app.load_game(SAVE) == "", "19. the career reloads into a clean state")
	# 20. consistency
	var comp2: Competition = app.career.competitions["e2e_league"]
	_check(JSON.stringify(comp2.standings()) == JSON.stringify(snapshot["standings"]) and comp2.get_fixture(fixture["match_id"])["played"],
			"20a. the competition state is identical after reload")
	_check(app.career.match_log.size() == snapshot["log"] and app.career.player_stats.has(snapshot["scorer"]) and app.career.player_stats[snapshot["scorer"]]["goals"] == 1,
			"20b. match records and the scorer's totals survived")
	_check(app.career.ledger().balance == snapshot["balance"] and app.career.ledger().is_consistent(), "20c. finances are identical and consistent")
	_check(db.players.size() == snapshot["player_count"] and PlayerAppearance.signature((db.get_player(snapshot["scorer"]) as PlayerData).appearance) == snapshot["scorer_look"],
			"20d. no player lost or duplicated; appearances preserved")
	_check(JSON.stringify(app.squad().to_dict()) == JSON.stringify(snapshot["squad"]), "20e. the user's lineup is unchanged by the match")
	var dup := false
	var seen := {}
	for t: TeamData in db.list_teams():
		for pid in t.squad_ids:
			dup = dup or seen.has(pid)
			seen[pid] = true
	_check(not dup, "20f. no player is in two squads after reloading")
	app.career = null
	app.user_team_id = ""


## Controlled fixture: the other 21 players are moved to the far corners so that no AI player reaches the
## ball during the few frames of a scripted action (the human's input and the engine are untouched).
func _isolate(human: Dictionary) -> void:
	var i := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e == human:
				continue
			(e["node"] as Node3D).global_position = Vector3(-30.0 if i % 2 == 0 else 30.0, 0.0, -42.0 if i % 4 < 2 else 42.0)
			i += 1


func _jersey(node: Node) -> Color:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name.ends_with("Jersey"):
				return mat.albedo_color
	return Color(-1, -1, -1)


## True when the jersey is patterned (the colour then lives in the texture, albedo is white).
func _jersey_flat(node: Node) -> bool:
	return _jersey(node).is_equal_approx(Color.WHITE)
