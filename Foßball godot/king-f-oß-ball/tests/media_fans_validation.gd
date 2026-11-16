## Career phase C6: fan satisfaction, social posts, rumours, trophy room, hall of fame, season summary.
##   godot --headless --path . res://tests/media_fans_validation.tscn
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
	print("=== KING FOOTBALL — Media and fans validation (C6) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_fans()
	_test_posts()
	await _test_rumours()
	await _test_history()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_fans() -> void:
	var c: CareerState = app.career
	c.fan_mood = 60
	var m := c.media
	_check(m.fan_event(c, 5, "FAN_WIN") == 5 and c.fan_mood == 65, "a win lifts the fans")
	_check(m.fan_event(c, -80, "FAN_LOSS") == -65 and c.fan_mood == 0, "the mood stays within 0-100")
	_check(m.fan_event(c, -3, "FAN_LOSS") == 0 and m.fan_reasons().size() == 2, "nothing is logged when nothing moved")
	_check(m.fan_reasons()[0]["key"] == "FAN_LOSS", "reasons are listed newest first")
	for i in 12:
		c.fan_mood = 50
		m.fan_event(c, 1, "FAN_WIN")
	_check(m.fan_reasons().size() == MediaFans.FAN_LOG_MAX, "the log is bounded")
	_check(MediaFans.attendance_from_mood(100) > MediaFans.attendance_from_mood(10), "a happier crowd fills more seats")
	var back := MediaFans.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(back.fan_reasons() == m.fan_reasons(), "fan reasons are saved")
	c.economy.set_ticket_level("high")
	c.fan_mood = 60
	var before := c.fan_mood
	for i in 8:
		c.record_match_revenue(c.club_id)
	_check(c.fan_mood < before, "ticket prices move the fans (60 -> %d)" % c.fan_mood)
	c.economy.set_ticket_level("normal")
	c.fan_mood = 60


func _test_posts() -> void:
	var c: CareerState = app.career
	var a := MediaFans.match_post(c, "win", "club_royal_harbor", "3-0")
	_check(a == MediaFans.match_post(c, "win", "club_royal_harbor", "3-0") and str(a["key"]).begins_with("POST_WIN"), "a post is a stable translated template")
	_check(MediaFans.match_post(c, "nothing", "x", "0-0").is_empty(), "an unknown outcome makes no post")
	for lang in ["en", "de", "ar"]:
		Loc.set_language(lang, false)
		var text := Loc.f(str(a["key"]), a["args"])
		_check(text != "" and not text.begins_with("POST_"), "the post is translated (%s)" % lang)
	Loc.set_language("en", false)
	var n := c.inbox.messages.size()
	c.media.post_match(c, "win", "club_royal_harbor", "3-0")
	c.media.post_match(c, "win", "club_royal_harbor", "3-0")
	_check(c.inbox.messages.size() == n + 1 and c.inbox.messages[-1]["category"] == "media", "the post reaches the inbox once, under media")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_rumours() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var made := 0
	var true_ones := 0
	for w in range(1, 41):
		c.week = w
		var r := c.media.weekly_rumour(c)
		if not r.is_empty():
			made += 1
			true_ones += 1 if r["true"] else 0
	_check(made >= 2 and made <= 20, "rumours appear now and then (%d in 40 weeks)" % made)
	_check(true_ones > 0 and true_ones < made, "some rumours are true and some are not (%d of %d)" % [true_ones, made])
	_check(c.inbox.messages.any(func(m: Dictionary) -> bool: return m["key"] == "INBOX_RUMOUR"), "rumours are inbox messages")
	var offers_before := c.market.offers.size()
	var delivered := 0
	for w in range(1, 45):
		c.week = w
		delivered += c.media.deliver_rumours(c)
	_check(delivered > 0 and c.market.offers.size() > offers_before, "a true rumour is followed by a real offer (%d)" % delivered)
	var first_true: Dictionary = {}
	for r in c.media.rumours:
		if r["true"] and first_true.is_empty():
			first_true = r
	_check(not first_true.is_empty() and int(first_true["due_week"]) - int(first_true["week"]) <= 2, "...within two weeks of the rumour")
	var back := MediaFans.from_dict(JSON.parse_string(JSON.stringify(c.media.to_dict())))
	_check(back.rumours.size() == c.media.rumours.size(), "rumours are saved")
	c.week = 0


func _test_history() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var guard := 0
	while c.week < CareerState.WEEKS_PER_SEASON and guard < 80:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_simulate_due()
	var sm := MediaFans.season_summary(c)
	var ud := c.user_division()
	var comp: Competition = c.competitions[(c.pyramids[ud["pyramid"]] as LeaguePyramid).comp[ud["division"]["id"]]]
	var row: Dictionary = {}
	for r in comp.standings():
		if r["team_id"] == c.club_id:
			row = r
	_check(not row.is_empty() and sm["points"] == row["points"] and sm["goals_for"] == row["gf"] and sm["goals_against"] == row["ga"] and sm["played"] == row["played"], "the season summary matches the real table row")
	_check(sm["rank"] >= 1 and sm["net_finance"] != 0, "rank and finances are filled")
	var hall := MediaFans.hall_of_fame(c)
	_check(not (hall["scorers"] as Array).is_empty() or c.player_stats.is_empty(), "the hall of fame lists scorers when there are statistics")
	var room := MediaFans.trophy_room(c)
	_check(room["titles"] is Array and room["manager_trophies"] == c.manager.trophies, "the trophy room reads the real history")
	c.manager.trophies = 0
	c.club_history.append({"key": "rewards_paid_x", "season": 1, "competition": "fic_league_s1", "champion": c.club_id, "runner_up": "z"})
	_check(MediaFans.trophy_room(c)["titles"].size() == 1, "a title in the history shows in the trophy room")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("club_history")
		await get_tree().process_frame
		_check(hub.current.find_child("SeasonSummary", true, false) != null and hub.current.find_child("TrophyRoom", true, false) != null and hub.current.find_child("HallOfFame", true, false) != null, "the club history screen builds (%s)" % lang)
	Loc.set_language("en", false)
	hub.queue_free()
