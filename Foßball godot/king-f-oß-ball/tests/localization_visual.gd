## Localization visual QA (needs a real window — NOT headless):
##   godot --path . res://tests/localization_visual.tscn --resolution 1280x720
## For ar / de / en it renders the main menu, the first-run dialog and every
## main hub screen, saves a PNG of each to docs/qa/ and writes
## docs/qa/visual_report.txt (text server, font coverage, direction, glyph checks).
extends Node

const OUT_DIR := "res://docs/qa"
const SCREENS: Array[String] = ["team_select", "squad", "tactics", "academy", "scouting", "training", "promotion",
		"competitions", "career", "transfers", "finance", "customize", "kit_editor", "match_setup", "settings"]

var _report: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var loc_settings := "user://visual_qa_settings.cfg"
	Loc.settings_path = loc_settings
	_log("=== KING FOOTBALL — localization visual QA ===")
	var ts := TextServerManager.get_primary_interface()
	_log("text server: %s | shaping (Arabic joining): %s | bidi: %s" % [ts.get_name(),
			ts.has_feature(TextServer.FEATURE_SHAPING), ts.has_feature(TextServer.FEATURE_BIDI_LAYOUT)])
	_log("display driver: %s | window %s" % [DisplayServer.get_name(), str(get_window().size)])
	_log("arabic font bundled and loaded: %s" % Loc.arabic_font_loaded)
	_font_report()
	var app := get_node("/root/AppHub")
	app.db.reload()
	app.start_career("club_royal_harbor")
	for code in ["ar", "de", "en"]:
		Loc.set_language(code, true)
		await _shot_main_menu(code)
		await _shot_first_run(code)
		await _shot_hub(code, app)
	var f := FileAccess.open("%s/visual_report.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(_report) + "\n")
	f.close()
	print("\n".join(_report))
	get_tree().quit(0)


func _log(s: String) -> void:
	_report.append(s)


func _font_report() -> void:
	var font: Font = get_tree().root.theme.default_font if get_tree().root.theme != null else ThemeDB.fallback_font
	var samples := {"Arabic alef/ba (U+0627 U+0628)": 0x0627, "Arabic lam-alef ligature base (U+0644)": 0x0644,
			"German a-umlaut": 0xE4, "German o-umlaut": 0xF6, "German u-umlaut": 0xFC, "German sharp s": 0xDF, "Latin A": 0x41}
	for label in samples:
		_log("glyph coverage (theme font) %s: %s" % [label, font.has_char(samples[label])])
	if ResourceLoader.exists(Loc.ARABIC_FONT_PATH):
		var ar := load(Loc.ARABIC_FONT_PATH) as Font
		_log("bundled Noto Sans Arabic has U+0627: %s, U+0644: %s, U+0649: %s" % [ar.has_char(0x0627), ar.has_char(0x0644), ar.has_char(0x0649)])


func _settle(frames: int = 8) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(ProjectSettings.globalize_path(path))
	_log("screenshot %s -> %s" % [name, "saved" if err == OK else "FAILED (%d)" % err])


func _shot_main_menu(code: String) -> void:
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await _settle(10)
	_log("[%s] main menu RTL=%s play='%s' settings='%s' exit='%s'" % [code, menu.is_layout_rtl(), (menu.get_node("%PlayButton") as Button).text, (menu.get_node("%SettingsButton") as Button).text, (menu.get_node("%QuitButton") as Button).text])
	await _save("menu_%s" % code)
	var settings: Button = menu.get_node("%SettingsButton")
	settings.pressed.emit()
	await _settle(6)
	await _save("settings_panel_%s" % code)
	menu.queue_free()
	await get_tree().process_frame


func _shot_first_run(code: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	LanguagePicker.show_first_run(host)
	await _settle(6)
	if code == "en":
		await _save("first_run_dialog")
	host.queue_free()
	await get_tree().process_frame


func _shot_hub(code: String, app: Node) -> void:
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await _settle(4)
	for id in SCREENS:
		var params := {}
		if id == "kit_editor":
			params = {"team_id": "club_royal_harbor"}
		hub.navigate(id, params)
		await _settle(8)
		await _save("hub_%s_%s" % [id, code])
	_log("[%s] hub rendered %d screens, hub RTL=%s" % [code, SCREENS.size(), hub.is_layout_rtl()])
	hub.queue_free()
	await get_tree().process_frame
