## Database phase 2 validation — unified club database, countries, club/league links:
##   godot --headless --path . res://tests/db_clubs_validation.tscn
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
	print("=== KING FOOTBALL — database phase 2 (clubs) validation ===")
	_test_countries()
	_test_team_fields()
	_test_default_world()
	_test_real_pack()
	_test_legacy_compat()
	_test_custom_club()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db() -> TeamDatabase:
	return load("res://scripts/core/team_database.gd").new()


func _test_countries() -> void:
	var db := _new_db()
	var n := db.load_countries()
	_check(n == 9 and db.errors.is_empty(), "9 countries load without errors", "%d %s" % [n, db.errors])
	for cid in ["eng", "esp", "ger", "ita", "fra"]:
		_check(db.countries.has(cid), "priority country %s exists" % cid)
	_check(db.country_id_for("England") == "eng" and db.country_id_for("Atlantis") == "", "country name -> id lookup")
	var codes := {}
	var dup_code := false
	for c: CountryData in db.countries.values():
		dup_code = dup_code or codes.has(c.country_code)
		codes[c.country_code] = true
	_check(not dup_code, "country codes are unique")
	var bad := CountryData.from_dict({"country_id": "", "country_name": "X", "country_code": "XX", "database_status": "??"})
	_check(bad.validate().size() == 3, "invalid country reports id, code and status", str(bad.validate()))
	db.load_countries()
	_check(db.errors.size() == 9, "loading countries twice reports every duplicate id", str(db.errors.size()))


func _test_team_fields() -> void:
	var t := TeamData.new()
	t.id = "x_club"
	t.display_name = "X"
	t.short_name = "X"
	t.country = "England"
	t.full_name = "X Football Club"
	t.city = "Xtown"
	t.founding_year = 1899
	t.club_type = TeamData.ClubType.CUSTOM
	t.rival_club_ids = PackedStringArray(["y_club"])
	t.transfer_budget = 5_000_000
	t.history = {"trophies": [{"name": "Cup", "year": 1999}]}
	t.kits = {"home": {}, "away": {}, "goalkeeper": {}}
	var back := TeamData.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	_check(back.to_dict() == t.to_dict(), "extended team JSON round-trip identical")
	_check(back.history["trophies"][0]["year"] == 1999 and typeof(back.history["trophies"][0]["year"]) == TYPE_INT, "history ints restored")
	_check(t.validate().is_empty(), "extended team is valid", str(t.validate()))
	t.founding_year = 1500
	t.rival_club_ids = PackedStringArray(["x_club"])
	t.transfer_budget = -1
	_check(t.validate().size() == 3, "bad founding year, self rival and negative money are reported", str(t.validate()))
	_check(TeamData.new().financial_status() == "UNKNOWN", "financial status unknown without data")
	t.current_balance = -5
	t.weekly_expenses = 1
	_check(t.financial_status() == "CRISIS", "negative balance is a crisis")


func _test_default_world() -> void:
	var db := _new_db()
	db.load_world("")
	_check(db.errors.is_empty(), "default world loads", str(db.errors))
	var problems := db.validate_relations()
	_check(problems.is_empty(), "default world relations are consistent", str(problems))
	var c := db.get_team("club_sunvale")
	_check(c.country_id == "ald" and c.club_type == TeamData.ClubType.FICTIONAL, "fictional club gets country id and FICTIONAL type")
	_check(c.crest_id == "crest_club_sunvale", "club gets a stable crest id")


func _test_real_pack() -> void:
	var db := _new_db()
	db.load_world("real_2025")
	_check(db.pack_id == "real_2025" and db.errors.is_empty(), "real pack loads", str(db.errors.slice(0, 3)))
	_check(db.teams.size() == 198, "198 clubs", str(db.teams.size()))
	var problems := db.validate_relations()
	_check(problems.is_empty(), "real pack: every club/league/country/squad link is consistent", "%d e.g. %s" % [problems.size(), problems.slice(0, 3)])
	var ars := db.get_team("eng_arsenal")
	_check(ars.country_id == "eng" and ars.league_id == "eng_d1" and ars.division == 1, "Arsenal: eng / eng_d1 / tier 1")
	_check(ars.club_type == TeamData.ClubType.REAL, "real club has REAL type")
	var ids := {}
	var all_linked := true
	for t: TeamData in db.teams.values():
		ids[t.id] = true
		all_linked = all_linked and t.league_id != "" and t.division >= 1
	_check(ids.size() == db.teams.size() and all_linked, "unique ids and every club has a league and division")
	# a broken link is detected
	ars.league_id = "esp_d1"
	ars.rival_club_ids = PackedStringArray(["nope"])
	var broken := db.validate_relations()
	_check(broken.size() == 2, "wrong league link and unknown rival are detected", str(broken))
	ars.league_id = "eng_d1"
	ars.rival_club_ids = PackedStringArray()
	db.players[ars.squad_ids[0]].team_id = "esp_real_madrid"
	_check(db.validate_relations().size() == 1, "player whose team_id differs from its squad is detected")


func _test_legacy_compat() -> void:
	# A team dictionary written before this system (no new keys) loads with safe defaults.
	var old := {"id": "old_fc", "name": "Old FC", "short_name": "OLD", "category": "CLUB", "real": true,
			"country": "Spain", "kits": {"home": {}, "away": {}, "goalkeeper": {}}, "reputation": 60}
	var t := TeamData.from_dict(old)
	_check(t.club_type == TeamData.ClubType.REAL and t.division == 0 and t.crest_id == "" and t.country_id == "", "old record gets defaults (REAL from the real flag)")
	var db := _new_db()
	db.load_countries()
	db.link_team(t)
	_check(t.country_id == "esp" and t.crest_id == "crest_old_fc", "link_team derives country and crest ids")
	t.crest_id = "custom_crest"
	db.link_team(t)
	_check(t.crest_id == "custom_crest", "link_team never overwrites existing values")
	# save/restore keeps the new fields and links old saves
	var db2 := _new_db()
	db2.load_world("")
	var snap := SaveManager.capture(db2)
	var db3 := _new_db()
	db3.load_countries()
	var res := SaveManager.restore(db3, snap)
	_check(res["ok"] and db3.get_team("club_sunvale").country_id == "ald", "restore keeps/derives country id", str(res.get("errors", [])))
	for td in snap["teams"]:
		td.erase("country_id")
		td.erase("crest_id")
	var db4 := _new_db()
	db4.load_countries()
	var res4 := SaveManager.restore(db4, snap)
	_check(res4["ok"] and db4.get_team("club_sunvale").country_id == "ald" and db4.get_team("club_sunvale").crest_id == "crest_club_sunvale", "an old save without the new keys is linked on restore")


func _test_custom_club() -> void:
	var db := _new_db()
	db.load_world("")
	var r := ClubCreator.create_club(db, {"name": "Test Rovers", "short_name": "TRV", "country": "Aldoria", "strength": 40}, false)
	_check(r["ok"], "custom club created", str(r))
	var t := db.get_team(r["team_id"])
	_check(t.club_type == TeamData.ClubType.CUSTOM and t.country_id == "ald", "custom club has CUSTOM type and a country id")
