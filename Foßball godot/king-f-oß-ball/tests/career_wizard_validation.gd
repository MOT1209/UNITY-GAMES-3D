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
	_check(_press("WizardNext") and w.step == 3, "step 4: the summary")
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
	_check(_press("Club_%s" % pick) and _press("WizardNext") and _press("WizardStart"), "club chosen and career started")
	await get_tree().process_frame
	var ud: Dictionary = app.career.user_division() if app.career != null else {}
	_check(app.career != null and app.career.club_id == pick and not ud.is_empty() and ud["division"]["id"] == div["id"],
			"the career runs in the chosen division of the data pack")
	_check(app.career.manager.objective.has("target_rank"), "with a board objective for that division")
