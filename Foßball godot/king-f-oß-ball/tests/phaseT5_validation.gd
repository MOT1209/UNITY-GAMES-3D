## Phase T5 validation — scouting, training, progression:
##   godot --headless --path . res://tests/phaseT5_validation.tscn
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
	print("=== KING FOOTBALL — Phase T5 validation ===")
	_test_progression_pure()
	_test_potential_cap()
	_test_training_system()
	_test_scouting_missions()
	_test_scouting_reliability()
	_test_signing_and_save()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _youth(age := 15, pot_gap := 30) -> PlayerData:
	var p := YouthGenerator.generate(1, 1, "c", "Aldoria", 0.5, age)
	p.traits = []
	p.potential = mini(95, p.get_overall() + pot_gap)
	return p


func _test_progression_pure() -> void:
	var p := _youth(15)
	_check(ProgressionModel.age_factor(14) > ProgressionModel.age_factor(19), "younger players grow faster")
	_check(ProgressionModel.age_factor(40) >= ProgressionModel.MIN_AGE_FACTOR, "age factor floor")
	var w := ProgressionModel.weekly_points(p, "pace", 0.5, 0.6)
	_check(w > 0.0 and w < 1.0, "weekly gain is fractional (gradual)", str(w))
	_check(ProgressionModel.weekly_points(p, "nonsense", 0.5, 0.6) == 0.0, "unknown attribute -> no gain")
	_check(ProgressionModel.weekly_points(p, "pace", 0.5, 0.0) == 0.0, "zero intensity -> no gain")
	var fast := _youth(15); fast.traits = ["Fast Learner"]
	_check(ProgressionModel.weekly_points(fast, "pace", 0.5, 0.6) > w, "Fast Learner trains faster")
	_check(ProgressionModel.weekly_points(p, "pace", 1.0, 0.6) > ProgressionModel.weekly_points(p, "pace", 0.0, 0.6),
			"better facilities train faster")
	var old := _youth(19)
	old.potential = old.get_overall() + 30
	var young := _youth(14)
	young.potential = young.get_overall() + 30
	young.pace = 40; old.pace = 40
	_check(ProgressionModel.weekly_points(young, "pace", 0.5, 0.6) > ProgressionModel.weekly_points(old, "pace", 0.5, 0.6),
			"age slows growth at equal rating")
	var tired := _youth(15); tired.fitness = 50
	_check(ProgressionModel.weekly_points(tired, "pace", 0.5, 0.6) < w, "low fitness slows growth")
	var lb := _youth(15); lb.traits = ["Late Bloomer"]
	var lb_old := _youth(19); lb_old.traits = ["Late Bloomer"]
	_check(ProgressionModel.weekly_points(lb, "pace", 0.5, 0.6) < w, "Late Bloomer slow when young")
	var report := ProgressionModel.development_report(p)
	_check(report["overall"] == p.get_overall() and report.has("attribute_gains"), "development report shape")


func _test_potential_cap() -> void:
	var p := _youth(15, 6)
	var cap := p.potential
	for week in range(1, 400):
		ProgressionModel.train_week(p, ["pace", "shooting", "passing", "dribbling", "defending", "physical"][week % 6], 1.0, 1.0, week)
	_check(p.get_overall() <= cap, "overall never exceeds potential", "%d > %d" % [p.get_overall(), cap])
	var ok := true
	for a in PlayerData.ATTRIBUTES:
		if p.get_attribute(a) > 99:
			ok = false
	_check(ok, "attributes never exceed 99")
	_check(p.validate().is_empty(), "trained player still validates")
	var g := _youth(15, 40)
	g.pace = 98
	g.potential = 99
	for week in range(1, 300):
		ProgressionModel.train_week(g, "pace", 1.0, 1.0, week)
	_check(g.pace <= 99, "single attribute capped at 99")
	var maxed := _youth(15, 0)
	var before := maxed.get_overall()
	for week in range(1, 100):
		ProgressionModel.train_week(maxed, "pace", 1.0, 1.0, week)
	_check(maxed.get_overall() == before, "player at potential does not improve")


func _test_training_system() -> void:
	var db := _db()
	var ac := Academy.new("club_royal_harbor", "Aldoria", 3)
	ac.generate_intake(db, 12)
	var plan := TrainingSystem.new()
	_check(plan.set_group_focus("U15", "pace") == "", "set group focus")
	_check(plan.set_group_focus("U99", "pace") != "", "unknown group rejected")
	_check(plan.set_group_focus("U15", "kicking") != "", "unknown category rejected")
	var target: PlayerData = null
	for p in ac.group_players(db, "U15"):
		target = p
		break
	if target == null:
		target = db.get_player(ac.roster_ids[0])
	_check(plan.set_individual_focus(db, target.id, "shooting") == "", "individual focus")
	_check(plan.focus_for(target) == "shooting", "individual focus overrides group focus")
	_check(plan.set_individual_focus(db, "ghost", "pace") != "", "unknown player rejected")
	plan.set_individual_focus(db, target.id, "")
	_check(plan.focus_for(target) == plan.group_focus.get(AcademyConfig.group_for_age(target.age), ""), "focus reset falls back to group")
	plan.set_intensity(5.0)
	_check(plan.intensity == 1.0, "intensity clamped")
	plan.set_intensity(0.7)
	# 30 weeks of pace training for U15; others rest.
	var snapshot := {}
	for pid in ac.roster_ids:
		snapshot[pid] = db.get_player(pid).to_dict()
	var gained_total := 0
	for i in 30:
		gained_total += plan.advance_week(db, ac).size()
	_check(plan.week == 30, "week counter advances")
	var u15_grew := false
	var untouched_ok := true
	var shooting_unchanged := true
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		var old: Dictionary = snapshot[pid]
		if AcademyConfig.group_for_age(p.age) == "U15":
			if p.pace > int(old["pace"]):
				u15_grew = true
			if p.shooting != int(old["shooting"]):
				shooting_unchanged = false
		else:
			for a in PlayerData.ATTRIBUTES:
				if p.get_attribute(a) != int(old[a]):
					untouched_ok = false
	_check(u15_grew or ac.group_count(db, "U15") == 0, "focused group improves pace")
	_check(shooting_unchanged, "unfocused attributes unchanged")
	_check(untouched_ok, "groups without a plan do not develop")
	_check(gained_total < 30 * 12, "growth is gradual, not every week for everyone")
	# Fitness: intensity 1.0 tires, 0.0 recovers
	var q := _youth(15)
	q.fitness = 80
	ProgressionModel.train_week(q, "pace", 0.5, 1.0, 1)
	_check(q.fitness < 80, "full intensity costs fitness")
	q.fitness = 80
	ProgressionModel.train_week(q, "pace", 0.5, 0.0, 1)
	_check(q.fitness > 80, "light training recovers fitness")
	# History + report
	var some := db.get_player(ac.roster_ids[0])
	var rep := ProgressionModel.development_report(some)
	_check(rep["player_id"] == some.id, "report for academy player")
	# Age up
	var ages_before := {}
	for pid in ac.roster_ids:
		ages_before[pid] = db.get_player(pid).age
	var out := plan.age_up(db, ac)
	var aged := true
	for pid in ac.roster_ids:
		if db.get_player(pid).age != int(ages_before[pid]) + 1:
			aged = false
	_check(aged, "age_up adds a year to everyone")
	var out_ok := true
	for pid in out:
		if AcademyConfig.group_for_age(db.get_player(pid).age) != "":
			out_ok = false
	_check(out_ok, "aged-out list only contains over-age players")
	var back := TrainingSystem.from_dict(JSON.parse_string(JSON.stringify(plan.to_dict())))
	_check(back.group_focus == plan.group_focus and back.week == plan.week, "training plan save/load")
	db.free()


func _scouting_fixture(db: TeamDatabase, budget := 1000000) -> Array:
	var ac := Academy.new("club_royal_harbor", "Aldoria", 21)
	ac.budget = budget
	var sc := ScoutingSystem.new(77)
	sc.add_scout("s_good", "Good Scout", 0.95, 1000)
	sc.add_scout("s_bad", "Bad Scout", 0.05, 200)
	return [ac, sc]


func _test_scouting_missions() -> void:
	var db := _db()
	var fx := _scouting_fixture(db)
	var ac: Academy = fx[0]
	var sc: ScoutingSystem = fx[1]
	_check(sc.add_scout("s_good", "dup", 0.5, 1) != "", "duplicate scout rejected")
	_check(sc.add_scout("x", "bad", 2.0, 1) != "", "invalid scout quality rejected")
	_check(sc.start_mission(ac, "nobody", "Zamoria", 2) != "", "unknown scout rejected")
	_check(sc.start_mission(ac, "s_good", "Atlantis", 2) != "", "unknown region rejected")
	_check(sc.start_mission(ac, "s_good", "Zamoria", 0) != "", "zero-week mission rejected")
	_check(sc.start_mission(ac, "s_good", "Zamoria", 99) != "", "too-long mission rejected")
	var b0 := ac.budget
	_check(sc.start_mission(ac, "s_good", "Zamoria", 3) == "", "start mission")
	_check(ac.budget == b0 - 3000, "mission cost charged", str(ac.budget))
	_check(sc.start_mission(ac, "s_good", "Norvland", 1) != "", "busy scout rejected")
	var poor := Academy.new("club_royal_harbor", "Aldoria", 1)
	poor.budget = 100
	_check(sc.start_mission(poor, "s_bad", "Zamoria", 2) != "", "insufficient budget rejected")
	_check(poor.budget == 100, "failed mission charges nothing")
	_check(sc.advance_week(db, ac).is_empty() and sc.advance_week(db, ac).is_empty(), "no discoveries before completion")
	var found := sc.advance_week(db, ac)
	_check(found.size() >= 1, "mission completes with discoveries", str(found.size()))
	_check(sc.missions.is_empty(), "completed mission removed")
	_check(sc.history.size() == found.size(), "discovery history recorded")
	var rep_ok := true
	var country_ok := true
	for pid in found:
		var r: Dictionary = sc.reports[pid]
		if r["estimate"] < 1 or r["estimate"] > 99 or r["margin"] <= 0:
			rep_ok = false
		if db.get_player(pid).nationality != "Zamoria" or db.get_player(pid).team_id != "":
			country_ok = false
	_check(rep_ok, "reports have estimate and margin")
	_check(country_ok, "prospects come from the scouted region and are unowned")
	var not_in_academy := true
	for pid in found:
		if pid in ac.roster_ids:
			not_in_academy = false
	_check(not_in_academy, "discovered prospects are not in the academy yet")
	_check(sc.is_scout_busy("s_good") == false, "scout free after mission")
	db.free()


func _test_scouting_reliability() -> void:
	var db := _db()
	var fx := _scouting_fixture(db, 100000000)
	var ac: Academy = fx[0]
	var good_err := 0.0
	var bad_err := 0.0
	var good_n := 0
	var bad_n := 0
	var good_margin := 0
	var bad_margin := 0
	for round_i in 12:
		var sc := ScoutingSystem.new(1000 + round_i)
		sc.add_scout("g", "G", 0.95, 10)
		sc.add_scout("b", "B", 0.05, 10)
		var gid := Academy.new("club_g%d" % round_i, "Aldoria", 1)
		gid.budget = 1000000
		var bid := Academy.new("club_b%d" % round_i, "Aldoria", 1)
		bid.budget = 1000000
		sc.start_mission(gid, "g", "Solmara", 6)
		sc.start_mission(bid, "b", "Solmara", 6)
		var fac := Academy.new("club_r%d" % round_i, "Aldoria", 1)   # unique ids per round
		for w in 6:
			sc.advance_week(db, fac)
		for h in sc.history:
			var pid: String = h["player_id"]
			var err := absf(sc.reports[pid]["estimate"] - db.get_player(pid).potential)
			if h["scout_id"] == "g":
				good_err += err
				good_n += 1
				good_margin = sc.reports[pid]["margin"]
			else:
				bad_err += err
				bad_n += 1
				bad_margin = sc.reports[pid]["margin"]
	_check(good_n > 0 and bad_n > 0, "both scouts produced reports", "%d/%d" % [good_n, bad_n])
	_check(good_err / maxf(good_n, 1) < bad_err / maxf(bad_n, 1),
			"high-quality scout estimates are more accurate", "%.1f vs %.1f" % [good_err / maxf(good_n, 1), bad_err / maxf(bad_n, 1)])
	_check(good_margin < bad_margin, "high-quality scout reports a tighter margin")
	db.free()


func _test_signing_and_save() -> void:
	var db := _db()
	var fx := _scouting_fixture(db)
	var ac: Academy = fx[0]
	var sc: ScoutingSystem = fx[1]
	sc.start_mission(ac, "s_good", "Solmara", 2)
	sc.advance_week(db, ac)
	var found := sc.advance_week(db, ac)
	_check(found.size() > 0, "mission produced prospects")
	var pid := found[0]
	var snapshot := JSON.stringify(sc.to_dict())
	var back := ScoutingSystem.from_dict(JSON.parse_string(snapshot))
	_check(back.pool == sc.pool and back.next_index == sc.next_index, "scouting state save/load")
	_check(back.reports.size() == sc.reports.size(), "reports survive save/load")
	var b0 := ac.budget
	var cost := sc.signing_cost(db.get_player(pid))
	var group := AcademyConfig.group_for_age(db.get_player(pid).age)
	var err := sc.sign_prospect(db, ac, pid)
	_check(err == "", "sign prospect", err)
	_check(ac.budget == b0 - cost, "signing cost charged")
	_check(pid in ac.roster_ids and not (pid in sc.pool), "prospect moved from pool to academy")
	_check(db.get_player(pid).team_id == "club_royal_harbor", "prospect now owned by the club")
	_check(sc.sign_prospect(db, ac, pid) != "", "cannot sign twice")
	_check(sc.sign_prospect(db, ac, "ghost") != "", "unknown prospect rejected")
	if found.size() > 1:
		var poor := Academy.new("club_royal_harbor", "Aldoria", 1)
		poor.budget = 10
		_check(sc.sign_prospect(db, poor, found[1]) != "", "signing needs budget")
	# after load, new missions do not reuse ids
	back.start_mission(ac, "s_good", "Solmara", 1)
	var more := back.advance_week(db, ac)
	var clash := false
	for m in more:
		if m in found:
			clash = true
	_check(not clash and more.size() > 0, "post-load discoveries use fresh ids")
	_check(group != "", "signed prospect has an age group")
	db.free()
