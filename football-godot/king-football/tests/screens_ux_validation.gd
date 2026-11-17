## Screens UX validation (UX phase 3): per-screen fixes from the review — squad pitch and best XI,
## portraits, card captions, team selection in a career, tactics columns, promotion details, training
## and transfer tables, kit column, developer-only database tools, first-run and main-menu visuals,
## match ratings. Layout limits for every screen: `ui_layout_validation`.
##   godot --headless --path . res://tests/screens_ux_validation.tscn
extends Node

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
	print("=== KING FOOTBALL — Screens UX validation ===")
	app = get_node("/root/AppHub")
	db = app.db
	db.load_world("")
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	_test_best_xi()
	_test_pitch_and_portraits()
	await _test_card_layout()
	_test_ratings()
	_test_market_order()
	app.start_career("club_royal_harbor")
	Loc.set_language("en", false)
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hub.size = Vector2(1280, 720)
	await get_tree().process_frame
	await _test_team_select()
	await _test_tactics()
	await _test_promotion_and_training()
	await _test_transfers_and_details()
	await _test_developer_tools()
	await _test_first_run_and_menu()
	hub.queue_free()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _go(id: String, p: Dictionary = {}) -> void:
	hub.navigate(id, p)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_best_xi() -> void:
	var bad: Array = []
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var sq := Squad.new(t.id)
		sq.auto_pick(db)
		var unused: Array = sq.bench + sq.reserves
		for slot in 11:
			var pid: String = sq.starting[slot]
			if pid == "":
				continue
			var slot_pos := FormationData.slot_position(sq.formation_id, slot)
			if (db.get_player(pid) as PlayerData).position == slot_pos:
				continue
			for other in unused:
				var o: PlayerData = db.get_player(other)
				if o != null and o.status == PlayerData.Status.ACTIVE and o.position == slot_pos:
					bad.append("%s slot %d" % [t.id, slot])
					break
	_check(bad.is_empty(), "best XI: no slot holds an out-of-position player while a natural one sits on the bench", str(bad.slice(0, 5)))


func _test_pitch_and_portraits() -> void:
	_check(SquadPitch.BG.g > SquadPitch.BG.r + 0.15 and SquadPitch.BG.g > 0.3, "squad pitch is grass green (was near-black)")
	var blank := Image.create(60, 72, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	_check(PlayerPortraitRenderer.is_blank(blank), "an empty first portrait frame is recognised (it is re-rendered, never cached)")
	var full := Image.create(60, 72, false, Image.FORMAT_RGBA8)
	full.fill(Color(0.8, 0.3, 0.2, 1.0))
	_check(not PlayerPortraitRenderer.is_blank(full), "a rendered portrait is accepted")
	_check(PlayerPortraitRenderer.new().has_signal("portrait_ready"), "renderer announces finished portraits (cards waiting for one refresh)")


func _test_card_layout() -> void:
	var gk: PlayerData = null
	for p: PlayerData in db.players.values():
		if p.position == PlayerData.Position.GK:
			gk = p
			break
	for code in ["ar", "en"]:
		Loc.set_language(code, false)
		var card := PlayerCard.new(150.0)
		add_child(card)
		card.size = card.custom_minimum_size
		card.setup(PlayerCardData.from_data(db, gk), db)
		await get_tree().process_frame
		card.relayout()
		var fits := true
		for s in card._stat_labels:
			var l := s["code"] as Label
			var w := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
			fits = fits and w <= l.size.x + 1.0
		_check(fits, "[%s] stat captions fit their cells" % code)
		var ovr := Rect2(card._ovr.position, card._ovr.size)
		var pos := Rect2(card._pos.position, card._pos.size)
		var gkr := Rect2(card._gk.position, card._gk.size)
		_check(card._gk.text != "" and not gkr.intersects(ovr) and not gkr.intersects(pos), "[%s] goalkeeper badge no longer overlaps the rating" % code)
		card.queue_free()
	Loc.set_language("ar", false)
	_check(Loc.t("CARD_STAT_DRI") == "مراوغة" and Loc.t("CARD_STAT_PAC") == "سرعة", "Arabic stat captions are words (سرعة، مراوغة) not cut-off stems")
	Loc.set_language("en", false)


func _test_ratings() -> void:
	var s := MatchStats.new()
	s.players["a"] = MatchStats._new_player("home")
	s.players["b"] = MatchStats._new_player("home")
	s.players["b"]["yellow"] = 1
	s.players["b"]["fouls"] = 2
	_check(s.rating("b", 0) < s.rating("a", 0), "a booked player who fouls is rated below a clean one",
			"%.1f vs %.1f" % [s.rating("b", 0), s.rating("a", 0)])


func _test_market_order() -> void:
	app.select_team("club_royal_harbor")
	var sq: Squad = app.squad()
	var pool: Array = []
	for p: PlayerData in db.players.values():
		if p.team_id != "club_royal_harbor" and p.status == PlayerData.Status.ACTIVE:
			pool.append(p)
	var ordered: Array = load("res://scripts/ui/screens/transfers_screen.gd").by_team_need(pool, sq, db)
	var gks := ordered.slice(0, 10).filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
	_check(gks < 10, "transfer list no longer starts with goalkeepers only", "%d of the first 10 are GK" % gks)


func _test_team_select() -> void:
	await _go("team_select")
	_check(hub.current.find_child("Career_club_royal_harbor", true, false) == null
			and hub.current.find_children("Career_*", "Button", true, false).is_empty(),
			"in a running career there is no 'Start career' button")
	var switch := hub.current.find_child("SwitchClub_club_northgate_utd", true, false) as Button
	_check(switch != null, "other clubs offer 'Switch club' instead")
	var row := hub.current.find_child("TeamRow_club_royal_harbor", true, false) as Control
	_check(row != null and row.get_combined_minimum_size().y <= 70.0, "club rows are compact (<= 70 px, were ~130)",
			str(row.get_combined_minimum_size().y if row != null else -1))
	switch.pressed.emit()
	await get_tree().process_frame
	var confirm: ConfirmationDialog = null
	for c in hub.current.get_children():
		if c is ConfirmationDialog:
			confirm = c
	_check(confirm != null, "switching club asks for confirmation first")
	_check(app.career.club_id == "club_royal_harbor", "nothing changes before the confirmation")
	if confirm != null:
		confirm.confirmed.emit()
		await get_tree().process_frame
	_check(app.career != null and app.career.club_id == "club_northgate_utd", "after confirming, the career continues with the new club")
	app.start_career("club_royal_harbor")
	await get_tree().process_frame


func _test_tactics() -> void:
	await _go("tactics")
	var cols := hub.current.find_child("TacticsColumns", true, false) as HBoxContainer
	_check(cols != null and cols.find_child("PitchPreview", true, false) != null and cols.get_child_count() == 2,
			"tactics: pitch and settings side by side")
	var slider := hub.current.find_child("PressingSlider", true, false) as HSlider
	var value := hub.current.find_child("PressingSliderValue", true, false) as Label
	_check(slider != null and value != null and value.text == str(int(slider.value)), "every slider shows its value")
	slider.value = 85
	_check(value.text == "85", "the value follows the slider")


func _test_promotion_and_training() -> void:
	await _go("promotion")
	_check(hub.current.find_child("PromotionDetails", true, false) != null, "promotion: details of a preselected player fill the right column")
	var texts: Array = []
	for l in hub.current.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	_check(not texts.any(func(t: String) -> bool: return t.begins_with("too young")), "eligibility is localized (no raw 'too young (min 16)')")
	await _go("training")
	var cells: Array = []
	for l in hub.current.find_children("*", "Label", true, false):
		cells.append((l as Label).text)
	_check(cells.has("—"), "training: 'this week' shows a dash until a week is trained")


func _test_transfers_and_details() -> void:
	await _go("transfers")
	var table := hub.current.find_child("MarketTable", true, false) as GridContainer
	_check(table != null and table.columns == 7 and (table.get_child(0) as Label).text == Loc.t("COMMON_NAME"),
			"transfers: a table with column headers")
	await _go("team_details", {"team_id": "club_royal_harbor"})
	var ok := true
	for l in hub.current.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with(Loc.f("KIT_NO_KIT", Loc.enum_name("KITSLOT", "third")).left(6)):
			ok = ok and (l as Control).custom_minimum_size.x >= 96.0
	_check(ok, "team details: a missing kit is described in a column wide enough for one or two lines")


func _test_developer_tools() -> void:
	ScreenRegistry.force_developer = 0
	_check(not ScreenRegistry.in_navigation("database") and ScreenRegistry.in_navigation("career"), "release build: database tools are not in the navigation")
	var h := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(h)
	await get_tree().process_frame
	_check(h.find_child("Nav_database", true, false) == null, "release build: no database button for players")
	h.queue_free()
	ScreenRegistry.force_developer = 1
	_check(ScreenRegistry.in_navigation("database"), "developer mode shows the database tools")
	ScreenRegistry.force_developer = -1
	await get_tree().process_frame


func _test_first_run_and_menu() -> void:
	var host := Control.new()
	add_child(host)
	var overlay := LanguagePicker.show_first_run(host)
	await get_tree().process_frame
	_check(overlay.find_child("Background", true, false) is TextureRect and overlay.find_child("Logo", true, false) is Label,
			"first-run language screen: stadium background and game logo (was black)")
	host.queue_free()
	var had_save := FileAccess.file_exists(AppHub.SAVE_PATH)
	var backup := FileAccess.get_file_as_string(AppHub.SAVE_PATH) if had_save else ""
	app.save_game()
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu.find_child("StadiumBackground", true, false) is TextureRect, "main menu: stadium background")
	var cont := menu.find_child("ContinueButton", true, false) as Button
	_check(cont != null and cont.get_index() < (menu.get_node("%PlayButton") as Button).get_index(), "main menu: 'Continue career' first when a save exists")
	menu.queue_free()
	if had_save:
		var f := FileAccess.open(AppHub.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(AppHub.SAVE_PATH)
	await get_tree().process_frame
