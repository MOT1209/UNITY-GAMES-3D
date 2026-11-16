## Career phase C5 (without national teams): derbies, club reputation, other managers, monthly / season awards, Super Cup.
##   godot --headless --path . res://tests/living_world_validation.tscn
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
	print("=== KING FOOTBALL — Living world validation (C5) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_derbies()
	await _test_three_seasons()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_derbies() -> void:
	var clubs: Array = app.db.list_teams(TeamData.Category.CLUB)
	var with_rival := 0
	var symmetric := true
	for t: TeamData in clubs:
		var r := WorldLife.rival_of(app.db, t.id)
		if r != "":
			with_rival += 1
			symmetric = symmetric and WorldLife.rival_of(app.db, r) == t.id and WorldLife.is_derby(app.db, t.id, r)
	_check(with_rival >= clubs.size() - 1 and symmetric, "every club has a rival and rivalry is symmetric (%d of %d)" % [with_rival, clubs.size()])
	_check(WorldLife.rival_of(app.db, "club_desert_kings") == WorldLife.rival_of(app.db, "club_desert_kings"), "rivals are stable")
	_check(not WorldLife.is_derby(app.db, "club_desert_kings", "club_desert_kings"), "a club is not its own rival")
	var c: CareerState = app.career
	var rival := WorldLife.rival_of(app.db, c.club_id)
	var r1 := MatchResult.make("d1", c.club_id, rival, 1, 0)
	var r2 := MatchResult.make("d2", c.club_id, "club_royal_harbor" if rival != "club_royal_harbor" else "club_sunvale", 1, 0)
	c.submit_result(c.competitions.keys()[0], r1)
	var rid := ""
	for cid in c.competitions:
		rid = str(cid)
		break
	c._derby_boost = 1.0
	c.submit_result(rid, r1)
	_check(c._derby_boost == 1.25, "a derby result raises the matchday income factor")
	c.submit_result(rid, r2)
	_check(c._derby_boost == 1.0, "an ordinary match does not")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _play_season(c: CareerState) -> void:
	var guard := 0
	while c.week < CareerState.WEEKS_PER_SEASON and guard < 80:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_simulate_due()


func _test_three_seasons() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var rep_start := {}
	for t: TeamData in app.db.list_teams(TeamData.Category.CLUB):
		rep_start[t.id] = t.reputation
	var changes := 0
	var rep_prev := rep_start.duplicate()
	var max_step := 0
	for s in 3:
		await _play_season(c)
		var managers_before := c.world.ai_managers.duplicate(true)
		c.end_season(app.academies, app.squads)
		for t: TeamData in app.db.list_teams(TeamData.Category.CLUB):
			max_step = maxi(max_step, absi(t.reputation - int(rep_prev[t.id])))
			rep_prev[t.id] = t.reputation
		if c.manager.unemployed:
			break
	_check(max_step <= WorldLife.REPUTATION_MAX_STEP, "club reputation never moves more than %d in a season (max %d)" % [WorldLife.REPUTATION_MAX_STEP, max_step])
	var moved := 0
	var in_range := true
	for t: TeamData in app.db.list_teams(TeamData.Category.CLUB):
		if t.reputation != int(rep_start[t.id]):
			moved += 1
		in_range = in_range and t.reputation >= 1 and t.reputation <= 99
	_check(moved >= 2 and in_range, "reputations changed for %d clubs and stay within 1-99" % moved)
	var managed := c.world.ai_managers.size()
	_check(managed > 0, "other clubs have managers (%d known)" % managed)
	var best: Array = app.db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.id != c.club_id)
	best.sort_custom(func(a: TeamData, b: TeamData) -> bool: return app.db.get_team_rating(a.id) > app.db.get_team_rating(b.id))
	var order: Array = app.db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	order.erase(best[0].id)
	order.append(best[0].id)                                   # the best squad finishes last
	var old_name: String = c.world.manager_of(app.db, best[0].id, c.season)["name"]
	var res := c.world.review_managers(c, {"x": {"tables": {"d1": order}}})
	_check(res.any(func(r: Dictionary) -> bool: return r["club"] == best[0].id and r["old"] == old_name and r["new"] != old_name), "a strong club that finishes last sacks its manager")
	_check(c.events.any(func(e: Dictionary) -> bool: return e["kind"] == "manager_change"), "...and it is in the news")
	_check(c.world.award_log.any(func(a: Dictionary) -> bool: return a["kind"] == "manager_of_season"), "a manager of the season is chosen")
	await app.advance_week_async()
	_check(c.world.super_cups.size() >= 1 or c.manager.unemployed, "the Super Cup is played in week 1 of the next season (%d played)" % c.world.super_cups.size())
	if not c.world.super_cups.is_empty():
		var sc: Dictionary = c.world.super_cups[0]
		_check(sc["winner"] in [sc["home"], sc["away"]] and sc["home"] != sc["away"], "the Super Cup has a winner among its two clubs")
	var guard := 0
	while c.week < 9 and guard < 12:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_check(c.world.award_log.any(func(a: Dictionary) -> bool: return a["kind"] == "manager_of_month" or a["kind"] == "player_of_month"), "monthly awards are given")
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.world.super_cups == c.world.super_cups and back.world.ai_managers.size() == c.world.ai_managers.size() and back.world.award_log.size() == c.world.award_log.size(), "the living-world state is saved")
	var feed := NewsFeed.build(c, 200)
	_check(feed.size() > 0, "the news feed still builds with the new events")
