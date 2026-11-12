## Localization validation — tables, switching, persistence, direction, fonts,
## formatting, plural rules, enum coverage, no hardcoded UI strings, and every
## hub screen rendered in all three languages.
##   godot --headless --path . res://tests/localization_validation.tscn
extends Node

const LANGS: Array[String] = ["ar", "de", "en"]
const TEST_SETTINGS := "user://test_loc_settings.cfg"
## Files allowed to contain literal UI text (language-neutral by design).
const LITERAL_ALLOWLIST: Array[String] = ["language_picker.gd"]

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
	print("=== KING FOOTBALL — Localization validation ===")
	app = get_node("/root/AppHub")
	var original_path: String = Loc.settings_path
	Loc.settings_path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)
	_test_tables()
	_test_required_keys()
	_test_switching_and_direction()
	_test_persistence()
	_test_text_quality()
	_test_formatting()
	_test_plurals()
	_test_enum_coverage()
	_test_no_hardcoded_ui_strings()
	await _test_main_menu()
	await _test_every_screen_in_every_language()
	await _test_rtl_layout()
	Loc.set_language("en", false)
	Loc.settings_path = original_path
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- tables -------------------------------------------------------------------------

func _test_tables() -> void:
	_check(Loc != null, "Loc autoload is registered")
	_check(Loc.load_errors.is_empty(), "translation files load without errors", str(Loc.load_errors))
	var problems: Array[String] = Loc.validate()
	_check(problems.is_empty(), "every key exists, is non-empty and placeholder-consistent in ar/de/en",
			"%d problems, first: %s" % [problems.size(), str(problems.slice(0, 3))])
	var n_en: int = Loc.tables["en"].size()
	_check(n_en > 400 and Loc.tables["de"].size() >= n_en - 8 and Loc.tables["ar"].size() >= n_en, "translation tables have comparable size",
			"en=%d de=%d ar=%d" % [n_en, Loc.tables["de"].size(), Loc.tables["ar"].size()])
	_check(Loc.supported_codes() == ["ar", "de", "en"], "three first-class languages are supported")
	_check(Loc.is_rtl("ar") and not Loc.is_rtl("de") and not Loc.is_rtl("en"), "only Arabic is RTL")
	var bad_keys: Array = []
	for k in Loc.tables["en"]:
		var base: String = str(k).get_slice("#", 0)
		if base.contains(" ") or base != base.to_upper():
			bad_keys.append(k)
	_check(bad_keys.is_empty(), "keys are stable identifiers (UPPER_SNAKE, no spaces)", str(bad_keys.slice(0, 5)))


func _test_required_keys() -> void:
	var required := ["MENU_PLAY", "MENU_SETTINGS", "MENU_EXIT", "SCREEN_TEAM_SELECT", "SCREEN_PLAYER_PROFILE",
			"SCREEN_ACADEMY", "SCREEN_PROMOTION", "SCREEN_CAREER", "SCREEN_COMPETITIONS", "SCREEN_STANDINGS",
			"SCREEN_BRACKET", "SCREEN_TRAINING", "SCREEN_TRANSFERS", "SCREEN_FINANCE", "SCREEN_KIT_EDITOR",
			"SCREEN_MATCH_SETUP", "SCREEN_SETTINGS", "HUD_HALF_TIME", "HUD_FULL_TIME", "COMMON_OK", "COMMON_CANCEL",
			"COMMON_CONFIRM", "SETTINGS_LANGUAGE"]
	var missing: Array = []
	for code in LANGS:
		for k in required:
			if not Loc.has_key(k, code):
				missing.append("%s/%s" % [code, k])
	_check(missing.is_empty(), "required navigation/menu/HUD/dialog keys exist in all languages", str(missing))
	_check(Loc.tables["ar"]["MENU_PLAY"] == "العب" and Loc.tables["de"]["MENU_PLAY"] == "Spielen"
			and Loc.tables["en"]["MENU_PLAY"] == "Play", "MENU_PLAY = العب / Spielen / Play")
	_check(Loc.tables["ar"]["SCREEN_ACADEMY"] == "أكاديمية الشباب" and Loc.tables["de"]["SCREEN_ACADEMY"] == "Jugendakademie",
			"YOUTH ACADEMY = أكاديمية الشباب / Jugendakademie")


# --- switching / direction ----------------------------------------------------------------

func _test_switching_and_direction() -> void:
	_check(Loc.set_language("xx", false) != "", "unsupported language is rejected")
	var seen := {}
	var changed: Array[String] = []
	var cb := func(c: String) -> void: changed.append(c)
	Loc.language_changed.connect(cb)
	for code in LANGS:
		_check(Loc.set_language(code, false) == "", "switch to %s" % code)
		seen[code] = Loc.t("MENU_PLAY")
		_check(Loc.language == code and TranslationServer.get_locale().begins_with(code), "%s becomes the active locale" % code)
		var rtl: bool = get_tree().root.is_layout_rtl()
		_check(rtl == (code == "ar"), "root layout direction is %s for %s" % ["RTL" if code == "ar" else "LTR", code])
	Loc.language_changed.disconnect(cb)
	_check(changed == ["ar", "de", "en"], "language_changed fires once per switch", str(changed))
	_check(seen["ar"] != seen["de"] and seen["de"] != seen["en"], "each language shows different text", str(seen))
	# Godot's own auto-translation of controls whose text is a key.
	var l := Label.new()
	l.text = "MENU_EXIT"
	add_child(l)
	Loc.set_language("de", false)
	_check(l.tr("MENU_EXIT") == "Beenden", "scene labels whose text is a key translate through the TranslationServer", l.tr("MENU_EXIT"))
	l.queue_free()
	Loc.missing.clear()
	_check(Loc.t("DOES_NOT_EXIST") == "DOES_NOT_EXIST" and Loc.missing.has("DOES_NOT_EXIST"), "missing key shows the key and is recorded")


func _test_persistence() -> void:
	DirAccess.remove_absolute(TEST_SETTINGS)
	_check(not Loc.has_saved_language(), "no saved language before the first choice (initial setup shown)")
	Loc.set_language("ar", true)
	_check(Loc.saved_language() == "ar", "choosing Arabic is saved to the settings file")
	# "Restart": a brand-new manager reading the same file finds the saved language.
	var fresh := Localization.new()
	fresh.settings_path = TEST_SETTINGS
	_check(fresh.saved_language() == "ar" and fresh.has_saved_language(), "a fresh start finds the saved language")
	Loc.set_language("de", true)
	var fresh2 := Localization.new()
	fresh2.settings_path = TEST_SETTINGS
	_check(fresh2.saved_language() == "de", "changing the language later overwrites the saved value")
	fresh.free()
	fresh2.free()
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	cfg.set_value("audio", "volume", 7)
	cfg.save(TEST_SETTINGS)
	Loc.set_language("en", true)
	cfg.load(TEST_SETTINGS)
	_check(int(cfg.get_value("audio", "volume", 0)) == 7 and cfg.get_value("game", "language", "") == "en", "saving the language keeps other settings")
	Loc.forget_saved_language()
	_check(not Loc.has_saved_language(), "saved language can be cleared")


# --- text quality ------------------------------------------------------------------------------

func _has_arabic(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x0600 and c <= 0x06FF:
			return true
	return false


func _test_text_quality() -> void:
	var de_blob := ""
	for k in Loc.tables["de"]:
		de_blob += str(Loc.tables["de"][k])
	for ch in ["ä", "ö", "ü", "ß"]:
		_check(de_blob.contains(ch), "German table contains and preserves '%s'" % ch)
	_check(Loc.tables["de"]["COMMON_CLOSE"] == "Schließen" and Loc.tables["de"]["MARKET_AVAILABLE_PLAYERS"] == "Verfügbare Spieler",
			"German special characters round-trip exactly (ß, ü)")
	var arabic_bad: Array = []
	var arabic_total := 0
	for k in Loc.tables["ar"]:
		var text := str(Loc.tables["ar"][k])
		if text == "" or k.begins_with("MENU_TITLE"):
			continue
		arabic_total += 1
		var en_text := str(Loc.tables["en"].get(k, ""))
		if not _has_arabic(text) and en_text.length() > 3 and not k.begins_with("MENU_VERSION"):
			arabic_bad.append(k)
	_check(arabic_bad.is_empty(), "every Arabic string actually contains Arabic text (%d checked)" % arabic_total, str(arabic_bad.slice(0, 5)))
	var same := []
	for k in Loc.tables["en"]:
		if k.contains("#"):
			continue
		var en_text := str(Loc.tables["en"][k])
		if en_text.length() >= 12 and en_text == str(Loc.tables["de"].get(k, "")) and not en_text.contains("KING"):
			same.append(k)
	_check(same.is_empty(), "no long German string is just the English text", str(same.slice(0, 5)))
	var bad_chars := []
	for code in LANGS:
		for k in Loc.tables[code]:
			var text := str(Loc.tables[code][k])
			if text.contains("�") or text.contains("Ã") or text.contains("Ø"):
				bad_chars.append("%s/%s" % [code, k])
	_check(bad_chars.is_empty(), "no mojibake / replacement characters in any table", str(bad_chars.slice(0, 5)))


# --- formatting --------------------------------------------------------------------------------

func _test_formatting() -> void:
	Loc.set_language("en", false)
	_check(Loc.num(1234567) == "1,234,567" and Loc.num(-1500) == "-1,500" and Loc.num(12) == "12", "en number format")
	_check(Loc.money(1500000) == "€1,500,000", "en currency format", Loc.money(1500000))
	_check(Loc.decimal(3.5, 1) == "3.5", "en decimal format", Loc.decimal(3.5, 1))
	Loc.set_language("de", false)
	_check(Loc.num(1234567) == "1.234.567" and Loc.money(1500000) == "1.500.000 €", "de number/currency format", Loc.money(1500000))
	_check(Loc.decimal(3.5, 1) == "3,5", "de decimal comma", Loc.decimal(3.5, 1))
	_check(Loc.date(1794441600) == "12.11.2026", "de date format", Loc.date(1794441600))
	Loc.set_language("ar", false)
	_check(Loc.num(1234567) == "1٬234٬567" and Loc.money(1500000).contains("€"), "ar number/currency format", Loc.num(1234567))
	_check(Loc.percent(0.5) == "50%", "percent")
	Loc.set_language("de", false)
	_check(Loc.f("SCOUT_ACADEMY_BUDGET", 4100000) == "Akademiebudget: 4.100.000" and Loc.f("SCOUT_ACADEMY_BUDGET", 900) == "Akademiebudget: 900" and Loc.f("SCOUT_ACADEMY_BUDGET", 8335) == "Akademiebudget: 8.335",
			"large whole numbers in dynamic text get locale separators", Loc.f("SCOUT_ACADEMY_BUDGET", 4100000))
	Loc.set_language("en", false)
	_check(Loc.f("SCOUT_ACADEMY_BUDGET", 4100000) == "Academy budget: 4,100,000", "en grouping in dynamic text")
	Loc.set_language("ar", false)
	for code in LANGS:
		Loc.set_language(code, false)
		var s := Loc.f("CAREER_SEASON_WEEK_OF", [3, 12, 46])
		_check(not s.contains("%") and s.contains("12") and s.contains("46"), "[%s] positional placeholders are filled" % code, s)
		var n := Loc.f("MARKET_SIGNED_FOR", ["Müller", 5000000])
		_check(n.contains("Müller") and not n.contains("%"), "[%s] player names (incl. umlauts) are inserted" % code, n)
		_check(not Loc.f("HUB_UNKNOWN_SCREEN", "x").contains("%"), "[%s] single-argument placeholder" % code)
	Loc.set_language("ar", false)
	_check(Loc.iso("FC Köln").begins_with("\u2068") and Loc.iso("FC Köln").ends_with("\u2069"), "Arabic mode isolates Latin names with bidi marks")
	Loc.set_language("en", false)
	_check(Loc.iso("FC Köln") == "FC Köln", "no bidi marks in LTR languages")
	_check("Hello {name}, {n} goals".format({"name": "Ali", "n": 3}) == "Hello Ali, 3 goals", "named placeholder formatting works")


func _test_plurals() -> void:
	_check(Localization.plural_category("ar", 0) == "zero" and Localization.plural_category("ar", 1) == "one"
			and Localization.plural_category("ar", 2) == "two" and Localization.plural_category("ar", 7) == "few"
			and Localization.plural_category("ar", 15) == "many" and Localization.plural_category("ar", 100) == "other",
			"Arabic plural categories (zero/one/two/few/many/other)")
	_check(Localization.plural_category("en", 1) == "one" and Localization.plural_category("en", 2) == "other"
			and Localization.plural_category("de", 1) == "one" and Localization.plural_category("de", 0) == "other", "en/de plural categories")
	Loc.set_language("en", false)
	_check(Loc.tn("CAREER_CONTRACTS_EXPIRE", 1) == "1 contract expires this season" and Loc.tn("CAREER_CONTRACTS_EXPIRE", 4) == "4 contracts expire this season", "en plurals", Loc.tn("CAREER_CONTRACTS_EXPIRE", 4))
	Loc.set_language("de", false)
	_check(Loc.tn("CAREER_CONTRACTS_EXPIRE", 1).begins_with("1 Vertrag ") and Loc.tn("CAREER_CONTRACTS_EXPIRE", 3).contains("Verträge"), "de plurals", Loc.tn("CAREER_CONTRACTS_EXPIRE", 3))
	Loc.set_language("ar", false)
	var distinct := {}
	var forms := {}
	for n in [0, 1, 2, 5, 12, 100]:
		forms[n] = Loc.tn("CAREER_CONTRACTS_EXPIRE", n)
		distinct[forms[n]] = true
	_check(distinct.size() == 6, "Arabic uses six distinct grammatical forms", str(forms))
	Loc.set_language("en", false)


func _test_enum_coverage() -> void:
	var groups := {
		"MENTALITY": TacticsPreset.Mentality.keys(), "BUILDUP": TacticsPreset.BuildUp.keys(),
		"PASSING": TacticsPreset.PassingStyle.keys(), "FOOT": PlayerData.Foot.keys(),
		"STATUS": PlayerData.Status.keys(), "COMP_TYPE": Competition.Type.keys(),
		"DIFFICULTY": MatchSetup.DIFFICULTIES, "SIDE": MatchSetup.SIDES,
		"CAT": TrainingSystem.CATEGORIES.keys(), "ATTR": PlayerData.ATTRIBUTES, "KITCOLOR": KitEditor.COLOR_FIELDS,
		"SETPIECE": ["penalty", "free_kick", "corner"], "LOGO": LogoService.TEMPLATES,
		"TRAIT": AcademyConfig.TRAITS, "KITSLOT": KitEditor.SLOTS, "PATTERN": KitEditor.PATTERNS,
	}
	var missing: Array = []
	for g in groups:
		for v in groups[g]:
			var key := "ENUM_%s_%s" % [g, str(v).to_upper().replace(" ", "_")]
			for code in LANGS:
				if not Loc.has_key(key, code):
					missing.append("%s/%s" % [code, key])
	_check(missing.is_empty(), "every enum / data value shown in the UI has a translation in all languages", str(missing.slice(0, 6)))


# --- no hardcoded UI strings --------------------------------------------------------------------------

func _test_no_hardcoded_ui_strings() -> void:
	var re := RegEx.new()
	re.compile("(UIKit\\.(label|title|muted|button|empty_state)\\(|\\bsay\\(|\\bheader\\()\\s*\"[^\"]*[A-Za-z]{3}")
	var hits: Array = []
	var files := 0
	for dir in ["res://scripts/ui", "res://scripts/ui/screens", "res://scripts/ui/hub", "res://scripts/ui/kit"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".gd") or f in LITERAL_ALLOWLIST:
				continue
			files += 1
			var src := FileAccess.get_file_as_string("%s/%s" % [dir, f])
			var ln := 0
			for line in src.split("\n"):
				ln += 1
				if re.search(line) != null and not line.strip_edges().begins_with("#"):
					hits.append("%s:%d" % [f, ln])
	_check(files >= 20 and hits.is_empty(), "no hardcoded UI string literals in %d UI scripts" % files, str(hits.slice(0, 8)))
	var raw_scene_text := false
	var menu_scene := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.tscn")
	for lit in ["Start Match", "Quit Game", "coming soon", "Phase 1"]:
		if menu_scene.contains(lit):
			raw_scene_text = true
	_check(not raw_scene_text, "main menu scene contains only translation keys")


# --- main menu ----------------------------------------------------------------------------------------

func _test_main_menu() -> void:
	DirAccess.remove_absolute(TEST_SETTINGS)
	Loc.set_language("en", false)
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu.get_node_or_null("FirstRunLanguage") != null, "first launch shows the language choice (initial setup)")
	var overlay := menu.get_node("FirstRunLanguage")
	(overlay.find_child("Lang_de", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Loc.language == "de" and Loc.saved_language() == "de", "choosing a language in the initial setup applies and saves it")
	_check(menu.get_node_or_null("FirstRunLanguage") == null, "the initial setup closes after the choice")
	var play: Button = menu.get_node("%PlayButton")
	var settings: Button = menu.get_node("%SettingsButton")
	var quit: Button = menu.get_node("%QuitButton")
	_check(play.text == "Spielen" and settings.text == "Einstellungen" and quit.text == "Beenden", "main menu is German", "%s/%s/%s" % [play.text, settings.text, quit.text])
	settings.pressed.emit()
	await get_tree().process_frame
	var panel := menu.get_node_or_null("SettingsPanel")
	_check(panel != null, "Settings opens the settings panel")
	(panel.find_child("Lang_ar", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(play.text == "العب" and settings.text == "الإعدادات" and quit.text == "خروج", "switching in Settings updates the menu immediately (no restart)", "%s/%s/%s" % [play.text, settings.text, quit.text])
	_check(menu.is_layout_rtl(), "main menu layout is RTL in Arabic")
	(panel.find_child("Lang_en", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(play.text == "Play" and not menu.is_layout_rtl(), "back to English: text and LTR layout restored")
	_check(Loc.saved_language() == "en", "the last choice is the saved one")
	menu.queue_free()
	await get_tree().process_frame


# --- every screen in every language ----------------------------------------------------------------------

func _collect_texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_texts(c, out)


func _raw_key_shown(text: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$")
	return re.search(text.strip_edges()) != null


func _test_every_screen_in_every_language() -> void:
	app.db.reload()
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career("club_royal_harbor")
	app.academy().budget = 500000
	var en_texts := {}
	for k in Loc.tables["en"]:
		var t: String = Loc.tables["en"][k]
		if t.length() >= 8 and not t.contains("%") and not t.contains("{"):
			en_texts[t] = k
	# Internal ids must never be shown as text outside English (home, solid, ...).
	var raw_ids: Array = []
	for lst in [KitEditor.SLOTS, KitEditor.PATTERNS, LogoService.TEMPLATES, MatchSetup.DIFFICULTIES, MatchSetup.SIDES]:
		raw_ids.append_array(lst)
	var screens_done := {}
	for code in LANGS:
		Loc.set_language(code, false)
		if hub != null:
			hub.queue_free()
			await get_tree().process_frame
		hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
		add_child(hub)
		await get_tree().process_frame
		var raw: Array = []
		var english: Array = []
		var count := 0
		for id in ScreenRegistry.SCREENS:
			var params := {}
			if id == "player_profile":
				params = {"player_id": app.db.get_team("club_royal_harbor").squad_ids[0]}
			if id == "kit_editor" or id == "team_details":
				params = {"team_id": "club_royal_harbor"}
			hub.navigate(id, params)
			await get_tree().process_frame
			var texts: Array = []
			_collect_texts(hub, texts)
			count += 1
			for t in texts:
				var s := str(t)
				if _raw_key_shown(s):
					raw.append("%s:%s" % [id, s])
				if code != "en" and s in raw_ids:
					raw.append("%s:raw id '%s'" % [id, s])
				if code != "en" and en_texts.has(s):
					var key: String = en_texts[s]
					if str(Loc.tables[code].get(key, "")) != s:
						english.append("%s:%s" % [id, s])
			screens_done[id] = true
		_check(raw.is_empty(), "[%s] no raw translation key is displayed on any of %d screens" % [code, count], str(raw.slice(0, 5)))
		_check(english.is_empty(), "[%s] no untranslated English UI text on any screen" % code, str(english.slice(0, 5)))
	_check(screens_done.size() == ScreenRegistry.SCREENS.size(), "all %d hub screens were rendered in ar, de and en" % screens_done.size())
	Loc.set_language("en", false)
	hub.navigate("academy")
	await get_tree().process_frame
	var before: Array = []
	_collect_texts(hub, before)
	Loc.set_language("de", false)
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Array = []
	_collect_texts(hub, after)
	_check(hub.current_id == "academy" and before != after and after.has("Jugendakademie"), "switching language on an open screen re-renders it in place",
			"id=%s" % hub.current_id)
	Loc.set_language("en", false)


func _test_rtl_layout() -> void:
	var xs := {}
	for code in ["en", "ar", "de"]:
		Loc.set_language(code, false)
		if hub != null:
			hub.queue_free()
			await get_tree().process_frame
		hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
		hub.size = Vector2(1280, 720)
		add_child(hub)
		await get_tree().process_frame
		await get_tree().process_frame
		var nav := hub.find_child("Nav_career", true, false) as Control
		var content := hub.current as Control
		if nav != null and content != null:
			xs[code] = [nav.global_position.x, content.global_position.x]
	_check(xs.has("en") and xs["en"][0] < xs["en"][1], "LTR: navigation is left of the content", str(xs.get("en")))
	_check(xs.has("de") and xs["de"][0] < xs["de"][1], "German LTR: navigation is left of the content", str(xs.get("de")))
	_check(xs.has("ar") and xs["ar"][0] > xs["ar"][1], "RTL: navigation moves to the right of the content", str(xs.get("ar")))
	Loc.set_language("ar", false)
	var picker := LanguagePicker.new()
	add_child(picker)
	await get_tree().process_frame
	_check(not picker.is_layout_rtl(), "language picker keeps the same button order in RTL")
	picker.queue_free()
	hub.navigate("tactics")
	await get_tree().process_frame
	var pitch := hub.current.find_child("PitchPreview", true, false) as Control
	_check(pitch is PitchDiagram and not pitch.is_layout_rtl() and (pitch as PitchDiagram).points.size() == 11,
			"tactics pitch diagram keeps its orientation and all 11 markers in Arabic", "pitch=%s" % [str(pitch)])
	Loc.set_language("en", false)
