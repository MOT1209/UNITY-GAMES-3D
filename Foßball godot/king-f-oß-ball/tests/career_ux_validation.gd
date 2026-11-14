## Career / navigation / settings / theme validation (UX phase 4):
##  4.1 a new career in the fictional world has a league + cup that advance_week really plays,
##  4.2 sectioned navigation, prominent "Play next match", active highlight, back history, phone drawer,
##  4.3 game settings saved and applied (audio buses, graphics, controls),
##  4.4 one UI theme and empty states with a next step.
##   godot --headless --path . res://tests/career_ux_validation.tscn
extends Node

const TEST_SETTINGS := "user://test_career_ux_settings.cfg"

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
	print("=== KING FOOTBALL — Career UX validation ===")
	app = get_node("/root/AppHub")
	var original: String = GameSettings.settings_path
	var original_input: String = InputSettings.settings_path
	GameSettings.settings_path = TEST_SETTINGS
	InputSettings.settings_path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)
	_fresh_career()
	_test_default_league()
	await _test_navigation()
	await _test_settings()
	await _test_theme()
	GameSettings.settings_path = original
	InputSettings.settings_path = original_input
	GameSettings.apply_all(get_tree().root)
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh_career() -> void:
	app.db.load_world("")
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career("club_royal_harbor")


func _test_default_league() -> void:
	var c: CareerState = app.career
	_check(c.pyramids.has(CareerState.DEFAULT_LEAGUE_KEY), "a new fictional-world career has a league (it had none)")
	var pyr: LeaguePyramid = c.pyramids[CareerState.DEFAULT_LEAGUE_KEY]
	var league: Competition = c.competitions[pyr.comp["fic_league"]]
	var clubs: int = app.db.list_teams(TeamData.Category.CLUB).size()
	_check(league.type == Competition.Type.LEAGUE and league.fixtures.size() == clubs * (clubs - 1),
			"every club, home and away", "%d fixtures for %d clubs" % [league.fixtures.size(), clubs])
	_check(pyr.comp.has("cup") and c.competitions.has(pyr.comp["cup"]), "and a domestic cup")
	_check(app.competition_title(league.id) == "%s 1" % Loc.t("LEAGUE_DEFAULT_NAME"),
			"the league name is translated", app.competition_title(league.id))
	var user_fixtures := 0
	var simulated := 0
	for i in 6:
		var info: Dictionary = app.advance_week()
		simulated += int(info["simulated"])
		user_fixtures += (info["user_fixtures"] as Array).size()
		for uf in info["user_fixtures"]:
			app.simulate_fixture(uf["competition_id"], uf["match_id"])
	_check(simulated > 0 and league.results.size() > 0, "advance_week plays the other clubs' matches", "%d simulated" % simulated)
	_check(user_fixtures > 0, "the user's own matches come up in the calendar", str(user_fixtures))
	var table: Array = league.standings()
	var points := 0
	for row in table:
		points += int(row["points"])
	_check(table.size() == clubs and points > 0, "the table fills with results", "%d rows, %d points" % [table.size(), points])
	var c2 := CareerState.from_dict(app.db, c.to_dict())
	_check(c2.pyramids.has(CareerState.DEFAULT_LEAGUE_KEY) and c2.competitions.size() == c.competitions.size(), "the league is saved and loaded with the career")
	var again := CareerState.start(app.db, "club_royal_harbor")
	_check(again.add_default_league() and not again.add_default_league(), "the league is added once only")


func _go(id: String) -> void:
	hub.navigate(id)
	await get_tree().process_frame


func _test_navigation() -> void:
	_fresh_career()
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hub.size = Vector2(1280, 720)
	await get_tree().process_frame
	var play := hub.find_child("PlayNextButton", true, false) as Button
	_check(play != null and play.get_index() == 0, "'Play next match' is the first, prominent navigation entry")
	var sections := hub.find_children("Section_*", "Button", true, false)
	_check(sections.size() == ScreenRegistry.SECTIONS.size() and sections.all(func(s: Node) -> bool: return s.find_children("*", "NavIcon", true, false).size() == 1),
			"six sections, each with an icon", str(sections.size()))
	await _go("academy")
	var youth := hub.find_child("SectionBox_youth", true, false) as Control
	var club := hub.find_child("SectionBox_club", true, false) as Control
	_check(youth.visible and not club.visible, "the open screen's section is expanded, the others are folded")
	var nav_academy := hub.find_child("Nav_academy", true, false) as Button
	_check(nav_academy.has_theme_stylebox_override("normal") and not (hub.find_child("Nav_scouting", true, false) as Button).has_theme_stylebox_override("normal"),
			"the active screen's button is highlighted")
	(hub.find_child("Section_club", true, false) as Button).pressed.emit()
	_check(club.visible, "a section header unfolds its section")
	await _go("transfers")
	await _go("finance")
	_check(hub.go_back() and hub.current_id == "transfers", "back returns to the previous screen")
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	hub._unhandled_input(ev)
	_check(hub.current_id == "academy", "Esc / Android back goes back through the history", hub.current_id)
	hub.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(hub.current_id != "academy", "the Android back request is handled")
	var visible_small := 0
	for b in hub.find_children("Nav_*", "Button", true, false):
		if (b as Control).is_visible_in_tree() and (b as Control).size.y < 48.0:
			visible_small += 1
	_check(visible_small == 0, "navigation buttons are >= 48 px tall")
	await _go("career")
	play.pressed.emit()
	await get_tree().process_frame
	_check(hub.current_id == "match_setup" or not app.due_user_fixtures().is_empty(), "no due match: 'Play next match' opens the match setup")
	hub.queue_free()
	await get_tree().process_frame
	HubRoot.force_compact = 1
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var toggle := hub.find_child("NavToggle", true, false) as Button
	var panel := hub.find_child("NavPanel", true, false) as Control
	_check(toggle.visible and not panel.visible, "phone: navigation is a drawer behind a menu button")
	toggle.pressed.emit()
	_check(panel.visible, "phone: the menu button opens the drawer")
	(hub.find_child("Nav_squad", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(not panel.visible and hub.current_id == "squad", "phone: choosing a screen closes the drawer")
	HubRoot.force_compact = -1
	hub.queue_free()
	await get_tree().process_frame


func _test_settings() -> void:
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	await _go("settings")
	var s := hub.current
	for n in ["AudioSettings", "GraphicsSettings", "ControlSettings", "Slider_master", "Slider_crowd", "Slider_effects",
			"Option_shadows", "Option_msaa", "Option_fps_cap", "Option_render_scale", "Option_switch_mode", "Option_camera",
			"Toggle_aim_assist", "Toggle_vibration", "Option_touch_button_scale"]:
		_check(s.find_child(n, true, false) != null, "settings offer %s" % n)
	(s.find_child("Slider_crowd", true, false) as HSlider).value = 40
	_check(is_equal_approx(float(GameSettings.get_value("audio", "crowd")), 0.4), "crowd volume is saved")
	var bus := AudioServer.get_bus_index(GameSettings.BUS_CROWD)
	_check(bus >= 0 and absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.4)) < 0.1, "and applied to the crowd bus at once")
	var msaa := s.find_child("Option_msaa", true, false) as OptionButton
	msaa.select(2)
	msaa.item_selected.emit(2)
	_check(int(GameSettings.get_value("graphics", "msaa")) == 4 and get_tree().root.msaa_3d == Viewport.MSAA_4X, "anti-aliasing is saved and applied")
	var fps := s.find_child("Option_fps_cap", true, false) as OptionButton
	fps.select(0)
	fps.item_selected.emit(0)
	_check(Engine.max_fps == 30, "frame cap 30 applied")
	var vib := s.find_child("Toggle_vibration", true, false) as CheckButton
	vib.button_pressed = false
	_check(not bool(InputSettings.get_value("rumble")), "vibration switch drives the controller rumble setting")
	var aim := s.find_child("Toggle_aim_assist", true, false) as CheckButton
	aim.button_pressed = false
	GameSettings.set_value("controls", "touch_button_scale", 1.4)
	var cfg := ConfigFile.new()
	_check(cfg.load(TEST_SETTINGS) == OK and cfg.has_section_key("graphics", "msaa") and cfg.has_section_key("audio", "crowd"),
			"everything lands in the settings file")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.rng_seed = 3
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, app.db)
	_check(not m.aim_assist_enabled and m.selected["actions"].aim_assist == null, "aim assist off reaches the match")
	m._touch.set_active(true)
	var btn := m._touch.find_child("Btn_pass", true, false) as Control
	_check(btn != null and btn.custom_minimum_size.x > 92.0 * 1.3, "touch buttons follow the size setting")
	m._touch.set_active(false)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	hub.queue_free()
	await get_tree().process_frame


func _test_theme() -> void:
	_check(ResourceLoader.exists(UIKit.THEME_PATH), "the game theme resource exists")
	var t := get_tree().root.theme
	var ok := t != null
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		ok = ok and t.has_stylebox(st, "Button")
	_check(ok, "root theme styles every button state (normal / hover / pressed / disabled / focus)")
	_check(t != null and t.default_font != null, "the theme keeps the Arabic font stack")
	_check(UIKit.SPACE_S == 8 and UIKit.SPACE_M == 16 and UIKit.SPACE_L == 24, "one spacing scale 8 / 16 / 24")
	var empty := UIKit.empty_state("x", "Go", func() -> void: pass, "trophy")
	add_child(empty)
	_check(empty.find_child("EmptyStateAction", true, false) is Button and empty.find_children("*", "NavIcon", true, false).size() == 1,
			"empty states have an illustration and a next-step button")
	empty.queue_free()
