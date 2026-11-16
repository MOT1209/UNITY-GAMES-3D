## Career phase C2 (board part): club vision (C2.1), extra objectives (C2.2), board meetings (C2.3), promises (C2.4).
##   godot --headless --path . res://tests/board_vision_validation.tscn
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
	print("=== KING FOOTBALL — Board / vision validation (C2 board part) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_vision()
	_test_meetings()
	_test_promises()
	await _test_season_review()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_vision() -> void:
	var c: CareerState = app.career
	var seen := {}
	for t: TeamData in app.db.list_teams(TeamData.Category.CLUB):
		seen[c.vision(t.id)] = true
	_check(seen.size() >= 2, "different clubs get different visions (%s)" % str(seen.keys()))
	_check(seen.keys().all(func(v: String) -> bool: return ClubVision.VISIONS.has(v)), "every vision is a known one")
	_check(c.vision() == c.vision(c.club_id), "the user's club has a vision like any other")
	var shapes := {}
	for v in ClubVision.VISIONS:
		shapes[v] = str(ClubVision.extras_for(v, 1000))
	_check(shapes["youth"] != shapes["profit"], "a youth club and a profit club get different extra objectives")
	_check(c.season_extras.size() >= 1, "the running season has extra objectives for the vision", str(c.season_extras))
	var d := c.to_dict()
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(d)))
	_check(back.season_extras == c.season_extras, "the extra objectives are saved")


func _test_meetings() -> void:
	var c: CareerState = app.career
	var b := c.board
	c.manager.confidence = 90
	c.ledger().balance = 5_000_000
	var tb := c.ledger().transfer_budget
	var r := b.request(c, "transfer_budget", "stability")
	_check(r["accepted"] and c.ledger().transfer_budget > tb and int(r["amount"]) > 0, "a trusted manager gets more transfer budget")
	var again := b.request(c, "transfer_budget", "stability")
	_check(not again["accepted"] and again["reason"] == "BOARD_REASON_TOO_SOON", "a second request right after is refused")
	c.week += Board_cooldown()
	c.manager.confidence = 30
	var low := b.request(c, "wage_budget", "stability")
	_check(not low["accepted"] and low["reason"] == "BOARD_REASON_CONFIDENCE", "a manager with low confidence is refused")
	var conf_before := c.manager.confidence
	c.week += Board_cooldown()
	var low2 := b.request(c, "wage_budget", "stability")
	_check(not low2["accepted"] and c.manager.confidence == conf_before - 1, "two refusals in a row cost a little confidence")
	c.week += Board_cooldown()
	c.manager.confidence = 58
	_check(not b.request(c, "transfer_budget", "profit")["accepted"], "a profit-minded board is harder to convince at the same confidence")
	c.week += Board_cooldown()
	c.manager.confidence = 58
	_check(b.request(c, "transfer_budget", "promotion")["accepted"], "...and an ambitious board easier")
	c.week += Board_cooldown()
	c.ledger().balance = -1000
	c.manager.confidence = 95
	_check(b.request(c, "wage_budget", "stability")["reason"] == "BOARD_REASON_FINANCES", "a club in debt is refused whatever the trust")
	_check(b.request(c, "stadium", "stability")["reason"] == "BOARD_REASON_UNKNOWN", "an unknown request is reported")
	c.ledger().balance = 5_000_000
	_check(c.week < CareerState.WEEKS_PER_SEASON + 100, "setup sanity")
	var back := BoardRelations.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	_check(back.last_meeting_abs_week == b.last_meeting_abs_week and back.refusals_in_a_row == b.refusals_in_a_row, "meeting state is saved")


func Board_cooldown() -> int:
	return BoardRelations.MEETING_COOLDOWN


func _test_promises() -> void:
	var c: CareerState = app.career
	var b := BoardRelations.new()
	_check(b.promise(c, "top_half", 0) == "" and b.promise(c, "profit", 0) == "", "two promises can be made")
	_check(b.promise(c, "youth_players", 2) == "BOARD_PROMISE_TOO_MANY", "a third is refused")
	var b2 := BoardRelations.new()
	b2.promise(c, "promotion", 0)
	_check(b2.promise(c, "promotion", 0) == "BOARD_PROMISE_DUPLICATE" and b2.promise(c, "nonsense", 0) == "BOARD_PROMISE_UNKNOWN", "duplicates and unknown promises are refused")
	# kept and broken
	c.board = BoardRelations.new()
	c.board.promise(c, "top_half", 0)
	c.board.promise(c, "promotion", 0)
	c.manager.objective["division_size"] = 8
	c.manager.confidence = 50
	var rep := c.manager.reputation
	var out := c.board.settle(c, 3, false)
	var kept: Array = out.filter(func(x: Dictionary) -> bool: return x["status"] == "kept")
	var broken: Array = out.filter(func(x: Dictionary) -> bool: return x["status"] == "broken")
	_check(kept.size() == 1 and kept[0]["kind"] == "top_half" and broken.size() == 1 and broken[0]["kind"] == "promotion", "a kept and a broken promise are told apart")
	_check(c.manager.confidence == 50 + 6 - 12, "kept +6, broken -12 board confidence", str(c.manager.confidence))
	_check(c.manager.reputation == rep + 2 - 3, "reputation follows")
	_check(c.board.open_promises().is_empty() and c.board.settle(c, 3, false).is_empty(), "a promise is settled only once")
	var back := BoardRelations.from_dict(JSON.parse_string(JSON.stringify(c.board.to_dict())))
	_check(back.promises.size() == 2, "promises are saved")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_season_review() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	c.board.promise(c, "top_half", 0)
	var guard := 0
	while c.week < CareerState.WEEKS_PER_SEASON and guard < 80:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_simulate_due()
	var info: Dictionary = c.end_season(app.academies, app.squads)
	_check(c.board.promises.all(func(p: Dictionary) -> bool: return p["status"] != "open"), "the season end settles the promise")
	_check(c.manager.history.size() >= 1, "the season review ran")
	_check(c.season == 2 and not c.season_extras.is_empty(), "the next season gets its own extra objectives")
