## Database phase 9 validation — save format v3: migration from v2 (and older), backups, recovery:
##   godot --headless --path . res://tests/db_migration_validation.tscn
extends Node

const TMP := "user://test_db_migration"
const TEAM_NEW_KEYS: Array[String] = ["full_name", "nickname", "city", "region", "founding_year", "club_type", "country_id", "description",
		"league_id", "division", "manager_id", "rival_club_ids", "transfer_budget", "wage_budget", "current_balance", "weekly_expenses",
		"sponsorship_income", "stadium_name", "stadium_capacity", "stadium_level", "crest_id", "accent_color", "history"]
const PLAYER_NEW_KEYS: Array[String] = ["first_name", "last_name", "nationality_id", "birth_year", "height_cm", "weight_kg",
		"secondary_positions", "player_type", "contract_id"]

var _passed := 0
var _failed := 0
var app: Node
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
	print("=== KING FOOTBALL — database phase 9 (migration) validation ===")
	DirAccess.make_dir_recursive_absolute(TMP)
	app = get_node("/root/AppHub")
	db = get_node("/root/TeamDB")
	_test_version()
	var v2 := _make_v2_save()
	_test_migrate_function(v2)
	_test_chain()
	_test_load_backup_save(v2)
	_test_failures(v2)
	_test_recovery()
	db.load_world("")
	app.career = null
	app.squads.clear()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh() -> void:
	db.load_world("")
	app.career = null
	app.squads.clear()
	app.academies.clear()
	app.scouting.clear()
	app.training.clear()
	app.user_team_id = ""


## A save in the exact v2 format: a real game state, captured by the current code, then reduced to the
## keys and values a v2 game wrote (no new identity fields, no "crests", no season statistics).
func _make_v2_save() -> Dictionary:
	_fresh()
	app.start_career("club_royal_harbor")
	var career: CareerState = app.career
	var pid: String = db.get_team("club_royal_harbor").squad_ids[4]
	career.record_match({"uid": "v2-a", "source": "engine", "motm": pid, "players": [{"player_id": pid, "goals": 3, "assists": 1, "saves": 0, "rating": 8.4}]}, "lg_old")
	career.record_match({"uid": "v2-b", "source": "engine", "motm": "", "players": [{"player_id": pid, "goals": 1, "assists": 0, "saves": 0, "rating": 6.9}]})
	app.save_game(TMP + "/_tmp_v3.json")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP + "/_tmp_v3.json"))
	DirAccess.remove_absolute(TMP + "/_tmp_v3.json")
	raw["save_version"] = 2
	raw.erase("crests")
	for t in raw["teams"]:
		for k in TEAM_NEW_KEYS:
			t.erase(k)
	for p in raw["players"]:
		for k in PLAYER_NEW_KEYS:
			p.erase(k)
	(raw["extras"]["career"] as Dictionary).erase("season_stats")
	return raw


func _test_version() -> void:
	_check(SaveManager.SAVE_VERSION == 3, "the save format version is 3")
	_fresh()
	app.start_career("club_royal_harbor")
	app.save_game(TMP + "/new.json")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP + "/new.json"))
	_check(int(raw["save_version"]) == 3 and raw.has("crests") and (raw["teams"][0] as Dictionary).has("club_type") and (raw["players"][0] as Dictionary).has("first_name"), "a new save is written as v3 with the new keys")
	_check(not FileAccess.file_exists(TMP + "/new.json.v3.bak") and not FileAccess.file_exists(TMP + "/new.json.v2.bak"), "saving a current-version file creates no backup")


func _test_migrate_function(v2: Dictionary) -> void:
	_check(v2["save_version"] == 2 and not (v2["teams"][0] as Dictionary).has("club_type") and not (v2["players"][0] as Dictionary).has("first_name"), "(fixture) the test save really is in the old v2 format")
	var m := SaveManager.migrate(v2)
	_check(not m.has("error") and m["save_version"] == 3, "v2 migrates to v3")
	var team_ok := true
	var by_id := {}
	for t in m["teams"]:
		by_id[t["id"]] = t
		team_ok = team_ok and t["club_type"] == ("REAL" if t["real"] else "FICTIONAL") and (t["category"] != "CLUB" or t["crest_id"] == "crest_" + t["id"])
	_check(team_ok, "clubs get club_type (from the real flag) and crest_id")
	_check(by_id["club_sunvale"]["country_id"] == "ald" and by_id["nat_aldoria"]["country_id"] == "ald", "teams get their country id from the country name")
	var player_ok := true
	for p in m["players"]:
		var parts := PlayerData.split_name(str(p["name"]))
		player_ok = player_ok and p["first_name"] == parts[0] and p["last_name"] == parts[1] and p.has("nationality_id") and p["player_type"] in ["REAL", "GENERATED", "YOUTH"]
	_check(player_ok, "players get first/last name, nationality id and player type")
	var unchanged := true
	for i in v2["players"].size():
		for k in (v2["players"][i] as Dictionary):
			unchanged = unchanged and JSON.stringify(m["players"][i][k]) == JSON.stringify(v2["players"][i][k])
	for i in v2["teams"].size():
		for k in (v2["teams"][i] as Dictionary):
			unchanged = unchanged and JSON.stringify(m["teams"][i][k]) == JSON.stringify(v2["teams"][i][k])
	_check(unchanged, "every value that existed in v2 (ids, names, attributes, appearance, squads, kits ...) is unchanged")
	_check(m["crests"] == [], "an empty crests block is added")
	var career: Dictionary = m["extras"]["career"]
	var pid: String = ""
	for k in career["player_stats"]:
		pid = k
		break
	var legacy: Dictionary = career["season_stats"][pid]["0:legacy"]
	_check(legacy == career["player_stats"][pid] and legacy["apps"] == 2 and legacy["goals"] == 4, "the all-time career statistics are kept as a legacy season bucket (nothing lost)")
	_check(JSON.stringify(SaveManager.migrate(m)) == JSON.stringify(m), "migrating a v3 save again changes nothing (idempotent)")
	var pre_filled := v2.duplicate(true)
	(pre_filled["teams"][0] as Dictionary)["club_type"] = "CUSTOM"
	(pre_filled["players"][0] as Dictionary)["first_name"] = "Keep"
	var m2 := SaveManager.migrate(pre_filled)
	_check(m2["teams"][0]["club_type"] == "CUSTOM" and m2["players"][0]["first_name"] == "Keep", "values that are already there are never overwritten")
	_check(SaveManager.validate(m).is_empty(), "the migrated save validates", str(SaveManager.validate(m).slice(0, 2)))


func _test_chain() -> void:
	var v0 := {"save_version": 0, "teams": [{"id": "t1", "name": "T One", "short_name": "T1", "country": "England", "real": true, "kits": {"home": {}, "away": {}, "goalkeeper": {}}}],
			"players": [{"id": "tm_1", "name": "Old Timer", "age": 30, "nationality": "England", "position": "GK", "team_id": "t1"}]}
	var m := SaveManager.migrate(v0)
	_check(not m.has("error") and m["save_version"] == 3 and m["players"][0].has("appearance") and m["players"][0]["player_type"] == "REAL" and m["teams"][0]["club_type"] == "REAL" and m["teams"][0]["country_id"] == "eng",
			"a v0 save passes through every step to v3")
	var v1 := {"save_version": 1, "teams": [], "players": [{"id": "gen_x", "name": "Solo", "position": "ST"}], "academies": {}, "scouting": {}, "training": {}, "squads": {}, "extras": {}}
	var m1 := SaveManager.migrate(v1)
	_check(m1["save_version"] == 3 and m1["players"][0]["last_name"] == "Solo" and m1["players"][0]["player_type"] == "GENERATED", "a v1 save gains appearance (v2) and the identity fields (v3)")
	_check(SaveManager.migrate({"save_version": 4}).has("error") and SaveManager.migrate({"save_version": 99}).has("error"), "a save from a newer game version is refused")


func _test_load_backup_save(v2: Dictionary) -> void:
	var path := TMP + "/career.json"
	_write(path, v2)
	var original_bytes := FileAccess.get_file_as_bytes(path)
	# the live game state the v2 file describes, for comparison
	_fresh()
	app.start_career("club_royal_harbor")
	var expected_players := {}
	for p: PlayerData in db.players.values():
		expected_players[p.id] = p.to_dict()
	var expected_teams := {}
	for t: TeamData in db.teams.values():
		expected_teams[t.id] = t.to_dict()
	_fresh()
	_check(app.load_game(path) == "", "a v2 save loads in the v3 game")
	_check(FileAccess.file_exists(path + ".v2.bak") and FileAccess.get_file_as_bytes(path + ".v2.bak") == original_bytes, "a byte-identical backup <file>.v2.bak was written before anything else happened")
	_check(FileAccess.get_file_as_bytes(path) == original_bytes, "loading does not modify the original file")
	var same_players: bool = db.players.size() == expected_players.size()
	for id in expected_players:
		var p: PlayerData = db.get_player(id)
		same_players = same_players and p != null and JSON.stringify(p.to_dict()) == JSON.stringify(expected_players[id])
	var same_teams: bool = db.teams.size() == expected_teams.size()
	for id in expected_teams:
		var t: TeamData = db.get_team(id)
		same_teams = same_teams and t != null and JSON.stringify(t.to_dict()) == JSON.stringify(expected_teams[id])
	_check(same_players and same_teams, "after loading the old save every player and team equals the original game state (%d players, %d teams)" % [db.players.size(), db.teams.size()])
	var career: CareerState = app.career
	var pid: String = db.get_team("club_royal_harbor").squad_ids[4]
	_check(career != null and career.player_stats[pid]["apps"] == 2 and career.stats_for(pid, 0)["goals"] == 4, "the career statistics are there, also as the legacy bucket")
	_check(db.validate_relations().is_empty() and db.validate_kits().is_empty(), "the loaded old save is consistent")
	# saving writes v3 and keeps the backup
	_check(app.save_game(path) == "", "saving after loading works")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(int(saved["save_version"]) == 3 and FileAccess.get_file_as_bytes(path + ".v2.bak") == original_bytes, "the file is now v3 and the v2 backup is still the original")
	_check(not FileAccess.file_exists(path + ".v3.bak"), "no backup is made of a current-version file")
	_fresh()
	_check(app.load_game(path) == "", "the re-saved v3 file loads")
	var again := true
	for id in expected_players:
		again = again and db.get_player(id) != null and JSON.stringify(db.get_player(id).to_dict()) == JSON.stringify(expected_players[id])
	_check(again, "and gives the same players again")
	_check(FileAccess.get_file_as_bytes(path + ".v2.bak") == original_bytes, "the backup is never replaced by later loads and saves")
	# an old save written again later by another game version: its backup is separate
	var v1_path := TMP + "/older.json"
	_write(v1_path, {"save_version": 1, "teams": [], "players": [], "academies": {}, "scouting": {}, "training": {}, "squads": {}, "extras": {}})
	_check(SaveManager.backup_if_outdated(v1_path) == "" and FileAccess.file_exists(v1_path + ".v1.bak"), "a v1 file gets a v1 backup of its own")


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", true, true))
	f.close()


func _test_failures(v2: Dictionary) -> void:
	_fresh()
	app.start_career("club_royal_harbor")
	var teams_before: int = db.teams.size()
	var first_team: TeamData = db.get_team("club_royal_harbor")
	var players_before: int = db.players.size()
	# corrupt file
	var corrupt := TMP + "/corrupt.json"
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("{ \"save_version\": 2, \"teams\": [ oops")
	f.close()
	var err: String = app.load_game(corrupt)
	_check(err != "" and db.teams.size() == teams_before and db.get_team("club_royal_harbor") == first_team, "a corrupt file is refused and the live database is untouched", err)
	_check(not FileAccess.file_exists(corrupt + ".v0.bak"), "no backup is made of a corrupt file")
	# newer version
	var newer := v2.duplicate(true)
	newer["save_version"] = 9
	_write(TMP + "/newer.json", newer)
	err = app.load_game(TMP + "/newer.json")
	_check(err != "" and "newer" in err and db.players.size() == players_before and not FileAccess.file_exists(TMP + "/newer.json.v9.bak"), "a save from a newer game is refused with a clear message, untouched, no backup", err)
	# invalid record
	var broken := v2.duplicate(true)
	(broken["players"][5] as Dictionary)["pace"] = 900
	_write(TMP + "/broken.json", broken)
	err = app.load_game(TMP + "/broken.json")
	_check(err != "" and db.players.size() == players_before and db.get_team("club_royal_harbor") == first_team, "an invalid record rejects the whole save (all or nothing) and leaves the live database as it was", err)
	var dup := v2.duplicate(true)
	(dup["players"] as Array).append((dup["players"][0] as Dictionary).duplicate(true))
	_write(TMP + "/dup.json", dup)
	_check(app.load_game(TMP + "/dup.json") != "" and db.players.size() == players_before, "a duplicate player id rejects the save")
	var missing := v2.duplicate(true)
	(missing["players"] as Array).remove_at(3)
	_write(TMP + "/missing.json", missing)
	err = app.load_game(TMP + "/missing.json")
	_check(err != "" and db.players.size() == players_before, "a squad that references a missing player rejects the save", err)
	_check(app.load_game(TMP + "/does_not_exist.json") != "", "a missing file is reported")
	# the backup cannot be written: nothing is overwritten
	var locked := TMP + "/locked.json"
	_write(locked, v2)
	DirAccess.make_dir_recursive_absolute(locked + ".v2.bak.d")
	DirAccess.make_dir_recursive_absolute(locked + ".v2.bak")          # a directory where the backup should go
	var bytes := FileAccess.get_file_as_bytes(locked)
	var save_err := SaveManager.backup_if_outdated(locked)
	_check(save_err == "" or FileAccess.get_file_as_bytes(locked) == bytes, "when the backup path is not usable the original file is never touched")
	# saving over an old file backs it up first
	var old_path := TMP + "/overwrite_me.json"
	_write(old_path, v2)
	var old_bytes := FileAccess.get_file_as_bytes(old_path)
	_check(app.save_game(old_path) == "" and FileAccess.get_file_as_bytes(old_path + ".v2.bak") == old_bytes, "saving over an old-version file first keeps a copy of it")
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	_check(int(after["save_version"]) == 3, "and then writes v3")


func _test_recovery() -> void:
	# incomplete records get safe defaults; unknown enum names fall back instead of crashing
	var t := TeamData.from_dict({"id": "x", "name": "X", "short_name": "X", "country": "England", "club_type": "SPACE_CLUB", "kits": {"home": {}, "away": {}, "goalkeeper": {}}})
	_check(t.club_type == TeamData.ClubType.FICTIONAL and t.crest_id == "" and t.stadium_level == 1 and t.history == {}, "an unknown club type and missing new fields fall back to defaults")
	var p := PlayerData.from_dict({"id": "gen_q", "name": "Q Q", "position": "CB", "player_type": "ALIEN"})
	_check(p.player_type == PlayerData.PlayerType.GENERATED and p.first_name == "Q" and p.secondary_positions == [] and p.birth_year == 0, "an unknown player type and missing fields fall back to defaults")
	var d := {"save_version": 3, "teams": [], "players": [{"id": "gen_ok", "name": "Ok Player", "position": "CM", "pace": 50, "shooting": 50, "passing": 50, "dribbling": 50, "defending": 50, "physical": 50, "potential": 60}], "academies": {}, "scouting": {}, "training": {}, "squads": {}, "extras": {}}
	var res := SaveManager.restore(db, d)
	_check(res["ok"] and db.get_player("gen_ok") != null and db.get_player("gen_ok").nationality_id == "", "a minimal v3 record restores (no crests key needed)")
	var before: int = db.players.size()
	var bad := SaveManager.restore(db, {"save_version": 3, "teams": "oops", "players": []})
	_check(bad["ok"] == false and db.players.size() == before, "a wrong kind of block (teams is a string) is reported, not a crash, and changes nothing", str(bad))
	var bad2 := SaveManager.restore(db, {"save_version": 3, "teams": [], "players": [5, "x"]})
	_check(bad2["ok"] == false and db.players.size() == before, "records that are not objects are reported too", str(bad2))
	var bad3 := SaveManager.restore(db, {"save_version": 3, "teams": [], "players": [], "academies": [1]})
	_check(bad3["ok"] == false and db.players.size() == before, "a wrong academies block is reported")
