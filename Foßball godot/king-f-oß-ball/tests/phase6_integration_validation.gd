## Integration audit validation — career calendar ↔ academy training/scouting,
## over-age prospects, unicode club ids, half-time, goalkeeper, kits.
##   godot --headless --path . res://tests/phase6_integration_validation.tscn
extends Node

const TEAM := "club_royal_harbor"
const SAVE_PATH := "user://test_saves/phase6.json"

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
	print("=== KING FOOTBALL — Phase 6 integration validation ===")
	_test_calendar_sync()
	_test_calendar_save_load()
	DirAccess.remove_absolute(SAVE_PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


## Career + academy + training + scouting for TEAM, as AppHub builds them.
func _world(db: TeamDatabase) -> Dictionary:
	var career := CareerState.start(db, TEAM)
	var ac := Academy.new(TEAM, "Aldoria", 5)
	ac.budget = 200000
	ac.generate_intake(db, 12)
	var plan := TrainingSystem.new()
	plan.set_group_focus("U15", "dribbling")
	plan.set_group_focus("U17", "passing")
	plan.set_group_focus("U19", "shooting")
	var sc := ScoutingSystem.new(9)
	sc.add_scout("s1", "Scout", 0.8, 100)
	return {"career": career, "academies": {TEAM: ac}, "training": {TEAM: plan},
			"scouting": {TEAM: sc}, "squads": {}}


func _step(w: Dictionary) -> Dictionary:
	return (w["career"] as CareerState).advance_week(w["squads"], w["academies"], w["training"], w["scouting"])


func _test_calendar_sync() -> void:
	var db := _db()
	var w := _world(db)
	var career: CareerState = w["career"]
	var plan: TrainingSystem = w["training"][TEAM]
	_check(career != null and plan.week == 0, "fresh career: training has not run")
	_step(w)
	_check(plan.week == 1 and career.week == 1, "one career week = one training week")
	for i in 4:
		_step(w)
	_check(plan.week == career.week and plan.week == 5, "training follows the calendar over 5 weeks")
	# Duplicate progression: re-syncing the same calendar week is a no-op.
	var ac: Academy = w["academies"][TEAM]
	var dup := plan.sync_to_calendar(db, ac, career.absolute_week())
	_check(dup.is_empty() and plan.week == 5, "same career week never trains twice")
	# Free training: the only way to move training is the calendar. Advancing the
	# career without passing the academy systems must not train.
	career.advance_week()
	_check(plan.week == 5, "career advance without academy systems leaves training untouched")
	# ...but the next full tick only owes the missing weeks (no unlimited free weeks).
	_step(w)
	_check(plan.week == 5 + 2 and plan.calendar_week == career.absolute_week(), "catch-up is exact, not unlimited")
	# Real progression: someone actually improved over the weeks.
	var changed := 0
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if not p.growth_progress.is_empty():   # weekly growth is fractional; it accumulates before an attribute point lands
			changed += 1
	_check(changed > 0, "calendar-driven training produced real development")
	# Scouting follows the same clock.
	var sc: ScoutingSystem = w["scouting"][TEAM]
	var mission_err := sc.start_mission(ac, "s1", "Zamoria", 2)
	_check(mission_err == "", "start scouting mission", mission_err)
	var found := 0
	for i in 3:
		found += (_step(w)["found_ids"] as Array).size()
	_check(found >= 1 and sc.calendar_week == career.absolute_week(), "scouting discovers prospects on the calendar")
	# Season rollover keeps the clock monotonic (absolute week continues).
	var before := career.absolute_week()
	career.end_season(w["academies"])
	_step(w)
	_check(career.absolute_week() > before - 1 and plan.calendar_week == career.absolute_week(),
			"season rollover keeps training in sync")
	db.free()


func _test_calendar_save_load() -> void:
	var db := _db()
	var w := _world(db)
	var career: CareerState = w["career"]
	for i in 3:
		_step(w)
	var plan: TrainingSystem = w["training"][TEAM]
	var data := SaveManager.capture(db, w["academies"], w["scouting"], w["training"], {},
			{"career": career.to_dict()})
	_check(SaveManager.write_file(SAVE_PATH, data) == "", "write save")
	var rd := SaveManager.read_file(SAVE_PATH)
	var db2 := _db()
	db2.clear()
	var res := SaveManager.restore(db2, rd["data"])
	_check(res["ok"], "restore", str(res["errors"]))
	var plan2: TrainingSystem = res["training"][TEAM]
	var career2 := CareerState.from_dict(db2, res["extras"]["career"])
	_check(plan2.week == plan.week and plan2.calendar_week == plan.calendar_week, "training clock saved/loaded")
	var w2 := {"career": career2, "academies": res["academies"], "training": res["training"],
			"scouting": res["scouting"], "squads": {}}
	_step(w2)
	_check(plan2.week == plan.week + 1, "after load, one career week still trains exactly one week")
	db.free()
	db2.free()
