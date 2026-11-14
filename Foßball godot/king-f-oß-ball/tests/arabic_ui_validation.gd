## Arabic UI validation — every hub screen rendered in Arabic must show:
##  * no untranslated Latin text in a Label / Button (proper names of clubs, players, countries
##    and the allowed abbreviations / key legends excepted),
##  * no Eastern-Arabic digits in any SpinBox / LineEdit / Label (the game uses Western digits),
##  * numbers, formations, ratios and signed deltas isolated LTR (bidi-safe),
##  * match key hints as separate key/action chips.
##   godot --headless --path . res://tests/arabic_ui_validation.tscn
extends Node

## Latin tokens allowed in Arabic UI: position codes, key legends, brand / file-format words.
const ALLOWED_TOKENS: Array[String] = ["KING", "CONTROLLER", "FOOTBALL", "QR", "Wi", "Fi", "WASD", "Shift", "Tab",
		"Esc", "E", "Q", "C", "R", "T", "V", "PNG", "JPG", "WebP", "MB", "OVR", "POT", "FC", "AI", "Deutsch", "English"]   # language names are shown in their own language

var _passed := 0
var _failed := 0
var app: Node
var hub: HubRoot
var _names: Array[String] = []


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Arabic UI validation ===")
	app = get_node("/root/AppHub")
	var original_path: String = Loc.settings_path
	Loc.settings_path = "user://test_arabic_ui_settings.cfg"
	_test_number_isolation()
	_test_ltr_helpers()
	_test_visual_order()
	await _test_control_hints()
	await _test_screens()
	Loc.set_language("en", false)
	Loc.settings_path = original_path
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_number_isolation() -> void:
	Loc.set_language("ar", false)
	var n := Loc.num(4100000)
	_check(n == Loc.LRI + "4,100,000" + Loc.PDI, "ar: Loc.num(4100000) is an LTR isolate with Western separators", n)
	_check(not n.contains("٬") and not Loc.decimal(3.5, 1).contains("٫"), "ar: no Arabic separators (bidi class AN reorders digit groups)")
	_check(Loc.money(82000000) == Loc.LRI + "82,000,000 €" + Loc.PDI, "ar: money is one LTR isolate", Loc.money(82000000))
	_check(Loc.percent(0.306) == Loc.LRI + "31%" + Loc.PDI, "ar: percent keeps the sign after the number", Loc.percent(0.306))
	_check(Loc.decimal(30.6, 1) == Loc.LRI + "30.6" + Loc.PDI, "ar: decimal isolated", Loc.decimal(30.6, 1))
	var budget := Loc.f("SCOUT_ACADEMY_BUDGET", 4100000)
	_check(budget.contains(Loc.LRI + "4,100,000" + Loc.PDI) or budget.contains(Loc.LRI + Loc.LRI + "4,100,000" + Loc.PDI),
			"ar: big numbers inside Arabic sentences are isolated", budget)
	_check(Loc.isolate_numeric_placeholders("x %d/%d y") == "x " + Loc.LRI + "%d/%d" + Loc.PDI + " y", "ar: ratio placeholders form one isolate")
	_check(Loc.isolate_numeric_placeholders("%+d") == Loc.LRI + "%+d" + Loc.PDI, "ar: signed placeholder isolated")
	_check(Loc.isolate_numeric_placeholders("%%%.1f") == Loc.LRI + "%%%.1f" + Loc.PDI, "ar: percent sign stays with its number")
	_check(Loc.match_clock(12.5).begins_with(Loc.LRI), "ar: match clock isolated")
	Loc.set_language("en", false)
	_check(Loc.num(4100000) == "4,100,000" and Loc.money(1500) == "€1,500", "en: no isolates")
	_check(Loc.isolate_numeric_placeholders("%d/%d") == "%d/%d", "en: format strings untouched")
	Loc.set_language("de", false)
	_check(Loc.num(4100000) == "4.100.000" and Loc.decimal(3.5, 1) == "3,5", "de: separators unchanged")
	Loc.set_language("en", false)


func _test_ltr_helpers() -> void:
	Loc.set_language("ar", false)
	var bad: Array = []
	for id in FormationData.ids():
		var shown := Loc.ltr(id)
		if not shown.begins_with(Loc.LRI) or not shown.ends_with(Loc.PDI):
			bad.append(id)
	_check(bad.is_empty() and FormationData.ids().size() > 0, "ar: every formation name (%d) is shown as an LTR isolate" % FormationData.ids().size(), str(bad))
	_check(Loc.signed(0) == Loc.LRI + "+0" + Loc.PDI and Loc.signed(-2) == Loc.LRI + "-2" + Loc.PDI, "ar: signed deltas keep the sign in front")
	_check(Loc.ratio(91, 97) == Loc.LRI + "91/97" + Loc.PDI, "ar: ratios isolated")
	_check(Loc.position_code(PlayerData.Position.GK) == Loc.LRI + "GK" + Loc.PDI, "ar: position codes isolated")
	_check(Loc.score(2, 1) == Loc.LRI + "1 - 2" + Loc.PDI, "ar: score puts the home goals on the right (next to the home name)")
	Loc.set_language("en", false)
	_check(Loc.ltr("4-3-3") == "4-3-3" and Loc.score(2, 1) == "2 - 1" and Loc.signed(3) == "+3", "en: helpers are no-ops")


## Characters of `text` that are in `keep`, in VISUAL left-to-right order, as the text server lays
## them out in a right-to-left paragraph (glyphs are returned in visual order).
func _visual(text: String, keep: String) -> String:
	var tl := TextLine.new()
	tl.direction = TextServer.DIRECTION_RTL
	tl.add_string(text, get_tree().root.theme.default_font if get_tree().root.theme != null else ThemeDB.fallback_font, 16)
	var out := ""
	var last := -1
	for g in TextServerManager.get_primary_interface().shaped_text_get_glyphs(tl.get_rid()):
		var i := int(g["start"])
		if i == last:
			continue
		last = i
		var ch := text.substr(i, 1)
		if keep.contains(ch):
			out += ch
	return out


func _test_visual_order() -> void:
	Loc.set_language("ar", false)
	var digits := "0123456789,.+-/%€"
	var bal := Loc.f("SCOUT_ACADEMY_BUDGET", 82000000)
	_check(_visual(bal, digits) == "82,000,000", "ar (rendered): 82,000,000 keeps its digit-group order in a sentence", _visual(bal, digits))
	_check(_visual("الرصيد " + Loc.money(4100000) + " · الميزانية", digits) == "4,100,000€", "ar (rendered): money keeps its order")
	_check(_visual(Loc.signed(0), digits) == "+0", "ar (rendered): '+0' table cell shows the sign first", _visual(Loc.signed(0), digits))
	_check(_visual("الزيادة " + Loc.signed(3) + " هذا الأسبوع", digits) == "+3", "ar (rendered): signed delta inside a sentence")
	_check(_visual("القدرات " + Loc.ratio(91, 97), digits) == "91/97", "ar (rendered): ratio 91/97 not 97/91")
	_check(_visual(Loc.decimal(30.6, 1) + "٪ استحواذ", digits) == "30.6", "ar (rendered): decimal 30.6")
	_check(_visual("الاستحواذ " + Loc.percent(0.306), digits) == "31%", "ar (rendered): percent sign after the number")
	var bad: Array = []
	for id in FormationData.ids():
		var shown := _visual(Loc.f("SQUAD_FORMATION_CHANGE_IT_IN_TACTICAL_FO", Loc.ltr(id)), "0123456789-")
		if shown != id:
			bad.append("%s->%s" % [id, shown])
	_check(bad.is_empty(), "ar (rendered): every formation keeps its order in a sentence (4-3-3 not 3-3-4)", str(bad))
	# "2,070/أسبوع" (wage per week) is read right-to-left: number, slash, week -> visually "/2,070".
	var wage := Loc.f("SCOUT_SCOUT_OPTION", ["x", 50.0, 2070])
	_check(_visual(wage, "0123456789,/").begins_with("/2,070"), "ar (rendered): wage per week keeps its digit groups together", _visual(wage, "0123456789,/"))
	Loc.set_language("en", false)


func _test_control_hints() -> void:
	Loc.set_language("ar", false)
	var hints := ControlHints.new()
	add_child(hints)
	await get_tree().process_frame
	var chips := hints.get_children()
	_check(chips.size() == ControlHints.PAIRS.size(), "ar: one hint chip per key/action pair", "%d chips" % chips.size())
	var ok := true
	var sprint_ok := false
	for chip in chips:
		var key := chip.find_child("KeyLabel", true, false) as Label
		var action := chip.find_child("ActionLabel", true, false) as Label
		if key == null or action == null or not key.text.begins_with(Loc.LRI) or _latin_rest(action.text) != "":
			ok = false
		if chip.name == "Hint_HINT_SPRINT" and key.text.contains("Shift") and action.text == "ركض":
			sprint_ok = true
	_check(ok, "ar: each chip = isolated key cap + Arabic action")
	_check(sprint_ok, "ar: Shift is paired with 'ركض' (sprint), never with another action")
	hints.show_for(0.1)
	for i in 30:
		await get_tree().process_frame
	_check(not hints.visible or hints.modulate.a < 1.0, "hints hide themselves after their display time")
	hints.queue_free()
	Loc.set_language("en", false)


# --- every screen ------------------------------------------------------------------------------

func _collect(node: Node, out: Array) -> void:
	if node is Label:
		out.append([node, (node as Label).text])
	elif node is Button:
		out.append([node, (node as Button).text])
	for c in node.get_children(true):
		_collect(c, out)


func _collect_numeric(node: Node, out: Array) -> void:
	if node is SpinBox:
		out.append(node)
		out.append((node as SpinBox).get_line_edit())
	elif node is LineEdit or node is Label:
		out.append(node)
	for c in node.get_children(true):
		_collect_numeric(c, out)


func _build_names() -> void:
	_names.clear()
	for t: TeamData in app.db.teams.values():
		_names.append(t.display_name)
		_names.append(t.short_name)
		_names.append(t.country)
	for p: PlayerData in app.db.players.values():
		_names.append(p.display_name)
		_names.append(p.nationality)
	for r in YouthGenerator.NAME_POOLS:
		for part in ["first", "last"]:
			for n in YouthGenerator.NAME_POOLS[r][part]:
				_names.append(str(n))
	_names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


## Latin text left after removing proper names and allowed tokens ("" = fine).
func _latin_rest(text: String) -> String:
	var s := text
	for n in _names:
		if n.length() >= 2 and s.contains(n):
			s = s.replace(n, " ")
	var re := RegEx.new()
	re.compile("[A-Za-zÀ-ÖØ-öø-ÿ]+")      # Latin letters (× and ÷ excluded)
	var rest: Array = []
	for m in re.search_all(s):
		var w := m.get_string()
		if w in ALLOWED_TOKENS or w in PlayerData.Position.keys():
			continue
		rest.append(w)
	return " ".join(rest)


func _test_screens() -> void:
	app.db.reload()
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career("club_royal_harbor")
	app.academy().budget = 4100000
	_build_names()
	Loc.set_language("ar", false)
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var latin: Array = []
	var digits: Array = []
	var localized: Array = []
	var screens := 0
	for id in ScreenRegistry.SCREENS:
		var params := {}
		if id == "player_profile":
			params = {"player_id": app.db.get_team("club_royal_harbor").squad_ids[0]}
		if id == "kit_editor" or id == "team_details":
			params = {"team_id": "club_royal_harbor"}
		var pyr: LeaguePyramid = app.career.pyramids.get(CareerState.DEFAULT_LEAGUE_KEY)
		if id == "standings" and pyr != null:
			params = {"competition_id": pyr.comp["fic_league"]}
		if id == "bracket" and pyr != null:
			params = {"competition_id": pyr.comp["cup"]}
		hub.navigate(id, params)
		await get_tree().process_frame
		await get_tree().process_frame
		screens += 1
		var texts: Array = []
		_collect(hub, texts)
		for pair in texts:
			var rest := _latin_rest(str(pair[1]))
			if rest != "" and id != "database":     # developer tool: shows internal ids by design (dev mode only)
				latin.append("%s: '%s' in '%s'" % [id, rest, str(pair[1]).left(60)])
		var nums: Array = []
		_collect_numeric(hub, nums)
		for c in nums:
			if not (c as Control).is_visible_in_tree():
				if c.localize_numeral_system:
					localized.append("%s: %s" % [id, c.name])
				continue            # hidden controls re-format their text when first drawn
			var txt: String = (c as SpinBox).get_line_edit().text if c is SpinBox else str(c.text)
			for ch in txt:
				var code := ch.unicode_at(0)
				if (code >= 0x0660 and code <= 0x0669) or (code >= 0x06F0 and code <= 0x06F9):
					digits.append("%s: %s" % [id, txt])
					break
			if c.localize_numeral_system:
				localized.append("%s: %s" % [id, c.name])
	_check(screens == ScreenRegistry.SCREENS.size(), "all %d hub screens rendered in Arabic" % screens)
	_check(latin.is_empty(), "ar: no untranslated Latin text on any screen (names / abbreviations excepted)",
			"%d hits, first: %s" % [latin.size(), str(latin.slice(0, 8))])
	_check(digits.is_empty(), "ar: no Eastern-Arabic digits in any SpinBox / LineEdit / Label", str(digits.slice(0, 5)))
	_check(localized.is_empty(), "ar: numeral localisation is off on every text control", str(localized.slice(0, 5)))
	# Formation names in the tactics dropdown.
	hub.navigate("tactics")
	await get_tree().process_frame
	var fo := hub.current.find_child("FormationOption", true, false) as OptionButton
	var all_ltr := fo != null and fo.item_count > 0
	if fo != null:
		for i in fo.item_count:
			all_ltr = all_ltr and fo.get_item_text(i).begins_with(Loc.LRI)
	_check(all_ltr, "ar: tactics formation dropdown shows LTR-isolated names (4-3-3, not 3-3-4)")
	# Career balance and scouting budget show grouped Western digits in one isolate.
	hub.navigate("scouting")
	await get_tree().process_frame
	var found := false
	var texts2: Array = []
	_collect(hub.current, texts2)
	for pair in texts2:
		if str(pair[1]).contains("4,100,000" + Loc.PDI):
			found = true
	_check(found, "ar: academy budget 4,100,000 is shown grouped and isolated on the scouting screen")
	hub.queue_free()
	await get_tree().process_frame
	Loc.set_language("en", false)
