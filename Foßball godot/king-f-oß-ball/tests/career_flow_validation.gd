## Career phase C9 (first part): central inbox (C9.1) and the smart "Continue" (C9.2).
##   godot --headless --path . res://tests/career_flow_validation.tscn
extends Node

const PATH := "user://saves/c9_flow_test.json"
var _passed := 0
var _failed := 0
var app: Node
var hub: HubRoot


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Career flow validation (C9: inbox + Continue) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_inbox_basics()
	await _test_continue_stops_at_matches()
	await _test_offer_stops_once()
	await _test_full_season()
	_test_save_load()
	await _test_ui()
	app.switch_world(saved_pack)
	DirAccess.remove_absolute(PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _career() -> CareerState:
	return app.career


func _test_inbox_basics() -> void:
	var ib := Inbox.new()
	var a := ib.add("u1", 1, 1, "board", "INBOX_UNEMPLOYED")
	_check(not a.is_empty() and ib.add("u1", 1, 1, "board", "INBOX_UNEMPLOYED").is_empty(), "a message with the same uid is added once")
	_check(ib.unread_count() == 1, "a new message is unread")
	ib.mark_read(int(a["id"]))
	_check(ib.unread_count() == 0, "mark_read clears the unread count")
	ib.add("u2", 1, 1, "transfers", "INBOX_NOTE_PREFIX", ["x"], {"needs_decision": true})
	_check(ib.pending_decisions().size() == 1, "a decision message is pending")
	ib.resolve(int(ib.messages[1]["id"]))
	_check(ib.pending_decisions().is_empty(), "a resolved decision is no longer pending")
	for i in Inbox.MAX_MESSAGES + 20:
		ib.add("bulk%d" % i, 1, 1, "media", "INBOX_NOTE_PREFIX", ["x"])
	_check(ib.messages.size() == Inbox.MAX_MESSAGES, "the inbox is bounded")
	_check(not ib.has_uid("u1"), "dropped messages free their uid")
	var back := Inbox.from_dict(JSON.parse_string(JSON.stringify(ib.to_dict())))
	_check(back.messages.size() == ib.messages.size() and back.unread_count() == ib.unread_count(), "an inbox survives a JSON round trip")


func _simulate_due() -> void:
	for pair in _career().due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_continue_stops_at_matches() -> void:
	var c := _career()
	_check(c.inbox.pending_decisions().is_empty(), "a new career has no pending decision")
	var res: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
	var stop: Dictionary = res["stop"]
	_check(not stop.is_empty() and stop["key"] == "INBOX_MATCH_DUE" and bool(stop["blocking"]), "Continue stops at the first match that is due", str(stop.get("key", "")))
	_check(not c.due_user_fixtures().is_empty(), "...and that match is really due")
	var week_before := c.week
	var again: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
	_check(c.week == week_before and int(again["weeks"]) == 0, "...and does not move on until the match is played")
	_simulate_due()
	var next: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
	_check(c.week > week_before, "after the match Continue advances again")
	_check(c.inbox.messages.any(func(m: Dictionary) -> bool: return m["key"] == "INBOX_MATCH_DUE" and bool(m["resolved"])), "the played match message is resolved")
	_check(next["stop"].is_empty() or next["stop"]["key"] in ["INBOX_MATCH_DUE", "INBOX_SEASON_OVER", "INBOX_OFFER_INCOMING"], "...and stops at the next match, offer or the season end")
	_simulate_due()


func _test_offer_stops_once() -> void:
	var c := _career()
	var squad: Array = app.db.get_team(c.club_id).squad_ids
	var pid := ""
	for id in squad:
		var p: PlayerData = app.db.get_player(id)
		if p != null and p.status != PlayerData.Status.YOUTH and p.loan_parent == "":
			pid = id
			break
	for m in c.inbox.pending_decisions():
		m["shown"] = true                      # AI clubs send offers too: only the one made below is new
	var o: TransferOffer = c.market.make_external_offer(pid, "Offer Town FC", "Spain", 900000)["offer"]
	_check(o != null, "an external offer arrives")
	CareerFlow.sync(c)
	var msg: Dictionary = {}
	for m in c.inbox.pending_decisions():
		if str(m["uid"]) == "offer_in:%d" % o.id:
			msg = m
	_check(not msg.is_empty() and msg["category"] == "transfers" and msg["action"]["screen"] == "transfers", "the offer becomes a transfers decision with an action")
	_check("Offer Town FC" in Loc.f(str(msg["key"]), msg["args"]), "...naming the external club")
	var first: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
	_check(first["stop"]["uid"] == msg["uid"] and int(first["weeks"]) == 0, "Continue stops at the new offer")
	var second: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
	_check(second["stop"].is_empty() or second["stop"]["uid"] != msg["uid"], "...but only once: an ignored offer does not trap the user")
	_simulate_due()
	c.market.answer_incoming(o.id, "reject")
	CareerFlow.sync(c)
	_check(bool(c.inbox.get_message(int(msg["id"]))["resolved"]), "answering the offer resolves its message")


func _test_full_season() -> void:
	var c := _career()
	var guard := 0
	var stops := 0
	while guard < 200:
		guard += 1
		var res: Dictionary = await CareerFlow.continue_until_decision(c, app.advance_week_async)
		var stop: Dictionary = res["stop"]
		if stop.is_empty():
			break
		stops += 1
		if stop["key"] == "INBOX_SEASON_OVER":
			break
		if stop["key"] == "INBOX_MATCH_DUE":
			_simulate_due()
	_check(c.week >= CareerState.WEEKS_PER_SEASON, "Continue plays a whole season (matches simulated)", "week %d" % c.week)
	_check(c.inbox.pending_decisions().any(func(m: Dictionary) -> bool: return m["key"] == "INBOX_SEASON_OVER" and bool(m["blocking"])), "the end of the season is a blocking decision")
	_check(stops < 80, "...with a sensible number of stops", str(stops))


func _test_save_load() -> void:
	var c := _career()
	var count := c.inbox.messages.size()
	var unread := c.inbox.unread_count()
	_check(count > 0, "the inbox holds messages before saving")
	_check(app.save_game(PATH) == "", "the career with an inbox is saved")
	app.career.inbox = Inbox.new()
	_check(app.load_game(PATH) == "", "...and loaded")
	_check(_career().inbox.messages.size() == count and _career().inbox.unread_count() == unread, "the inbox is restored exactly")
	CareerFlow.sync(_career())
	_check(_career().inbox.messages.size() == count, "syncing after a load does not duplicate messages", "%d vs %d" % [_career().inbox.messages.size(), count])


func _test_ui() -> void:
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("career")
	await get_tree().process_frame
	_check(hub.current.find_child("ContinueButton", true, false) != null, "the career screen has a Continue button")
	_career().inbox.add("ui_unread", _career().season, _career().week, "board", "INBOX_UNEMPLOYED")
	app.state_changed.emit()
	await get_tree().process_frame
	var nav := hub.find_child("Nav_inbox", true, false)
	_check(nav != null and nav.get_node_or_null("Badge") != null, "the inbox navigation entry shows an unread counter")
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("inbox")
		await get_tree().process_frame
		_check(hub.current.find_child("MarkAllRead", true, false) != null and hub.current.find_child("Tab_transfers", true, false) != null, "the inbox screen builds (%s)" % lang)
	var open := hub.current.find_children("Open_*", "Button", true, false)
	_check(not open.is_empty(), "messages with an action have an Open button")
	(hub.current.find_child("MarkAllRead", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(_career().inbox.unread_count() == 0, "Mark all as read clears the unread counter")
	Loc.set_language("en", false)
	hub.queue_free()
