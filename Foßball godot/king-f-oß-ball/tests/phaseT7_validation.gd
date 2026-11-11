## Phase T7 validation — club creation, kits, logos, import/export:
##   godot --headless --path . res://tests/phaseT7_validation.tscn
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase T7 validation ===")
	_test_slug()
	_test_create_club()
	_test_create_failures()
	_test_kits()
	_test_logos()
	_test_import_export_delete()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> Node:
	var db: Node = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _params() -> Dictionary:
	return {"name": "Test Rovers", "short_name": "tr", "country": "Aldoria",
			"primary": Color("e74c3c"), "secondary": Color("f1c40f"), "strength": 60, "seed": 3}


func _test_slug() -> void:
	_check(ClubCreator.slugify("Royal Harbor FC") == "royal_harbor_fc", "slugify spaces")
	_check(ClubCreator.slugify("  A--B!! ") == "a_b", "slugify punctuation")
	_check(ClubCreator.slugify("!!!") == "", "slugify empty")


func _test_create_club() -> void:
	var db := _db()
	var teams_before := db.teams.size()
	var r := ClubCreator.create_club(db, _params(), false)
	_check(r["ok"], "create fictional club", r["error"])
	var t: TeamData = db.get_team("club_test_rovers")
	_check(t != null and t.short_name == "TR" and not t.is_real, "club fields set (short name upper-cased, fictional)")
	_check(db.teams.size() == teams_before + 1, "one team added")
	_check(db.get_squad(t.id).size() == 23, "generated squad of 23")
	_check(t.validate().is_empty(), "created team validates")
	var all_ok := true
	var ids := {}
	for p in db.get_squad(t.id):
		if not p.validate().is_empty() or ids.has(p.id) or p.team_id != t.id:
			all_ok = false
		ids[p.id] = true
	_check(all_ok, "generated players valid, unique, owned by the club")
	_check(db.get_team_rating(t.id) > 30, "rating computed from squad")
	var weak := _params(); weak["name"] = "Weak FC"; weak["strength"] = 25
	var strong := _params(); strong["name"] = "Strong FC"; strong["strength"] = 90
	ClubCreator.create_club(db, weak, false)
	ClubCreator.create_club(db, strong, false)
	_check(db.get_team_rating("club_strong_fc") > db.get_team_rating("club_weak_fc") + 10, "strength setting drives team rating")
	_check(t.kits.has("home") and t.kits.has("away") and t.kits.has("third") and t.kits.has("goalkeeper"), "default kits created")
	_check(LogoService.is_template(t.logo_path), "default logo is an original template")
	var a := SquadGenerator.generate("x", "Zamoria", 60, 5)
	var b := SquadGenerator.generate("x", "Zamoria", 60, 5)
	var same := true
	for i in a.size():
		if a[i].to_dict() != b[i].to_dict():
			same = false
	_check(same, "squad generation is deterministic")
	var oob := _params(); oob["name"] = "Clamp FC"; oob["strength"] = 500
	ClubCreator.create_club(db, oob, false)
	_check(db.get_team("club_clamp_fc").reputation == ClubCreator.MAX_STRENGTH, "strength clamped to max")
	db.free()


func _test_create_failures() -> void:
	var db := _db()
	_check(ClubCreator.create_club(db, _params(), false)["ok"], "first creation ok")
	_check(not ClubCreator.create_club(db, _params(), false)["ok"], "duplicate club id rejected")
	var bad := _params(); bad["name"] = ""
	_check(not ClubCreator.create_club(db, bad, false)["ok"], "empty name rejected")
	bad = _params(); bad["name"] = "Long Short"; bad["short_name"] = "TOOLONG"
	_check(not ClubCreator.create_club(db, bad, false)["ok"], "invalid short name rejected")
	bad = _params(); bad["name"] = "No Country"; bad["country"] = ""
	_check(not ClubCreator.create_club(db, bad, false)["ok"], "missing country rejected")
	_check(db.get_team("club_no_country") == null and db.get_team("club_long_short") == null, "failed creations register nothing")
	var missing := _params(); missing["name"] = "Missing Logo"; missing["logo"] = "user://does/not/exist.png"
	var r := ClubCreator.create_club(db, missing, false)
	_check(r["ok"] and LogoService.is_template(db.get_team("club_missing_logo").logo_path), "missing logo asset falls back to template")
	db.free()


func _test_kits() -> void:
	var db := _db()
	ClubCreator.create_club(db, _params(), false)
	var t: TeamData = db.get_team("club_test_rovers")
	_check(KitEditor.set_field(t, "home", "main", "#112233") == "", "set kit color")
	_check(t.kits["home"]["main"] == "112233", "color normalised (no #, lower-case)")
	_check(KitEditor.set_field(t, "away", "pattern", "hoops") == "", "set kit pattern")
	_check(KitEditor.set_field(t, "home", "main", "red") != "", "invalid color rejected")
	_check(KitEditor.set_field(t, "home", "pattern", "polka") != "", "unknown pattern rejected")
	_check(KitEditor.set_field(t, "fourth", "main", "ffffff") != "", "unknown slot rejected")
	_check(KitEditor.set_field(t, "home", "gloves", "ffffff") != "", "unknown field rejected")
	for f in KitEditor.COLOR_FIELDS:
		_check(KitEditor.set_field(t, "third", f, "abcdef") == "", "set third kit %s" % f)
	_check(KitEditor.set_field(t, "goalkeeper", "shorts", "000000") == "", "set goalkeeper kit")
	for slot in KitEditor.SLOTS:
		_check(KitEditor.validate_kit(t.kits[slot]).is_empty(), "%s kit validates" % slot)
	_check(not KitEditor.validate_kit({"main": "zz"}).is_empty(), "broken kit fails validation")
	# Preview reflects the SAVED configuration.
	var restored := TeamData.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	var pv := KitEditor.preview(restored, "home")
	_check(pv["main"] == Color("112233"), "preview shows saved home main color")
	_check(KitEditor.preview(restored, "away")["pattern"] == "hoops", "preview shows saved pattern")
	_check(KitEditor.preview(restored, "nope").is_empty(), "preview of unknown slot is empty")
	var white := {"main": "ffffff"}
	var near_white := {"main": "fafafa"}
	var red := {"main": "ff0000"}
	_check(KitEditor.kits_clash(white, near_white), "similar kits clash")
	_check(not KitEditor.kits_clash(white, red), "distinct kits do not clash")
	t.kits["away"]["main"] = "112234"
	_check(KitEditor.pick_away_kit(t, t.kits["home"]) == "third", "clashing away kit falls back to third")
	_check(KitEditor.pick_away_kit(t, {"main": "ffffff"}) == "away", "non-clashing away kit chosen")
	db.free()


func _test_logos() -> void:
	for tid in LogoService.TEMPLATES:
		var img := LogoService.render_template(tid, Color.RED, Color.WHITE, 64)
		var opaque := 0
		for y in 64:
			for x in 64:
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		_check(img.get_width() == 64 and opaque > 300 and opaque < 64 * 64, "template '%s' renders a shape" % tid, str(opaque))
	_check(LogoService.is_template("template:shield") and not LogoService.is_template("template:evil"), "template reference check")
	var team := TeamData.new()
	team.primary_color = Color.BLUE
	team.secondary_color = Color.WHITE
	team.logo_path = "res://nope/missing.png"
	var fallback := LogoService.resolve(team, 64)
	_check(fallback != null and not fallback.is_empty(), "missing logo resolves to placeholder")
	# Import validation
	_check(LogoService.validate_import("user://nothing.png") != "", "missing file rejected")
	var dir := "user://test_logos"
	DirAccess.make_dir_recursive_absolute(dir)
	var good := LogoService.render_template("circle", Color.GREEN, Color.WHITE, 128)
	good.save_png(dir + "/good.png")
	_check(LogoService.validate_import(dir + "/good.png") == "", "valid png accepted")
	var tiny := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tiny.save_png(dir + "/tiny.png")
	_check(LogoService.validate_import(dir + "/tiny.png") != "", "too-small image rejected")
	var fake := FileAccess.open(dir + "/fake.png", FileAccess.WRITE)
	fake.store_string("not an image")
	fake.close()
	_check(LogoService.validate_import(dir + "/fake.png") != "", "non-image file rejected")
	var txt := FileAccess.open(dir + "/logo.txt", FileAccess.WRITE)
	txt.store_string("x")
	txt.close()
	_check(LogoService.validate_import(dir + "/logo.txt") != "", "wrong extension rejected")
	var t2 := TeamData.new()
	t2.id = "club_logo_test"
	var res := LogoService.import_logo(t2, dir + "/good.png")
	_check(res["ok"] and t2.logo_path == LogoService.LOGO_DIR + "/club_logo_test.png", "import stores logo for team", str(res))
	var stored := LogoService.resolve(t2, 128)
	_check(stored.get_width() == 128, "stored logo resolves")
	_check(not LogoService.import_logo(t2, dir + "/fake.png")["ok"], "invalid import reports failure")
	for f in ["good.png", "tiny.png", "fake.png", "logo.txt"]:
		DirAccess.remove_absolute("%s/%s" % [dir, f])
	DirAccess.remove_absolute(LogoService.LOGO_DIR + "/club_logo_test.png")


func _test_import_export_delete() -> void:
	var db := _db()
	var r := ClubCreator.create_club(db, _params(), true)
	_check(r["ok"], "create + persist club", r["error"])
	var file := "%s/%s.json" % [ClubCreator.USER_DIR, r["team_id"]]
	_check(FileAccess.file_exists(file), "club written to user://teams")
	# A fresh database picks the user club up automatically (no code change needed).
	var db2 := _db()
	_check(db2.get_team(r["team_id"]) != null, "TeamDB loads user-created club on start-up")
	_check(db2.get_squad(r["team_id"]).size() == 23, "persisted squad restored")
	_check(db2.get_team(r["team_id"]).to_dict() == db.get_team(r["team_id"]).to_dict(), "persisted team identical (kits, colors)")
	# Export / import
	var export_path := "user://test_export/exported.json"
	_check(ClubCreator.export_team(db, r["team_id"], export_path) == "", "export team")
	_check(ClubCreator.export_team(db, "ghost", export_path) != "", "export unknown team rejected")
	var db3 := _db()
	db3.remove_team(r["team_id"])
	_check(ClubCreator.import_team(db3, export_path)["ok"], "import exported team")
	_check(db3.get_squad(r["team_id"]).size() == 23, "imported squad complete")
	_check(not ClubCreator.import_team(db3, export_path)["ok"], "duplicate import rejected")
	_check(not ClubCreator.import_team(db3, "user://test_export/missing.json")["ok"], "missing import file rejected")
	var junk := FileAccess.open("user://test_export/junk.json", FileAccess.WRITE)
	junk.store_string("[1,2")
	junk.close()
	_check(not ClubCreator.import_team(db3, "user://test_export/junk.json")["ok"], "corrupt import rejected")
	# Deletion: only user clubs.
	_check(ClubCreator.delete_user_club(db, "club_royal_harbor") != "", "seed club cannot be deleted")
	_check(db.get_team("club_royal_harbor") != null, "seed club still present")
	_check(ClubCreator.delete_user_club(db, r["team_id"]) == "", "delete user club")
	_check(db.get_team(r["team_id"]) == null and not FileAccess.file_exists(file), "club and file removed")
	var leftover := false
	for pid in db.players:
		if pid.begins_with("plr_" + r["team_id"]):
			leftover = true
	_check(not leftover, "deleted club's players removed from database")
	for f in ["exported.json", "junk.json"]:
		DirAccess.remove_absolute("user://test_export/" + f)
	db.free()
	db2.free()
	db3.free()
