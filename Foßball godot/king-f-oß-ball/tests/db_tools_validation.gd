## Database phase 7 validation — management tools: statistics, validation (with planted errors),
## search, profiles, metadata editing, export/import, generation, the Database screen and the CLI:
##   godot --headless --path . res://tests/db_tools_validation.tscn
extends Node

const TMP := "user://test_db_tools"

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
	print("=== KING FOOTBALL — database phase 7 (tools) validation ===")
	DirAccess.make_dir_recursive_absolute(TMP)
	_test_stats_and_validate()
	_test_planted_errors()
	_test_search()
	_test_profiles()
	_test_metadata()
	_test_export_import()
	_test_generate()
	await _test_screen()
	_test_cli()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db(world: String) -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.load_world(world)
	return db


func _test_stats_and_validate() -> void:
	var db := _new_db("real_2025")
	var s := DatabaseTools.stats(db)
	_check(s["clubs"] == 298 and s["players"] == 8013 and s["crests"] == 306 and s["countries"] == 116 and s["leagues"] == 5 and s["divisions"] == 15,
			"statistics of the real world: 298 clubs, 8013 players, 306 crests, 116 countries, 5 leagues, 15 divisions", str(s))
	_check(s["clubs_by_type"]["REAL"] == 198 and s["clubs_by_type"]["FICTIONAL"] == 100, "clubs by type: 198 real, 100 fictional")
	_check(s["players_by_type"]["REAL"] == 2867 and s["players_by_type"].get("YOUTH", 0) == 0, "players by type: 2867 real")
	_check(s["clubs_by_division"].get("eng_d3", 0) == 20 and s["clubs_by_country"]["England"] == 64, "clubs by division/country (England 64, eng_d3 20)")
	var t0 := Time.get_ticks_msec()
	var r := DatabaseTools.validate_all(db)
	var ms := Time.get_ticks_msec() - t0
	print("[PERF] validate_all on 298 clubs / 8013 players: %d ms, %d warnings" % [ms, r["warnings"].size()])
	_check(r["critical"].is_empty(), "validation of the real world reports no critical errors", str(r["critical"].slice(0, 3)))
	_check(r["checked"]["players"] == 8013 and ms < 60000, "validation covers every player and is fast enough (%d ms)" % ms)
	_check(r["warnings"].any(func(w: String) -> bool: return "no verified source" in w), "unverified real-club data is reported as a warning, not hidden")


func _test_planted_errors() -> void:
	var db := _new_db("")
	_check(DatabaseTools.validate_all(db)["critical"].is_empty(), "the default world validates clean")
	var a: TeamData = db.get_team("club_sunvale")
	var b: TeamData = db.get_team("club_cedar_city")
	var stolen := b.squad_ids[2]
	a.squad_ids.append(stolen)
	var r := DatabaseTools.validate_all(db)
	_check(r["critical"].any(func(e: String) -> bool: return "squads" in e or "two squads" in e or "is in" in e), "a player listed in two squads is a critical error", str(r["critical"].slice(0, 2)))
	a.squad_ids.remove_at(a.squad_ids.size() - 1)
	var p: PlayerData = db.get_player(a.squad_ids[0])
	p.pace = 500
	_check(DatabaseTools.validate_all(db)["critical"].any(func(e: String) -> bool: return "pace" in e), "an out-of-range attribute is critical")
	p.pace = 60
	var q: PlayerData = db.get_player(a.squad_ids[1])
	q.team_id = "ghost_club"
	_check(DatabaseTools.validate_all(db)["critical"].any(func(e: String) -> bool: return "ghost_club" in e), "a player of an unknown club is critical (broken reference)")
	q.team_id = a.id
	a.rival_club_ids = PackedStringArray(["nowhere_fc"])
	_check(DatabaseTools.validate_all(db)["critical"].any(func(e: String) -> bool: return "rival" in e), "a rival that does not exist is critical")
	a.rival_club_ids = PackedStringArray()
	var bad_crest := CrestData.new()
	bad_crest.crest_id = "crest_missing_file"
	bad_crest.club_id = a.id
	bad_crest.asset_type = CrestData.AssetType.USER_CUSTOM
	bad_crest.license_status = "USER_SUPPLIED"
	bad_crest.created_at = "x"
	bad_crest.asset_path = TMP + "/no_such.png"
	db.crests.register(bad_crest)
	var cr := DatabaseTools.crest_report(db)
	_check("crest_missing_file" in cr["missing_assets"] and DatabaseTools.validate_all(db)["critical"].any(func(e: String) -> bool: return "missing" in e), "a crest whose file is missing is reported (crest report and validation)")
	db.crests.crests.erase("crest_missing_file")
	var dup := PlayerData.from_dict(p.to_dict())
	dup.id = "gen_dup_1"
	dup.team_id = ""
	db.register_player(dup)
	var w: Array = DatabaseTools.validate_all(db)["warnings"]
	_check(w.any(func(x: String) -> bool: return "names" in x and "duplicate" in x), "a duplicated player name is reported as a warning", str(w))
	var dup_id := PlayerData.from_dict(p.to_dict())
	_check(not db.register_player(dup_id), "a duplicate player id is refused at registration (and recorded in errors)")
	_check(DatabaseTools.validate_all(db)["critical"].any(func(e: String) -> bool: return "duplicate player id" in e), "the refused duplicate id stays visible in the validation report")


func _test_search() -> void:
	var db := _new_db("real_2025")
	var ars := DatabaseTools.search_clubs(db, {"text": "arsenal"})
	_check(ars.size() == 1 and ars[0].id == "eng_arsenal", "club search by name")
	_check(DatabaseTools.search_clubs(db, {"text": "fic_eng_"}).size() == 20, "club search by id fragment (20 fictional English clubs)")
	_check(DatabaseTools.search_clubs(db, {"type": "FICTIONAL"}).size() == 100 and DatabaseTools.search_clubs(db, {"type": "REAL"}).size() == 198, "club filter by type")
	_check(DatabaseTools.search_clubs(db, {"division": "eng_d3"}).size() == 20, "club filter by division")
	_check(DatabaseTools.search_clubs(db, {"country": "Spain"}).size() == 62 + 0 or DatabaseTools.search_clubs(db, {"country": "Spain"}).size() == 62, "club filter by country (Spain 20+22+20)")
	_check(DatabaseTools.search_clubs(db, {"country": "Germany", "type": "FICTIONAL"}).size() == 20, "filters combine")
	_check(DatabaseTools.search_clubs(db, {"text": "Munchen"}).size() >= 1 and DatabaseTools.search_clubs(db, {"text": "münchen"}).size() == DatabaseTools.search_clubs(db, {"text": "munchen"}).size(), "search ignores accents and case")
	_check(DatabaseTools.search_clubs(db, {"limit": 7}).size() == 7, "result limit")
	var by_id := DatabaseTools.search_players(db, {"text": "tm_262749"})
	_check(by_id.size() >= 1 and by_id[0].display_name == "David Raya", "player search by id")
	var by_name := DatabaseTools.search_players(db, {"text": "raya"})
	_check(by_name.any(func(p: PlayerData) -> bool: return p.id == "tm_262749"), "player search by name fragment")
	var gks := DatabaseTools.search_players(db, {"club": "eng_arsenal", "position": "GK"})
	_check(gks.size() >= 2 and gks.all(func(p: PlayerData) -> bool: return p.team_id == "eng_arsenal" and p.position == PlayerData.Position.GK), "filter by club and position")
	var young := DatabaseTools.search_players(db, {"min_age": 17, "max_age": 19, "limit": 50})
	_check(young.size() == 50 and young.all(func(p: PlayerData) -> bool: return p.age >= 17 and p.age <= 19), "filter by age")
	var sorted_ok := true
	var spanish := DatabaseTools.search_players(db, {"country": "Spain", "limit": 100})
	for i in range(1, spanish.size()):
		sorted_ok = sorted_ok and spanish[i - 1].get_overall() >= spanish[i].get_overall()
	_check(spanish.size() == 100 and sorted_ok and spanish.all(func(p: PlayerData) -> bool: return p.nationality == "Spain"), "filter by nationality, best players first")
	_check(DatabaseTools.search_players(db, {"type": "REAL"}).size() == 2867, "filter by player type")


func _test_profiles() -> void:
	var db := _new_db("real_2025")
	var pr := DatabaseTools.club_profile(db, "eng_arsenal")
	var g: Dictionary = pr["squad_groups"]
	_check(pr["name"] == "Arsenal FC" and pr["league_id"] == "eng_d1" and pr["type"] == "REAL" and g["GK"] + g["DEF"] + g["MID"] + g["ATT"] == pr["squad_size"], "club profile: identity, league and squad composition add up")
	_check(pr["crest_type"] == "ORIGINAL_ALTERNATIVE" and pr["finance"]["status"] in ["UNKNOWN", "HEALTHY", "TIGHT", "CRISIS"], "club profile: crest type and financial status")
	_check(DatabaseTools.club_profile(db, "nope").is_empty(), "an unknown club gives an empty profile")
	var pp := DatabaseTools.player_profile(db, "tm_262749")
	_check(pp["name"] == "David Raya" and pp["position"] == "GK" and pp["attributes"].size() == 18 and pp["type"] == "REAL", "player profile: identity, position and 18 detailed attributes")
	_check(pp["height_is_estimate"] and pp["height_cm"] >= 160 and pp["appearance"]["version"] >= 1 and pp["appearance"]["fields"].size() > 5, "player profile: height marked as estimate, appearance metadata present")
	_check(DatabaseTools.player_profile(db, "nope").is_empty(), "an unknown player gives an empty profile")


func _test_metadata() -> void:
	var db := _new_db("")
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "city", "  Sunvale Bay ") == "" and db.get_team("club_sunvale").city == "Sunvale Bay", "a supported text field is changed (trimmed)")
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "founding_year", "1921") == "" and db.get_team("club_sunvale").founding_year == 1921, "a supported number field is changed")
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "founding_year", "abc") != "", "a non-number for a number field is refused")
	var err := DatabaseTools.set_club_metadata(db, "club_sunvale", "founding_year", "1500")
	_check(err != "" and db.get_team("club_sunvale").founding_year == 1921, "an invalid value is refused and the old value is restored", err)
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "id", "x") != "" and db.get_team("club_sunvale") != null, "identity (id) cannot be edited")
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "reputation", "99") != "", "fields that are not supported are refused")
	_check(DatabaseTools.set_club_metadata(db, "no_club", "city", "x") != "", "an unknown club is refused")
	_check(DatabaseTools.set_club_metadata(db, "club_sunvale", "stadium_level", "9") != "" and db.get_team("club_sunvale").stadium_level == 1, "stadium level is range-checked")


func _snapshot(db: TeamDatabase) -> Dictionary:
	var t := {}
	for x: TeamData in db.teams.values():
		t[x.id] = x.to_dict()
	var p := {}
	for x: PlayerData in db.players.values():
		p[x.id] = x.to_dict()
	return {"t": t, "p": p}


func _test_export_import() -> void:
	var src := _new_db("")
	var path := TMP + "/snapshot.json"
	_check(DatabaseTools.export_snapshot(src, path) == "", "a snapshot is written")
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed["counts"]["teams"] == src.teams.size() and parsed["counts"]["players"] == src.players.size() and parsed["format"] == DatabaseTools.SNAPSHOT_FORMAT, "snapshot has format, version and counts")
	DatabaseTools.export_snapshot(src, TMP + "/snapshot2.json")
	_check(raw == FileAccess.get_file_as_string(TMP + "/snapshot2.json"), "exporting twice gives identical files (deterministic)")
	var dst: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	dst.load_countries()
	var dry := DatabaseTools.import_package(dst, path, true)
	_check(dry["ok"] and dry["teams"] == src.teams.size() and dst.teams.is_empty(), "a dry run checks the package and adds nothing")
	var res := DatabaseTools.import_package(dst, path)
	_check(res["ok"] and dst.teams.size() == src.teams.size() and dst.players.size() == src.players.size(), "import into an empty database adds every team and player", str(res))
	_check(_snapshot(dst) == _snapshot(src), "after export and import every team and player is identical (nothing lost or changed)")
	var again := DatabaseTools.import_package(dst, path)
	_check(not again["ok"] and again["errors"].any(func(e: String) -> bool: return "already exists" in e) and dst.teams.size() == src.teams.size(), "importing the same package again is refused (duplicate ids), nothing changes")
	# all-or-nothing
	var bad: Dictionary = parsed.duplicate(true)
	bad["players"][3]["pace"] = 900
	var bad_path := TMP + "/bad.json"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(bad))
	f.close()
	var empty: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	var rb := DatabaseTools.import_package(empty, bad_path)
	_check(not rb["ok"] and empty.teams.is_empty() and empty.players.is_empty() and rb["errors"].any(func(e: String) -> bool: return "pace" in e), "one invalid record rejects the whole package (all-or-nothing)")
	var orphan: Dictionary = parsed.duplicate(true)
	orphan["players"][0]["team_id"] = "no_such_team"
	f = FileAccess.open(TMP + "/orphan.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(orphan))
	f.close()
	_check(not DatabaseTools.import_package(empty, TMP + "/orphan.json")["ok"], "a player of an unknown team is rejected")
	f = FileAccess.open(TMP + "/garbage.json", FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	_check(not DatabaseTools.import_package(empty, TMP + "/garbage.json")["ok"] and not DatabaseTools.import_package(empty, TMP + "/missing.json")["ok"], "corrupt and missing files are rejected")
	var newer: Dictionary = parsed.duplicate(true)
	newer["version"] = 99
	f = FileAccess.open(TMP + "/newer.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(newer))
	f.close()
	_check(not DatabaseTools.import_package(empty, TMP + "/newer.json")["ok"], "a package from a newer version is rejected")
	var wrong := {"format": "something_else", "teams": [], "players": []}
	f = FileAccess.open(TMP + "/wrong.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(wrong))
	f.close()
	_check(not DatabaseTools.import_package(empty, TMP + "/wrong.json")["ok"], "an unknown package format is rejected")
	# snapshot of a loaded save-like state survives a restore: existing saves are unaffected
	var snap := SaveManager.capture(src)
	var restored := _new_db("")
	_check(SaveManager.restore(restored, snap)["ok"], "snapshot tools do not interfere with save/restore")


func _test_generate() -> void:
	var db := _new_db("")
	var path := TMP + "/generated.json"
	var g := DatabaseTools.generate_package(db, 77, 2, path)
	_check(g["ok"] and g["teams"] == 10 and g["players"] == 280, "generation writes 10 fictional clubs and 280 players", str(g))
	var g2 := DatabaseTools.generate_package(db, 77, 2, TMP + "/generated2.json")
	_check(FileAccess.get_file_as_string(path) == FileAccess.get_file_as_string(TMP + "/generated2.json"), "the same seed writes the same package")
	var before_teams := db.teams.size()
	var before_players := db.players.size()
	var imp := DatabaseTools.import_package(db, path)
	_check(imp["ok"] and db.teams.size() == before_teams + 10 and db.players.size() == before_players + 280, "the generated package imports", str(imp.get("errors", [])))
	var all_fic := true
	for t: TeamData in db.teams.values():
		if t.id.begins_with("fic_"):
			all_fic = all_fic and t.club_type == TeamData.ClubType.FICTIONAL and not t.is_real
	_check(all_fic, "imported generated clubs are FICTIONAL")
	_check(DatabaseTools.validate_all(db, false)["critical"].is_empty(), "the database stays valid after importing generated clubs", str(DatabaseTools.validate_all(db, false)["critical"].slice(0, 3)))


func _press(root: Node, node_name: String) -> bool:
	var b := root.find_child(node_name, true, false) as Button
	if b == null:
		return false
	b.pressed.emit()
	return true


func _test_screen() -> void:
	var app: Node = get_node("/root/AppHub")
	app.career = null
	app.squads.clear()
	app.db.load_world("real_2025")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("database")
	await get_tree().process_frame
	await get_tree().process_frame
	var scr := hub.current
	var tabs := scr.find_child("DbTabs", true, false) as TabContainer
	_check(tabs != null and tabs.get_tab_count() == 4, "the Database screen has 4 tabs (clubs, players, crests, database)")
	_check(scr.find_children("Club_*", "Button", true, false).size() == 40, "the club list shows the first 40 of 298 clubs")
	var search := scr.find_child("ClubSearch", true, false) as LineEdit
	search.text_submitted.emit("arsenal")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	_check(scr.find_children("Club_*", "Button", true, false).size() == 1, "searching 'arsenal' leaves one club")
	_check(_press(scr, "Club_eng_arsenal"), "a club can be opened")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var detail := scr.find_child("ClubDetail", true, false)
	_check(detail != null and detail.get_child_count() > 6, "the club profile shows identity, squad, finance, stadium and crest")
	var field := scr.find_child("ClubField", true, false) as OptionButton
	var value := scr.find_child("ClubValue", true, false) as LineEdit
	var city_index := DatabaseTools.EDITABLE_CLUB_FIELDS.find("city")
	field.select(city_index)
	field.item_selected.emit(city_index)
	value.text = "Test City"
	_press(scr, "ClubApply")
	_check(app.db.get_team("eng_arsenal").city == "Test City", "editing metadata on the screen changes the live club")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	# players tab
	tabs = scr.find_child("DbTabs", true, false) as TabContainer
	tabs.current_tab = 1
	var ps := scr.find_child("PlayerSearch", true, false) as LineEdit
	ps.text_submitted.emit("tm_262749")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	_check(scr.find_child("Player_tm_262749", true, false) != null, "player search by id finds David Raya")
	_press(scr, "Player_tm_262749")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var pd := scr.find_child("PlayerDetail", true, false)
	_check(pd != null and pd.find_children("*", "ProgressBar", true, false).size() == 18, "the player profile shows 18 attribute bars")
	# crests tab
	tabs = scr.find_child("DbTabs", true, false) as TabContainer
	tabs.current_tab = 2
	var cs := scr.find_child("CrestSearch", true, false) as LineEdit
	cs.text_submitted.emit("chelsea")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var tile := scr.find_child("CrestTile_eng_chelsea_fc", true, false)
	_check(tile != null and tile.find_children("*", "TextureRect", true, false).size() >= 3, "the crest tile previews the crest, the kit and a card")
	var before: int = app.db.crests.crests_of("eng_chelsea_fc").size()
	_press(scr, "NewAlt_eng_chelsea_fc")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(app.db.crests.crests_of("eng_chelsea_fc").size() == before + 1 and app.db.get_team("eng_chelsea_fc").crest_id.ends_with("alt%d" % before), "'new alternative crest' adds a crest design and assigns it to the club")
	scr = hub.current
	tabs = scr.find_child("DbTabs", true, false) as TabContainer
	tabs.current_tab = 2
	_check(_press(scr, "UseCrest_crest_eng_chelsea_fc") and app.db.get_team("eng_chelsea_fc").crest_id == "crest_eng_chelsea_fc", "the original crest can be assigned back")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var img := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.8))
	img.save_png(TMP + "/screen_crest.png")
	(scr.find_child("ImportPath_eng_chelsea_fc", true, false) as LineEdit).text = TMP + "/screen_crest.png"
	_press(scr, "ImportCrest_eng_chelsea_fc")
	_check(CrestService.crest_of(app.db, "eng_chelsea_fc").asset_type == CrestData.AssetType.USER_CUSTOM, "importing an image on the screen makes a user crest")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	_press(scr, "CrestReportButton")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	_check(scr.find_child("CrestOutput", true, false) != null, "the crest report is shown")
	# database tab
	tabs = scr.find_child("DbTabs", true, false) as TabContainer
	tabs.current_tab = 3
	_press(scr, "ValidateButton")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var out := (scr.find_child("DbOutput", true, false) as Label).text
	_check("0" in out and out.length() > 20, "validation output is shown on the screen", out.substr(0, 120))
	(scr.find_child("ExportPath", true, false) as LineEdit).text = TMP + "/screen_export.json"
	_press(scr, "ExportButton")
	_check(FileAccess.file_exists(TMP + "/screen_export.json"), "the export button writes the snapshot file")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	(scr.find_child("ImportPath", true, false) as LineEdit).text = TMP + "/screen_export.json"
	_press(scr, "ImportButton")
	await get_tree().process_frame
	await get_tree().process_frame
	scr = hub.current
	var imp_out := (scr.find_child("DbOutput", true, false) as Label).text
	_check("already exists" in imp_out, "importing the live database's own snapshot is refused on the screen", imp_out.substr(0, 100))
	(scr.find_child("GenPath", true, false) as LineEdit).text = TMP + "/screen_generated.json"
	_press(scr, "GenerateButton")
	_check(FileAccess.file_exists(TMP + "/screen_generated.json"), "the generate button writes a package")
	hub.queue_free()
	app.db.reload()


func _run_cli(args: Array) -> Array:
	var output: Array = []
	var full: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tools/db_cli.tscn", "--"]
	full.append_array(args)
	var code := OS.execute(OS.get_executable_path(), full, output, true)
	return [code, "\n".join(output)]


func _test_cli() -> void:
	var out_path := ProjectSettings.globalize_path(TMP) + "/cli_export.json"
	var v := _run_cli(["validate", "world=default"])
	_check(v[0] == 0 and "critical errors: 0" in v[1], "CLI validate on the default world exits 0 with no critical errors", str(v[1]).right(200))
	var e := _run_cli(["export", out_path, "world=default"])
	_check(e[0] == 0 and FileAccess.file_exists(out_path), "CLI export writes a snapshot", str(e[1]).right(200))
	var i := _run_cli(["import", out_path, "dry", "world=default"])
	_check(i[0] == 1 and "already exists" in i[1], "CLI import of an existing world is refused with exit code 1")
	var g := _run_cli(["generate", "3", "1", ProjectSettings.globalize_path(TMP) + "/cli_gen.json", "world=default"])
	_check(g[0] == 0 and "generated 5 clubs" in g[1], "CLI generate writes 5 clubs", str(g[1]).right(200))
	var s := _run_cli(["search-club", "sunvale", "world=default"])
	_check(s[0] == 0 and "club_sunvale" in s[1], "CLI search-club finds a club")
	var bad := _run_cli(["frobnicate"])
	_check(bad[0] == 2, "an unknown CLI command exits with code 2")
