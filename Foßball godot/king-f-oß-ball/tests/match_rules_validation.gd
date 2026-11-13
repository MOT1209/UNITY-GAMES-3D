## Tackles, fouls, free kicks, penalties, cards: the rules of a real match.
##   godot --headless --path . res://tests/match_rules_validation.tscn
## Every outcome is forced through the tackle roll, so the tests are deterministic; the engine, the match state,
## the statistics, the report and the save/restore round trip are the real ones.
extends Node

const SAVE := "user://test_saves/match_rules.json"
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
	print("=== KING FOOTBALL — Match rules validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	await _test_tackle_outcomes()
	await _test_cards_and_send_off()
	await _test_penalty()
	await _test_report_and_save()
	await _test_human_input()
	await _test_ai_tackles()
	for f in [SAVE, SAVE + ".bak", SAVE + ".tmp"]:
		DirAccess.remove_absolute(f)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _discard(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _match(human := "none") -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 2
	setup.human_side = human
	setup.rng_seed = 11
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


## Puts `victim` (away) on the ball at (x, z) facing `face_z`, `tackler` (home) 1 m away on `behind` side.
func _scene(m: MatchManager, x: float, z: float, behind: bool) -> Array:
	var victim: Dictionary = m.entries["away"][5]
	var tackler: Dictionary = m.entries["home"][5]
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e != victim and e != tackler:
				(e["node"] as CharacterBody3D).global_position = Vector3(-30.0 + park * 2.5, 0.05, 40.0 if side == "home" else -40.0)
				park += 1
	var vn := victim["node"] as CharacterBody3D
	vn.global_position = Vector3(x, 0.05, z)
	vn.global_rotation = Vector3(0.0, 0.0, 0.0)            # faces -Z
	vn.velocity = Vector3.ZERO
	var tn := tackler["node"] as CharacterBody3D
	tn.global_position = Vector3(x, 0.05, z + (1.0 if behind else -1.0))     # +Z is behind a player facing -Z
	tn.velocity = Vector3.ZERO
	m.ball.reset_ball(Vector3(x, 0.2, z - 0.3))
	m.last_toucher_id = victim["player_id"]
	return [tackler, victim]


func _test_tackle_outcomes() -> void:
	var m := _match()
	var tv := _scene(m, 5.0, 0.0, false)
	await _frames(3)
	var t: Dictionary = tv[0]
	var v: Dictionary = tv[1]
	_check(not m.rules.from_behind(t, v), "a tackle from the front is not from behind")
	_scene(m, 5.0, 0.0, true)
	_check(m.rules.from_behind(t, v), "a tackle from behind is detected")
	_scene(m, 5.0, 0.0, false)
	var p_win := m.rules.win_probability(t, v)
	_check(p_win >= 0.15 and p_win <= 0.8, "the win probability stays between 0.15 and 0.8", str(p_win))
	var fouls_before: int = m.state.stats.teams["home"]["fouls"]
	_check(m.rules.resolve(t, v, 0.0) == "won", "a low roll wins the ball")
	_check(m.state.stats.teams["home"]["fouls"] == fouls_before and m.state.phase == MatchState.Phase.PLAYING, "a clean tackle is not a foul and play continues")
	_check(m.rules.resolve(t, v, 0.99) == "missed", "a very high roll misses (no foul)")
	_check(m.state.stats.teams["home"]["fouls"] == fouls_before, "a missed tackle is not a foul")
	_scene(m, 5.0, 0.0, false)
	var roll := m.rules.foul_roll(t, v, 0.0) + 0.0001
	_check(m.rules.resolve(t, v, roll) == "foul", "a roll just above the win chance is a foul")
	_check(m.state.stats.teams["home"]["fouls"] == fouls_before + 1 and m.state.stats.players[t["player_id"]]["fouls"] == 1
			and m.state.stats.players[v["player_id"]]["fouled"] == 1, "the foul is counted for the team, the player and the victim")
	_check(m.state.events.any(func(e: Dictionary) -> bool: return e["type"] == "foul" and e["player_id"] == t["player_id"]), "the foul is in the event log")
	_check(m.state.phase == MatchState.Phase.KICKOFF, "the ball is dead after a foul")
	_check(m.ball.global_position.distance_to(Vector3(5.0, 0.3, 0.0)) < 0.6, "the ball is placed on the foul spot (free kick)", str(m.ball.global_position))
	var wall_ok := true
	for e in m.entries["home"]:
		if int(e["slot"]) != 0 and (e["node"] as Node3D).global_position.distance_to(Vector3(5.0, 0.05, 0.0)) < 8.9:
			wall_ok = false
	_check(wall_ok, "the fouling side stands at least 9 m from the free kick")
	await _frames(120)
	_check(m.state.phase == MatchState.Phase.PLAYING, "play resumes after the free kick pause")
	await _discard(m)


func _test_cards_and_send_off() -> void:
	var m := _match()
	var tv := _scene(m, 5.0, 0.0, true)
	await _frames(3)
	var t: Dictionary = tv[0]
	var v: Dictionary = tv[1]
	var always_foul := m.rules.foul_roll(t, v, 0.9)            # a serious foul from behind
	_check(m.rules.resolve(t, v, always_foul) == "foul", "foul from behind")
	_check(m.state.stats.players[t["player_id"]]["yellow"] == 1 and m.state.stats.teams["home"]["yellows"] == 1, "a foul from behind is a yellow card")
	_check(m.state.events.any(func(e: Dictionary) -> bool: return e["type"] == "yellow_card"), "the yellow card is in the event log")
	await _frames(120)
	_scene(m, 5.0, 0.0, true)
	await _frames(3)
	_check(m.rules.resolve(t, v, always_foul) == "foul", "second foul from behind")
	var p: Dictionary = m.state.stats.players[t["player_id"]]
	_check(p["yellow"] == 2 and p["red"] == 1 and m.state.stats.teams["home"]["reds"] == 1, "a second yellow card is a red card")
	_check(m.rules.sent_off.has(t["player_id"]) and not (t["node"] as Node3D).visible and (t["node"] as Node).process_mode == Node.PROCESS_MODE_DISABLED,
			"the sent-off player leaves the pitch")
	_check(m._closest_to_ball("home", -1).get("player_id", "") != t["player_id"], "a sent-off player is never selected")
	await _discard(m)


func _test_penalty() -> void:
	var m := _match()
	# away is fouled inside the HOME penalty area: home defends +Z in the first half
	var tv := _scene(m, 3.0, 46.0, false)
	await _frames(3)
	var t: Dictionary = tv[0]
	var v: Dictionary = tv[1]
	var roll := m.rules.foul_roll(t, v, 0.5)
	_check(m.rules.resolve(t, v, roll) == "foul", "foul inside the penalty area")
	var spot_z: float = 52.5 - FootballPitch.PENALTY_SPOT_DISTANCE
	_check(absf(m.ball.global_position.z - spot_z) < 0.6 and absf(m.ball.global_position.x) < 0.6, "the ball is on the penalty spot", str(m.ball.global_position))
	var box_clear := true
	for e in m.entries["home"]:
		var pz: float = (e["node"] as Node3D).global_position.z
		if int(e["slot"]) != 0 and pz > 52.5 - FootballPitch.PENALTY_AREA_DEPTH:
			box_clear = false
	_check(box_clear, "the defenders are outside the penalty area")
	await _discard(m)


func _test_report_and_save() -> void:
	var m := _match()
	var tv := _scene(m, 5.0, 0.0, true)
	await _frames(3)
	var t: Dictionary = tv[0]
	var v: Dictionary = tv[1]
	var roll := m.rules.foul_roll(t, v, 0.9)
	m.rules.resolve(t, v, roll)
	m.rules.resolve(t, v, roll)           # still dead ball: ignored, not counted twice
	_check(m.state.stats.teams["home"]["fouls"] == 1, "a foul during dead ball is not counted twice")
	await _frames(120)
	_scene(m, 5.0, 0.0, true)
	m.rules.resolve(t, v, roll)
	var snapshot := m.state.stats.to_dict()
	var copy := MatchStats.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	_check(copy.teams["home"]["fouls"] == 2 and copy.players[t["player_id"]]["red"] == 1 and copy.players[t["player_id"]]["yellow"] == 2,
			"fouls and cards survive a JSON round trip")
	_check(m.save_match(SAVE) == "", "a match with a red card saves")
	var data: Dictionary = MatchSave.read(db, SAVE)["data"]
	var m2 := MatchManager.new()
	m2.return_to_menu_on_finish = false
	add_child(m2)
	_check(m2.restore(data, db) == "", "and restores")
	_check(m2.rules.sent_off.has(t["player_id"]), "the red card is still in force after restoring")
	var report := MatchReport.build(m.state, null, "none")
	_check(int(report["team_stats"]["home"]["fouls"]) == 2 and int(report["team_stats"]["home"]["reds"]) == 1, "the match report carries fouls and cards")
	_check("fouls" in report["measured"] and "cards" in report["measured"], "fouls and cards are declared as measured")
	await _discard(m)
	await _discard(m2)


func _test_human_input() -> void:
	var m := _match("home")
	var hum: Dictionary = m.selected
	var tn := hum["node"] as CharacterBody3D
	var victim: Dictionary = m.entries["away"][5]
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e != victim and e != hum:
				(e["node"] as CharacterBody3D).global_position = Vector3(-30.0 + park * 2.5, 0.05, 40.0 if side == "home" else -40.0)
				park += 1
	var vn := victim["node"] as CharacterBody3D
	vn.global_position = Vector3(0.0, 0.05, 0.0)
	vn.global_rotation = Vector3.ZERO
	tn.global_position = Vector3(0.0, 0.05, -1.0)
	tn.velocity = Vector3.ZERO
	m.ball.reset_ball(Vector3(0.0, 0.2, 0.2))      # at the opponent's feet: he is the ball carrier
	await _frames(4)
	var before: String = m.rules.last_outcome
	Input.action_press("tackle")
	await _frames(3)
	Input.action_release("tackle")
	await _frames(2)
	_check(m.rules.last_outcome != "" or m.rules.cooldown.has(hum["player_id"]), "the tackle button makes the human player attempt a tackle", "before '%s' now '%s'" % [before, m.rules.last_outcome])
	await _discard(m)


## Without any scripted roll: an AI defender next to an AI ball carrier eventually tackles (difficulty 2: 1.3 / s).
func _test_ai_tackles() -> void:
	var m := _match()
	var tv := _scene(m, 5.0, 0.0, false)
	await _frames(2)
	var t: Dictionary = tv[0]
	var attempts := 0
	for i in 12:
		_scene(m, 5.0, 0.0, false)
		m.state.phase = MatchState.Phase.PLAYING
		m.rules.cooldown.clear()
		m.rules.last_outcome = ""
		await _frames(90)
		if m.rules.last_outcome != "" or m.rules.cooldown.has(t["player_id"]) or m.rules.cooldown.size() > 0:
			attempts += 1
	_check(attempts >= 1, "AI defenders tackle the ball carrier on their own (%d of 12 tries)" % attempts)
	await _discard(m)
