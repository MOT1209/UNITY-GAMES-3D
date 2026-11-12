## Phase 7 localization audit: error-code layer, new screens in en/de/ar, hard-coded string scan.
##   godot --headless --path . res://tests/phase7_localization_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase 7 localization validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	_test_rules()
	_test_real_errors()
	_test_source_coverage()
	_test_hardcoded_scan()
	await _test_screens()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_rules() -> void:
	_check(ErrorTextRules.RULES.size() >= 60, "error rule table is populated", str(ErrorTextRules.RULES.size()))
	var missing := []
	for rule in ErrorTextRules.RULES:
		for code in ["en", "de", "ar"]:
			if not Loc.has_key(rule[1], code) or Loc.tables[code][rule[1]] == "":
				missing.append("%s/%s" % [rule[1], code])
	_check(missing.is_empty(), "every error key exists and is non-empty in en, de and ar", str(missing.slice(0, 5)))
	_check(Loc.validate().is_empty(), "the whole translation set still validates (parity, placeholders)", str(Loc.validate().slice(0, 3)))
	var bad_rx := 0
	for rule in ErrorTextRules.RULES:
		var re := RegEx.new()
		bad_rx += 0 if re.compile(rule[0]) == OK else 1
	_check(bad_rx == 0, "all error patterns compile")


## Errors that the game's own systems really produce.
func _real_errors() -> Array:
	var errs: Array = []
	var squad := Squad.new("club_royal_harbor")
	squad.auto_pick(db)
	errs.append(squad.assign_starter(db, 3, "ghost_player"))
	errs.append(squad.set_captain("ghost_player"))
	errs.append(squad.substitute(db, 99, "x"))
	errs.append(squad.add_to_bench(db, "ghost_player"))
	var market := TransferMarket.new(db, {})
	errs.append(market.buy("club_obsidian", "ghost_player", 0, 100, 2, 1))
	errs.append(market.buy("ghost_club", db.get_squad("club_royal_harbor")[0].id, 0, 100, 2, 1))
	var ac := Academy.new("club_royal_harbor", "Aldoria", 3)
	ac.generate_intake(db, 3)
	errs.append(PromotionSystem.promote(db, ac, "ghost_player"))
	errs.append(PromotionSystem.promote(db, ac, db.get_squad("club_royal_harbor")[0].id))
	errs.append(ac.keep_extended(db, "ghost_player"))
	var setup := MatchSetup.new()
	errs.append(setup.validate(db)[0])
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_royal_harbor"
	errs.append(setup.validate(db)[0])
	setup.away_id = "nowhere"
	errs.append(setup.validate(db)[0])
	errs.append(KitEditor.set_field(db.get_team("club_royal_harbor"), "nope", "main", "ffffff"))
	errs.append(KitEditor.set_field(db.get_team("club_royal_harbor"), "home", "main", "zzz"))
	errs.append(SaveManager.read_file("user://does_not_exist.json")["error"])
	errs.append(SaveManager.migrate({"save_version": 99})["error"])
	errs.append(MatchSave.migrate({"version": 99})["error"])
	errs.append(MatchSave.read(db, "user://nothing_here.json")["errors"][0])
	var ledger := FinanceLedger.new("t", 100)
	errs.append(ledger.record("salary", 0, "x", 1))
	errs.append(ledger.record("other", -1000, "x", 1))
	errs.append(Loc.set_language("xx", false))
	var comp := Competition.create_league("l", "L", ["a", "b"], false)
	errs.append(Competition.validate_setup(Competition.Type.LEAGUE, ["a"]))
	return errs.filter(func(e: Variant) -> bool: return str(e) != "")


func _test_real_errors() -> void:
	var errs := _real_errors()
	_check(errs.size() >= 20, "collected real error messages from the systems", str(errs.size()))
	var unmapped: Array = errs.filter(func(e: String) -> bool: return ErrorText.key_for(e) == "")
	_check(unmapped.is_empty(), "every real system error has a translation key", str(unmapped))
	for code in ["ar", "de"]:
		Loc.set_language(code, false)
		var same := errs.filter(func(e: String) -> bool: return ErrorText.localize(e, db) == e)
		_check(same.is_empty(), "[%s] real errors are shown translated" % code, str(same.slice(0, 3)))
	Loc.set_language("en", false)
	var p: PlayerData = db.get_squad("club_royal_harbor")[0]
	Loc.set_language("de", false)
	var txt := ErrorText.localize("player '%s' is not available" % p.id, db)
	_check(txt.contains(p.display_name) and not txt.contains(p.id), "ids inside messages become names", txt)
	Loc.set_language("en", false)
	_check(ErrorText.localize("squad is full (30)", db) == "The squad is full (30 players).", "numbers are substituted into the translation")
	_check(ErrorText.localize("something nobody mapped", db) == "something nobody mapped", "unknown messages pass through unchanged")


## Static scan: how many of the English error literals in the systems layer does the table cover?
func _test_source_coverage() -> void:
	var literals: Array = []
	for dir in ["res://scripts/systems", "res://scripts/core"]:
		_scan_dir(dir, literals)
	var re := RegEx.new()
	re.compile("return \"([^\"]*[a-z]+ [^\"]*)\"")
	var total := 0
	var covered := 0
	var missing := []
	for text in literals:
		# turn a format string into a sample message: %s -> x, %d -> 5
		var sample: String = text.replace("%s", "x").replace("%d", "5").replace("%02d", "5")
		if sample.begins_with("%") or sample.length() < 8:
			continue
		total += 1
		if ErrorText.key_for(sample) != "":
			covered += 1
		else:
			missing.append(text)
	print("[INFO] error-message literals in systems/core: %d, mapped: %d (%.0f%%); unmapped: %s" % [total, covered, 100.0 * covered / maxf(total, 1), str(missing)])
	_check(total > 40 and float(covered) / float(total) >= 0.8, "at least 80% of the English error literals in the systems layer are mapped", "%d / %d, e.g. %s" % [covered, total, str(missing.slice(0, 6))])


func _scan_dir(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var re := RegEx.new()
			re.compile("return \"([^\"]*[a-z]+ [^\"]*)\"")
			for line in FileAccess.get_file_as_string("%s/%s" % [path, f]).split("\n"):
				var m := re.search(line)
				if m != null:
					out.append(m.get_string(1))
	for sub in d.get_directories():
		_scan_dir("%s/%s" % [path, sub], out)


## Heuristic scan of UI scripts for user-visible English literals that bypass Loc.
func _test_hardcoded_scan() -> void:
	var re := RegEx.new()
	re.compile("(?:UIKit\\.(?:label|muted|title|button)\\(|\\.text = |say\\()\"([A-Z][a-z]+[^\"]*)\"")
	var found: Array = []
	var allowed := ["MatchResultsView", "%s"]
	for dir in ["res://scripts/ui", "res://ui"]:
		_scan_ui(dir, re, found)
	_check(found.is_empty(), "no hard-coded English labels/buttons/messages in the UI scripts", str(found.slice(0, 6)))


func _scan_ui(path: String, re: RegEx, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var n := 0
			for line in FileAccess.get_file_as_string("%s/%s" % [path, f]).split("\n"):
				n += 1
				var m := re.search(line)
				if m != null and not line.strip_edges().begins_with("#"):
					out.append("%s:%d %s" % [f, n, m.get_string(1)])
	for sub in d.get_directories():
		_scan_ui("%s/%s" % [path, sub], re, out)


func _test_screens() -> void:
	var app: Node = get_node("/root/AppHub")
	app.start_career("club_royal_harbor")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var ids := ["career", "squad", "academy", "collection", "standings", "settings", "match_setup", "finance", "competitions", "transfers"]
	for code in ["ar", "de", "en"]:
		Loc.set_language(code, false)
		var bad_screens := []
		for id in ids:
			hub.navigate(id)
			await get_tree().process_frame
			var leaked := hub.current.find_children("*", "Label", true, false).filter(func(l: Label) -> bool:
				return l.text.length() > 4 and l.text == l.text.to_upper() and l.text.contains("_") and not l.text.contains(" "))
			var key_like := hub.current.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
				return b.text.contains("_") and b.text == b.text.to_upper() and not b.text.contains(" "))
			if not leaked.is_empty() or not key_like.is_empty():
				bad_screens.append(id)
		_check(bad_screens.is_empty(), "[%s] no raw translation keys on %d screens" % [code, ids.size()], str(bad_screens))
		_check(Loc.is_rtl() == (code == "ar"), "[%s] text direction follows the language" % code)
	hub.queue_free()
	app.career = null
	app.user_team_id = ""
	await get_tree().process_frame
