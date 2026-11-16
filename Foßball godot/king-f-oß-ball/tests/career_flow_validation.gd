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
	await _test_slots()
	await _test_delegation()
	await _test_calendar_dashboard()
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


## C9.5: five slots, the safety copy before a new career, the newest save wins for "Continue", worlds are kept per slot.
func _test_slots() -> void:
	for n in [1, 2, 3, 4, 5]:
		DirAccess.remove_absolute(app.slot_path(n))
	DirAccess.remove_absolute(app.BACKUP_PATH)
	app.switch_world("")
	app.start_career("club_desert_kings")
	_check(app.save_to_slot(1) == "" and app.save_info(app.slot_path(1))["exists"], "slot 1 is saved")
	var info: Dictionary = app.save_info(app.slot_path(1))
	_check(info["club"] != "" and info["season"] == 1 and info["pack_id"] == "", "a slot knows its club, season and world")
	app.switch_world("real_2025")
	var lg: LeagueDef = app.db.leagues[app.db.leagues.keys()[0]]
	var club := str(lg.divisions[0]["team_ids"][0])
	app.start_career(club)
	_check(app.save_to_slot(2) == "" and app.save_info(app.slot_path(2))["pack_id"] == "real_2025", "slot 2 keeps another world")
	_check(app.save_to_slot(6) != "" and app.save_to_slot(0) != "", "slots outside 1-5 are refused")
	_check(app.load_slot(1) == "" and app.db.pack_id == "" and app.user_team_id == "club_desert_kings", "loading slot 1 restores the fictional world and club")
	_check(app.load_slot(2) == "" and app.db.pack_id == "real_2025" and app.user_team_id == club, "loading slot 2 restores the real world and club")
	_check(app.load_slot(4) != "", "an empty slot cannot be loaded")
	var saves: Array = app.all_saves()
	_check(saves.size() >= 2 and int(saves[0]["saved_unix"]) >= int(saves[-1]["saved_unix"]), "all_saves lists the saves newest first")
	_check(app.backup_running_career() == "" and app.save_info(app.BACKUP_PATH)["exists"], "the running career is backed up before a new one")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("save_slots")
	await get_tree().process_frame
	_check(hub.current.find_child("Save_3", true, false) != null and hub.current.find_child("Load_Slot_1", true, false) != null, "the save slots screen lists the slots")
	(hub.current.find_child("Save_3", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(app.save_info(app.slot_path(3))["exists"], "the Save button writes its slot")
	hub.queue_free()
	for n in [1, 2, 3]:
		DirAccess.remove_absolute(app.slot_path(n))
	DirAccess.remove_absolute(app.BACKUP_PATH)


## C9.3: the assistant renews small contracts and promotes academy prospects with the same rules, and reports to the inbox.
func _test_delegation() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c := _career()
	var d := c.delegation
	_check(not d.is_delegated("academy") and not d.is_delegated("renewals"), "nothing is delegated by default")
	_check(d.set_domain("renewals", "assistant") and not d.set_domain("press", "assistant") and not d.set_domain("renewals", "boss"), "only known domains and owners are accepted")
	d.set_domain("renewals", "me")
	# an expiring regular player
	var squad: Array = app.db.get_squad(c.club_id)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var star: PlayerData = squad[0]
	star.contract_years = 1
	var wage_before := star.salary
	var results := d.run_week(c, app.squads, app.academies)
	_check(results.is_empty(), "a delegated domain does nothing for a player the user must handle (default off for academy)")
	var ex: Array = c.market.expiring_contracts(c.club_id)
	_check(star in ex, "the star is expiring (setup)")
	d.set_domain("renewals", "assistant")
	var done := d.run_week(c, app.squads, app.academies)
	_check(star.contract_years > 1 or done.any(func(a: Dictionary) -> bool: return a["domain"] == "renewals"), "the assistant renewed the expiring star", str(done))
	_check(c.inbox.messages.any(func(m: Dictionary) -> bool: return m["category"] == "staff"), "...and reported it to the inbox")
	# academy: an over-age prospect good enough for the first team is promoted, a weak one is kept
	var acad: Academy = app.academy()
	_check(acad != null and not acad.roster_ids.is_empty(), "the academy has prospects (setup)")
	var pid: String = acad.roster_ids[0]
	var prospect: PlayerData = app.db.get_player(pid)
	prospect.age = AcademyConfig.max_age() + 1
	d.set_domain("academy", "assistant")
	var squad_size: int = app.db.get_team(c.club_id).squad_ids.size()
	var acts := d.run_week(c, app.squads, app.academies)
	var promoted: bool = app.db.get_team(c.club_id).squad_ids.size() > squad_size
	var kept: bool = pid in acad.extended_ids
	_check(promoted or kept, "the assistant decided about the over-age prospect (promoted or kept)", str(acts))
	_check(star.salary >= wage_before, "renewing never lowers a wage")
	# persistence
	var back := Delegation.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	_check(back.is_delegated("academy") and back.is_delegated("renewals") and is_equal_approx(back.quality, d.quality), "delegation survives a JSON round trip")
	_check(Delegation.from_dict({"settings": {"academy": "assistant", "bogus": "assistant"}, "quality": 7}).quality == 1.0, "damaged delegation data is sanitised")
	# a week with the assistant on still advances normally
	var wk := c.week
	await app.advance_week_async()
	_check(c.week == wk + 1, "a week advances with delegation on")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("career")
	await get_tree().process_frame
	_check(hub.current.find_child("Delegate_academy", true, false) != null and hub.current.find_child("Delegate_renewals", true, false) != null, "the career screen shows the delegation switches")
	(hub.current.find_child("Delegate_academy", true, false) as OptionButton).select(0)
	(hub.current.find_child("Delegate_academy", true, false) as OptionButton).item_selected.emit(0)
	_check(not c.delegation.is_delegated("academy"), "switching back to 'me' takes effect")
	hub.queue_free()


## C9.4 / C9.6: the calendar and the dashboard describe the real fixtures.
func _test_calendar_dashboard() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c := _career()
	var weeks := CareerCalendar.season_weeks(c)
	_check(weeks.size() == CareerState.WEEKS_PER_SEASON, "the calendar has one entry per week")
	var total := 0
	for e in weeks:
		total += (e["matches"] as Array).size()
	var mine := 0
	for k in c.competitions:
		for f in (c.competitions[k] as Competition).fixtures:
			if f["home"] == c.club_id or f["away"] == c.club_id:
				mine += 1
	_check(total > 0 and total <= mine, "the calendar lists the user's fixtures (%d of %d)" % [total, mine])
	_check(weeks.any(func(e: Dictionary) -> bool: return bool(e["window"])) and weeks.any(func(e: Dictionary) -> bool: return not bool(e["window"])), "transfer windows are marked")
	var nm := CareerCalendar.next_match(c)
	_check(not nm.is_empty() and int(nm["week"]) >= c.week, "there is a next match")
	var res := CareerCalendar.recent_results(c)
	_check(res.is_empty(), "no result before the first match")
	var stop: Dictionary = (await CareerFlow.continue_until_decision(c, app.advance_week_async))["stop"]
	var due_week := c.week
	_simulate_due()
	var after := CareerCalendar.recent_results(c)
	_check(not after.is_empty() and int(after[0]["week"]) <= due_week and "-" in str(after[0]["score"]), "a played match shows up with its score", str(after))
	_check(not CareerCalendar.league_line(c).is_empty(), "the league line exists")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("career")
		await get_tree().process_frame
		_check(hub.current.find_child("DashNext", true, false) != null and hub.current.find_child("DashResults", true, false) != null and hub.current.find_child("DashDecisions", true, false) != null, "the dashboard is built (%s)" % lang)
		hub.navigate("calendar")
		await get_tree().process_frame
		_check(hub.current.find_child("CalTitle", true, false) != null, "the calendar screen builds (%s)" % lang)
	Loc.set_language("en", false)
	hub.navigate("calendar")
	await get_tree().process_frame
	var wk_btn := hub.current.find_children("CalWeek_*", "Button", true, false)
	_check(wk_btn.size() == 4, "a month shows four weeks")
	(wk_btn[0] as Button).pressed.emit()
	await get_tree().process_frame
	_check(hub.current.find_child("CalDetails", true, false) != null, "tapping a week opens its details")
	(hub.current.find_child("CalNext", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(hub.current.find_children("CalWeek_*", "Button", true, false).size() == 4, "the next month shows its weeks")
	hub.queue_free()
