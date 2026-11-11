## Phase T6 validation — promotion + versioned save/load:
##   godot --headless --path . res://tests/phaseT6_validation.tscn
extends Node

const TEAM := "club_royal_harbor"
const SAVE_PATH := "user://test_saves/phaseT6.json"

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
	print("=== KING FOOTBALL — Phase T6 validation ===")
	_test_promotion()
	_test_promotion_failures()
	_test_release()
	_test_save_load_roundtrip()
	_test_save_failures()
	_test_migration()
	DirAccess.remove_absolute(SAVE_PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> Node:
	var db: Node = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


## Academy with prospects; returns [academy, an eligible (>=16) player id].
func _academy(db: Node) -> Array:
	var ac := Academy.new(TEAM, "Aldoria", 5)
	ac.generate_intake(db, 20, 17)
	return [ac, ac.roster_ids[0]]


func _test_promotion() -> void:
	var db := _db()
	var fx := _academy(db)
	var ac: Academy = fx[0]
	var pid: String = fx[1]
	var p: PlayerData = db.get_player(pid)
	var snapshot_attrs := {}
	for a in PlayerData.ATTRIBUTES:
		snapshot_attrs[a] = p.get_attribute(a)
	var history_len := p.development_history.size()
	var squad_before := db.get_squad(TEAM).size()
	var roster_before := ac.roster_ids.size()
	_check(PromotionSystem.why_not(db, ac, pid) == "", "eligible player has no blockers")
	var err := PromotionSystem.promote(db, ac, pid)
	_check(err == "", "promotion succeeds", err)
	_check(db.get_player(pid) == p, "same player object / id after promotion")
	_check(p.status == PlayerData.Status.ACTIVE, "status becomes ACTIVE")
	_check(not (pid in ac.roster_ids) and ac.roster_ids.size() == roster_before - 1, "removed from academy roster")
	_check(pid in db.get_team(TEAM).squad_ids, "added to first-team squad")
	_check(db.get_squad(TEAM).size() == squad_before + 1, "first-team squad grew by one")
	var attrs_same := true
	for a in PlayerData.ATTRIBUTES:
		if p.get_attribute(a) != int(snapshot_attrs[a]):
			attrs_same = false
	_check(attrs_same, "attributes unchanged by promotion")
	_check(p.development_history.size() == history_len + 1 and p.development_history[0]["event"] == "generated",
			"history preserved and extended")
	_check(p.development_history[-1]["event"] == "promoted", "promotion recorded in history")
	_check(p.shirt_number >= 1 and p.shirt_number <= 99, "squad number assigned", str(p.shirt_number))
	_check(p.contract_years > 0 and p.salary > 0, "contract and salary set")
	var nums := PromotionSystem.used_numbers(db, TEAM)
	var unique := {}
	for n in nums:
		unique[n] = true
	_check(unique.size() == nums.size(), "no duplicate squad numbers")
	# Promote with explicit free number.
	var pid2: String = ac.roster_ids[0]
	var free := PromotionSystem.next_free_number(db, TEAM)
	_check(PromotionSystem.promote(db, ac, pid2, 77) == "", "promotion with explicit number")
	_check(db.get_player(pid2).shirt_number == 77, "explicit number applied")
	# Available for team selection.
	var sq := Squad.new(TEAM)
	sq.auto_pick(db)
	var all_ids: Array[String] = []
	all_ids.append_array(sq.starting)
	all_ids.append_array(sq.bench)
	all_ids.append_array(sq.reserves)
	_check(pid in all_ids or pid2 in all_ids, "promoted players can be picked into the squad")
	_check(sq.validate(db).is_empty(), "squad with promoted players validates")
	_check(free >= 1, "next_free_number returns a number")
	db.free()


func _test_promotion_failures() -> void:
	var db := _db()
	var fx := _academy(db)
	var ac: Academy = fx[0]
	var pid: String = fx[1]
	_check(PromotionSystem.promote(db, ac, "ghost") != "", "unknown player rejected")
	_check(PromotionSystem.promote(db, ac, "plr_rhf_05") != "", "first-team player cannot be 'promoted' again")
	var young := Academy.new("club_northgate_utd", "Aldoria", 9)
	young.generate_intake(db, 3, 14)
	var yid: String = young.roster_ids[0]
	_check(PromotionSystem.promote(db, young, yid) != "", "too-young player rejected")
	_check(PromotionSystem.why_not(db, young, yid) != "", "why_not explains age block")
	_check(young.roster_ids.has(yid) and db.get_player(yid).status == PlayerData.Status.YOUTH,
			"rejected promotion changes nothing")
	_check(PromotionSystem.promote(db, ac, pid, 0) != "", "number 0 rejected")
	_check(PromotionSystem.promote(db, ac, pid, 100) != "", "number 100 rejected")
	var taken: int = db.get_player("plr_rhf_01").shirt_number
	_check(PromotionSystem.promote(db, ac, pid, taken) != "", "taken number rejected")
	_check(pid in ac.roster_ids, "failed promotion keeps player in academy")
	_check(PromotionSystem.promote(db, ac, pid) == "", "valid promotion works after failures")
	_check(PromotionSystem.promote(db, ac, pid) != "", "duplicate promotion rejected")
	var squad_ids := db.get_team(TEAM).squad_ids
	var count := 0
	for s in squad_ids:
		if s == pid:
			count += 1
	_check(count == 1, "player appears exactly once in squad ids")
	# Wrong academy cannot promote someone else's youth.
	var other := Academy.new("club_obsidian", "Zamoria", 3)
	other.generate_intake(db, 2, 17)
	var stolen := PromotionSystem.promote(db, ac, other.roster_ids[0])
	_check(stolen != "", "cannot promote another academy's youth")
	db.free()


func _test_release() -> void:
	var db := _db()
	var fx := _academy(db)
	var ac: Academy = fx[0]
	var pid: String = fx[1]
	_check(PromotionSystem.release_youth(db, ac, pid) == "", "release academy youth")
	_check(not (pid in ac.roster_ids) and db.get_player(pid).team_id == "", "released youth is unowned")
	_check(PromotionSystem.release_youth(db, ac, pid) != "", "cannot release twice")
	var sq := Squad.new(TEAM)
	sq.auto_pick(db)
	var starter := sq.starting[3]
	sq.set_captain(starter)
	_check(PromotionSystem.release_from_squad(db, TEAM, starter, sq) == "", "release first-team player")
	_check(not (starter in db.get_team(TEAM).squad_ids), "removed from squad ids")
	_check(not sq.contains(starter) and sq.captain_id == "", "lineup and captaincy cleaned")
	_check(PromotionSystem.release_from_squad(db, TEAM, starter) != "", "cannot release non-member")
	db.free()


func _test_save_load_roundtrip() -> void:
	var db := _db()
	var ac := Academy.new(TEAM, "Aldoria", 5)
	ac.budget = 123456
	ac.generate_intake(db, 20, 17)
	var plan := TrainingSystem.new()
	plan.set_group_focus("U17", "passing")
	for i in 20:
		plan.advance_week(db, ac)
	var sc := ScoutingSystem.new(9)
	sc.add_scout("s1", "Scout", 0.8, 100)
	sc.start_mission(ac, "s1", "Zamoria", 1)
	sc.advance_week(db, ac)
	var pid: String = ac.roster_ids[0]
	_check(PromotionSystem.promote(db, ac, pid, 30) == "", "promote before saving")
	var sq := Squad.new(TEAM, "4-4-2")
	sq.auto_pick(db)
	var before: Dictionary = db.get_player(pid).to_dict()
	var data := SaveManager.capture(db, {TEAM: ac}, {TEAM: sc}, {TEAM: plan}, {TEAM: sq},
			{"note": "hello"})
	_check(SaveManager.write_file(SAVE_PATH, data) == "", "write save file")
	_check(not FileAccess.file_exists(SAVE_PATH + ".tmp"), "no temp file left behind")
	var rd := SaveManager.read_file(SAVE_PATH)
	_check(rd["ok"], "read save file", rd["error"])
	var db2 := _db()
	db2.clear()   # prove restore rebuilds everything
	var res := SaveManager.restore(db2, rd["data"])
	_check(res["ok"], "restore succeeds", str(res["errors"]))
	var p2: PlayerData = db2.get_player(pid)
	_check(p2 != null and p2.to_dict() == before, "promoted player identical after save/load")
	_check(pid in db2.get_team(TEAM).squad_ids, "promoted player still in first team")
	var ac2: Academy = res["academies"][TEAM]
	_check(not (pid in ac2.roster_ids), "promoted player not back in academy")
	_check(ac2.roster_ids == ac.roster_ids and ac2.budget == 123456, "academy roster + budget restored")
	_check(db2.players.size() == db.players.size() and db2.teams.size() == db.teams.size(), "same record counts")
	var sq2: Squad = res["squads"][TEAM]
	_check(sq2.to_dict() == sq.to_dict(), "squad restored")
	var tr2: TrainingSystem = res["training"][TEAM]
	_check(tr2.week == 20 and tr2.group_focus.get("U17") == "passing", "training plan restored")
	var sc2: ScoutingSystem = res["scouting"][TEAM]
	_check(sc2.pool == sc.pool and sc2.next_index == sc.next_index, "scouting state restored")
	_check(res["extras"].get("note") == "hello", "extras restored")
	# No duplicates after load + new intake.
	var count_before := db2.players.size()
	var more := ac2.generate_intake(db2, 3, 17)
	_check(more.size() == 3 and db2.players.size() == count_before + 3, "post-load intake adds only new players")
	var dup_academy := false
	for q in more:
		if q.id in ac.roster_ids or q.id == pid:
			dup_academy = true
	_check(not dup_academy, "post-load intake never reuses ids")
	# Second promotion of same player after reload still rejected.
	_check(PromotionSystem.promote(db2, ac2, pid) != "", "reloaded promoted player cannot be promoted again")
	db.free()
	db2.free()


func _test_save_failures() -> void:
	var db := _db()
	var good := SaveManager.capture(db)
	_check(SaveManager.validate(good).is_empty(), "fresh capture validates")
	var snapshot_teams := db.teams.size()
	var bad := good.duplicate(true)
	bad["teams"][0]["squad"].append("ghost_player")
	_check(not SaveManager.validate(bad).is_empty(), "dangling squad reference detected")
	var res := SaveManager.restore(db, bad)
	_check(not res["ok"] and db.teams.size() == snapshot_teams, "failed restore leaves database untouched")
	var dup := good.duplicate(true)
	dup["players"].append(dup["players"][0].duplicate(true))
	_check(not SaveManager.validate(dup).is_empty(), "duplicate player record detected")
	var both := good.duplicate(true)
	both["academies"] = {TEAM: {"team_id": TEAM, "roster": [good["players"][0]["id"]]}}
	_check(not SaveManager.validate(both).is_empty(), "player both in academy and squad detected")
	var corrupt := FileAccess.open("user://test_saves/corrupt.json", FileAccess.WRITE)
	if corrupt == null:
		DirAccess.make_dir_recursive_absolute("user://test_saves")
		corrupt = FileAccess.open("user://test_saves/corrupt.json", FileAccess.WRITE)
	corrupt.store_string("{not json")
	corrupt.close()
	var r := SaveManager.read_file("user://test_saves/corrupt.json")
	_check(not r["ok"], "corrupt save rejected")
	DirAccess.remove_absolute("user://test_saves/corrupt.json")
	_check(not SaveManager.read_file("user://test_saves/missing.json")["ok"], "missing save handled")
	var newer := good.duplicate(true)
	newer["save_version"] = SaveManager.SAVE_VERSION + 5
	_check(SaveManager.migrate(newer).has("error"), "newer save version refused")
	var invalid_player := good.duplicate(true)
	invalid_player["players"][0]["pace"] = 500
	_check(not SaveManager.validate(invalid_player).is_empty(), "invalid attribute in save detected")
	db.free()


func _test_migration() -> void:
	var db := _db()
	var legacy := {"teams": SaveManager.capture(db)["teams"], "players": SaveManager.capture(db)["players"]}
	var migrated := SaveManager.migrate(legacy)
	_check(not migrated.has("error") and migrated["save_version"] == SaveManager.SAVE_VERSION,
			"v0 save migrates to current version")
	_check(migrated.has("academies") and migrated.has("extras"), "migration adds missing blocks")
	var db2 := _db()
	db2.clear()
	_check(SaveManager.restore(db2, legacy)["ok"], "legacy save restores")
	_check(db2.players.size() == db.players.size(), "legacy restore keeps all players")
	db.free()
	db2.free()
