## Career phase C2 (facilities + staff): upgrades through the ledger, build time, upkeep, staff market / hire / fire, real effects.
##   godot --headless --path . res://tests/club_ops_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Facilities and staff validation (C2.5 / C2.6) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_facilities()
	_test_staff()
	await _test_weekly_and_effects()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_facilities() -> void:
	var c: CareerState = app.career
	var f := Facilities.new()
	var l := c.ledger()
	l.opening_balance = 3_000_000
	l.balance = 3_000_000
	l.entries.clear()
	var before := l.balance
	_check(f.upgrade(l, "clinic", 1, 70) == "" and l.balance == before - Facilities.cost_of(2), "an upgrade charges its cost through the ledger")
	_check(f.level("clinic") == 1 and f.is_building("clinic"), "...and the level only rises when the build is done")
	_check(f.upgrade(l, "clinic", 1, 70) == "FAC_ERR_BUSY", "a facility cannot be upgraded twice at once")
	_check(f.upgrade(l, "castle", 1, 70) == "FAC_ERR_UNKNOWN", "an unknown facility is refused")
	var weeks := Facilities.build_weeks(2)
	var done: Array = []
	for i in weeks:
		done = f.weekly(l, 2 + i)
	_check(f.level("clinic") == 2 and done == ["clinic"], "the upgrade completes after %d weeks" % weeks)
	_check(l.balance < before - Facilities.cost_of(2), "upkeep is paid every week")
	_check(l.is_consistent(), "the ledger stays consistent")
	var poor := FinanceLedger.new("x", 1000, 0, 0)
	_check(Facilities.new().upgrade(poor, "stadium", 1, 90, true) == "FAC_ERR_MONEY", "an upgrade the club cannot pay is refused")
	var rich := FinanceLedger.new("y", 1_000_000, 0, 0)
	var big := Facilities.new()
	big.levels["training"] = 4
	_check(big.upgrade(rich, "training", 1, 40) == "FAC_ERR_BOARD", "an expensive upgrade needs the board when trust is low")
	_check(big.upgrade(rich, "training", 1, 40, true) == "" or big.upgrade(rich, "training", 1, 40, true) == "FAC_ERR_MONEY", "...and goes ahead with approval (if affordable)")
	var top := Facilities.new()
	top.levels["stadium"] = 5
	_check(top.upgrade(rich, "stadium", 1, 90, true) == "FAC_ERR_MAX", "level 5 is the maximum")
	var maxed := Facilities.new()
	for k in Facilities.KINDS:
		maxed.levels[k] = 5
	_check(maxed.injury_factor() < 1.0 and maxed.recovery_factor() < 1.0 and maxed.development_factor() > 1.0 and maxed.matchday_factor() > 1.0, "better facilities have real effects")
	_check(Facilities.new().injury_factor() == 1.0 and Facilities.new().development_factor() == 1.0, "level 1 is neutral")
	var back := Facilities.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	_check(back.level("clinic") == 2, "facilities are saved")
	_check(Facilities.from_dict({"levels": {"clinic": 99, "bogus": 3}}).level("clinic") == 5, "damaged data is clamped")
	var ai_f := Facilities.new()
	var ai_l := FinanceLedger.new("ai", 50_000_000, 0, 0)
	var started := ""
	for i in 12:
		started = Facilities.ai_develop(ai_f, ai_l, 1, i)
		if started != "":
			break
	_check(started != "" and ai_l.balance < 50_000_000, "an AI club develops its facilities with the same costs")


func _test_staff() -> void:
	var c: CareerState = app.career
	var cand := StaffTeam.market("fitness_coach", 1, 7)
	_check(cand.size() == 4 and cand == StaffTeam.market("fitness_coach", 1, 7), "the staff market is deterministic")
	_check(StaffTeam.market("fitness_coach", 2, 7) != cand, "...and changes with the season")
	var team := StaffTeam.new()
	var ledger := FinanceLedger.new("s", 1_000_000, 0, 1_000_000)
	_check(team.hire(cand[0], 1, ledger, 1) == "" and team.skill("fitness_coach") == int(cand[0]["skill"]), "a candidate can be hired")
	_check(team.hire(cand[1], 1, ledger, 1) == "STAFF_ERR_FILLED", "a post can hold one person")
	for r in ["doctor", "assistant", "chief_scout"]:
		team.hire(StaffTeam.market(r, 1, 7)[0], 1, ledger, 1)
	_check(team.members.size() == 4 and team.hire(StaffTeam.market("youth_coach", 1, 7)[0], 1, ledger, 1) == "STAFF_ERR_FULL", "the staff size is limited by the training centre")
	_check(team.hire(StaffTeam.market("youth_coach", 1, 7)[0], 3, ledger, 1) == "", "a better training centre allows more staff")
	var tight := FinanceLedger.new("t", 1_000_000, 0, 100)
	_check(StaffTeam.new().hire(StaffTeam.market("doctor", 1, 7)[0], 1, tight, 1) == "STAFF_ERR_BUDGET", "the wage budget is respected")
	var bal := ledger.balance
	var wage := int(team.member_for("doctor")["wage"])
	_check(team.fire("doctor", ledger, 2) == "" and ledger.balance == bal - wage * StaffTeam.FIRING_WEEKS and team.skill("doctor") == 0, "firing pays compensation")
	_check(team.fire("doctor", ledger, 2) == "STAFF_ERR_EMPTY", "an empty post cannot be fired")
	var good := StaffTeam.new()
	var bad := StaffTeam.new()
	var g: Dictionary = StaffTeam.market("fitness_coach", 1, 7)[0]
	g["skill"] = 18
	var b: Dictionary = g.duplicate()
	b["skill"] = 6
	good.hire(g, 1, null, 1)
	bad.hire(b, 1, null, 1)
	_check(good.injury_factor() < bad.injury_factor() and bad.injury_factor() < 1.0 and StaffTeam.new().injury_factor() == 1.0, "a better fitness coach lowers injuries more; an empty post is neutral")
	var ass: Dictionary = StaffTeam.market("assistant", 1, 7)[0]
	ass["skill"] = 20
	var star := StaffTeam.new()
	star.hire(ass, 1, null, 1)
	_check(star.assistant_quality() == 1.0 and StaffTeam.new().assistant_quality() < 0.5, "the assistant sets the delegation quality")
	_check(StaffTeam.from_dict(JSON.parse_string(JSON.stringify(team.to_dict()))).members.size() == team.members.size(), "staff is saved")
	var leaving := StaffTeam.new()
	var short: Dictionary = StaffTeam.market("doctor", 1, 7)[0]
	short["years"] = 1
	leaving.hire(short, 1, null, 1)
	_check(leaving.season_end() == ["doctor"] and leaving.members.is_empty(), "a contract that ends frees the post")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_weekly_and_effects() -> void:
	var c: CareerState = app.career
	var cand: Dictionary = StaffTeam.market("assistant", c.season, 3)[0]
	cand["skill"] = 20
	c.ledger().wage_budget = 10_000_000
	c.ledger().opening_balance += 0
	c.staff.hire(cand, 1, c.ledger(), c.week)
	c.facilities.upgrade(c.ledger(), "stadium", c.week, 90, true)
	var bal := c.ledger().balance
	await app.advance_week_async()
	_check(c.delegation.quality == 1.0, "the career week applies the assistant's quality to delegation")
	_check(c.ledger().balance != bal and c.ledger().is_consistent(), "staff wages and upkeep are booked in the weekly step")
	# measured effect on injuries: a 20-skill fitness coach + doctor vs none over many weekly rolls on the same squad
	var squad: Array = app.db.get_squad(c.club_id)
	var counts := {}
	for mode in ["none", "staff"]:
		c.staff = StaffTeam.new()
		if mode == "staff":
			for role in ["fitness_coach", "doctor"]:
				var m: Dictionary = StaffTeam.market(role, 1, 5)[0]
				m["skill"] = 20
				c.staff.members.append(m)
		var n := 0
		for w in 400:
			for p: PlayerData in squad:
				if p.status != PlayerData.Status.ACTIVE:
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(["inj", w, p.id])
				if rng.randf() < Availability.injury_probability(p, 0, true) * c.injury_factor_for(c.club_id):
					n += 1
		counts[mode] = n
	_check(counts["staff"] < counts["none"], "a strong fitness coach lowers the injury count over 400 weeks of rolls", str(counts))
	c.staff = StaffTeam.new()
	_check(c.injury_factor_for("club_royal_harbor") == 1.0, "other clubs are unaffected")
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.facilities.queue.size() == c.facilities.queue.size(), "facilities and staff survive the career save")
