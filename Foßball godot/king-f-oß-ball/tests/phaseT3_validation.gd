## Phase T3 validation — formations, squad management, tactics:
##   godot --headless --path . res://tests/phaseT3_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var db: TeamDatabase


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase T3 validation ===")
	db = load("res://scripts/core/team_database.gd").new()
	db.reload()
	_test_formations()
	_test_auto_pick()
	_test_assignment()
	_test_substitution()
	_test_validation_failures()
	_test_tactics()
	_test_roundtrip()
	db.free()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_formations() -> void:
	for want in ["4-3-3", "4-4-2", "4-2-3-1", "3-5-2", "5-3-2", "4-1-4-1"]:
		_check(FormationData.is_valid(want), "formation %s exists" % want)
	for fid in FormationData.ids():
		var sl := FormationData.slots(fid)
		_check(sl.size() == 11, "%s has 11 slots" % fid)
		_check(FormationData.slot_position(fid, 0) == PlayerData.Position.GK, "%s slot 0 is GK" % fid)
		var parts := fid.split("-")
		var outfield := 0
		for n in parts:
			outfield += int(n)
		_check(outfield == 10, "%s numbers add to 10" % fid)
		var in_range := true
		for s in sl:
			if absf(s[1]) > 1.0 or s[2] < 0.0 or s[2] > 1.0:
				in_range = false
		_check(in_range, "%s slot coordinates in range" % fid)
	_check(FormationData.position_fit(PlayerData.Position.ST, PlayerData.Position.ST) == 1.0, "exact fit = 1.0")
	_check(FormationData.position_fit(PlayerData.Position.GK, PlayerData.Position.CB) == 0.0, "GK cannot play outfield")


func _test_auto_pick() -> void:
	for fid in FormationData.ids():
		var sq := Squad.new("club_royal_harbor", fid)
		sq.auto_pick(db)
		var errs := sq.validate(db)
		_check(errs.is_empty(), "auto_pick valid for %s" % fid, str(errs))
		_check(sq.bench.size() == 7, "bench filled for %s" % fid)
		_check(sq.starting.size() + sq.bench.size() + sq.reserves.size() >= 11 + 7, "all players placed")
	var sq2 := Squad.new("club_royal_harbor")
	sq2.auto_pick(db)
	_check(sq2.captain_id != "" and sq2.captain_id in sq2.starting, "default captain is a starter")
	var total := sq2.starting.size() + sq2.bench.size() + sq2.reserves.size()
	_check(total == 11 + 7 + 5, "23 players split 11/7/5", str(total))


func _test_assignment() -> void:
	var sq := Squad.new("club_royal_harbor")
	sq.auto_pick(db)
	var a := sq.starting[2]
	var b := sq.starting[3]
	# Move player a into slot 3: must leave slot 2 (no duplicate positions).
	_check(sq.assign_starter(db, 3, a) == "", "assign starter to another slot")
	var count := 0
	for pid in sq.starting:
		if pid == a:
			count += 1
	_check(count == 1, "player cannot hold two slots")
	_check(sq.starting[2] == "", "previous slot freed")
	_check(sq.contains(b), "displaced player kept in squad")
	_check(sq.validate(db).size() > 0, "XI with empty slot is invalid")
	# Fill again
	sq.auto_pick(db)
	_check(sq.assign_starter(db, 0, sq.starting[5]) != "", "outfielder cannot take GK slot")
	_check(sq.assign_starter(db, 5, sq.starting[0]) != "", "goalkeeper cannot take outfield slot")
	_check(sq.assign_starter(db, 11, sq.starting[1]) != "", "slot out of range rejected")
	_check(sq.assign_starter(db, 1, "nobody") != "", "unknown player rejected")
	_check(sq.assign_starter(db, 1, "plr_ngu_05") != "", "other team's player rejected")
	_check(sq.set_formation("9-9-9") != "", "unknown formation rejected")
	_check(sq.set_formation("4-4-2") == "" and sq.formation_id == "4-4-2", "formation change")
	_check(sq.set_captain(sq.bench[0]) != "", "captain must be a starter")
	_check(sq.set_captain(sq.starting[4]) == "", "set captain")
	_check(sq.set_set_piece_taker("penalty", sq.starting[9]) == "", "set penalty taker")
	_check(sq.set_set_piece_taker("throw", sq.starting[9]) != "", "unknown set piece rejected")
	_check(sq.set_set_piece_taker("corner", sq.reserves[0]) != "", "taker must be starter")
	# Injured player cannot be assigned
	var inj: PlayerData = db.get_player(sq.reserves[0])
	inj.status = PlayerData.Status.INJURED
	_check(sq.add_to_bench(db, inj.id) != "", "injured player unavailable")
	inj.status = PlayerData.Status.ACTIVE


func _test_substitution() -> void:
	var sq := Squad.new("club_royal_harbor")
	sq.auto_pick(db)
	sq.set_captain(sq.starting[6])
	sq.set_set_piece_taker("penalty", sq.starting[6])
	var out_pid := sq.starting[6]
	var in_pid := ""
	for pid in sq.bench:
		if db.get_player(pid).position != PlayerData.Position.GK:
			in_pid = pid
			break
	_check(sq.substitute(db, 6, in_pid) == "", "substitution succeeds")
	_check(sq.starting[6] == in_pid and out_pid in sq.bench, "players swapped")
	_check(sq.captain_id == in_pid, "captaincy passes to substitute")
	_check(sq.set_pieces["penalty"] == in_pid, "set-piece role passes to substitute")
	_check(sq.validate(db).is_empty(), "squad valid after substitution")
	_check(sq.substitute(db, 6, "ghost") != "", "non-bench substitute rejected")
	var gk_bench := ""
	for pid in sq.bench:
		if db.get_player(pid).position == PlayerData.Position.GK:
			gk_bench = pid
	if gk_bench != "":
		_check(sq.substitute(db, 6, gk_bench) != "", "GK cannot replace outfielder")
		_check(sq.substitute(db, 0, gk_bench) == "", "GK replaces GK")
	var full := Squad.new("club_royal_harbor")
	full.auto_pick(db)
	_check(full.add_to_bench(db, full.reserves[0]) != "", "bench capacity enforced")


func _test_validation_failures() -> void:
	var sq := Squad.new("club_royal_harbor")
	sq.auto_pick(db)
	sq.bench.append(sq.starting[3])   # forced duplicate
	_check(not sq.validate(db).is_empty(), "duplicate across XI/bench detected")
	sq.bench.erase(sq.starting[3])
	sq.captain_id = sq.reserves[0] if not sq.reserves.is_empty() else "x"
	_check(not sq.validate(db).is_empty(), "captain outside XI detected")


func _test_tactics() -> void:
	var t := TacticsPreset.new()
	_check(t.validate().is_empty(), "default tactics valid")
	t.pressing = 150
	_check(not t.validate().is_empty(), "pressing out of range rejected")
	t.pressing = 50
	var base := t.target_position("4-3-3", 9)
	t.mentality = TacticsPreset.Mentality.ULTRA_ATTACKING
	_check(t.target_position("4-3-3", 9).y > base.y, "attacking mentality pushes striker forward")
	t.mentality = TacticsPreset.Mentality.BALANCED
	var cb_base := t.target_position("4-3-3", 2)
	t.defensive_line = 100
	_check(t.target_position("4-3-3", 2).y > cb_base.y, "high line moves defenders up")
	var gk_before := t.target_position("4-3-3", 0)
	t.defensive_line = 0
	_check(t.target_position("4-3-3", 0).y == gk_before.y, "defensive line does not move the goalkeeper")
	var low := TacticsPreset.new(); low.pressing = 0
	var high := TacticsPreset.new(); high.pressing = 100
	_check(high.press_distance() > low.press_distance(), "higher pressing = larger trigger distance")
	_check(t.target_position("4-3-3", 9, 1.0).y > t.target_position("4-3-3", 9, 0.0).y, "team shifts with ball progress")
	var sq := Squad.new("club_royal_harbor")
	var p2 := TacticsPreset.new(); p2.preset_name = "Park the bus"; p2.mentality = TacticsPreset.Mentality.ULTRA_DEFENSIVE
	_check(sq.save_preset(p2) == "" and sq.presets.size() == 2, "save second preset")
	var p2b := TacticsPreset.new(); p2b.preset_name = "Park the bus"; p2b.pressing = 10
	sq.save_preset(p2b)
	_check(sq.presets.size() == 2, "same-name preset overwrites")
	_check(sq.select_preset("Park the bus") and sq.get_tactics().pressing == 10, "select preset")
	_check(not sq.select_preset("nope"), "unknown preset rejected")
	var bad := TacticsPreset.new(); bad.preset_name = ""
	_check(sq.save_preset(bad) != "", "invalid preset not saved")


func _test_roundtrip() -> void:
	var sq := Squad.new("club_royal_harbor", "4-2-3-1")
	sq.auto_pick(db)
	var p2 := TacticsPreset.new(); p2.preset_name = "Press"; p2.pressing = 90
	sq.save_preset(p2)
	sq.select_preset("Press")
	var back := Squad.from_dict(JSON.parse_string(JSON.stringify(sq.to_dict())))
	_check(back.to_dict() == sq.to_dict(), "squad JSON round-trip identical")
	_check(back.validate(db).is_empty(), "restored squad valid")
