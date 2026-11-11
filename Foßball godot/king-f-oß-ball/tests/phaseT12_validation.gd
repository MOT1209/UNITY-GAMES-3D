## Phase T12 validation — end-to-end integration, regression guards, performance:
##   godot --headless --path . res://tests/phaseT12_validation.tscn
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
	print("=== KING FOOTBALL — Phase T12 validation ===")
	_test_project_integrity()
	_test_end_to_end_career()
	_test_data_integrity_after_everything()
	await _test_performance()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _test_project_integrity() -> void:
	_check(not FileAccess.file_exists("res://main.tscn"), "stray root main.tscn removed")
	_check(str(ProjectSettings.get_setting("application/config/version")) != "0.1.0-phase1", "project version updated")
	for autoload in ["GameManager", "TeamDB", "AppHub"]:
		_check(ProjectSettings.has_setting("autoload/%s" % autoload), "autoload %s registered" % autoload)
	for action in ["move_forward", "move_backward", "move_left", "move_right", "sprint", "pass", "shoot", "lob_pass", "dribble", "tackle", "switch_player"]:
		_check(InputMap.has_action(action), "input action %s still mapped" % action)
	for path in ["res://scenes/player/player.tscn", "res://scenes/ball/football_ball.tscn", "res://scenes/stadium/stadium_arena.tscn",
			"res://scenes/match/match_scene.tscn", "res://ui/hub/hub.tscn", "res://ui/main_menu/main_menu.tscn"]:
		_check(load(path) is PackedScene, "scene loads: %s" % path)
	var dir := DirAccess.open("res://scripts")
	var missing: Array[String] = []
	_collect_missing("res://scripts", missing)
	_check(missing.is_empty(), "every script loads", str(missing))


func _collect_missing(path: String, missing: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd") and load("%s/%s" % [path, f]) == null:
			missing.append("%s/%s" % [path, f])
	for d in dir.get_directories():
		_collect_missing("%s/%s" % [path, d], missing)


## Full journey: create club → academy → scout → train → promote → lineup → match → competition → finance → save/load.
func _test_end_to_end_career() -> void:
	var db := _db()
	var made := ClubCreator.create_club(db, {"name": "Integration FC", "short_name": "INT", "country": "Aldoria",
			"primary": Color("d35400"), "secondary": Color("ecf0f1"), "strength": 60, "seed": 12}, false)
	_check(made["ok"], "e2e: custom club created", made["error"])
	var club: String = made["team_id"]
	var career := CareerState.start(db, club)
	_check(career != null, "e2e: career started with the new club")
	var academy := Academy.new(club, "Aldoria", 77)
	academy.budget = 2_000_000
	academy.quality = 0.7
	academy.generate_intake(db, 15, 17)
	var scouting := ScoutingSystem.new(5)
	scouting.add_scout("s", "Scout", 0.9, 1000)
	scouting.start_mission(academy, "s", "Solmara", 2)
	scouting.advance_week(db, academy)
	var found := scouting.advance_week(db, academy)
	_check(found.size() > 0, "e2e: scouting found prospects")
	_check(scouting.sign_prospect(db, academy, found[0]) == "", "e2e: prospect signed")
	var plan := TrainingSystem.new()
	plan.set_group_focus("U17", "passing")
	plan.set_group_focus("U19", "shooting")
	plan.set_group_focus("U15", "dribbling")
	for i in 12:
		plan.advance_week(db, academy)
		career.advance_week()
	var candidate := ""
	var best := -1
	for pid in academy.roster_ids:
		var p := db.get_player(pid)
		if p.age >= AcademyConfig.MIN_PROMOTION_AGE and p.get_overall() > best:
			best = p.get_overall()
			candidate = pid
	var history_len: int = db.get_player(candidate).development_history.size()
	_check(PromotionSystem.promote(db, academy, candidate, 40) == "", "e2e: academy player promoted")
	var squad := Squad.new(club, "4-2-3-1")
	squad.auto_pick(db)
	_check(squad.validate(db).is_empty(), "e2e: lineup valid after promotion")
	_check(db.get_player(candidate).development_history.size() == history_len + 1, "e2e: promoted player keeps development history")
	# Transfers
	var market := career.market
	var target: PlayerData = null
	for p in market.search({"exclude_team": club, "max_price": 3_000_000}):
		target = p
		break
	if target != null:
		var err := market.buy(club, target.id, market.asking_price(target), maxi(market.minimum_wage(target), target.salary), 3, career.week, {club: squad})
		_check(err == "" or err.find("budget") >= 0 or err.find("wage") >= 0 or err.find("funds") >= 0, "e2e: transfer succeeds or is refused for financial reasons", err)
	# Competition + match engine results
	var rivals: Array = ["club_royal_harbor", "club_obsidian", "club_sunvale"]
	var comp := Competition.create_league("e2e", "E2E League", [club] + rivals, true)
	career.register_competition(comp)
	var played := 0
	var guard := 0
	while not comp.is_finished() and guard < 100:
		guard += 1
		var f: Dictionary = comp.pending_fixtures()[0]
		var setup := MatchSetup.new()
		setup.home_id = f["home"]
		setup.away_id = f["away"]
		setup.match_id = f["match_id"]
		if played < 2:
			_check(setup.validate(db).is_empty(), "e2e: fixture %d is a valid match" % played)
		var st := MatchState.create(f["home"], f["away"], 5, f["match_id"])
		st.kick_off()
		var home_goals := (played * 3 + 1) % 4
		for g in home_goals:
			st.goal("home", "x")
			st.kick_off()
		if played % 2 == 0:
			st.goal("away", "y")
		var res := st.to_result(false)
		var err := career.submit_result("e2e", res)
		if err != "":
			print("  e2e result error: ", err)
			break
		played += 1
	_check(comp.is_finished() and played == 12, "e2e: 12-match league completed from engine-style results", str(played))
	_check(comp.results.size() == comp.fixtures.size(), "e2e: no duplicate or missing results")
	for tid in career.ledgers:
		_check(career.ledgers[tid].is_consistent(), "e2e: ledger audit for %s" % tid)
	_check(career.ledgers[comp.champion_id].total("competition_reward") >= 1_000_000, "e2e: champion paid")
	# Save / load everything
	var path := "user://test_saves/t12.json"
	var data := SaveManager.capture(db, {club: academy}, {club: scouting}, {club: plan}, {club: squad}, {"career": career.to_dict()})
	_check(SaveManager.write_file(path, data) == "", "e2e: save written")
	var db2 := _db()
	var rd := SaveManager.read_file(path)
	var res := SaveManager.restore(db2, rd["data"])
	_check(res["ok"], "e2e: save restored", str(res["errors"]))
	var p1 := db.get_player(candidate).to_dict()
	var p2 := db2.get_player(candidate).to_dict()
	_check(p1 == p2, "e2e: promoted player identical after save/load")
	_check(candidate in db2.get_team(club).squad_ids and not (candidate in (res["academies"][club] as Academy).roster_ids), "e2e: promoted player stays in the first team after load")
	var career2 := CareerState.from_dict(db2, res["extras"]["career"])
	_check(career2.competitions["e2e"].champion_id == comp.champion_id, "e2e: competition result persisted")
	_check(career2.ledger().balance == career.ledger().balance, "e2e: finances persisted")
	var n_before := db2.players.size()
	(res["academies"][club] as Academy).generate_intake(db2, 3, 17)
	_check(db2.players.size() == n_before + 3, "e2e: loading never regenerates academy players; new intake only adds new ones")
	DirAccess.remove_absolute(path)
	db.free()
	db2.free()


func _test_data_integrity_after_everything() -> void:
	var db := _db()
	var squad_owner := {}
	var dup := false
	for t: TeamData in db.teams.values():
		for pid in t.squad_ids:
			if squad_owner.has(pid):
				dup = true
			squad_owner[pid] = t.id
	_check(not dup, "seed data: no player in two squads")
	_check(db.errors.is_empty(), "seed data loads with no errors", str(db.errors))
	var all_valid := true
	for p: PlayerData in db.players.values():
		if not p.validate().is_empty():
			all_valid = false
	_check(all_valid, "seed data: every player validates")
	db.free()


func _test_performance() -> void:
	var db: TeamDatabase = get_node("/root/TeamDB")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_obsidian"
	setup.duration_minutes = 5
	var manager := MatchManager.new()
	manager.return_to_menu_on_finish = false
	add_child(manager)
	var err := manager.begin(setup, db)
	_check(err == "", "perf: 22-player match starts", err)
	if err != "":
		manager.queue_free()
		return
	for i in 60:
		await get_tree().physics_frame
	var samples: Array[float] = []
	for i in 180:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var sum := 0.0
	var worst := 0.0
	for s in samples:
		sum += s
		worst = maxf(worst, s)
	var avg := sum / samples.size()
	print("  perf: avg %.2f ms, worst %.2f ms per physics frame (22 players + ball, headless)" % [avg, worst])
	_check(avg < 33.0, "perf: average physics frame under 33 ms with 22 players", "%.2f ms" % avg)
	var moving := 0
	for side in manager.entries:
		for e in manager.entries[side]:
			if (e["node"] as PlayerController).get_current_speed() > 0.1:
				moving += 1
	_check(moving > 0, "perf: players are actually simulating")
	manager.queue_free()
	await get_tree().process_frame
