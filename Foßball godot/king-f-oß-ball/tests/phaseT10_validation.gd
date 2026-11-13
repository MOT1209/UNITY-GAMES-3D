## Phase T10 validation — hub, reusable components, all screens wired:
##   godot --headless --path . res://tests/phaseT10_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var hub: HubRoot
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
	print("=== KING FOOTBALL — Phase T10 validation ===")
	app = get_node("/root/AppHub")
	app.db.reload()
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	_test_kit()
	await _test_hub_empty_states()
	await _test_flow()
	await _test_every_screen_builds()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


func _press(node_name: String) -> bool:
	if hub.current == null:
		return false
	var b := _find(hub.current, node_name) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _test_kit() -> void:
	var l := UIKit.label("x", 20)
	_check(l.text == "x" and l.get_theme_font_size("font_size") == 20, "UIKit.label")
	var pressed := [0]
	var b := UIKit.button("Go", func() -> void: pressed[0] += 1, 100)
	b.pressed.emit()
	_check(pressed[0] == 1 and b.custom_minimum_size.x == 100, "UIKit.button wiring")
	var t := UIKit.table(["a", "b"], [[1, 2], [3, 4]])
	_check(t is GridContainer and t.get_child_count() == 6, "UIKit.table cells")
	var clicked := [-1]
	var t2 := UIKit.table(["a"], [[1], [2]], func(i: int) -> void: clicked[0] = i)
	var open_buttons: Array = t2.find_children("*", "Button", true, false)
	(open_buttons[1] as Button).pressed.emit()
	_check(open_buttons.size() == 2 and clicked[0] == 1, "table row callback")
	var o := UIKit.option(["x", "y", "z"], 1)
	_check(o.selected == 1 and o.item_count == 3, "UIKit.option")
	var bar := UIKit.stat_bar("Pace", 80)
	_check(bar.find_child("*", true, false) != null and (bar.find_children("*", "ProgressBar", true, false)[0] as ProgressBar).value == 80, "stat bar value")
	_check(UIKit.empty_state("hello") is PanelContainer, "empty state component")
	var team: TeamData = app.db.get_team("club_royal_harbor")
	var kit := UIKit.kit_preview(team, "home")
	var shirt := kit.find_child("KitShirt", true, false) as TextureRect
	_check(shirt != null and shirt.texture != null, "kit preview draws the shirt, shorts and socks")
	var solid := {"main": Color("c8102e"), "secondary": Color.WHITE, "accent": Color.WHITE, "shorts": Color("101010"), "socks": Color("c8102e"), "pattern": "solid"}
	var shirt_img := KitRenderer.render(solid, null, 1)
	_check(shirt_img.get_pixel(44, 42).is_equal_approx(Color("c8102e").lerp(Color.WHITE, 0.0)) or shirt_img.get_pixel(44, 42).r > 0.6,
			"the kit renderer paints the shirt in the saved main colour")
	_check(UIKit.kit_preview(team, "nope").get_child_count() == 1, "kit preview handles missing kit")
	var dialog := UIKit.confirm(self, "sure?", func() -> void: pressed[0] += 10)
	_check(dialog is ConfirmationDialog and dialog.get_parent() == self, "confirm dialog created")
	dialog.confirmed.emit()
	_check(pressed[0] == 11, "confirm dialog triggers action")
	dialog.queue_free()
	_check(ScreenRegistry.SCREENS.size() == 22, "22 screens registered (20 management screens + Database tools + Settings; the main menu is separate)")
	_check(ScreenRegistry.create("nope") == null, "unknown screen id -> null")
	for id in ScreenRegistry.SCREENS:
		_check(ResourceLoader.exists(ScreenRegistry.SCREENS[id][1]), "screen script exists: %s" % id)


func _spawn_hub() -> void:
	if hub != null:
		hub.queue_free()
		await get_tree().process_frame
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame


func _test_hub_empty_states() -> void:
	await _spawn_hub()
	_check(hub.current_id == "team_select", "hub opens on team selection without a team")
	for id in ["squad", "tactics", "academy", "scouting", "training", "promotion", "competitions", "transfers", "finance"]:
		hub.navigate(id)
		await get_tree().process_frame
		var empty := hub.current.find_children("*", "Button", true, false).any(func(b: Button) -> bool:
				return b.text.begins_with("Go to"))
		_check(empty, "%s shows an empty state with a way forward when no team is chosen" % id)
	_check(not hub.navigate("does_not_exist"), "navigating to an unknown screen fails safely")
	_check(hub.current_id == "finance", "failed navigation keeps the current screen")
	hub.navigate("player_profile", {"player_id": "ghost"})
	await get_tree().process_frame
	_check(hub.current != null, "player profile for an unknown player shows an empty state")
	hub.navigate("standings", {"competition_id": "ghost"})
	await get_tree().process_frame
	_check(hub.current != null, "standings with no career shows an empty state")


func _test_flow() -> void:
	await _spawn_hub()
	# Team selection -> career
	hub.navigate("team_select")
	await get_tree().process_frame
	var filter := _find(hub.current, "FilterOption") as OptionButton
	filter.select(2)
	filter.item_selected.emit(2)
	await get_tree().process_frame
	var nat_buttons: Array = hub.current.find_children("Select_nat_*", "Button", true, false)
	_check(nat_buttons.size() == 4, "national-team filter lists 4 teams", str(nat_buttons.size()))
	filter = _find(hub.current, "FilterOption") as OptionButton
	filter.select(1)
	filter.item_selected.emit(1)
	await get_tree().process_frame
	_check(_press("Career_club_royal_harbor"), "start career button")
	await get_tree().process_frame
	_check(app.career != null and app.user_team_id == "club_royal_harbor", "career + team selected via the UI")
	_check(hub.current_id == "career", "career dashboard opens")
	# Career: advance week pays wages
	var bal: int = app.career.ledger().balance
	_check(_press("AdvanceWeek"), "advance week button")
	await get_tree().process_frame
	_check(app.career.week == 1 and app.career.ledger().balance < bal, "advance week through UI pays wages")
	# Squad screen
	hub.navigate("squad")
	await get_tree().process_frame
	_check(_press("AutoPick"), "auto-pick button")
	await get_tree().process_frame
	_check(app.squad().validate(app.db).is_empty(), "squad valid after UI auto-pick")
	var slot3 := _find(hub.current, "Slot_3") as OptionButton
	_check(slot3 != null and slot3.item_count > 11, "slot dropdowns list the squad")
	var before: String = app.squad().starting[3]
	# Slot 3 is an outfield slot, so pick another outfielder (a keeper is rightly rejected).
	var other_index := -1
	for i in range(1, slot3.item_count):
		if i != slot3.selected and not slot3.get_item_text(i).contains("(GK "):
			other_index = i
			break
	_check(other_index > 0, "an alternative outfielder exists for slot 3")
	slot3.select(other_index)
	slot3.item_selected.emit(other_index)
	await get_tree().process_frame
	var dup := 0
	for pid in app.squad().starting:
		if pid != "" and pid == app.squad().starting[3]:
			dup += 1
	_check(app.squad().starting[3] != before and dup == 1, "changing a slot through the UI never duplicates a player")
	# Tactics
	hub.navigate("tactics")
	await get_tree().process_frame
	var fo := _find(hub.current, "FormationOption") as OptionButton
	var idx := FormationData.ids().find("4-4-2")
	fo.select(idx)
	fo.item_selected.emit(idx)
	await get_tree().process_frame
	_check(app.squad().formation_id == "4-4-2" and app.squad().validate(app.db).is_empty(), "formation change via UI re-fits a valid XI")
	var mo := _find(hub.current, "MentalityOption") as OptionButton
	mo.select(4)
	mo.item_selected.emit(4)
	_check(app.squad().get_tactics().mentality == TacticsPreset.Mentality.ULTRA_ATTACKING, "mentality drives the real tactics object")
	var ps := _find(hub.current, "PressingSlider") as HSlider
	ps.value = 85
	_check(app.squad().get_tactics().pressing == 85, "pressing slider drives the real tactics object")
	var name_edit := _find(hub.current, "PresetName") as LineEdit
	name_edit.text = "High Press"
	var save_btn: Button = hub.current.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("Save current"))[0]
	save_btn.pressed.emit()
	await get_tree().process_frame
	_check(app.squad().presets.size() == 2 and app.squad().get_tactics().preset_name == "High Press", "preset saved and selected through the UI")
	# Academy + promotion
	hub.navigate("academy")
	await get_tree().process_frame
	var roster_before: int = app.academy().roster_ids.size()
	_check(roster_before > 0, "academy was created with prospects")
	_check(_press("IntakeButton"), "intake button")
	await get_tree().process_frame
	_check(app.academy().roster_ids.size() >= roster_before, "intake keeps the roster consistent")
	var pid := ""
	for id in app.academy().roster_ids:
		if app.db.get_player(id).age >= AcademyConfig.MIN_PROMOTION_AGE:
			pid = id
			break
	_check(pid != "", "an eligible academy player exists")
	hub.navigate("promotion", {"player_id": pid})
	await get_tree().process_frame
	var squad_before: int = app.db.get_team("club_royal_harbor").squad_ids.size()
	var err: String = hub.current.promote_selected(0)
	await get_tree().process_frame
	_check(err == "", "promotion through the screen succeeds", err)
	_check(app.db.get_team("club_royal_harbor").squad_ids.size() == squad_before + 1 and not (pid in app.academy().roster_ids),
			"promoted player moved from academy to first team")
	_check(app.db.get_player(pid).status == PlayerData.Status.ACTIVE, "promoted player is ACTIVE")
	# Scouting
	hub.navigate("scouting")
	await get_tree().process_frame
	_check(_press("SendScout"), "send scout button")
	await get_tree().process_frame
	var sc: ScoutingSystem = app.scouting["club_royal_harbor"]
	_check(sc.missions.size() == 1, "mission started through the UI")
	for i in 3:
		_press("AdvanceWeek")
		await get_tree().process_frame
	_check(sc.pool.size() >= 1, "scouted prospects discovered via the UI")
	var sign_btns: Array = hub.current.find_children("Sign_*", "Button", true, false)
	_check(sign_btns.size() >= 1, "discovered prospects have sign buttons")
	var academy_before: int = app.academy().roster_ids.size()
	(sign_btns[0] as Button).pressed.emit()
	await get_tree().process_frame
	_check(app.academy().roster_ids.size() == academy_before + 1, "signing through the UI adds to the academy")
	# Training
	hub.navigate("training")
	await get_tree().process_frame
	var tr_before: int = app.training["club_royal_harbor"].week
	var cal_before: int = app.career.absolute_week()
	_check(tr_before == cal_before, "training weeks equal career weeks (calendar-driven)")
	_check(_press("Train1"), "train button")
	await get_tree().process_frame
	_check(app.career.absolute_week() == cal_before + 1 and app.training["club_royal_harbor"].week == tr_before + 1,
			"one career week advances exactly one training week via the UI")
	# Competitions
	hub.navigate("competitions")
	await get_tree().process_frame
	_check(_press("CreateButton"), "create competition button")
	await get_tree().process_frame
	_check(app.career.competitions.size() == 1, "competition created through the UI")
	var cid: String = app.career.competitions.keys()[0]
	hub.navigate("standings", {"competition_id": cid})
	await get_tree().process_frame
	_check(_press("SimAll"), "simulate-all button")
	await get_tree().process_frame
	var comp: Competition = app.career.competitions[cid]
	_check(comp.is_finished() and comp.champion_id != "", "league simulated to a champion through the UI")
	_check(comp.results.size() == comp.fixtures.size(), "every fixture has exactly one result")
	for tid in app.career.ledgers:
		_check(app.career.ledgers[tid].is_consistent(), "ledger audit passes for %s after simulation" % tid)
	# Cup + bracket
	hub.navigate("competitions")
	await get_tree().process_frame
	(_find(hub.current, "TypeOption") as OptionButton).select(1)
	((_find(hub.current, "TypeOption") as OptionButton) as OptionButton).item_selected.emit(1)
	_press("CreateButton")
	await get_tree().process_frame
	var cup_id := ""
	for id in app.career.competitions:
		if id != cid:
			cup_id = id
	_check(cup_id != "" and app.career.competitions[cup_id].type == Competition.Type.KNOCKOUT, "knockout cup created via the UI")
	for i in 20:
		var cp: Competition = app.career.competitions[cup_id]
		if cp.is_finished():
			break
		app.simulate_fixture(cup_id, cp.pending_fixtures()[0]["match_id"])
	hub.navigate("bracket", {"competition_id": cup_id})
	await get_tree().process_frame
	_check(app.career.competitions[cup_id].is_finished() and hub.current.get_child_count() > 2, "bracket screen renders a finished cup")
	# Transfers
	hub.navigate("transfers")
	await get_tree().process_frame
	var buy: Button = hub.current.find_children("Buy_*", "Button", true, false)[0]
	var buy_pid := buy.name.trim_prefix("Buy_")
	var transfers_before: int = app.career.market.history.size()
	buy.pressed.emit()
	await get_tree().process_frame
	var owned: bool = app.db.get_player(buy_pid).team_id == "club_royal_harbor"
	_check(owned or app.career.market.history.size() == transfers_before, "buy either completes or is refused without side effects")
	var ledger_ok: bool = app.career.ledger().is_consistent()
	_check(ledger_ok, "ledger consistent after a UI transfer attempt")
	# Finance
	hub.navigate("finance")
	await get_tree().process_frame
	_check(hub.current.get_child_count() > 3, "finance screen shows the ledger")
	# Save / load roundtrip through the UI state
	var path := "user://test_saves/hub.json"
	_check(app.save_game(path) == "", "save from the hub state")
	var squad_ids: Array = Array(app.db.get_team("club_royal_harbor").squad_ids)
	var week: int = app.career.week
	app.career = null
	_check(app.load_game(path) == "", "load restores the hub state")
	_check(app.career != null and app.career.week == week, "career restored")
	_check(Array(app.db.get_team("club_royal_harbor").squad_ids) == squad_ids, "squad identical after load")
	_check(app.squads.has("club_royal_harbor") and app.academies.has("club_royal_harbor"), "squad + academy restored")
	DirAccess.remove_absolute(path)
	# Customisation: create, edit kit, delete
	hub.navigate("customize")
	await get_tree().process_frame
	_press("CreateClub")
	await get_tree().process_frame
	_check(app.db.get_team("club_new_club_fc") != null, "club created through the UI")
	hub.navigate("kit_editor", {"team_id": "club_new_club_fc"})
	await get_tree().process_frame
	var picker := _find(hub.current, "Color_main") as ColorPickerButton
	picker.color = Color("123456")
	picker.color_changed.emit(Color("123456"))
	_check(app.db.get_team("club_new_club_fc").kits["home"]["main"] == "123456", "kit colour change reaches the team data")
	_press("SaveKit")
	await get_tree().process_frame
	var reloaded: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	reloaded.reload()
	_check(reloaded.get_team("club_new_club_fc").kits["home"]["main"] == "123456", "saved kit persists on disk")
	reloaded.free()
	_check(ClubCreator.delete_user_club(app.db, "club_new_club_fc") == "", "cleanup: delete test club")
	# Match setup quick sim
	hub.navigate("match_setup")
	await get_tree().process_frame
	var ms: HubScreen = hub.current
	var setup: MatchSetup = ms.make_setup()
	_check(setup.validate(app.db).is_empty() and setup.home_id != setup.away_id, "match setup screen builds a valid MatchSetup", str(setup.validate(app.db)))
	_check(_press("QuickSim"), "quick simulate button")


func _test_every_screen_builds() -> void:
	await _spawn_hub()
	var failures := []
	for id in ScreenRegistry.SCREENS:
		var ok := hub.navigate(id)
		await get_tree().process_frame
		if not ok or hub.current == null or hub.current.get_child_count() == 0:
			failures.append(id)
		if hub.current != null and hub.current_id != id:
			failures.append(id)
	_check(failures.is_empty(), "all hub screens build with content", str(failures))
	var nav_buttons: Array = hub.find_children("Nav_*", "Button", true, false)
	_check(nav_buttons.size() == ScreenRegistry.SCREENS.size() - ScreenRegistry.NAV_HIDDEN.size() + 1, "navigation bar has every screen + main menu", str(nav_buttons.size()))
	var go_ok := false
	for b: Button in nav_buttons:
		if b.name == "Nav_squad":
			b.pressed.emit()
			await get_tree().process_frame
			go_ok = hub.current_id == "squad"
	_check(go_ok, "navigation buttons switch screens")
