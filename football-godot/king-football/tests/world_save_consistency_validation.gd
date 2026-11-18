## Career phase C0: a save keeps the world it was written in, loading it restores that world, a mixed database
## is never left behind, and the new-career wizard can always reach "Start career".
##   godot --headless --path . res://tests/world_save_consistency_validation.tscn
extends Node

const PACK := "real_2025"
const PATH := "user://test_saves/c0_world_test.json"
const FICTIONAL_CLUB := "club_desert_kings"

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
	print("=== KING FOOTBALL — World / save consistency validation (C0) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	_test_fictional_save_loaded_in_real_world()
	_test_real_save_loaded_in_fictional_world()
	_test_legacy_saves_without_world_field()
	_test_restore_is_defensive()
	_test_is_consistent()
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	await _test_wizard_repairs_mixed_database()
	await _test_wizard_every_division()
	app.switch_world(saved_pack)
	hub.queue_free()
	DirAccess.remove_absolute(PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	return app.db


## The reported bug: fictional career saved, real world loaded, save loaded -> mixed database.
func _test_fictional_save_loaded_in_real_world() -> void:
	app.switch_world("")
	_check(app.start_career(FICTIONAL_CLUB) == "", "fictional career starts")
	_check(app.save_game(PATH) == "", "fictional career saved")
	app.switch_world(PACK)
	_check(_db().pack_id == PACK and not _db().leagues.is_empty(), "real world loaded before the load")
	var err: String = app.load_game(PATH)
	_check(err == "", "loading a fictional save while the real world is loaded works", err)
	_check(_db().pack_id == "", "...the database is the fictional world again", _db().pack_id)
	_check(_db().leagues.is_empty(), "...with no leftover leagues", str(_db().leagues.size()))
	_check(_db().is_consistent().is_empty(), "...and is consistent", str(_db().is_consistent()))
	_check(app.career != null and app.user_team_id == FICTIONAL_CLUB, "...and the career is the saved one")


func _test_real_save_loaded_in_fictional_world() -> void:
	app.switch_world(PACK)
	var club := _first_club_of_pack()
	_check(app.start_career(club) == "", "real career starts (%s)" % club)
	_check(app.save_game(PATH) == "", "real career saved")
	app.switch_world("")
	var err: String = app.load_game(PATH)
	_check(err == "", "loading a real save while the fictional world is loaded works", err)
	_check(_db().pack_id == PACK and _db().teams.size() > 100, "...the real pack is loaded", "%s %d" % [_db().pack_id, _db().teams.size()])
	_check(_db().is_consistent().is_empty() and app.career != null and app.user_team_id == club, "...and the career runs")
	_check(app.career.advance_week(app.squads, app.academies, app.training, app.scouting) is Dictionary, "...and a week can be played")


func _test_legacy_saves_without_world_field() -> void:
	for world in ["", PACK]:
		app.switch_world(world)
		var club := FICTIONAL_CLUB if world == "" else _first_club_of_pack()
		app.start_career(club)
		app.save_game(PATH)
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_check((parsed["extras"] as Dictionary).has("world"), "the save stores its world (%s)" % ("fictional" if world == "" else world))
		(parsed["extras"] as Dictionary).erase("world")
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(parsed))
		f.close()
		app.switch_world(PACK if world == "" else "")
		var err: String = app.load_game(PATH)
		_check(err == "" and _db().pack_id == world and _db().is_consistent().is_empty(),
				"legacy save without a world field loads in its own world (%s)" % ("fictional" if world == "" else world), "%s pack=%s" % [err, _db().pack_id])


## restore() called directly (no world switch first) must not leave leagues of another world behind.
func _test_restore_is_defensive() -> void:
	app.switch_world("")
	var fictional := SaveManager.capture(_db())
	app.switch_world(PACK)
	var res := SaveManager.restore(_db(), fictional)
	_check(res["ok"], "restore of a fictional snapshot over the real world succeeds")
	_check(_db().leagues.is_empty() and _db().pack_id == "", "...and drops the real leagues / pack id")
	_check(_db().is_consistent().is_empty(), "...leaving a consistent database")


func _test_is_consistent() -> void:
	app.switch_world(PACK)
	_check(_db().is_consistent().is_empty(), "a freshly loaded pack is consistent")
	var some: String = (_db().leagues.values()[0] as LeagueDef).divisions[0]["team_ids"][0]
	_db().teams.erase(some)
	_check(not _db().is_consistent().is_empty(), "a league listing a missing club is reported")
	app.switch_world("")
	_check(_db().is_consistent().is_empty(), "the fictional world is consistent")


func _first_club_of_pack() -> String:
	var lg: LeagueDef = _db().leagues[_sorted_keys()[0]]
	return str(lg.divisions[0]["team_ids"][0])


func _sorted_keys() -> Array:
	var keys: Array = _db().leagues.keys()
	keys.sort()
	return keys


func _wizard() -> HubScreen:
	hub.navigate("career_wizard")
	await get_tree().process_frame
	return hub.current


func _press(n: String) -> bool:
	var b := hub.current.find_child(n, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


## The wizard's world says "real" but the loaded database is a mix: Next reloads the chosen world.
func _test_wizard_repairs_mixed_database() -> void:
	app.switch_world(PACK)
	_db().teams.clear()
	_db().load_directory("res://data/clubs")       # clubs of the default world + leagues of the pack = the broken state
	_check(not _db().is_consistent().is_empty(), "the broken (mixed) state is reproduced")
	app.career = null
	var w := await _wizard()
	w.set("world_id", PACK)
	w.call("rebuild")
	await get_tree().process_frame
	_press("WizardNext")
	await get_tree().process_frame
	_check(_db().is_consistent().is_empty() and _db().pack_id == PACK, "Next from the world step repairs the database")
	_check(int(w.get("step")) == 1 and not (w.call("division_clubs") as Array).is_empty(), "...and the division has clubs")


## Real button presses on Next for every country x division and the fictional world until the career starts.
func _test_wizard_every_division() -> void:
	var runs: Array = [{"world": "", "key": "", "div": 0}]
	app.switch_world(PACK)
	for key in _sorted_keys():
		for i in (_db().leagues[key] as LeagueDef).divisions.size():
			runs.append({"world": PACK, "key": key, "div": i})
	for run in runs:
		var label := "%s/%s/%d" % [run["world"] if run["world"] != "" else "fictional", run["key"], run["div"]]
		app.career = null
		app.switch_world(run["world"])
		var w := await _wizard()
		w.set("world_id", run["world"])
		w.call("rebuild")
		await get_tree().process_frame
		_check(_press("WizardNext"), "%s: Next enabled on the world step" % label)
		await get_tree().process_frame
		if run["world"] != "":
			w.set("league_key", run["key"])
			w.call("_pick_division", run["div"])
			await get_tree().process_frame
		_check(not (w.call("division_clubs") as Array).is_empty(), "%s: the division lists clubs" % label)
		_check(_press("WizardNext"), "%s: Next enabled on the league step" % label)
		await get_tree().process_frame
		var club: TeamData = (w.call("division_clubs") as Array)[0]
		_check(_press("Club_%s" % club.id), "%s: a club can be picked" % label)
		await get_tree().process_frame
		_check(_press("WizardNext"), "%s: Next enabled on the club step" % label)
		await get_tree().process_frame
		_check(_press("WizardNext"), "%s: Next enabled on the coach step" % label)
		await get_tree().process_frame
		_check(_press("WizardNext"), "%s: Next enabled on the settings step" % label)
		await get_tree().process_frame
		_check(_press("WizardStart"), "%s: Start career is enabled" % label)
		await get_tree().process_frame
		_check(app.career != null and app.user_team_id == club.id, "%s: the career started with the chosen club" % label)
