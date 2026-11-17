## Career phase C8: manager xp / levels, skill tree effects, achievements, challenges.
##   godot --headless --path . res://tests/manager_progression_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Manager progression validation (C8) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_levels_and_tree()
	_test_effects()
	_test_achievements()
	await _test_play()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_levels_and_tree() -> void:
	var p := ManagerProgress.new()
	_check(p.level() == 1 and p.points_available() == 0, "a new manager is level 1 with no points")
	_check(p.spend("negotiation") == "SKILL_ERR_POINTS", "no points, no skill")
	_check(p.add_xp(250) == 2 and p.level() == 3 and p.points_available() == 2, "250 xp = level 3, two points")
	_check(p.spend("negotiation") == "" and p.spend("negotiation") == "" and p.spend("negotiation") == "SKILL_ERR_POINTS", "points are spent one at a time")
	_check(p.spend("magic") == "SKILL_ERR_UNKNOWN", "an unknown branch is refused")
	p.add_xp(5000)
	for i in 6:
		p.spend("youth")
	_check(p.branch_levels["youth"] == 4 and p.spend("youth") == "SKILL_ERR_MAX", "a branch stops at 4 levels")
	_check(is_equal_approx(p.effect("youth"), 0.10) and p.effect("youth") <= 0.10 + 0.0001, "a complete branch is worth at most 10%")
	_check(p.level() <= ManagerProgress.MAX_LEVEL, "levels are capped")
	var back := ManagerProgress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	_check(back.xp == p.xp and back.branch_levels == p.branch_levels and back.points_available() == p.points_available(), "progress is saved")
	_check(ManagerProgress.from_dict({"branches": {"youth": 99}}).branch_levels["youth"] == 4, "damaged data is clamped")
	_check(ManagerProgress.xp_for_season(true, true, false) > ManagerProgress.xp_for_season(false, false, false), "titles give more experience")


func _test_effects() -> void:
	var c: CareerState = app.career
	var victim: PlayerData = null
	for t: TeamData in app.db.list_teams(TeamData.Category.CLUB):
		if t.id == "club_desert_kings" or victim != null:
			continue
		for pl: PlayerData in app.db.get_squad(t.id):
			if pl.status != PlayerData.Status.YOUTH and pl.loan_parent == "" and t.squad_ids.size() > TransferMarket.MIN_SQUAD:
				victim = pl
				break
	_check(victim != null, "a player to negotiate for exists")
	var m: TransferMarket = c.market
	var price := m.asking_price(victim)
	var low := int(price * 0.97)
	c.progress.branch_levels["negotiation"] = 0
	var none: Dictionary = m.negotiate(c.club_id, victim.id, low, c.week)
	c.progress.branch_levels["negotiation"] = 4
	var skilled: Dictionary = m.negotiate(c.club_id, victim.id, low, c.week)
	_check(none["status"] != "accepted" and skilled["status"] == "accepted", "a negotiation master gets the player for 3% under the asking price")
	var other: Dictionary = m.negotiate("club_royal_harbor", victim.id, low, c.week) if victim.team_id != "club_royal_harbor" else {"status": "counter"}
	_check(other["status"] != "accepted", "other clubs get no such discount")
	c.progress.branch_levels["negotiation"] = 0
	c.progress.branch_levels["fitness"] = 4
	_check(c.injury_factor_for(c.club_id) < 1.0 and c.injury_factor_for("club_royal_harbor") == 1.0, "the fitness branch lowers the managed club's injuries only")
	c.progress.branch_levels["fitness"] = 0
	c.progress.branch_levels["management"] = 4
	var ev := {"confidence": -20, "reputation": 0}
	var dc := int(round(float(ev["confidence"]) * (1.0 - c.progress.effect("management"))))
	_check(dc == -18, "the management branch softens confidence losses (-20 becomes %d)" % dc)
	c.progress.branch_levels["management"] = 0


func _test_achievements() -> void:
	var c: CareerState = app.career
	var p := c.progress
	p.unlocked.clear()
	var start_unlocks := p.check_achievements(c)
	_check(not start_unlocks.has("first_win") and not start_unlocks.has("first_trophy") and not start_unlocks.has("promoted"), "no play-earned achievement is unlocked at the start", str(start_unlocks))
	p.record_result("win")
	var fresh := p.check_achievements(c)
	_check(fresh == ["first_win"], "the first win unlocks its achievement", str(fresh))
	_check(p.check_achievements(c).is_empty(), "an achievement is awarded once")
	for i in 10:
		p.record_result("win")
	var more := p.check_achievements(c)
	_check(more.has("ten_wins") and more.has("unbeaten_streak") and more.has("ten_streak"), "wins and streaks unlock theirs", str(more))
	p.record_result("loss")
	_check(p.streak == 0 and p.best_streak == 11, "a loss ends the streak but keeps the record")
	_check(ManagerProgress.definitions().size() >= 20, "there is a set of achievements (%d)" % ManagerProgress.definitions().size())
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.progress.unlocked == p.unlocked and back.progress.wins == p.wins, "unlocked achievements survive a save")
	var before := c.manager.reputation
	p.challenges = ManagerProgress.new_challenges(1)
	for i in 3:
		p.progress_challenge("win_3", 1, c)
	_check(c.manager.reputation == before + 1 and p.challenges[0]["done"], "a finished challenge pays its reward once")
	p.progress_challenge("win_3", 1, c)
	_check(c.manager.reputation == before + 1, "...and not twice")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_play() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var guard := 0
	while c.week < 14 and guard < 30:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_check(c.progress.wins + c.progress.draws + c.progress.losses > 0 and c.progress.xp > 0, "playing weeks earns results and experience (%d xp)" % c.progress.xp)
	_check(c.progress.unlocked.has("first_win") == (c.progress.wins >= 1), "achievements follow the results")
	_check(c.inbox.messages.any(func(m: Dictionary) -> bool: return str(m["uid"]).begins_with("ach:")) == (not c.progress.unlocked.is_empty()), "unlocked achievements reach the inbox")
