## KING Player Development System: coaching staff, plans, weekly engine, youth fixes, persistence, calendar catch-up.
##   godot --headless --path . res://tests/player_development_validation.tscn
extends Node

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
	print("=== KING FOOTBALL — Player development validation ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	db = get_node("/root/TeamDB")
	_test_coach_quality()
	_test_recruitment()
	_test_contracts()
	_test_plans()
	_test_engine()
	_test_catch_up()
	_test_youth()
	_test_persistence()
	await _test_ui()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _coach(dept: String, overall: int, spec := "") -> Dictionary:
	var s := CoachingStaff.new(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = overall
	var c := s.generate_candidate(dept, rng, 0)
	for k in ["overall", "technical", "tactical", "youth", "pro"]:
		c[k] = overall
	if spec != "":
		c["specialization"] = spec
	c["salary"] = CoachingStaff.salary_demand(c)
	return c


func _test_coach_quality() -> void:
	_check(DevConfig.stars(1) == 1 and DevConfig.stars(4) == 1 and DevConfig.stars(5) == 2 and DevConfig.stars(13) == 4 and DevConfig.stars(20) == 5, "five star bands over the 1..20 rating")
	var s := CoachingStaff.new(3)
	var vacant := s.dept_multiplier("attacking")
	s.coaches = [_coach("attacking", 3)]
	var low := s.dept_multiplier("attacking")
	s.coaches = [_coach("attacking", 19)]
	var high := s.dept_multiplier("attacking")
	_check(vacant < low and low < high, "vacant < beginner < elite department multiplier", "%.3f %.3f %.3f" % [vacant, low, high])
	_check(vacant >= 0.75 and high <= DevConfig.DEPT_MULT_CAP, "multipliers stay inside the configured bounds")
	s.coaches = [_coach("attacking", 20), _coach("attacking", 20), _coach("attacking", 20)]
	_check(s.dept_multiplier("attacking", "pro", "shooting") <= DevConfig.DEPT_MULT_CAP + 0.0001, "several elite coaches cannot exceed the cap")
	s.coaches = [_coach("attacking", 10, "finishing")]
	_check(s.dept_multiplier("attacking", "pro", "shooting") > s.dept_multiplier("attacking", "pro", "pace"), "a matching specialisation helps the trained attribute")
	var youth := _coach("midfield", 10)
	youth["youth"] = 18
	youth["pro"] = 4
	s.coaches = [youth]
	_check(s.dept_multiplier("midfield", "youth") > s.dept_multiplier("midfield", "pro"), "a youth specialist helps academy players more than professionals")
	s.coaches = []
	_check(s.academy_factor() < 1.0 and s.vacancies().size() == 6, "an empty staff slows academy development but the factor stays positive")
	_check(s.attribute_multiplier("goalkeeping") > 0.5, "development still works with every department vacant")


func _test_recruitment() -> void:
	var s := CoachingStaff.new(11)
	s.refresh_market(1)
	_check(s.market.size() == DevConfig.MARKET_PER_DEPT * 6, "market has candidates for every department", str(s.market.size()))
	var ids := {}
	for c in s.market:
		ids[c["id"]] = true
	_check(ids.size() == s.market.size(), "candidate ids are unique")
	_check(s.browse("goalkeeping").size() == DevConfig.MARKET_PER_DEPT, "department filter")
	var any: Dictionary = s.market[0]
	_check(s.browse("", str(any["name"]).substr(0, 3).to_upper()).has(any), "name search is case-insensitive")
	var best := s.browse("attacking")
	_check(int(best[0]["overall"]) >= int(best[-1]["overall"]), "browse sorts by rating")
	var s2 := CoachingStaff.new(11)
	s2.refresh_market(1)
	_check(s2.market[0]["name"] == s.market[0]["name"] and s2.market[0]["overall"] == s.market[0]["overall"], "the same seed gives the same candidates")
	var before := s.market.size()
	s.refresh_market(2)
	_check(s.market.size() == before, "market is not refreshed before the interval")
	var old_ids: Array = s.market.map(func(c: Dictionary) -> String: return c["id"])
	s.refresh_market(1 + DevConfig.MARKET_MAX_AGE_WEEKS + 5)
	var fresh := s.market.filter(func(c: Dictionary) -> bool: return not (c["id"] in old_ids))
	_check(fresh.size() == s.market.size(), "after the maximum age every old candidate has left and new ones arrived")
	var salaries := s.market.map(func(c: Dictionary) -> int: return int(c["salary"]))
	_check(salaries.min() < salaries.max(), "candidates have varied salary expectations")


func _test_contracts() -> void:
	var s := CoachingStaff.new(5)
	s.refresh_market(1)
	var l := FinanceLedger.new("t", 5_000_000, 0, 0)
	var cand: Dictionary = s.browse("midfield")[0]
	var id: String = cand["id"]
	var low := s.negotiate(id, int(cand["salary"] * 0.3), 3)
	_check(not low["accepted"] and low["reply"] == "DEV_NEG_REFUSE", "a lowball salary is refused")
	var mid := s.negotiate(id, int(CoachingStaff.min_acceptable(cand, 3) * 0.9), 3)
	_check(not mid["accepted"] and mid["reply"] == "DEV_NEG_COUNTER" and int(mid["counter_salary"]) == CoachingStaff.min_acceptable(cand, 3), "a near offer gets a counter")
	_check(CoachingStaff.min_acceptable(cand, 5) <= CoachingStaff.min_acceptable(cand, 1), "a longer contract lowers the asking salary")
	var r := s.hire(id, int(low["min_salary"]) - 10, 3, 1, l, 1, 1)
	_check(not r["ok"] and s.coaches.is_empty(), "hire refuses an offer under his price")
	var wage := int(low["min_salary"])
	r = s.hire(id, wage, 3, 1, l, 1, 1)
	_check(r["ok"] and s.coaches.size() == 1 and s.candidate(id).is_empty(), "hire moves the candidate to the staff")
	var coach: Dictionary = s.coaches[0]
	_check(int(coach["expiry_season"]) == 3 and CoachingStaff.years_left(coach, 1) == 3 and l.balance == 5_000_000 - wage * DevConfig.SIGNING_WEEKS, "contract expiry and signing bonus")
	var second: Dictionary = s.browse("midfield")[0]
	var rr := s.hire(second["id"], CoachingStaff.min_acceptable(second, 3), 3, 1, l, 1, 1)
	_check(not rr["ok"] and rr["error"] == "DEV_ERR_DEPT_FULL", "a second coach needs a higher training facility level")
	rr = s.hire(second["id"], CoachingStaff.min_acceptable(second, 3), 3, 3, l, 1, 1)
	_check(rr["ok"] and s.in_department("midfield").size() == 2, "multiple coaches per department at facility level 3")
	var full := CoachingStaff.new(1)
	full.refresh_market(1)
	var cnt := 0
	var last := {}
	for d in DevConfig.DEPARTMENTS:
		var c: Dictionary = full.browse(d)[0]
		var x := full.hire(c["id"], CoachingStaff.min_acceptable(c, 3), 3, 1, null, 1, 1)
		cnt += 1 if x["ok"] else 0
	_check(cnt == 6, "one coach per department fills the base staff")
	var extra: Dictionary = full.browse("attacking")[0]
	_check(full.hire(extra["id"], 999999, 3, 1, null, 1, 1)["error"] in ["DEV_ERR_DEPT_FULL", "DEV_ERR_STAFF_FULL"], "the staff size is limited")
	var budget := FinanceLedger.new("t", 1_000_000, 0, 100)
	var s3 := CoachingStaff.new(2)
	s3.refresh_market(1)
	var c3: Dictionary = s3.browse("fitness")[0]
	_check(s3.hire(c3["id"], CoachingStaff.min_acceptable(c3, 3), 3, 1, budget, 1, 1)["error"] == "DEV_ERR_WAGE_BUDGET", "hire respects the wage budget")
	var poor := FinanceLedger.new("t", 10, 0, 0)
	_check(s3.hire(c3["id"], CoachingStaff.min_acceptable(c3, 3), 3, 1, poor, 1, 1)["error"] == "DEV_ERR_NO_MONEY", "hire respects the balance")
	_check(s3.reject(c3["id"], 1) and s3.candidate(c3["id"]).is_empty() and s3.activity[-1]["kind"] == "rejected", "reject removes the candidate and is logged")
	# weekly wages, expiry warning, renewal, dismissal
	var before := l.balance
	var ev := s.weekly(l, 5, 3)
	_check(l.balance == before - s.weekly_wages(), "weekly wages go through the ledger")
	_check(ev.any(func(e: Dictionary) -> bool: return e["key"] == "INBOX_COACH_EXPIRING"), "a contract in its final season warns once")
	_check(s.weekly(l, 6, 3).filter(func(e: Dictionary) -> bool: return e["key"] == "INBOX_COACH_EXPIRING").is_empty(), "the warning is not repeated")
	var ren := s.renew(id, 100, 2, l, 5, 3)
	_check(not ren["ok"], "renewal at a silly salary fails")
	ren = s.renew(id, int(coach["salary"]) * 3, 3, l, 5, 3)
	_check(ren["ok"] and int(coach["expiry_season"]) == 6, "renewal extends the contract", str(ren))
	var cost := CoachingStaff.dismiss_cost(coach, 3)
	var b2 := l.balance
	s.dismiss(id, l, 6, 3)
	_check(s.coach(id).is_empty() and l.balance == b2 - cost and cost > 0, "dismissal pays compensation")
	# season end: expiry + progression at different rates
	var p := CoachingStaff.new(9)
	p.refresh_market(1)
	for d in DevConfig.DEPARTMENTS:
		var c: Dictionary = p.browse(d)[0]
		p.hire(c["id"], CoachingStaff.min_acceptable(c, 1), 1, 1, null, 1, 1)
	var snap := p.coaches.map(func(c: Dictionary) -> int: return int(c["overall"]) * 100 + int(c["technical"]))
	var gone := p.season_end(1, 0.9)
	_check(p.coaches.is_empty() and gone.size() == 6, "one-year contracts end with the season")
	var q := CoachingStaff.new(9)
	q.refresh_market(1)
	for i in 20:
		var c: Dictionary = q.market[i % q.market.size()].duplicate(true)
		c["id"] = "x%d" % i
		c["years"] = 9
		c["expiry_season"] = 9
		c["status"] = "employed"
		q.coaches.append(c)
	var start_sum := 0
	var deltas := {}
	var starts: Array = q.coaches.map(func(c: Dictionary) -> int: return int(c["overall"]))
	for yr in 4:
		q.season_end(yr + 1, 0.8)
	for i in q.coaches.size():
		deltas[int(q.coaches[i]["overall"]) - starts[i]] = true
	_check(deltas.size() >= 2, "coaches progress at different rates", str(deltas.keys()))
	var q2 := CoachingStaff.new(9)
	q2.refresh_market(1)
	var a: Dictionary = q2.market[0].duplicate(true)
	a["expiry_season"] = 9
	q2.coaches = [a.duplicate(true)]
	var q3 := CoachingStaff.new(9)
	q3.coaches = [a.duplicate(true)]
	q2.season_end(1, 0.5)
	q3.season_end(1, 0.5)
	_check(q2.coaches[0]["overall"] == q3.coaches[0]["overall"] and q2.coaches[0]["reputation"] == q3.coaches[0]["reputation"], "coach progression is deterministic")
	_check(int(q2.coaches[0]["experience"]) == int(a["experience"]) + 1, "coaches gain experience each season")


func _player(pos: int, age: int, ov: int, pot: int) -> PlayerData:
	var p := PlayerData.new()
	p.id = "t_%d_%d_%d" % [pos, age, ov]
	p.display_name = "Test Player"
	p.position = pos as PlayerData.Position
	p.age = age
	for a in PlayerData.ATTRIBUTES:
		p.set(a, ov)
	p.set("goalkeeping", ov if pos == PlayerData.Position.GK else 10)
	p.potential = pot
	return p


func _test_plans() -> void:
	var st := _player(PlayerData.Position.ST, 20, 60, 85)
	var gk := _player(PlayerData.Position.GK, 20, 60, 85)
	var plans := DevelopmentPlans.new()
	_check(plans.assign(st, "position", 1) == "" and plans.plan_for(st.id)["weights"].has("shooting"), "position plan assigns the striker template")
	_check((plans.plan_for(st.id)["items"] as Array).size() == 7, "the striker template lists the seven focus items")
	_check(plans.assign(st, "attribute", 2, {"attribute": "goalkeeping"}) != "", "an outfield player cannot train goalkeeping")
	_check(plans.assign(gk, "attribute", 2, {"attribute": "goalkeeping"}) == "", "a goalkeeper can")
	_check(plans.assign(st, "bogus", 1) != "", "unknown plan type is rejected")
	_check(plans.assign(st, "custom", 1, {"attrs": {"pace": 1, "shooting": 1, "passing": 1, "dribbling": 1}}) != "", "custom plans are limited to three attributes")
	_check(plans.assign(st, "custom", 1, {"attrs": {"pace": 1, "shooting": 2}}) == "", "custom plan")
	_check(plans.plan_for(st.id)["weights"]["shooting"] > plans.plan_for(st.id)["weights"]["pace"], "custom weights are respected")
	_check(plans.assign(st, "role", 3, {"role": "target_man"}) == "" and plans.plan_for(st.id)["weights"].has("physical"), "role plan")
	_check(plans.assign(st, "role", 3, {"role": "nonsense"}) != "", "unknown role rejected")
	_check(plans.assign(st, "balanced", 3) == "" and not plans.plan_for(st.id)["weights"].has("goalkeeping"), "balanced plan for an outfield player has no goalkeeping")
	var hist := (plans.plan_for(st.id)["history"] as Array).size()
	_check(hist >= 3, "switching keeps the old plans in the history", str(hist))
	plans.assign(st, "position", 4)
	_check(DevelopmentPlans.consistency(plans.plan_for(st.id)) == DevConfig.PLAN_SWITCH_ADAPTATION, "a fresh switch costs adaptation time")
	plans.plan_for(st.id)["weeks"] = 20
	_check(DevelopmentPlans.consistency(plans.plan_for(st.id)) == DevConfig.CONSISTENCY_MAX, "staying with a plan earns the consistency bonus")
	_check(plans.assign(st, "conversion", 5, {"target_position": "LW"}) == "" and plans.plan_for(st.id)["target_position"] == "LW", "position conversion plan")
	_check(plans.assign(st, "conversion", 5, {"target_position": "ST"}) != "", "cannot convert to the own position")
	_check(plans.assign(st, "conversion", 5, {"target_position": "GK"}) != "", "an outfield player cannot convert to goalkeeper")
	var prog := plans.progress(st)
	_check(prog["targets"].size() > 0 and prog["department"] in DevConfig.DEPARTMENTS, "progress view lists targets and the coaching department")
	var back := DevelopmentPlans.from_dict(JSON.parse_string(JSON.stringify(plans.to_dict())))
	var w1: Dictionary = plans.plan_for(st.id)["weights"]
	var w2: Dictionary = back.plan_for(st.id)["weights"]
	var same_w := w1.size() == w2.size()
	for k in w1:
		same_w = same_w and w2.has(k) and absf(float(w1[k]) - float(w2[k])) < 0.0001
	_check(same_w and back.plan_for(st.id)["type"] == "conversion", "plans survive a JSON round trip", str(w2))
	var each_group := true
	for pos in PlayerData.Position.values():
		var pp := _player(pos, 22, 60, 80)
		each_group = each_group and DevelopmentPlans.new().assign(pp, "position", 1) == ""
	_check(each_group, "every position has a plan template")


func _squad_sample(career: CareerState, n: int) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in db.get_squad(career.club_id):
		if p.status == PlayerData.Status.ACTIVE and p.position != PlayerData.Position.GK and p.age <= 26 and p.potential > p.get_overall() + 4:
			out.append(p)
		if out.size() >= n:
			break
	return out


func _clone(p: PlayerData, id: String) -> PlayerData:
	var c := PlayerData.from_dict(p.to_dict())
	c.id = id
	c.age = 19
	c.potential = 95
	c.fitness = 100
	c.status = PlayerData.Status.ACTIVE
	return c


func _test_engine() -> void:
	var c: CareerState = app.career
	var dev: DevelopmentState = c.development
	DevelopmentEngine.ensure_staff(c, dev)
	_check(dev.coaching.initialized and dev.coaching.coaches.size() == 6 and dev.coaching.vacancies().is_empty(), "a career gets a starter staff in every department")
	_check(dev.validate().is_empty(), "development state validates", str(dev.validate()))
	# a controlled comparison: the same 19-year-old, elite coaching vs no coaching, 30 weeks
	var base: PlayerData = _squad_sample(c, 1)[0]
	var a := _clone(base, "cmp_a")
	var b := _clone(base, "cmp_b")
	var plan_a := DevelopmentPlans.new()
	plan_a.assign(a, "attribute", 1, {"attribute": "shooting"})
	var elite := CoachingStaff.new(1)
	elite.coaches = [_coach("attacking", 20), _coach("tactical", 20)]
	var none := CoachingStaff.new(1)
	var fq := 0.5
	var pa := 0.0
	var pb := 0.0
	for i in 30:
		pa += ProgressionModel.weekly_points(a, "shooting", fq, 0.6, elite.attribute_multiplier("shooting", "youth"))
		pb += ProgressionModel.weekly_points(a, "shooting", fq, 0.6, none.attribute_multiplier("shooting", "youth"))
	_check(pa > pb * 1.25 and pa < pb * 1.5, "elite coaching adds a clear but bounded boost", "%.2f vs %.2f" % [pa, pb])
	# potential cap and season cap through the real engine
	var p := _clone(base, "cap_test")
	p.potential = p.get_overall() + 1
	db.register_player(p)
	var state := DevelopmentState.new()
	state.coaching = elite
	state.coaching.initialized = true
	state.plans.assign(p, "position", 1)
	for w in range(1, 120):
		DevelopmentEngine._first_team_week(c, state, p, w, 0.5)
	_check(p.get_overall() <= p.potential, "weekly development never exceeds potential", "%d / %d" % [p.get_overall(), p.potential])
	var q := _clone(base, "season_cap")
	db.register_player(q)
	var st2 := DevelopmentState.new()
	st2.coaching = elite
	st2.coaching.initialized = true
	st2.plans.assign(q, "attribute", 1, {"attribute": "shooting"})
	var shoot0 := q.shooting
	for w in range(1, 46):
		q.fitness = 100
		DevelopmentEngine._first_team_week(c, st2, q, w, 1.0)
	_check(q.shooting - shoot0 <= DevConfig.season_attr_cap(q.age), "an attribute cannot gain more than the seasonal cap", str(q.shooting - shoot0))
	var old := _clone(base, "old_test")
	old.age = 33
	db.register_player(old)
	var st3 := DevelopmentState.new()
	st3.coaching = elite
	st3.coaching.initialized = true
	st3.plans.assign(old, "position", 1)
	var ov0 := old.get_overall()
	for w in range(1, 46):
		old.fitness = 100
		DevelopmentEngine._first_team_week(c, st3, old, w, 1.0)
	_check(old.get_overall() - ov0 <= 1, "a 33-year-old hardly improves through training", str(old.get_overall() - ov0))
	# fatigue and overload
	var f := _clone(base, "fatigue_test")
	db.register_player(f)
	var st4 := DevelopmentState.new()
	st4.coaching.initialized = true
	st4.plans.assign(f, "position", 1, {"intensity": 1.0})
	st4.plans.set_intensity(f.id, 1.0)
	f.fitness = 100
	for w in range(1, 11):
		if f.status == PlayerData.Status.ACTIVE:
			DevelopmentEngine._first_team_week(c, st4, f, w, 0.5)
	_check(f.fitness < 100, "maximum intensity wears the player down", str(f.fitness))
	var g := _clone(base, "rest_test")
	db.register_player(g)
	var st5 := DevelopmentState.new()
	st5.coaching.initialized = true
	st5.plans.assign(g, "position", 1)
	st5.plans.set_intensity(g.id, 0.2)
	g.fitness = 70
	DevelopmentEngine._first_team_week(c, st5, g, 1, 0.5)
	_check(g.fitness > 70, "a light plan lets the player recover")
	var tired := _clone(base, "tired_test")
	db.register_player(tired)
	tired.fitness = 30
	var st6 := DevelopmentState.new()
	st6.coaching = elite
	st6.coaching.initialized = true
	st6.plans.assign(tired, "position", 1)
	var res := DevelopmentEngine._first_team_week(c, st6, tired, 1, 0.5)
	_check(res["gains"].is_empty() or res["gains"].values().all(func(v: int) -> bool: return v == 0), "an exhausted player does not train")
	# match experience: a regular starter develops faster than a bench player
	var starter := _clone(base, "starter_test")
	var bench := _clone(base, "bench_test")
	db.register_player(starter)
	db.register_player(bench)
	var sa := DevelopmentState.new()
	sa.coaching = elite
	sa.coaching.initialized = true
	sa.plans.assign(starter, "position", 1)
	sa.plans.assign(bench, "position", 1)
	var s0 := starter.get_overall() * 1000 + 0
	var tot_s := 0.0
	var tot_b := 0.0
	for w in range(1, 41):
		c.world_stats[starter.id] = {"apps": w, "rating_sum": 7.2 * w}
		c.world_stats[bench.id] = {"apps": 0, "rating_sum": 0.0}
		starter.fitness = 100
		bench.fitness = 100
		DevelopmentEngine._first_team_week(c, sa, starter, w, 0.5)
		DevelopmentEngine._first_team_week(c, sa, bench, w, 0.5)
	for a2 in PlayerData.ATTRIBUTES:
		tot_s += float(starter.growth_progress.get(a2, 0.0)) + float((sa.season_gain.get(starter.id, {}) as Dictionary).get(a2, 0))
		tot_b += float(bench.growth_progress.get(a2, 0.0)) + float((sa.season_gain.get(bench.id, {}) as Dictionary).get(a2, 0))
	_check(tot_s > tot_b, "a regular starter develops more than a player who never plays", "%.2f vs %.2f" % [tot_s, tot_b])
	_check(sa.idle_weeks.get(bench.id, 0) >= 40 and sa.notifications.any(func(n: Dictionary) -> bool: return n["key"] == "INBOX_DEV_NO_PLAYTIME"), "a young player without games triggers a playing-time notification")
	for pid in ["cmp_a", "cmp_b", "cap_test", "season_cap", "old_test", "fatigue_test", "rest_test", "tired_test", "starter_test", "bench_test"]:
		db.players.erase(pid)


func _test_catch_up() -> void:
	var c: CareerState = app.career
	var dev := DevelopmentState.new()
	var now := c.absolute_week() + 60
	dev.last_week = now - 10
	var ev := DevelopmentEngine.sync(c, dev, now, app.academy())
	_check(dev.last_week == now and dev.skipped_weeks == 0, "a 10-week jump is caught up completely")
	var pid: String = db.get_squad(c.club_id)[0].id
	_check(dev.plans.plan_for(pid).get("weeks", 0) == 10 or db.get_squad(c.club_id)[0].status == PlayerData.Status.LOANED, "every owed week was processed once for a player", str(dev.plans.plan_for(pid).get("weeks", -1)))
	var weeks := int(dev.plans.plan_for(pid).get("weeks", 0))
	var rep_count := dev.reports.size()
	DevelopmentEngine.sync(c, dev, now, app.academy())
	_check(int(dev.plans.plan_for(pid).get("weeks", 0)) == weeks and dev.reports.size() == rep_count, "processing the same week twice changes nothing")
	var d2 := DevelopmentState.new()
	d2.last_week = now + 40
	now += 240
	DevelopmentEngine.sync(c, d2, now, null)
	_check(d2.skipped_weeks == 200 - DevConfig.YOUTH_CATCH_UP_MAX_WEEKS and d2.last_week == now, "a huge jump is capped but the skipped weeks are counted")
	# academy: youth development catches up all weeks
	var ac: Academy = app.academy()
	if ac == null:
		return
	var yd := YouthDevelopment.state(ac)
	yd["last_week"] = 100
	yd["league"] = {}
	var sq: Array = db.get_team(c.club_id).squad_ids
	YouthDevelopment.sync(db, ac, sq, 112)
	var own_row := _own_played(ac)
	var season_weeks_in_range := 0
	for w in range(101, 113):
		if posmod(w - 1, 46) + 1 <= 36:
			season_weeks_in_range += 1
	_check(int(yd["last_week"]) == 112 and own_row == season_weeks_in_range, "youth development processes every owed league week (12 weeks, not 4)", "%d vs %d" % [own_row, season_weeks_in_range])
	YouthDevelopment.sync(db, ac, sq, 112)
	_check(_own_played(ac) == own_row, "the youth week is not processed twice")


func _own_played(ac: Academy) -> int:
	for r in YouthDevelopment.table(db, ac):
		if r["id"] == "own":
			return int(r["p"])
	return -1


func _test_youth() -> void:
	var c: CareerState = app.career
	var ac: Academy = app.academy()
	if ac == null:
		_check(false, "the managed club has an academy")
		return
	if ac.roster_ids.size() < 25:
		ac.generate_intake(db, 25)
	# put an U15 star and make sure he never plays the league; check the keeper
	var kid := YouthGenerator.generate(ac.academy_seed, 9001, ac.team_id, ac.country, 0.9, 14)
	kid.id = "kid_u15_test"
	kid.position = PlayerData.Position.ST
	for a in PlayerData.ATTRIBUTES:
		kid.set(a, 90)
	kid.potential = 99
	db.register_player(kid)
	ac.roster_ids.append(kid.id)
	var lineup := YouthDevelopment.league_lineup(db, ac)
	_check(lineup.all(func(p: PlayerData) -> bool: return p.age >= AcademyConfig.LEAGUE_MIN_AGE and p.age <= AcademyConfig.LEAGUE_MAX_AGE), "the youth league lineup respects age eligibility")
	_check(not (kid in lineup), "an U15 player is never fielded in the U19 league")
	_check(lineup.size() <= 11 and YouthDevelopment.lineup_has_keeper(lineup) == (YouthDevelopment.league_eligible(db, ac).any(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK)), "the lineup has a goalkeeper whenever an eligible one exists")
	var gk_count := lineup.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
	_check(gk_count <= 1, "at most one goalkeeper in the eleven")
	# injured players are not selected
	if not lineup.is_empty():
		var hurt: PlayerData = lineup[0]
		hurt.status = PlayerData.Status.INJURED
		hurt.unavailable_weeks = 3
		_check(not (hurt in YouthDevelopment.league_lineup(db, ac)), "injured prospects are not selected")
		hurt.status = PlayerData.Status.YOUTH
		hurt.unavailable_weeks = 0
	# loans never go to the own club and carry real loan data
	var prospect: PlayerData = null
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and p.age >= YouthDevelopment.MIN_LOAN_AGE and not YouthDevelopment.state(ac)["loans"].has(pid):
			prospect = p
			break
	if prospect != null:
		var opts := YouthDevelopment.loan_options(db, ac, prospect, 20)
		_check(not opts.is_empty() and opts.all(func(o: Dictionary) -> bool: return o["id"] != ac.team_id), "loan destinations never include the own club")
		_check(float(opts[0]["score"]) >= float(opts[-1]["score"]), "loan options are ranked")
		_check(YouthDevelopment.loan_out(db, ac, prospect.id) == "", "loan_out succeeds")
		var l: Dictionary = YouthDevelopment.state(ac)["loans"][prospect.id]
		_check(l["club_id"] != ac.team_id and l.has("expected_playing") and l.has("start_overall"), "the loan records club quality and expected playing time")
		YouthDevelopment.recall(ac, prospect.id)
	# readiness
	var ready := DevelopmentEngine.promotion_candidates(db, ac, c.club_id)
	_check(ready.all(func(p: PlayerData) -> bool: return p.age >= AcademyConfig.MIN_PROMOTION_AGE), "promotion candidates respect the minimum promotion age")
	# plan-driven academy training
	var tr := TrainingSystem.new()
	var state := DevelopmentState.new()
	tr.plan_focus = func(p: PlayerData, w: int) -> String: return DevelopmentEngine.academy_focus(state, p, w)
	var some: PlayerData = db.get_player(ac.roster_ids[0])
	var picks := {}
	for w in 40:
		picks[DevelopmentEngine.academy_focus(state, some, w)] = true
	var wts: Dictionary = state.plans.plan_for(some.id)["weights"]
	_check(picks.keys().all(func(k: String) -> bool: return wts.has(k)) and picks.size() >= 2, "the academy plan rotates the training over its target attributes")
	_check(tr.focus_for(some) in wts, "TrainingSystem reads the plan focus")
	tr.set_individual_focus(db, some.id, "pace")
	_check(tr.focus_for(some) == "pace", "a manual individual focus still beats the plan")
	db.players.erase(kid.id)
	ac.roster_ids.erase(kid.id)


func _test_persistence() -> void:
	var c: CareerState = app.career
	var dev: DevelopmentState = c.development
	DevelopmentEngine.sync(c, dev, c.absolute_week() + 2, app.academy())
	var sq: Array = db.get_squad(c.club_id)
	dev.plans.assign(sq[3], "role" if not DevelopmentPlans.roles_for(DevelopmentPlans.group_of(sq[3].position)).is_empty() else "balanced", c.absolute_week(),
			{"role": (DevelopmentPlans.roles_for(DevelopmentPlans.group_of(sq[3].position)) + [""])[0]})
	var coach_ids: Array = dev.coaching.coaches.map(func(x: Dictionary) -> String: return x["id"])
	var data := c.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	var c2 := CareerState.from_dict(db, parsed)
	var d2: DevelopmentState = c2.development
	var ids2: Array = d2.coaching.coaches.map(func(x: Dictionary) -> String: return x["id"])
	_check(ids2 == coach_ids and d2.last_week == dev.last_week, "coaches and the processed-week marker survive save and load")
	_check(d2.plans.plans.size() == dev.plans.plans.size() and d2.history.size() == dev.history.size(), "plans and history survive save and load")
	_check(d2.coaching.market.size() == dev.coaching.market.size() and d2.coaching.next_id == dev.coaching.next_id, "market and id counter survive save and load")
	_check(d2.validate().is_empty(), "the loaded state validates", str(d2.validate()))
	_check(d2.coaching.coaches[0]["salary"] is int and d2.coaching.coaches[0]["overall"] is int, "numbers come back as integers (JSON floats are converted)")
	# old save: no "development" key -> safe defaults and a starter staff on the first week
	var old := parsed.duplicate(true)
	old.erase("development")
	var c3 := CareerState.from_dict(db, old)
	_check(not c3.development.coaching.initialized and c3.development.last_week == -1, "an old save loads with an empty development state")
	DevelopmentEngine.ensure_staff(c3, c3.development)
	_check(c3.development.coaching.coaches.size() == 6, "an old save gets its starter staff on the first week")
	var full := SaveManager.capture(db, {}, {}, {}, {}, {"career": data})
	var errs := SaveManager.validate(SaveManager.migrate(JSON.parse_string(JSON.stringify(full, "", true, true))))
	_check(errs.is_empty(), "the full save validates with the development block", str(errs.slice(0, 3)))
	# corrupt data is repaired, not trusted
	var bad := {"coaches": [{"id": "z1", "department": "nope", "overall": 5}, {"id": "z2", "department": "attacking", "overall": 99, "youth": -4},
			{"id": "z2", "department": "midfield"}], "market": []}
	var rs := CoachingStaff.from_dict(bad)
	_check(rs.coaches.size() == 1 and rs.coaches[0]["overall"] == DevConfig.RATING_MAX and rs.coaches[0]["youth"] == DevConfig.RATING_MIN, "corrupt coach records are dropped or clamped and duplicate ids removed")


func _test_ui() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	c.ledger().opening_balance = 20_000_000
	c.ledger().balance = 20_000_000
	c.ledger().wage_budget = 5_000_000
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		for sid in ["dev_hub", "coaching_staff", "coach_recruitment"]:
			hub.navigate(sid)
			await get_tree().process_frame
			_check(hub.current != null and hub.current.get_child_count() > 2, "screen %s builds (%s)" % [sid, lang])
	Loc.set_language("en", false)
	var press := func(n: String) -> bool:
		var b := hub.current.find_child(n, true, false) as Button
		if b == null or b.disabled:
			return false
		b.pressed.emit()
		return true
	hub.navigate("coaching_staff")
	await get_tree().process_frame
	var co: Dictionary = c.development.coaching.coaches[0]
	var until := int(co["expiry_season"])
	_check(press.call("Renew_%s" % co["id"]) and int(c.development.coaching.coach(co["id"])["expiry_season"]) > until, "the Renew button extends the contract")
	await get_tree().process_frame
	var n0 := c.development.coaching.coaches.size()
	hub.navigate("coach_recruitment", {"department": "goalkeeping"})
	await get_tree().process_frame
	var cand: Dictionary = c.development.coaching.browse("goalkeeping")[0]
	var cid: String = cand["id"]
	_check(press.call("Negotiate_%s" % cid), "the Negotiate button answers")
	await get_tree().process_frame
	_check(press.call("Compare_%s" % cid), "the Compare button works")
	await get_tree().process_frame
	# one coach per department at facility level 1: free the goalkeeping post first
	var gk: Dictionary = c.development.coaching.in_department("goalkeeping")[0]
	c.development.coaching.dismiss(gk["id"], c.ledger(), 1, c.season)
	hub.navigate("coach_recruitment", {"department": "goalkeeping"})
	await get_tree().process_frame
	var sal := hub.current.find_child("Salary_%s" % cid, true, false) as SpinBox
	sal.value = float(CoachingStaff.min_acceptable(cand, int(cand["pref_years"])) + 50)
	_check(press.call("Hire_%s" % cid) and c.development.coaching.in_department("goalkeeping").size() == 1, "the Hire button hires the candidate")
	await get_tree().process_frame
	var other: Dictionary = c.development.coaching.browse("attacking")[0]
	hub.navigate("coach_recruitment", {"department": "attacking"})
	await get_tree().process_frame
	_check(press.call("Reject_%s" % other["id"]) and c.development.coaching.candidate(other["id"]).is_empty(), "the Reject button removes the candidate")
	# development hub: pick a player and switch his plan
	var p: PlayerData = db.get_squad(c.club_id).filter(func(x: PlayerData) -> bool: return x.status == PlayerData.Status.ACTIVE)[0]
	hub.navigate("dev_hub")
	await get_tree().process_frame
	hub.current.set("_selected", p.id)
	hub.current.call("rebuild")
	await get_tree().process_frame
	var opt := hub.current.find_child("PlanType", true, false) as OptionButton
	_check(opt != null, "the selected player shows plan controls")
	if opt != null:
		opt.select(0)
		opt.item_selected.emit(0)
		await get_tree().process_frame
		_check(c.development.plans.plan_for(p.id)["type"] == "balanced", "choosing a plan in the list changes the player's plan")
	var sl := hub.current.find_child("PlanIntensity", true, false) as HSlider
	if sl != null:
		sl.value = 90
		_check(absf(float(c.development.plans.plan_for(p.id)["intensity"]) - 0.9) < 0.01, "the intensity slider sets the plan workload")
	hub.queue_free()
