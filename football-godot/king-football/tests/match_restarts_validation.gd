## Ball out of play (throw-in, corner, goal kick) and offside.
##   godot --headless --path . res://tests/match_restarts_validation.tscn
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

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
	print("=== KING FOOTBALL — Restarts and offside validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	await _test_out_of_play()
	await _test_offside()
	await _test_live_ball_out()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _match() -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 21
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	return m


func _discard(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


## Parks everybody far away on the touchline area behind the stands, so nothing interferes.
func _park(m: MatchManager, keep: Array) -> void:
	var i := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if not (e in keep):
				(e["node"] as CharacterBody3D).global_position = Vector3(-30.0 + (i % 12) * 5.0, 0.05, 30.0 + (i / 12) * 5.0)
				(e["node"] as CharacterBody3D).velocity = Vector3.ZERO
				i += 1


func _test_out_of_play() -> void:
	var m := _match()
	var home5: Dictionary = m.entries["home"][5]
	var away5: Dictionary = m.entries["away"][5]
	var rs: MatchRestarts = m.rules.restarts
	# throw-in: home touched it last, ball over the right touchline
	m.last_toucher_id = home5["player_id"]
	m.ball.reset_ball(Vector3(36.0, 0.3, 10.0))
	_check(rs.check_out_of_play() == "throw_in", "ball over the touchline: throw-in")
	_check(m.state.stats.teams["away"]["throw_ins"] == 1 and m.state.stats.teams["home"]["throw_ins"] == 0, "the throw-in is counted for the side that did not touch it last")
	_check(m.state.phase == MatchState.Phase.KICKOFF and absf(absf(m.ball.global_position.x) - 33.5) < 0.6 and absf(m.ball.global_position.z - 10.0) < 0.6,
			"the ball is put back on the touchline at the same height", str(m.ball.global_position))
	_check(m.state.events.any(func(e: Dictionary) -> bool: return e["type"] == "throw_in" and e["side"] == "away"), "the throw-in is in the event log")
	await _frames(120)
	_check(m.state.phase == MatchState.Phase.PLAYING, "play resumes after the throw-in pause")
	# corner: away (defends the -Z end in the first half) touched it last, ball over that goal line outside the goal
	_park(m, [])
	m.last_toucher_id = away5["player_id"]
	m.ball.reset_ball(Vector3(20.0, 0.3, -54.0))
	_check(rs.check_out_of_play() == "corner", "defender touched it last over the goal line: corner")
	_check(m.state.stats.teams["home"]["corners"] == 1, "the corner is counted for the attackers")
	_check(m.ball.global_position.x > 32.0 and m.ball.global_position.z < -51.0, "the ball is in the corner on the side it left", str(m.ball.global_position))
	await _frames(120)
	# goal kick: attacker touched it last
	_park(m, [])
	m.last_toucher_id = home5["player_id"]
	m.ball.reset_ball(Vector3(-20.0, 0.3, -54.0))
	_check(rs.check_out_of_play() == "goal_kick", "attacker touched it last over the goal line: goal kick")
	_check(m.state.stats.teams["away"]["goal_kicks"] == 1, "the goal kick is counted for the defenders")
	_check(absf(m.ball.global_position.z + (52.5 - FootballPitch.GOAL_AREA_DEPTH)) < 0.6, "the ball is on the edge of the goal area", str(m.ball.global_position))
	# the goal mouth belongs to the goal trigger
	await _frames(120)
	m.ball.reset_ball(Vector3(0.0, 0.3, -54.0))
	_check(rs.check_out_of_play() == "" and m.state.phase == MatchState.Phase.PLAYING, "ball behind the line inside the goal mouth is left to the goal trigger")
	m.ball.reset_ball(Vector3(10.0, 0.3, 0.0))
	_check(rs.check_out_of_play() == "", "ball in play: nothing happens")
	await _discard(m)


func _test_offside() -> void:
	var m := _match()
	var rs: MatchRestarts = m.rules.restarts
	var passer: Dictionary = m.entries["home"][6]
	var onside: Dictionary = m.entries["home"][7]
	var level: Dictionary = m.entries["home"][8]
	var offs: Dictionary = m.entries["home"][9]
	_park(m, [passer, onside, level, offs])
	for e in m.entries["away"]:
		if int(e["slot"]) == 0:
			(e["node"] as Node3D).global_position = Vector3(0.0, 0.05, -50.0)    # keeper deepest
		elif e == m.entries["away"][5]:
			(e["node"] as Node3D).global_position = Vector3(5.0, 0.05, -10.0)    # last outfield defender (second-last opponent)
		else:
			(e["node"] as Node3D).global_position = Vector3(-5.0, 0.05, 0.0)
	(passer["node"] as Node3D).global_position = Vector3(0.0, 0.05, 0.0)
	(onside["node"] as Node3D).global_position = Vector3(8.0, 0.05, -5.0)
	(level["node"] as Node3D).global_position = Vector3(-8.0, 0.05, -10.0)
	(offs["node"] as Node3D).global_position = Vector3(10.0, 0.05, -30.0)
	m.ball.reset_ball(Vector3(0.0, 0.3, 0.0))
	var list := rs.offside_positioned("home", 0.0)
	_check(offs["player_id"] in list, "a team-mate ahead of the ball and the second-last opponent is in an offside position")
	_check(not (onside["player_id"] in list), "a team-mate behind the second-last opponent is onside")
	_check(not (level["player_id"] in list), "a team-mate level with the second-last opponent is onside")
	_check(not (passer["player_id"] in list) and not (m.entries["home"][0]["player_id"] in list), "the passer and the keeper are never offside")
	# onside reception
	rs.on_pass("home", passer["player_id"])
	_check(rs.on_owner(onside) == "" and m.state.phase == MatchState.Phase.PLAYING, "receiving the pass onside: play goes on")
	# opponent gets it first: no offside afterwards
	rs.on_pass("home", passer["player_id"])
	rs.on_owner(m.entries["away"][5])
	_check(rs.on_owner(offs) == "", "an opponent touch in between cancels the offside")
	# offside reception
	rs.on_pass("home", passer["player_id"])
	_check(rs.on_owner(offs) == "offside", "receiving the pass in an offside position is offside")
	_check(m.state.stats.teams["home"]["offsides"] == 1 and m.state.stats.players[offs["player_id"]]["offsides"] == 1, "the offside is counted for the team and the player")
	_check(m.state.events.any(func(e: Dictionary) -> bool: return e["type"] == "offside" and e["player_id"] == offs["player_id"]), "the offside is in the event log")
	_check(m.state.phase == MatchState.Phase.KICKOFF and m.ball.global_position.distance_to(Vector3(10.0, 0.3, -30.0)) < 0.6, "the indirect free kick is taken where he received it", str(m.ball.global_position))
	var report := MatchReport.build(m.state, null, "none")
	_check(int(report["team_stats"]["home"]["offsides"]) == 1 and "offsides" in report["measured"] and "corners" in report["measured"], "the report carries offsides and declares them measured")
	var copy := MatchStats.from_dict(JSON.parse_string(JSON.stringify(m.state.stats.to_dict())))
	_check(copy.teams["home"]["offsides"] == 1 and copy.teams["away"]["throw_ins"] == 0, "restart counters survive a JSON round trip")
	await _frames(120)
	# a pass played from the own half to a player in his own half is never offside
	rs.on_pass("home", passer["player_id"])
	(offs["node"] as Node3D).global_position = Vector3(0.0, 0.05, 20.0)
	_check(rs.on_owner(offs) == "", "a player in his own half is never offside")
	await _discard(m)


## No scripted call: the ball really leaves the pitch in a running match and the rules react on their own.
func _test_live_ball_out() -> void:
	var m := _match()
	_park(m, [])
	m.last_toucher_id = m.entries["home"][5]["player_id"]
	m.ball.reset_ball(Vector3(30.0, 0.3, 5.0))
	m.ball.linear_velocity = Vector3(12.0, 0.0, 0.0)
	await _frames(90)
	_check(m.state.stats.teams["away"]["throw_ins"] >= 1, "a ball rolling over the touchline in a running match produces a throw-in by itself")
	await _discard(m)
