## Phase T4 validation — youth academy foundation:
##   godot --headless --path . res://tests/phaseT4_validation.tscn
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
	print("=== KING FOOTBALL — Phase T4 validation ===")
	_test_age_groups()
	_test_generation_quality()
	_test_determinism()
	_test_academy_roster()
	_test_save_load_no_duplicates()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> Node:
	var db: Node = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _test_age_groups() -> void:
	_check(AcademyConfig.group_for_age(14) == "U15", "age 14 -> U15")
	_check(AcademyConfig.group_for_age(15) == "U15", "age 15 -> U15")
	_check(AcademyConfig.group_for_age(16) == "U17", "age 16 -> U17")
	_check(AcademyConfig.group_for_age(18) == "U19", "age 18 -> U19")
	_check(AcademyConfig.group_for_age(20) == "", "age 20 is not academy age")
	_check(AcademyConfig.group_for_age(12) == "", "age 12 is not academy age")
	_check(AcademyConfig.is_eligible(17, "U17") and not AcademyConfig.is_eligible(17, "U19"), "eligibility by group")
	_check(AcademyConfig.group_ids() == ["U15", "U17", "U19"] as Array[String], "group ids ordered")


func _test_generation_quality() -> void:
	var all: Array[PlayerData] = []
	for i in range(1, 301):
		all.append(YouthGenerator.generate(7, i, "club_x", "Zamoria"))
	var valid := true
	var ids := {}
	var gap_min := 999
	var gap_max := -1
	var high_pot_low_cur := 0
	var low_pot_high_cur := 0
	var gks := 0
	var by_age := {}
	for p in all:
		if not p.validate().is_empty():
			valid = false
		ids[p.id] = true
		var gap := p.potential - p.get_overall()
		gap_min = mini(gap_min, gap)
		gap_max = maxi(gap_max, gap)
		if p.potential >= 75 and p.get_overall() < 50:
			high_pot_low_cur += 1
		if p.get_overall() >= 45 and gap <= 6:
			low_pot_high_cur += 1
		if p.position == PlayerData.Position.GK:
			gks += 1
		if not by_age.has(p.age):
			by_age[p.age] = []
		by_age[p.age].append(p.get_overall())
	_check(valid, "all 300 generated prospects validate")
	_check(ids.size() == 300, "300 unique ids")
	_check(gap_min >= 0, "potential never below current")
	_check(gap_max - gap_min >= 15, "potential gap varies widely", "%d..%d" % [gap_min, gap_max])
	_check(high_pot_low_cur > 0, "high potential does not imply high current ability")
	_check(low_pot_high_cur > 0, "decent current ability can come with low potential")
	_check(gks > 5 and gks < 80, "goalkeepers appear at a sane rate", str(gks))
	var avg := func(a: Array) -> float:
		var s := 0.0
		for v in a:
			s += v
		return s / a.size()
	_check(avg.call(by_age[19]) > avg.call(by_age[14]) + 8.0, "older prospects are better on average")
	var ages_ok := true
	for p in all:
		if AcademyConfig.group_for_age(p.age) == "":
			ages_ok = false
	_check(ages_ok, "every prospect belongs to an academy age group")
	var forced := YouthGenerator.generate(7, 999, "club_x", "Zamoria", 0.5, 16)
	_check(forced.age == 16 and forced.status == PlayerData.Status.YOUTH, "forced age + YOUTH status")
	_check(forced.traits.size() >= 1 and forced.development_history.size() == 1, "traits + history initialised")
	var hi := 0.0
	var lo := 0.0
	for i in range(1, 201):
		hi += YouthGenerator.generate(3, i, "c", "Aldoria", 1.0, 16).potential
		lo += YouthGenerator.generate(3, i, "c", "Aldoria", 0.0, 16).potential
	_check(hi > lo, "better facilities raise average potential")
	var gk_ok := true
	for p in all:
		if p.position == PlayerData.Position.GK and p.goalkeeping < p.pace:
			gk_ok = false
	_check(gk_ok, "goalkeepers have goalkeeping as best attribute")


func _test_determinism() -> void:
	var a := YouthGenerator.generate(42, 5, "club_x", "Norvland")
	var b := YouthGenerator.generate(42, 5, "club_x", "Norvland")
	var c := YouthGenerator.generate(42, 6, "club_x", "Norvland")
	_check(a.to_dict() == b.to_dict(), "same (seed,index) -> identical prospect")
	_check(a.to_dict() != c.to_dict() and a.id != c.id, "different index -> different prospect")
	var d := YouthGenerator.generate(43, 5, "club_x", "Norvland")
	_check(a.to_dict() != d.to_dict(), "different seed -> different prospect")


func _test_academy_roster() -> void:
	var db := _db()
	var ac := Academy.new("club_royal_harbor", "Aldoria", 11)
	var made := ac.generate_intake(db, 30)
	_check(made.size() == 30, "intake of 30 created", str(made.size()))
	_check(ac.roster_ids.size() == 30, "roster tracks 30 ids")
	var team: TeamData = db.get_team("club_royal_harbor")
	var in_squad := false
	for p in made:
		if p.id in team.squad_ids:
			in_squad = true
	_check(not in_squad, "prospects are not first-team squad members")
	_check(db.get_squad("club_royal_harbor").size() == 23, "first-team squad unchanged")
	var all_in_db := true
	for p in made:
		if db.get_player(p.id) != p or p.status != PlayerData.Status.YOUTH:
			all_in_db = false
	_check(all_in_db, "prospects registered in player database as YOUTH")
	var groups := 0
	for g in AcademyConfig.group_ids():
		var n := ac.group_count(db, g)
		_check(n <= AcademyConfig.capacity(g), "%s within capacity" % g, str(n))
		groups += n
	_check(groups == 30, "group counts add up to roster")
	# Fill to capacity: forced age 14 into U15 only.
	var ac2 := Academy.new("club_royal_harbor", "Aldoria", 99)
	var many := ac2.generate_intake(db, 50, 14)
	_check(many.size() == AcademyConfig.capacity("U15"), "full group rejects extra prospects", str(many.size()))
	_check(not ac2.has_room(db, "U15"), "U15 reported full")
	var names := {}
	var dup_name := false
	for p in made:
		var key := "%s|%d|%d" % [p.display_name, p.pace, p.shooting]
		if names.has(key):
			dup_name = true
		names[key] = true
	_check(not dup_name, "no identical (name+attributes) prospects")
	db.free()


func _test_save_load_no_duplicates() -> void:
	var db := _db()
	var ac := Academy.new("club_royal_harbor", "Aldoria", 5)
	ac.generate_intake(db, 10)
	var snapshot := JSON.stringify(ac.to_dict())
	var before_ids := ac.roster_ids.duplicate()
	var back := Academy.from_dict(JSON.parse_string(snapshot))
	_check(back.roster_ids == before_ids, "roster ids survive save/load")
	_check(back.next_index == ac.next_index, "next index survives save/load")
	# New intake after load must not reuse ids nor clone existing prospects.
	var more := back.generate_intake(db, 5)
	_check(more.size() == 5, "post-load intake works")
	var seen := {}
	var dup := false
	for pid in back.roster_ids:
		if seen.has(pid):
			dup = true
		seen[pid] = true
	_check(not dup and back.roster_ids.size() == 15, "no duplicate ids after load + intake")
	for pid in before_ids:
		if not (pid in back.roster_ids):
			dup = true
	_check(not dup, "original prospects preserved")
	db.free()
