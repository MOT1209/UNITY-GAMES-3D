## New-career wizard validation: world -> league -> club -> summary -> start, in the fictional world
## and in the real-leagues data pack; Back / Next rules; the started career matches the choices;
## entry points (career dashboard, team selection, empty states, main menu).
##   godot --headless --path . res://tests/career_wizard_validation.tscn
extends Node

const PACK := "real_2025"

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
	print("=== KING FOOTBALL — Career wizard validation ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	await _test_entry_points()
	await _test_fictional_flow()
	await _test_pack_flow()
	await _test_coach_styles()
	await _test_scratch_mode()
	await _test_settings_and_bar()
	app.switch_world(saved_pack)
	hub.queue_free()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _wizard() -> HubScreen:
	hub.navigate("career_wizard")
	await get_tree().process_frame
	return hub.current


func _press(n: String) -> bool:
	var b := hub.current.find_child(n, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _test_entry_points() -> void:
	_check(ScreenRegistry.SCREENS.has("career_wizard") and ScreenRegistry.section_of("career_wizard") == "home",
			"the wizard is a hub screen in the Home section")
	app.career = null
	hub.navigate("career")
	await get_tree().process_frame
	_check(hub.current.find_child("NewCareerButton", true, false) != null, "career dashboard without a career offers 'New career'")
	hub.navigate("team_select")
	await get_tree().process_frame
	_check(hub.current.find_child("NewCareerButton", true, false) != null, "team selection offers 'New career'")
	app.select_team("club_royal_harbor")        # a club but no career: the "start a career" empty state
	app.career = null
	hub.navigate("finance")
	await get_tree().process_frame
	var action := hub.current.find_child("EmptyStateAction", true, false) as Button
	if action != null:
		action.pressed.emit()
		await get_tree().process_frame
	_check(hub.current_id == "career_wizard", "screens that need a career lead to the wizard", hub.current_id)
	Loc.set_language("en", false)
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var nb := menu.find_child("NewCareerButton", true, false) as Button
	_check(nb != null and nb.get_index() == (menu.get_node("%PlayButton") as Button).get_index() + 1, "main menu: 'New career' right after Play")
	menu.queue_free()
	await get_tree().process_frame


func _test_fictional_flow() -> void:
	var w := await _wizard()
	_check(w.step == 0 and w.find_child("World_fictional", true, false) != null, "step 1: the world choice")
	_check((w.find_child("WizardBack", true, false) as Button).disabled, "no Back on the first step")
	_check(_press("WizardNext") and w.step == 1, "the loaded fictional world: Next to the league")
	_check(w.find_child("League_fictional", true, false) != null, "step 2: the King League (all fictional clubs)")
	_check(_press("WizardNext") and w.step == 2, "Next to the club")
	_check((w.find_child("WizardNext", true, false) as Button).disabled, "no Next before a club is chosen")
	var cards := w.find_children("Club_*", "Button", true, false)
	_check(cards.size() == app.db.list_teams(TeamData.Category.CLUB).size(), "every club is offered", str(cards.size()))
	var ratings: Array = w.division_clubs().map(func(t: TeamData) -> int: return app.db.get_team_rating(t.id))
	var sorted := ratings.duplicate()
	sorted.sort()
	sorted.reverse()
	_check(ratings == sorted, "clubs are listed strongest first")
	_check(_press("Club_club_northgate_utd") and w.club_id == "club_northgate_utd", "choosing a club")
	_check(_press("WizardBack") and w.step == 1 and _press("WizardNext") and w.club_id == "club_northgate_utd", "Back keeps the choices")
	_check(_press("WizardNext") and w.step == 3, "step 4: the coach")
	_check(_press("WizardNext") and w.step == 4, "step 5: the settings")
	_check(_press("WizardNext") and w.step == 5, "step 6: the summary")
	var texts: Array = []
	for l in w.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	_check(texts.has("Northgate United") or texts.any(func(t: String) -> bool: return t.contains("Northgate")), "the summary names the club")
	_check(texts.any(func(t: String) -> bool: return t.begins_with("Board objective")), "the summary shows the board objective")
	_check(_press("WizardStart"), "Start career")
	await get_tree().process_frame
	_check(app.career != null and app.career.club_id == "club_northgate_utd" and app.career.pyramids.has(CareerState.DEFAULT_LEAGUE_KEY),
			"the career starts with the chosen club and the King League")
	_check(hub.current_id == "career", "the career dashboard opens")


func _test_pack_flow() -> void:
	var packs := TeamDatabase.available_packs().map(func(p: Dictionary) -> String: return str(p["id"]))
	if not (PACK in packs):
		_check(true, "data pack not installed: pack flow skipped")
		return
	var w := await _wizard()
	_check(w.find_child("World_%s" % PACK, true, false) != null, "the real-leagues pack is offered as a world")
	Loc.set_language("ar", false)
	await get_tree().process_frame
	w = hub.current
	var pack_card := w.find_child("World_%s" % PACK, true, false)
	var latin := false
	for l in pack_card.find_children("*", "Label", true, false):
		latin = latin or (l as Label).text.contains("Real leagues")
	_check(not latin, "[ar] the pack name is translated")
	var season_ok := false
	for l in pack_card.find_children("*", "Label", true, false):
		var t := (l as Label).text
		if t.contains("2025"):
			var tl := TextLine.new()
			tl.direction = TextServer.DIRECTION_RTL
			tl.add_string(t, get_tree().root.theme.default_font, 16)
			var seen := ""
			for g in TextServerManager.get_primary_interface().shaped_text_get_glyphs(tl.get_rid()):
				var ch := t.substr(int(g["start"]), 1)
				if "0123456789-".contains(ch):
					seen += ch
			season_ok = seen == "2025-26"
	_check(season_ok, "[ar] the season reads 2025-26 (rendered order), not 26-2025")
	Loc.set_language("en", false)
	await get_tree().process_frame
	w = hub.current
	_check(w.select_world(PACK) == "" and app.db.pack_id == PACK and app.career == null, "choosing the pack loads it (the old career ends)")
	_check(_press("WizardNext") and w.step == 1, "Next to the league")
	_check(w.find_child("CountryOption", true, false) != null and w.find_children("Division_*", "Button", true, false).size() >= 2,
			"step 2: country and divisions")
	_check(_press("Division_1"), "choosing the second division")
	_check(_press("WizardNext") and w.step == 2, "Next to the club")
	var div: Dictionary = w.division()
	var cards := w.find_children("Club_*", "Button", true, false)
	_check(cards.size() == (div["team_ids"] as Array).size(), "only that division's clubs are offered", "%d vs %d" % [cards.size(), (div["team_ids"] as Array).size()])
	var pick: String = (w.division_clubs()[0] as TeamData).id
	_check(_press("Club_%s" % pick) and _press("WizardNext") and _press("WizardNext") and _press("WizardNext") and _press("WizardStart"), "club chosen and career started")
	await get_tree().process_frame
	var ud: Dictionary = app.career.user_division() if app.career != null else {}
	_check(app.career != null and app.career.club_id == pick and not ud.is_empty() and ud["division"]["id"] == div["id"],
			"the career runs in the chosen division of the data pack")
	_check(app.career.manager.objective.has("target_rank"), "with a board objective for that division")


## C1.2: the coach step and the style effects (measured on 400 simulated seasons of fixtures, not asserted by formula).
func _test_coach_styles() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var f := {"match_id": "x", "stage": "league", "home": "club_desert_kings", "away": "club_royal_harbor"}
	var base_for := 0
	var base_against := 0
	var mods_for := {}
	for style in ManagerProfile.STYLES:
		var gf := 0
		var ga := 0
		c.manager.style = style
		var mods := c.style_mods()
		for i in 400:
			var g := {"match_id": "m%d" % i, "stage": "league", "home": "club_desert_kings", "away": "club_royal_harbor"}
			var r := MatchSimulator.result(app.db, g, i, {}, [], mods)
			gf += r.home_goals
			ga += r.away_goals
		mods_for[style] = [gf, ga]
	var neutral: Array = mods_for["tactical"]
	_check(mods_for["attacking"][0] > neutral[0] and absf(float(mods_for["attacking"][1]) / float(maxi(neutral[1], 1)) - 1.0) < 0.12, "attacking style scores more and concedes about the same")
	_check(mods_for["defensive"][1] < neutral[1] and absf(float(mods_for["defensive"][0]) / float(maxi(neutral[0], 1)) - 1.0) < 0.12, "defensive style concedes less and scores about the same")
	var gain := float(mods_for["attacking"][0]) / float(maxi(neutral[0], 1)) - 1.0
	_check(gain > 0.0 and gain < 0.15, "the attacking edge is small (+%.1f%% goals over 400 matches)" % (gain * 100.0))
	var yb := ManagerProfile.new()
	yb.style = "youth"
	_check(is_equal_approx(float(yb.style_effects()["youth"]), 1.10), "youth developers develop academy players 10% faster")
	var m := ManagerProfile.new()
	m.set_profile("  Ada  ", "country_x", 99, "bogus", "former_star", 7)
	_check(m.manager_name == "Ada" and m.age == 75 and m.style == ManagerProfile.DEFAULT_STYLE and m.reputation == 60, "set_profile sanitises its input")
	var back := ManagerProfile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(back.manager_name == "Ada" and back.background == "former_star" and back.avatar_seed == 7 and back.reputation == 60, "the profile survives a save round trip")
	_check(ManagerProfile.from_dict({}).style == ManagerProfile.DEFAULT_STYLE, "an old save without a profile gets defaults")
	# through the wizard
	app.career = null
	hub.navigate("career_wizard")
	await get_tree().process_frame
	var w: HubScreen = hub.current
	w.set("coach_name", "Zed")
	w.set("coach_style", "motivator")
	w.set("coach_background", "known")
	w.set("club_id", "club_desert_kings")
	_check(w.call("start_career") == "" and app.career.manager.manager_name == "Zed" and app.career.manager.style == "motivator" and app.career.manager.reputation == 40,
			"the wizard applies the chosen coach profile")


## C1.2: "from scratch" = three offers from the weakest clubs of the lowest division, an unknown manager.
func _test_scratch_mode() -> void:
	for world in ["", PACK]:
		app.career = null
		app.switch_world(world)
		hub.navigate("career_wizard")
		await get_tree().process_frame
		var w: HubScreen = hub.current
		w.set("world_id", world)
		_check(_press("Kind_scratch") and w.career_kind == "scratch", "scratch kind chosen (%s)" % ("fictional" if world == "" else world))
		w = hub.current
		_check(_press("WizardNext"), "Next on the world step (scratch)")
		await get_tree().process_frame
		var offers: Array = w.division_clubs()
		_check(offers.size() == 3, "three job offers", str(offers.size()))
		var all: Array = w._clubs_of(w.division())
		var weakest := all.map(func(t: TeamData) -> int: return app.db.get_team_rating(t.id))
		weakest.sort()
		var offered_max := 0
		for t: TeamData in offers:
			offered_max = maxi(offered_max, app.db.get_team_rating(t.id))
		_check(offered_max <= int(weakest[2]), "the offers are the three weakest clubs", "%d vs %d" % [offered_max, int(weakest[2])])
		if world == PACK:
			var lg: LeagueDef = app.db.leagues[w.league_key]
			_check(str(w.division()["id"]) == str((lg.divisions[lg.divisions.size() - 1])["id"]), "...of the lowest division")
		_check(_press("WizardNext"), "Next to the offers")
		await get_tree().process_frame
		var pick: String = (offers[0] as TeamData).id
		_check(_press("Club_%s" % pick) and _press("WizardNext") and _press("WizardNext") and _press("WizardNext") and _press("WizardStart"), "an offer is accepted and the career starts")
		await get_tree().process_frame
		_check(app.career != null and app.career.club_id == pick and app.career.manager.reputation == 20 and app.career.manager.background == "unknown", "the career starts with an unknown manager")


## C1.1 / C1.2: the numbered step bar, the settings step, the welcome message and the real effect of every setting.
func _test_settings_and_bar() -> void:
	app.career = null
	app.switch_world("")
	hub.navigate("career_wizard")
	await get_tree().process_frame
	var w: HubScreen = hub.current
	var circles := w.find_children("Step_*", "Button", true, false)
	_check(circles.size() == 6, "the step bar has one circle per step (%d)" % circles.size())
	_check(_press("WizardNext") and _press("WizardNext") and w.step == 2, "Next twice reaches the club step")
	var back_circle := w.find_child("Step_0", true, false) as Button
	_check(back_circle != null and not back_circle.disabled and (w.find_child("Step_3", true, false) as Button).disabled, "finished steps are clickable, later ones are not")
	back_circle.pressed.emit()
	await get_tree().process_frame
	_check(w.step == 0, "clicking a finished step goes back to it")
	for i in 3:
		_press("WizardNext")
		await get_tree().process_frame
	w.set("club_id", "club_desert_kings")
	w.call("rebuild")
	_press("WizardNext")
	await get_tree().process_frame
	_check(_press("WizardNext") and w.step == 4 and w.find_child("SetMatchDiff", true, false) != null and w.find_child("SetInjuries", true, false) != null, "the settings step offers the options")
	var ws: CareerSettings = w.wizard_settings
	(w.find_child("SetMatchDiff", true, false) as OptionButton).item_selected.emit(2)
	(w.find_child("SetBudget", true, false) as OptionButton).item_selected.emit(0)
	(w.find_child("SetInjuries", true, false) as CheckButton).toggled.emit(false)
	(w.find_child("SetDelegateRenewals", true, false) as CheckButton).toggled.emit(true)
	_check(ws.match_difficulty == "hard" and ws.start_budget == "low" and not ws.injuries and ws.delegate_renewals, "choices are kept in the wizard")
	var default_budget := int(FinanceLedger.new("x", 0, 1000, 0).transfer_budget)
	_check(_press("WizardNext") and w.step == 5, "Next to the summary")
	_check(_press("WizardStart"), "the career starts")
	await get_tree().process_frame
	var c: CareerState = app.career
	_check(c.settings.match_difficulty == "hard" and c.settings.start_budget == "low" and not c.settings.injuries, "the career keeps the chosen settings")
	var normal := CareerState.start(app.db, "club_desert_kings")
	_check(c.ledger().transfer_budget < normal.ledger().transfer_budget, "a lower starting budget really lowers the transfer budget (%d < %d)" % [c.ledger().transfer_budget, normal.ledger().transfer_budget])
	_check(c.delegation.is_delegated("renewals") and not c.delegation.is_delegated("academy"), "the delegation default is applied")
	var welcome := c.inbox.messages.filter(func(m: Dictionary) -> bool: return m["key"] == "INBOX_WELCOME")
	_check(welcome.size() == 1 and welcome[0]["sender"] == "chairman" and "Desert" in Loc.f("INBOX_WELCOME", welcome[0]["args"]), "a welcome message from the chairman arrives in the inbox")
	# real effects
	var squad: Array = app.db.get_squad(c.club_id)
	var victim: PlayerData = squad[0]
	Availability.injure(c, victim, 4)
	_check(victim.status == PlayerData.Status.ACTIVE, "with injuries off nobody gets injured")
	c.settings.injuries = true
	Availability.injure(c, victim, 4)
	_check(victim.status == PlayerData.Status.INJURED, "...and with injuries on they do")
	victim.status = PlayerData.Status.ACTIVE
	victim.unavailable_weeks = 0
	var gf := {}
	for level in ["easy", "hard"]:
		c.settings.match_difficulty = level
		var mods := c.style_mods()
		var g := 0
		for i in 400:
			var f := {"match_id": "s%d" % i, "stage": "league", "home": c.club_id, "away": "club_royal_harbor"}
			var r := MatchSimulator.result(app.db, f, i, {}, [], mods)
			g += r.home_goals - r.away_goals
		gf[level] = g
	_check(gf["easy"] > gf["hard"], "easy matches give the managed club a better goal difference than hard ones", str(gf))
	c.settings.market_difficulty = "hard"
	_check(c._buyer_price_factor(c.club_id) > 1.0 and c._buyer_price_factor("club_royal_harbor") == 1.0, "a hard market raises only the user's prices")
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.settings.to_dict() == c.settings.to_dict(), "settings are saved")
	_check(CareerSettings.from_dict({"match_difficulty": "insane"}).match_difficulty == "normal", "an old save without settings loads with defaults")
