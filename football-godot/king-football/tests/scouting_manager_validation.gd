## Phase 4: career manager selection (the club's own manager or a new one) and the youth scouting redesign (weekly scout
## market, scout profiles and contracts, regional knowledge, mission recall, rejecting prospects, the searchable country
## picker and the new scouting screen). Data is checked in the real stores and through a save file, the UI through its
## buttons.
##   godot --headless --path . res://tests/scouting_manager_validation.tscn
extends Node

const PACK := "real_2026"

var _passed := 0
var _failed := 0
var app: Node
var db: Node
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
	print("=== KING FOOTBALL — Manager selection & youth scouting validation (Phase 4) ===")
	app = get_node("/root/AppHub")
	db = get_node("/root/TeamDB")
	var cfg := ConfigFile.new()
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if cfg.load(TeamDatabase.SETTINGS_PATH) == OK else ""
	Loc.set_language("en", false)
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	await _test_manager_club_option()
	await _test_manager_custom_option()
	await _test_manager_no_db_manager()
	_test_scout_market()
	_test_contracts_region_recall()
	_test_reject()
	await _test_scouting_screen()
	_test_country_picker()
	app.switch_world(saved_pack)
	hub.queue_free()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _wizard_at_coach(club_id: String) -> HubScreen:
	app.career = null
	hub.navigate("career_wizard")
	await get_tree().process_frame
	var w: HubScreen = hub.current
	w.set("club_id", club_id)
	w.set("step", 3)                              # the coach step (go_to_step only goes back to a step already passed)
	w.call("rebuild")
	await get_tree().process_frame
	return hub.current


func _press(n: String) -> bool:
	var b := hub.current.find_child(n, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _save_and_reload(path: String) -> void:
	app.save_game(path)
	app.load_game(path)


func _remove(path: String) -> void:
	for q in [path, SaveManager.meta_path(path), path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(q):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(q))


# ------------------------------------------------------------------------------------------------- manager: option A

func _test_manager_club_option() -> void:
	app.switch_world(PACK)
	var club := "esp_real_madrid_c_f"
	var team: TeamData = db.get_team(club)
	var db_name := team.manager_name
	_check(db_name != "", "[mgr] the data pack stores the club's manager (%s)" % db_name)
	var w := await _wizard_at_coach(club)
	_check(w.find_child("CoachModeCards", true, false) != null and w.find_child("CoachMode_club", true, false) != null
			and w.find_child("CoachMode_custom", true, false) != null, "[mgr] the coach step shows the two manager cards")
	var name_lbl := false
	var card_a := w.find_child("CoachMode_club", true, false)
	if card_a != null:
		for l in card_a.find_children("*", "Label", true, false):
			name_lbl = name_lbl or (l as Label).text == db_name
	_check(name_lbl, "[mgr] option A shows the database manager's name")
	_check(_press("CoachModeClubButton") and str(hub.current.get("coach_mode")) == "club", "[mgr] 'Continue with him' selects option A")
	_check(hub.current.find_child("CoachName", true, false) == null, "[mgr] option A hides the create-manager fields")
	hub.current.set("coach_style", "youth")
	hub.current.set("coach_background", "known")
	_check(hub.current.call("start_career") == "", "[mgr] career started with the club's manager")
	var m: ManagerProfile = app.career.manager
	_check(m.manager_name == db_name and m.is_club_manager() and m.origin_club_id == club and m.manager_id == "club_mgr_%s" % club,
			"[mgr] the career's manager is the club's manager (name, source, id)", "%s %s %s" % [m.manager_name, m.source, m.manager_id])
	_check(m.age == 0 and m.nationality_id == "" and m.style == "youth" and m.reputation == ManagerProfile.START_TIERS["known"],
			"[mgr] nothing invented: age / nationality unknown, style and background as chosen")
	_check((db.get_team(club) as TeamData).manager_name == db_name, "[mgr] the club's database entry is unchanged")
	_save_and_reload("user://p4_mgr_club.json")
	var m2: ManagerProfile = app.career.manager
	_check(m2 != m and m2.manager_name == db_name and m2.is_club_manager() and m2.manager_id == m.manager_id and m2.age == 0 and m2.style == "youth",
			"[mgr] option A survives save / load", "%s %s %d" % [m2.manager_name, m2.source, m2.age])
	hub.navigate("team_details", {"team_id": club})
	await get_tree().process_frame
	var shown := false
	for l in hub.current.find_children("*", "Label", true, false):
		shown = shown or (l as Label).text.contains(db_name)
	_check(shown, "[mgr] the club page shows the manager")
	_remove("user://p4_mgr_club.json")


# ------------------------------------------------------------------------------------------------- manager: option B

func _test_manager_custom_option() -> void:
	app.switch_world(PACK)
	var club := "esp_real_madrid_c_f"
	var db_name := (db.get_team(club) as TeamData).manager_name
	var w := await _wizard_at_coach(club)
	_check(_press("CoachModeCustomButton") and str(hub.current.get("coach_mode")) == "custom", "[mgr] 'Create manager' selects option B")
	_check(hub.current.find_child("CoachName", true, false) != null and hub.current.find_child("CoachNationality", true, false) is CountryPicker,
			"[mgr] option B shows name and a searchable nationality picker")
	w = hub.current
	w.set("coach_name", "Layla Haddad")
	w.set("coach_age", 41)
	var ids: Array = db.countries.keys()
	ids.sort()
	w.set("coach_country_id", str(ids[0]))
	w.set("coach_style", "tactical")
	w.set("coach_background", "unknown")
	_check(w.call("start_career") == "", "[mgr] career started with a new manager")
	var m: ManagerProfile = app.career.manager
	_check(m.manager_name == "Layla Haddad" and not m.is_club_manager() and m.age == 41 and m.nationality_id == str(ids[0]) and m.manager_id.begins_with("mgr_"),
			"[mgr] the new manager's profile and unique id", m.manager_id)
	_check((db.get_team(club) as TeamData).manager_name == db_name, "[mgr] creating a manager does not overwrite the club's database manager")
	hub.navigate("team_details", {"team_id": club})
	await get_tree().process_frame
	var shows_user := false
	for l in hub.current.find_children("*", "Label", true, false):
		shows_user = shows_user or (l as Label).text.contains("Layla Haddad")
	_check(shows_user, "[mgr] your club's page shows your manager")
	var first_id := m.manager_id
	_save_and_reload("user://p4_mgr_custom.json")
	var m2: ManagerProfile = app.career.manager
	_check(m2.manager_name == "Layla Haddad" and m2.manager_id == first_id and m2.age == 41 and not m2.is_club_manager(), "[mgr] option B survives save / load")
	# a second career with the same choices: a new, different manager id (one manager per career, never shared)
	w = await _wizard_at_coach(club)
	w.set("coach_mode", "custom")
	w.set("coach_name", "Layla Haddad")
	w.set("coach_age", 41)
	w.call("start_career")
	_check(app.career.manager.manager_id != first_id, "[mgr] a second career gets its own manager id", "%s vs %s" % [app.career.manager.manager_id, first_id])
	_remove("user://p4_mgr_custom.json")


func _test_manager_no_db_manager() -> void:
	app.switch_world("")                             # the fictional world stores no managers
	var club := "club_desert_kings"
	_check((db.get_team(club) as TeamData).manager_name == "", "[mgr] fictional club without a database manager")
	var w := await _wizard_at_coach(club)
	var ab := w.find_child("CoachModeClubButton", true, false) as Button
	_check(ab != null and ab.disabled, "[mgr] option A is disabled when the database has no manager")
	w.set("coach_mode", "club")                     # even when forced, the career falls back to a created manager
	_check(str(w.call("effective_coach_mode")) == "custom", "[mgr] no database manager: the wizard uses option B")
	w.set("coach_name", "Zed")
	_check(w.call("start_career") == "" and app.career.manager.manager_name == "Zed" and not app.career.manager.is_club_manager(),
			"[mgr] the career starts with the created manager")


# ------------------------------------------------------------------------------------------------- scout market

func _academy(budget := 10_000_000) -> Academy:
	var ac := Academy.new("test_club", "", 1)
	ac.budget = budget
	return ac


func _test_scout_market() -> void:
	app.switch_world(PACK)
	var sc := ScoutingSystem.new(4242)
	sc.add_scout("scout_a", "Regional Scout", 0.5, 1500)
	var ac := _academy()
	var list := sc.candidates()
	_check(list.size() == ScoutingSystem.MARKET_SIZE, "[market] %d scouts on the market" % list.size())
	var fields_ok := true
	var names := {}
	for c: Dictionary in list:
		for k in ["cid", "name", "nationality", "quality", "experience", "specialty", "region", "weekly_cost", "contract_weeks", "listed_week"]:
			fields_ok = fields_ok and c.has(k)
		fields_ok = fields_ok and float(c["quality"]) >= 0.3 and float(c["quality"]) <= 0.95 and int(c["experience"]) >= 1 and str(c["specialty"]) in ScoutingSystem.SPECIALTIES
		fields_ok = fields_ok and db.countries.has(str(c["nationality"]))
		names[str(c["name"])] = true
	_check(fields_ok, "[market] every candidate has a full, balanced profile (nationality from the database)")
	_check(names.size() == list.size(), "[market] no duplicate scouts on the market")
	var costs_ok := true
	for c: Dictionary in list:
		costs_ok = costs_ok and int(c["weekly_cost"]) == int(snappedf(500.0 + float(c["quality"]) * float(c["quality"]) * 5500.0, 50.0))
	_check(costs_ok, "[market] salary follows quality (better scouts cost more)")
	# the same list after save / load
	var back := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(sc.to_dict())) as Dictionary)
	_check(JSON.stringify(back.candidates()) == JSON.stringify(sc.candidates()), "[market] the market is the same after save / load")
	# weekly refresh through the calendar: new scouts appear without any hire
	var first_ids: Array = list.map(func(c: Dictionary) -> String: return str(c["cid"]))
	var new_seen := 0
	for i in 8:
		sc.advance_week(db, ac)
		for c: Dictionary in sc.market:
			if not first_ids.has(str(c["cid"])):
				new_seen += 1
				first_ids.append(str(c["cid"]))
	_check(new_seen >= 4 and sc.market.size() == ScoutingSystem.MARKET_SIZE, "[market] %d new scouts arrived over 8 weeks, market stays full" % new_seen)
	# hire: the profile carries over, the fee is paid, the others stay, a new one fills the place
	var others: Array = sc.market.slice(1).map(func(c: Dictionary) -> String: return str(c["cid"]))
	var pick: Dictionary = (sc.market[0] as Dictionary).duplicate()
	var budget0 := ac.budget
	_check(sc.hire(ac, 0) == "", "[market] a candidate is hired")
	var hired: Dictionary = sc.scouts["scout_h1"]
	_check(str(hired["name"]) == str(pick["name"]) and hired["nationality"] == pick["nationality"] and hired["specialty"] == pick["specialty"]
			and hired["region"] == pick["region"] and int(hired["experience"]) == int(pick["experience"]), "[market] the hired scout keeps his profile")
	_check(int(hired["contract_until"]) == sc.week + int(pick["contract_weeks"]) and ac.budget == budget0 - sc.hire_fee(pick),
			"[market] contract length and signing fee are applied")
	var still: Array = sc.market.map(func(c: Dictionary) -> String: return str(c["cid"]))
	var kept := others.all(func(cid: String) -> bool: return still.has(cid))
	_check(kept and sc.market.size() == ScoutingSystem.MARKET_SIZE and not still.has(str(pick["cid"])), "[market] the other candidates stay; the place is refilled")
	for i in 6:
		sc.advance_week(db, ac)
	_check(sc.scouts.has("scout_h1") and str(sc.scouts["scout_h1"]["name"]) == str(pick["name"]), "[market] the weekly refresh never touches hired scouts")
	# an old save without a stored market fills it on first use
	var old := sc.to_dict()
	old.erase("market")
	old.erase("next_candidate_id")
	var loaded := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(old)) as Dictionary)
	_check(loaded.candidates().size() == ScoutingSystem.MARKET_SIZE and loaded.scouts.has("scout_h1"), "[market] an older save gets a market and keeps its scouts")
	var reloaded := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(sc.to_dict())) as Dictionary)
	_check(typeof(reloaded.scouts["scout_h1"]["contract_until"]) == TYPE_INT and typeof(reloaded.market[0]["weekly_cost"]) == TYPE_INT,
			"[market] scout numbers are integers again after loading")


# ------------------------------------------------------------------------------------------------- contracts, region, recall

func _test_contracts_region_recall() -> void:
	var sc := ScoutingSystem.new(77)
	sc.add_scout("a", "A", 0.5, 1000)
	sc.add_scout("b", "B", 0.6, 1000)
	sc.add_scout("c", "C", 0.7, 1000)
	var ac := _academy()
	sc.scouts["b"]["contract_until"] = sc.week + 2
	sc.scouts["c"]["contract_until"] = sc.week + 2
	var country := str((db.countries.keys() as Array)[0])
	_check(sc.start_mission(ac, "c", country, 6) == "", "[contract] scout C goes on a 6-week mission")
	sc.advance_week(db, ac)
	sc.advance_week(db, ac)
	_check(not sc.scouts.has("b") and sc.departures.any(func(d: Dictionary) -> bool: return d["scout_id"] == "b"), "[contract] an idle scout leaves when his contract ends")
	_check(sc.scouts.has("c") and int(sc.scouts["c"]["contract_until"]) > sc.week, "[contract] a scout on a mission gets an extension instead")
	var last := ScoutingSystem.new(78)
	last.add_scout("only", "Only", 0.5, 100)
	last.scouts["only"]["contract_until"] = 1
	last.advance_week(db, ac)
	_check(last.scouts.has("only"), "[contract] the club's last scout is never lost")
	# regional knowledge
	var s1 := {"quality": 0.6, "region": country}
	_check(is_equal_approx(ScoutingSystem.effective_quality(s1, country), 0.7) and is_equal_approx(ScoutingSystem.effective_quality(s1, "elsewhere"), 0.6)
			and is_equal_approx(ScoutingSystem.effective_quality({"quality": 0.95, "region": country}, country), 1.0)
			and is_equal_approx(ScoutingSystem.effective_quality({"quality": 0.5}, country), 0.5), "[region] +0.1 in his region only, capped at 1, none without a region")
	_check(ScoutingSystem.specialty_of("GK") == "goalkeepers" and ScoutingSystem.specialty_of("CB") == "defenders" and ScoutingSystem.specialty_of("CAM") == "midfielders"
			and ScoutingSystem.specialty_of("ST") == "forwards" and ScoutingSystem.specialty_of("") == "", "[region] positions map to specialties")
	# recall: no prospects, unworked weeks refunded
	var r := ScoutingSystem.new(79)
	r.add_scout("x", "X", 0.5, 1000)
	var ac2 := _academy(100_000)
	r.start_mission(ac2, "x", country, 4)
	var after_start := ac2.budget
	r.advance_week(db, ac2)
	var mid := int(r.missions[0]["id"])
	_check(r.recall(ac2, mid) == "" and r.missions.is_empty() and ac2.budget == after_start + 3000 and r.pool.is_empty(),
			"[recall] the mission ends, 3 unworked weeks refunded, no prospects", str(ac2.budget - after_start))
	_check(r.recall(ac2, mid) != "" and not r.is_scout_busy("x"), "[recall] a second recall is refused; the scout is free again")


# ------------------------------------------------------------------------------------------------- reject

func _test_reject() -> void:
	var sc := ScoutingSystem.new(4243)
	sc.add_scout("g", "G", 0.9, 100)
	var ac := _academy()
	var country := str((db.countries.keys() as Array)[0])
	sc.start_mission(ac, "g", country, 3)
	var found: Array[String] = []
	for i in 3:
		found.append_array(sc.advance_week(db, ac))
	_check(found.size() >= 2 and found.all(func(id: String) -> bool: return db.get_player(id) != null and (db.get_player(id) as PlayerData).team_id == ""),
			"[reject] a mission finds unsigned prospects (%d)" % found.size())
	if found.size() < 2:
		return
	var pid: String = found[0]
	var pname := (db.get_player(pid) as PlayerData).display_name
	var pool0 := sc.pool.size()
	_check(sc.reject_prospect(db, pid) == "", "[reject] a prospect is rejected")
	_check(not (pid in sc.pool) and sc.pool.size() == pool0 - 1 and not sc.reports.has(pid) and db.get_player(pid) == null,
			"[reject] he leaves the list, his report and the player database")
	_check(sc.rejected.size() == 1 and str(sc.rejected[0]["name"]) == pname and sc.history.any(func(h: Dictionary) -> bool: return h["player_id"] == pid and h.get("status", "") == "rejected"),
			"[reject] the decision is kept in the history")
	_check(sc.reject_prospect(db, pid) != "" and sc.rejected.size() == 1, "[reject] rejecting twice is refused")
	_check(sc.sign_prospect(db, ac, pid) != "", "[reject] a rejected prospect cannot be signed")
	var other: String = found[1]
	var signed := sc.sign_prospect(db, ac, other)
	_check(signed == "" and other in ac.roster_ids and sc.reject_prospect(db, other) != "",
			"[reject] signing is separate: a signed player cannot be rejected", signed)
	var back := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(sc.to_dict())) as Dictionary)
	_check(back.rejected.size() == 1 and not (pid in back.pool), "[reject] rejections survive save / load")


# ------------------------------------------------------------------------------------------------- screen

func _test_scouting_screen() -> void:
	app.switch_world(PACK)
	app.start_career("esp_real_madrid_c_f")
	var sc: ScoutingSystem = app.scouting[app.user_team_id]
	app.academy().budget = 50_000_000
	hub.navigate("scouting")
	await get_tree().process_frame
	var scr := hub.current
	for n in ["ScoutOverview", "MissionForm", "ScoutStaff", "ScoutMarket", "RegionOption", "SendScout", "AdvanceWeek"]:
		_check(scr.find_child(n, true, false) != null, "[screen] %s is shown" % n)
	_check(scr.find_child("RegionOption", true, false) is CountryPicker, "[screen] the region field is the searchable country picker")
	_check(scr.find_children("Hire_*", "Button", true, false).size() == ScoutingSystem.MARKET_SIZE, "[screen] one Hire button per market scout")
	_check(scr.find_child("EmptyState", true, false) != null or not sc.pool.is_empty(), "[screen] empty state while no talent was found")
	var n0 := sc.scouts.size()
	_check(_press("Hire_0") and sc.scouts.size() == n0 + 1, "[screen] Hire adds a scout")
	scr = hub.current
	scr.set("_weeks", 2)
	_check(_press("SendScout") and sc.missions.size() == 1, "[screen] Send scout starts a mission")
	if not sc.missions.is_empty():
		_check(hub.current.find_child("Mission_%d" % int(sc.missions[0]["id"]), true, false) != null, "[screen] the mission card is shown")
	for i in 2:
		_press("AdvanceWeek")
		await get_tree().process_frame
	_check(not sc.pool.is_empty(), "[screen] the calendar delivered talents (%d)" % sc.pool.size())
	if sc.pool.is_empty():
		return
	scr = hub.current
	var pid: String = sc.pool[0]
	for n in ["Talent_%s" % pid, "View_%s" % pid, "Sign_%s" % pid, "Reject_%s" % pid]:
		_check(scr.find_child(n, true, false) != null, "[screen] talent card part %s" % n.split("_")[0])
	var dialogs0 := scr.find_children("*", "ConfirmationDialog", true, false).size()
	_check(_press("Reject_%s" % pid) and pid in sc.pool, "[screen] Reject asks for confirmation (nothing removed yet)")
	var dlg: Array = hub.current.find_children("*", "ConfirmationDialog", true, false)
	_check(dlg.size() == dialogs0 + 1, "[screen] a confirmation dialog is open")
	if dlg.size() > dialogs0:
		(dlg[-1] as ConfirmationDialog).confirmed.emit()
		await get_tree().process_frame
	_check(not (pid in sc.pool) and hub.current.find_child("Talent_%s" % pid, true, false) == null, "[screen] confirmed: the talent card is gone")
	if not sc.pool.is_empty():
		var pid2: String = sc.pool[0]
		_check(_press("View_%s" % pid2) and hub.current_id == "player_profile", "[screen] View opens the player profile", hub.current_id)
		hub.navigate("scouting")
		await get_tree().process_frame
		var roster0: int = app.academy().roster_ids.size()
		var ok := _press("Sign_%s" % pid2)
		_check(ok and app.academy().roster_ids.size() == roster0 + 1 and not (pid2 in sc.pool), "[screen] Sign moves the talent into the academy")
	Loc.set_language("ar", false)
	hub.navigate("scouting")
	await get_tree().process_frame
	_check(hub.current.find_child("ScoutMarket", true, false) != null, "[screen] the screen builds in Arabic")
	Loc.set_language("en", false)


func _test_country_picker() -> void:
	var labels := ["Germany", "Ghana", "Greece", "Spain", "Sweden", "Argentina"]
	var got := [-1]
	var cp := CountryPicker.make(labels, 3, func(i: int) -> void: got[0] = i)
	add_child(cp)
	_check(cp.text.begins_with("Spain"), "[picker] the button shows the chosen country")
	cp.filter("")
	_check(cp.shown_count() == 6, "[picker] all countries listed")
	cp.filter("gh")
	_check(cp.shown_count() == 1 and cp.list.get_item_text(0) == "Ghana", "[picker] search narrows the list")
	cp.filter("zz")
	_check(cp.shown_count() == 0 and cp.list.get_item_count() == 1 and cp.list.is_item_disabled(0), "[picker] no match: a disabled hint row")
	cp.filter("s")
	var row := -1
	for i in cp.list.get_item_count():
		if cp.list.get_item_text(i) == "Sweden":
			row = i
	cp.list.item_selected.emit(row)
	_check(got[0] == 4 and cp.selected == 4 and cp.text.begins_with("Sweden"), "[picker] picking from a filtered list reports the right country")
	cp.open()
	var vp := get_viewport().get_visible_rect().size
	_check(cp.popup.visible and cp.popup.size.x <= int(vp.x) and cp.popup.size.y <= int(vp.y) and cp.popup.size.y <= CountryPicker.POPUP_SIZE.y,
			"[picker] the popup has a fixed size inside the window", str(cp.popup.size))
	cp.popup.hide()
	cp.queue_free()
