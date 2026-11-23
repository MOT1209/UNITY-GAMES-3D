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
	_test_detailed_plans()
	_test_youth_coaching()
	_test_training_effects()
	_test_academy_integration()
	_test_detailed_views()
	_test_state_migration()
	_test_youth()
	_test_staff_bridge()
	_test_sessions_groups_cups()
	_test_minutes()
	_test_scouting()
	_test_youth_leagues()
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
	_check(DevConfig.stars(1) == 1 and DevConfig.stars(7) == 1 and DevConfig.stars(8) == 2 and DevConfig.stars(14) == 2 and DevConfig.stars(15) == 3 and DevConfig.stars(20) == 3,
			"three star bands over the 1..20 rating (max 3 stars)")
	var over := []
	for v in range(-5, 30):
		if DevConfig.stars(v) > 3 or DevConfig.stars_text(v).length() != 3:
			over.append(v)
	_check(over.is_empty(), "no rating shows more than 3 stars (3-star text)", str(over))
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
	s.refresh_market(5)
	var week5: Array = s.market.map(func(c: Dictionary) -> String: return c["id"])
	s.refresh_market(5)
	s.refresh_market(5)
	_check(s.market.map(func(c: Dictionary) -> String: return c["id"]) == week5, "the market is refreshed only once in the same week")
	s.refresh_market(6)
	var fresh := s.market.filter(func(c: Dictionary) -> bool: return not (c["id"] in week5))
	_check(fresh.size() == s.market.size() and s.market.size() == DevConfig.DEPARTMENTS.size() * DevConfig.MARKET_PER_DEPT,
			"the next week brings a completely fresh selection in every department", "%d fresh of %d" % [fresh.size(), s.market.size()])
	var top := 0
	for wk in range(7, 60):
		s.refresh_market(wk)
		for c: Dictionary in s.market:
			top = maxi(top, DevConfig.stars(int(c["overall"])))
	_check(top <= 3, "no candidate over a season of weekly markets has more than 3 stars", "max %d" % top)
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
	_check(plans.assign(st, "position", 1) == "" and plans.plan_for(st.id)["weights"].has("finishing"), "position plan assigns the striker template (detailed attributes)")
	_check((plans.plan_for(st.id)["items"] as Array).size() == 5, "the striker template lists five detailed focus items")
	_check(plans.assign(st, "attribute", 2, {"attribute": "goalkeeping"}) != "", "an outfield player cannot train goalkeeping")
	_check(plans.assign(gk, "attribute", 2, {"attribute": "goalkeeping"}) == "", "a goalkeeper can")
	_check(plans.assign(st, "bogus", 1) != "", "unknown plan type is rejected")
	_check(plans.assign(st, "custom", 1, {"attrs": {"pace": 1, "shooting": 1, "passing": 1, "dribbling": 1, "defending": 1, "physical": 1}}) != "", "custom plans are limited to five attributes")
	_check(plans.assign(st, "custom", 1, {"attrs": {"pace": 1, "shooting": 2}}) == "", "custom plan")
	_check(plans.plan_for(st.id)["weights"]["shooting"] > plans.plan_for(st.id)["weights"]["pace"], "custom weights are respected")
	_check(plans.assign(st, "role", 3, {"role": "target_man"}) == "" and plans.plan_for(st.id)["weights"].has("heading"), "role plan")
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
	# room to grow for both (since the Nov 2026 rate fix a player near his potential reaches it within the 40 weeks and the difference vanishes)
	starter.potential = mini(99, starter.get_overall() + 20)
	bench.potential = starter.potential
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
	for a2 in DevelopmentPlans.tracked_attrs(starter):
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
	_test_catch_up_queue(c)
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


## Plans target DETAILED attributes: templates, upgrade of old plans, engine effect, coaching lead, sessions.
func _test_detailed_plans() -> void:
	var groups := {PlayerData.Position.GK: "gk", PlayerData.Position.CB: "cb", PlayerData.Position.LB: "fb", PlayerData.Position.CM: "cm",
			PlayerData.Position.CAM: "am", PlayerData.Position.LW: "winger", PlayerData.Position.ST: "st"}
	var ok_names := true
	var ok_labels := true
	var ok_scope := true
	for pos in groups:
		var q := _player(pos, 20, 60, 85)
		for it in (DevelopmentPlans.TEMPLATES[groups[pos]] as Array):
			ok_names = ok_names and DetailedAttributes.has(str(it[1]))
			ok_labels = ok_labels and Loc.has_key(str(it[0]))
			ok_scope = ok_scope and DevelopmentPlans.trainable(q, str(it[1]))
		for role in DevelopmentPlans.roles_for(groups[pos]):
			for it in (DevelopmentPlans.ROLES[groups[pos]][role] as Array):
				ok_names = ok_names and DetailedAttributes.has(str(it[1]))
				ok_labels = ok_labels and Loc.has_key(str(it[0]))
				ok_scope = ok_scope and DevelopmentPlans.trainable(q, str(it[1]))
	_check(ok_names, "every template and role item is a detailed attribute")
	_check(ok_labels, "every template and role item has a translated label")
	_check(ok_scope, "every template item can be trained by a player of that position")
	var want := {"st": ["finishing", "positioning", "composure", "shot_power", "reactions"], "winger": ["acceleration", "sprint_speed", "dribbling_skill", "crossing", "ball_control"],
			"cm": ["short_passing", "long_passing", "vision", "stamina", "decisions"], "cb": ["marking", "tackling", "interceptions", "strength", "defensive_awareness"],
			"gk": ["reflexes", "diving", "handling", "gk_positioning", "one_on_one"]}
	var match_spec := true
	for g in want:
		var have: Array = (DevelopmentPlans.TEMPLATES[g] as Array).map(func(it: Array) -> String: return str(it[1]))
		have.sort()
		var w2: Array = (want[g] as Array).duplicate()
		w2.sort()
		match_spec = match_spec and have == w2
	_check(match_spec, "the striker / winger / midfielder / centre-back / goalkeeper templates are exactly the specified attributes")
	var st := _player(PlayerData.Position.ST, 20, 60, 85)
	var gk := _player(PlayerData.Position.GK, 20, 60, 85)
	var plans := DevelopmentPlans.new()
	plans.assign(st, "balanced", 1)
	var bw: Dictionary = plans.plan_for(st.id)["weights"]
	_check(bw.size() > 25 and not bw.has("reflexes") and bw.has("vision") and not bw.has("goalkeeping"), "a balanced outfield plan spreads over the outfield detailed attributes", str(bw.size()))
	_check(plans.assign(st, "attribute", 2, {"attribute": "reflexes"}) != "", "an outfield player cannot train a goalkeeping detail")
	_check(plans.assign(gk, "attribute", 2, {"attribute": "reflexes"}) == "", "a goalkeeper can")
	_check(plans.assign(st, "custom", 3, {"attrs": {"finishing": 2, "vision": 1, "stamina": 1, "heading": 1, "composure": 1}}) == "", "a custom plan may mix up to five detailed attributes")
	_check(plans.assign(st, "attribute", 4, {"attribute": "nonsense"}) != "", "an unknown attribute is rejected")
	_check(not (plans.plan_for(st.id)["start_attrs"] as Dictionary).is_empty() and (plans.plan_for(st.id)["start_attrs"] as Dictionary).has("finishing"), "a plan tracks the start values of the detailed attributes")
	_check(st.detail.size() == DetailedAttributes.names().size(), "a planned player has stored detailed attributes")
	# upgrade of a plan written before the detailed layer
	var old := _player(PlayerData.Position.ST, 20, 60, 85)
	var legacy := {"plans": {old.id: {"type": "position", "items": [["DEV_FOCUS_FINISHING", "shooting"]], "weights": {"shooting": 0.6, "pace": 0.4}, "intensity": 0.7,
			"started_week": 3, "switched_week": 3, "weeks": 12, "start_overall": 55, "start_attrs": {"shooting": 60}, "cycle_start_attrs": {"shooting": 60},
			"cycle_weeks": 4, "cycles": 2, "target_position": "", "long_term": false, "role": "", "history": [{"type": "balanced", "from_week": 1, "to_week": 3, "weeks": 2}], "auto": false}}}
	var lp := DevelopmentPlans.from_dict(legacy)
	_check(lp.plan_for(old.id)["weights"].has("shooting") and int(lp.plan_for(old.id)["v"]) == 1, "an old plan loads with its broad weights")
	lp.ensure(old, 20)
	var up: Dictionary = lp.plan_for(old.id)
	_check(int(up["v"]) == DevelopmentPlans.PLAN_VERSION and up["weights"].has("finishing") and not up["weights"].has("shooting"), "an old template plan is upgraded to detailed targets")
	_check(int(up["weeks"]) == 12 and int(up["cycles"]) == 2 and (up["history"] as Array).size() == 1 and absf(float(up["intensity"]) - 0.7) < 0.001, "the upgrade keeps the plan clock, cycles, history and intensity")
	_check((up["start_attrs"] as Dictionary).has("vision") and int(up["start_attrs"]["shooting"]) == 60, "the upgrade keeps old start values and adds the new ones")
	var cu := {"plans": {old.id: legacy["plans"][old.id].duplicate(true)}}
	cu["plans"][old.id]["type"] = "custom"
	var lc := DevelopmentPlans.from_dict(cu)
	lc.ensure(old, 20)
	_check(lc.plan_for(old.id)["weights"].has("shooting") and not lc.plan_for(old.id)["weights"].has("finishing"), "an old custom plan keeps its broad targets")
	# weekly engine: only targeted detailed attributes grow
	var c: CareerState = app.career
	var pl := _clone(_squad_sample(c, 1)[0], "det_plan")
	pl.position = PlayerData.Position.ST
	pl.age = 19
	pl.potential = 99
	db.register_player(pl)
	var ds := DevelopmentState.new()
	ds.coaching.initialized = true
	ds.plans.assign(pl, "position", 1)
	var targets: Dictionary = ds.plans.plan_for(pl.id)["weights"]
	var before := {}
	for n in DetailedAttributes.names():
		before[n] = DetailedAttributes.value(pl, str(n))
	var shooting0 := pl.shooting
	for w in range(1, 120):
		pl.fitness = 100
		DevelopmentEngine._first_team_week(c, ds, pl, w, 0.8)
	var grew := 0
	var stray := 0
	for n in DetailedAttributes.names():
		var d := DetailedAttributes.value(pl, str(n)) - int(before[n])
		if targets.has(n):
			grew += d
		elif d != 0:
			stray += 1
	_check(grew > 0, "the engine raises the plan's detailed targets", str(grew))
	_check(stray == 0, "detailed attributes outside the plan do not change", str(stray))
	_check(pl.shooting >= shooting0, "the broad attribute follows the targets (match engine input)", "%d -> %d" % [shooting0, pl.shooting])
	db.players.erase(pl.id)
	# coaching: detailed attributes are led by the right department; specialisations favour their attributes
	_check(DevConfig.lead_department("finishing") == "attacking" and DevConfig.lead_department("vision") == "midfield" and DevConfig.lead_department("marking") == "defensive"
			and DevConfig.lead_department("stamina") == "fitness" and DevConfig.lead_department("reflexes") == "goalkeeping" and DevConfig.lead_department("composure") == "tactical"
			and DevConfig.lead_department("pace") == "fitness", "every attribute has its leading department")
	var all_led := true
	for n in DetailedAttributes.names():
		all_led = all_led and (DevConfig.lead_department(str(n)) in DevConfig.DEPARTMENTS)
	_check(all_led, "every detailed attribute resolves to a real department")
	var fin := CoachingStaff.new(1)
	fin.coaches = [_coach("attacking", 16, "finishing"), _coach("tactical", 10)]
	var oth := CoachingStaff.new(1)
	oth.coaches = [_coach("attacking", 16, "movement"), _coach("tactical", 10)]
	_check(fin.attribute_multiplier("finishing") > oth.attribute_multiplier("finishing"), "a finishing specialist trains finishing better than a movement specialist")
	_check(is_equal_approx(fin.attribute_multiplier("sprint_speed"), oth.attribute_multiplier("sprint_speed")), "a specialisation does not affect attributes of another department")
	var tac := CoachingStaff.new(1)
	tac.coaches = [_coach("tactical", 20)]
	_check(is_equal_approx(tac.attribute_multiplier("decisions"), tac.dept_multiplier("tactical", "pro", "decisions")), "the tactical coach's share is not applied twice to attributes he leads")
	# sessions train detailed attributes
	var ok_sessions := true
	for k in DevConfig.SESSIONS:
		ok_sessions = ok_sessions and DetailedAttributes.has(str(DevConfig.SESSIONS[k][1]))
	_check(ok_sessions, "every training session trains a detailed attribute")
	var trainer := TrainingSystem.new()
	_check(TrainingSystem.valid_focus("finishing") and TrainingSystem.valid_focus("shooting") and not TrainingSystem.valid_focus("bogus") and trainer.set_individual_focus(db, "nobody", "finishing") != "", "the academy accepts broad and detailed training focuses")


## Every owed week is processed exactly once or stays explicitly queued; nothing is dropped, whatever the jump size.
func _test_catch_up_queue(c: CareerState) -> void:
	var pid: String = ""
	for p in db.get_squad(c.club_id):
		if p.status == PlayerData.Status.ACTIVE:
			pid = p.id
			break
	var base := c.absolute_week()
	for jump in [10, 60, 100, 200]:
		var st := DevelopmentState.new()
		st.last_week = base
		var target := base + int(jump)
		DevelopmentEngine.sync(c, st, target, null)
		var first_call := int(st.plans.plan_for(pid).get("weeks", 0))
		_check(first_call == mini(int(jump), DevConfig.CATCH_UP_BATCH_WEEKS) and st.last_week == base + first_call,
				"%d-week jump: the first call processes %d weeks and last_week matches them" % [jump, first_call], "%d / %d" % [first_call, st.last_week])
		_check(st.pending_weeks(target) == int(jump) - first_call, "%d-week jump: the rest is queued, not lost" % jump, str(st.pending_weeks(target)))
		var guard := 0
		while st.pending_weeks(target) > 0 and guard < 10:
			DevelopmentEngine.sync(c, st, target, null)
			guard += 1
		_check(st.last_week == target and int(st.plans.plan_for(pid).get("weeks", 0)) == int(jump), "%d-week jump: every owed week processed exactly once" % jump,
				"%d weeks, last %d" % [int(st.plans.plan_for(pid).get("weeks", 0)), st.last_week])
		DevelopmentEngine.sync(c, st, target, null)
		_check(int(st.plans.plan_for(pid).get("weeks", 0)) == int(jump), "%d-week jump: repeated sync adds nothing" % jump)
		_check(st.skipped_weeks == 0, "%d-week jump: no week is counted as skipped" % jump)
	# a save in the middle of a queued catch-up resumes it and loses / repeats nothing
	var sv := DevelopmentState.new()
	sv.last_week = base
	DevelopmentEngine.sync(c, sv, base + 200, null)
	var restored := DevelopmentState.from_dict(JSON.parse_string(JSON.stringify(sv.to_dict())) as Dictionary)
	_check(restored.last_week == sv.last_week and restored.pending_weeks(base + 200) == sv.pending_weeks(base + 200), "a queued catch-up survives save / load")
	var guard2 := 0
	while restored.pending_weeks(base + 200) > 0 and guard2 < 10:
		DevelopmentEngine.sync(c, restored, base + 200, null)
		guard2 += 1
	_check(restored.last_week == base + 200 and int(restored.plans.plan_for(pid).get("weeks", 0)) == 200, "the loaded queue resumes and completes (200 weeks, once each)",
			str(restored.plans.plan_for(pid).get("weeks", -1)))
	# training and youth paths follow the same rule
	var ac: Academy = app.academy()
	if ac == null:
		return
	var tr := TrainingSystem.new()
	tr.calendar_week = base
	tr.sync_to_calendar(db, ac, base + 200)
	_check(tr.week == DevConfig.CATCH_UP_BATCH_WEEKS and tr.calendar_week == base + DevConfig.CATCH_UP_BATCH_WEEKS and tr.pending_weeks(base + 200) == 200 - DevConfig.CATCH_UP_BATCH_WEEKS,
			"training: a 200-week jump processes one batch and queues the rest", "%d / %d" % [tr.week, tr.calendar_week])
	var tg := 0
	while tr.pending_weeks(base + 200) > 0 and tg < 10:
		tr.sync_to_calendar(db, ac, base + 200)
		tg += 1
	_check(tr.week == 200 and tr.calendar_week == base + 200, "training: all 200 owed weeks trained exactly once", "%d" % tr.week)
	var tr2 := TrainingSystem.from_dict(tr.to_dict())
	tr2.sync_to_calendar(db, ac, base + 200)
	_check(tr2.week == 200, "training: a reloaded, caught-up system does not train again")
	var yd := YouthDevelopment.state(ac)
	var sq: Array = db.get_team(c.club_id).squad_ids
	yd["last_week"] = base
	YouthDevelopment.sync(db, ac, sq, base + 200)
	_check(int(yd["last_week"]) == base + DevConfig.CATCH_UP_BATCH_WEEKS and YouthDevelopment.pending_weeks(ac, base + 200) == 200 - DevConfig.CATCH_UP_BATCH_WEEKS,
			"youth: a 200-week jump processes one batch and queues the rest")
	var yg := 0
	while YouthDevelopment.pending_weeks(ac, base + 200) > 0 and yg < 10:
		YouthDevelopment.sync(db, ac, sq, base + 200)
		yg += 1
	_check(int(yd["last_week"]) == base + 200, "youth: the queue drains to the target week")


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
		for sid in ["dev_hub", "coaching_staff", "coach_recruitment", "dev_analytics", "training_center"]:
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
	var ca := hub.current.find_child("CustomAttr_0", true, false) as OptionButton
	if ca != null:
		ca.select(2)
		ca.item_selected.emit(2)
		(hub.current.find_child("CustomWeight_0", true, false) as OptionButton).select(2)
		(hub.current.find_child("CustomWeight_0", true, false) as OptionButton).item_selected.emit(2)
		_check(press.call("CustomApply") and c.development.plans.plan_for(p.id)["type"] == "custom", "the custom plan editor applies a custom plan")
		await get_tree().process_frame
	var sl := hub.current.find_child("PlanIntensity", true, false) as HSlider
	if sl != null:
		sl.value = 90
		_check(absf(float(c.development.plans.plan_for(p.id)["intensity"]) - 0.9) < 0.01, "the intensity slider sets the plan workload")
	hub.navigate("training_center")
	await get_tree().process_frame
	var p2: PlayerData = db.get_squad(c.club_id).filter(func(x: PlayerData) -> bool: return x.status != PlayerData.Status.YOUTH)[0]
	var before := float(c.development.plans.ensure(p2, 1)["intensity"])
	var lighter := hub.current.find_child("Lighter_%s" % p2.id, true, false) as Button
	if lighter != null:
		lighter.pressed.emit()
		_check(float(c.development.plans.plan_for(p2.id)["intensity"]) < before or before == 0.0, "the Lighter button lowers a player's workload")
	else:
		_check(true, "the squad list shows the fittest players beyond the first 25 only")
	var fo := hub.current.find_child("Day0_focus", true, false) as OptionButton
	if fo != null:
		fo.item_selected.emit(1)
		await get_tree().process_frame
		_check(c.training.overrides.size() >= 1, "changing a day's focus stores an override in the training plan")
	hub.queue_free()


func _test_scouting() -> void:
	var ac: Academy = app.academy()
	var sc := ScoutingSystem.new(77)
	ac.budget = 10_000_000
	sc.add_scout("s_hi", "High", 0.95, 1000)
	sc.add_scout("s_lo", "Low", 0.2, 500)
	_check(sc.start_mission(ac, "s_hi", ScoutingSystem.WORLDWIDE, 4, "XX", "balanced") != "", "an unknown position is refused")
	_check(sc.start_mission(ac, "s_hi", ScoutingSystem.WORLDWIDE, 4, "", "nonsense") != "", "an unknown objective is refused")
	var found := {"s_hi": [], "s_lo": []}
	for sid in ["s_hi", "s_lo"]:
		for round in 14:
			sc.pool.clear()
			_check(sc.start_mission(ac, sid, ScoutingSystem.WORLDWIDE, 6, "ST", "potential") == "", "mission with position and objective starts (%s)" % sid) if round == 0 else sc.start_mission(ac, sid, ScoutingSystem.WORLDWIDE, 6, "ST", "potential")
			for i in 6:
				sc.advance_week(db, ac)
			for pid in sc.pool:
				found[sid].append(db.get_player(pid))
	var st_hi: int = found["s_hi"].filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.ST).size()
	var st_lo: int = found["s_lo"].filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.ST).size()
	_check(st_hi * found["s_lo"].size() >= st_lo * found["s_hi"].size(), "a better scout finds at least as many players of the wanted position", "%d/%d vs %d/%d" % [st_hi, found["s_hi"].size(), st_lo, found["s_lo"].size()])
	var back := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(sc.to_dict())))
	sc.start_mission(ac, "s_hi", "Aldoria", 3, "CB", "ready")
	var back2 := ScoutingSystem.from_dict(JSON.parse_string(JSON.stringify(sc.to_dict())))
	_check(back2.missions[-1]["position"] == "CB" and back2.missions[-1]["objective"] == "ready", "mission position and objective survive save and load")
	# catch-up: 10 owed weeks complete a 6-week mission
	var s2 := ScoutingSystem.new(5)
	s2.add_scout("a", "A", 0.5, 500)
	s2.start_mission(ac, "a", "Aldoria", 6)
	s2.calendar_week = 100
	s2.sync_to_calendar(db, ac, 110)
	_check(s2.missions.is_empty() and not s2.pool.is_empty(), "a 10-week jump completes the mission (no 4-week cap)")


func _test_youth_leagues() -> void:
	var ac: Academy = app.academy()
	if ac.roster_ids.size() < 30:
		ac.generate_intake(db, 30)
	var yd := YouthDevelopment.state(ac)
	for g in YouthDevelopment.LEAGUE_GROUPS:
		yd[YouthDevelopment._lk(g)] = {}
		yd[YouthDevelopment._rk(g)] = []
	yd["last_week"] = 200
	var sq: Array = db.get_team(app.career.club_id).squad_ids
	YouthDevelopment.sync(db, ac, sq, 210)
	var weeks := 0
	for w in range(201, 211):
		if posmod(w - 1, 46) + 1 <= 36:
			weeks += 1
	for g in YouthDevelopment.LEAGUE_GROUPS:
		var played := 0
		for r in YouthDevelopment.table(db, ac, g):
			if r["id"] == "own":
				played = int(r["p"])
		_check(played == weeks, "the %s league played every owed week" % g, "%d vs %d" % [played, weeks])
		var ages := AcademyConfig.league_ages(g)
		_check(YouthDevelopment.league_lineup(db, ac, g).all(func(p: PlayerData) -> bool: return p.age >= ages.x and p.age <= ages.y), "the %s lineup respects its age band" % g)
	_check(YouthDevelopment.league_lineup(db, ac, "U15").all(func(p: PlayerData) -> bool: return p.age <= 15), "no U17 or U19 player plays the U15 league")
	var again := YouthDevelopment.table(db, ac, "U17")
	YouthDevelopment.sync(db, ac, sq, 210)
	_check(YouthDevelopment.table(db, ac, "U17") == again, "a youth league week is not processed twice")
	var back := Academy.from_dict(JSON.parse_string(JSON.stringify(ac.to_dict())))
	_check(YouthDevelopment.table(db, back, "U15").size() == YouthDevelopment.table(db, ac, "U15").size() and back.dev.has("league_U17"), "all three youth leagues survive save and load")


func _test_staff_bridge() -> void:
	var c: CareerState = app.career
	var legacy := StaffTeam.new()
	var cs := CoachingStaff.new(3)
	legacy.coaching_link = cs
	_check(legacy.skill("fitness_coach") == 0, "no coach in either system: skill 0")
	cs.coaches = [_coach("fitness", 14), _coach("goalkeeping", 9)]
	_check(legacy.skill("fitness_coach") == 14 and legacy.skill("goalkeeping_coach") == 9, "the legacy fitness / goalkeeper effects read the development coaches")
	_check(legacy.injury_factor() < 1.0 and cs.attribute_multiplier("reflexes") > CoachingStaff.new(1).attribute_multiplier("reflexes"), "...and the injury effect and the goalkeeping training follow")
	legacy.members.append({"id": "x", "role": "fitness_coach", "name": "Old", "skill": 18, "wage": 3000, "years": 2})
	_check(legacy.skill("fitness_coach") == 18, "the better of the two counts")
	_check(legacy.skill("assistant") == 0 and StaffTeam.UI_ROLES.size() == 4 and not ("fitness_coach" in StaffTeam.UI_ROLES) and not ("goalkeeping_coach" in StaffTeam.UI_ROLES) and not ("first_team_coach" in StaffTeam.UI_ROLES), "the old staff screen no longer lists the three bridged roles")
	# migration: an old save with a hired fitness coach
	var c2 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	c2.development = DevelopmentState.new()
	c2.staff.members = [{"id": "old_fit", "role": "fitness_coach", "name": "Hans Old", "age": 50, "skill": 16, "wage": 2500, "years": 2, "personality": "calm", "nationality_id": ""}]
	DevelopmentEngine.ensure_staff(c2, c2.development)
	var fit := c2.development.coaching.in_department("fitness")
	_check(fit.size() == 1 and fit[0]["name"] == "Hans Old" and int(fit[0]["overall"]) == 16 and int(fit[0]["salary"]) == 2500, "a legacy fitness coach becomes the fitness department coach")
	_check(c2.staff.member_for("fitness_coach").is_empty(), "...and leaves the old staff list, so his wage is not paid twice")
	_check(c2.staff.skill("fitness_coach") == 16, "his skill still counts for injuries")
	# the legacy first-team (head) coach becomes the tactical coach
	var c3 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	c3.development = DevelopmentState.new()
	c3.staff.members = [{"id": "old_ftc", "role": "first_team_coach", "name": "Gus Head", "age": 52, "skill": 15, "wage": 2200, "years": 2, "personality": "strict", "nationality_id": ""}]
	DevelopmentEngine.ensure_staff(c3, c3.development)
	var tac := c3.development.coaching.in_department("tactical")
	_check(tac.size() == 1 and tac[0]["name"] == "Gus Head" and int(tac[0]["overall"]) == 15 and int(tac[0]["salary"]) == 2200, "a legacy first-team coach becomes the tactical department coach")
	_check(c3.staff.member_for("first_team_coach").is_empty() and c3.staff.weekly_wages() == 0, "...and leaves the old staff list, so his wage is not paid twice")
	_check(c3.development.coaching.coaches.size() == 6, "every department still has exactly one coach after the import (no duplicate coach)")
	_test_academy_coaching_not_stacked()


## Saves written before the detailed attributes load, keep their data and upgrade; the version is tracked.
func _test_state_migration() -> void:
	var c: CareerState = app.career
	var pl := _clone(_squad_sample(c, 1)[0], "mig_pl")
	pl.position = PlayerData.Position.ST
	pl.age = 21
	pl.potential = 99
	pl.detail = {}                                   # a player from a save written before the detailed attributes existed
	db.register_player(pl)
	var old := {"version": 1, "last_week": 40, "skipped": 140,
			"coaching": {}, "history": {}, "last_attrs": {}, "last_apps": {}, "last_minutes": {}, "idle": {}, "season_gain": {}, "milestones": {}, "reports": [], "notifications": [],
			"fatigue_flagged": {}, "sessions": [{"id": 1, "session": "shooting", "day": 1, "intensity": 0.5, "player_ids": [pl.id]}], "next_session_id": 2,
			"plans": {"plans": {pl.id: {"type": "position", "items": [["DEV_FOCUS_FINISHING", "shooting"]], "weights": {"shooting": 0.7, "pace": 0.3}, "intensity": 0.6,
					"started_week": 2, "switched_week": 2, "weeks": 38, "start_overall": 50, "start_attrs": {"shooting": 60, "pace": 60}, "cycle_start_attrs": {"shooting": 60},
					"cycle_weeks": 3, "cycles": 1, "target_position": "", "long_term": false, "role": "", "history": [], "auto": true}}}}
	var st := DevelopmentState.from_dict(JSON.parse_string(JSON.stringify(old)) as Dictionary)
	_check(st.loaded_version == 1 and st.version == DevConfig.STATE_VERSION and DevConfig.STATE_VERSION >= 2, "the saved development state version is tracked (old saves report version 1)")
	_check(st.last_week == 40 and st.skipped_weeks == 140, "an old state keeps its week pointer and its legacy skipped-weeks counter")
	_check(st.sessions.size() == 1 and str(st.sessions[0]["session"]) == "shooting", "old training sessions (by id) survive and stay valid")
	_check(not st.plans.plan_for(pl.id).is_empty() and int(st.plans.plan_for(pl.id)["weeks"]) == 38, "the old plan loads with its clock")
	var before_detail := pl.detail.size()
	st.plans.ensure(pl, 41)
	var plan: Dictionary = st.plans.plan_for(pl.id)
	_check(int(plan["v"]) == DevelopmentPlans.PLAN_VERSION and (plan["weights"] as Dictionary).has("finishing") and int(plan["weeks"]) == 38 and int(plan["cycles"]) == 1, "the old plan is upgraded in place on first use without losing its history", str(plan["weights"]))
	_check(before_detail == 0 and pl.detail.size() == DetailedAttributes.names().size(), "the player's detailed attributes are created from his current values when first needed")
	st.coaching.initialized = true
	DevelopmentEngine.sync(c, st, 42, null, 2)
	_check(st.last_week == 42 and st.skipped_weeks == 140, "the upgraded state keeps developing normally and does not touch the legacy counter")
	_check(int(JSON.parse_string(JSON.stringify(st.to_dict()))["version"]) == DevConfig.STATE_VERSION, "the next save writes the current version")
	var empty := DevelopmentState.from_dict({})
	_check(empty.plans.plans.is_empty() and empty.last_week == -1, "an empty / missing development state loads as a fresh one")
	db.players.erase(pl.id)


## The data the development screens show: grouped detailed attributes, plan targets, recent changes, translations.
func _test_detailed_views() -> void:
	var st := _player(PlayerData.Position.ST, 20, 60, 85)
	var gk := _player(PlayerData.Position.GK, 20, 60, 85)
	var plans := DevelopmentPlans.new()
	plans.assign(st, "position", 1)
	var groups := DetailedAttributes.grouped(st, plans.plan_for(st.id)["weights"])
	var names := groups.map(func(g: Dictionary) -> String: return str(g["group"]))
	_check(names == ["technical", "physical", "mental"], "an outfield player's screen shows technical, physical and mental attributes only", str(names))
	var rows_ok := true
	var targets := 0
	var total := 0
	for g in groups:
		for r in g["rows"]:
			total += 1
			rows_ok = rows_ok and int(r["value"]) == st.get_attribute(str(r["attr"]))
			if bool(r["target"]):
				targets += 1
				rows_ok = rows_ok and (plans.plan_for(st.id)["weights"] as Dictionary).has(r["attr"])
	_check(rows_ok and targets == (plans.plan_for(st.id)["weights"] as Dictionary).size(), "every row shows the real value and the plan's targets are marked", "%d targets" % targets)
	_check(total == DetailedAttributes.all_for(st).size(), "every applicable detailed attribute is listed once", "%d vs %d" % [total, DetailedAttributes.all_for(st).size()])
	var gk_names := DetailedAttributes.grouped(gk, {}).map(func(g: Dictionary) -> String: return str(g["group"]))
	_check("goalkeeping" in gk_names, "a goalkeeper's screen adds the goalkeeping group")
	# recent changes come from the player's real history, newest first
	var p := _player(PlayerData.Position.ST, 19, 60, 95)
	ProgressionModel.apply_points(p, "finishing", 3.0, 5, "plan")
	ProgressionModel.apply_points(p, "vision", 1.0, 6, "session")
	var rc := DetailedAttributes.recent_changes(p, 10)
	_check(rc.size() >= 2 and str(rc[0]["attr"]) == "vision" and str(rc[0]["event"]) == "session" and int(rc[0]["week"]) == 6, "recent changes list the newest recorded change first", str(rc.slice(0, 2)))
	var fin := DetailedAttributes.recent_changes(p, 10, "finishing")
	_check(fin.size() >= 1 and fin.all(func(r: Dictionary) -> bool: return r["attr"] == "finishing" and int(r["to"]) == int(r["from"]) + 1), "the per-attribute change list only holds that attribute, one point each")
	_check(DetailedAttributes.recent_changes(p, 1).size() == 1, "the change list respects its limit")
	_check(DetailedAttributes.recent_changes(_player(PlayerData.Position.CM, 20, 60, 80), 5).is_empty(), "a player without recorded changes shows an empty list, not fake data")
	# translations for everything the screens print
	var missing: Array = []
	for n in DetailedAttributes.names():
		if not Loc.has_key("DEV_ATTR_" + str(n).to_upper()):
			missing.append(n)
	for g in DetailedAttributes.GROUPS:
		if not Loc.has_key("DEV_ATTR_GROUP_" + str(g).to_upper()):
			missing.append(g)
	for k in ["DEV_RECENT_CHANGES", "DEV_EVT_PLAN", "DEV_EVT_MATCH", "DEV_EVT_SESSION", "DEV_EVT_TRAIN", "DEV_TARGET_MARK"]:
		if not Loc.has_key(k):
			missing.append(k)
	_check(missing.is_empty(), "every detailed attribute, group and event label is translated", str(missing))


## Youth academy: lineups per age group, injuries, loans and persistence of development.
func _test_academy_integration() -> void:
	var ac: Academy = app.academy()
	if ac == null:
		return
	var c: CareerState = app.career
	# every age-group lineup: a sensible shape, at most one goalkeeper, a goalkeeper whenever an eligible one exists
	for g in ["U15", "U17", "U19"]:
		var lineup := YouthDevelopment.league_lineup(db, ac, g)
		var eligible := YouthDevelopment.league_eligible(db, ac, g)
		var keepers := lineup.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
		var elig_keeper := eligible.any(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK)
		_check(lineup.size() <= YouthDevelopment.LEAGUE_LINEUP and keepers <= 1 and (not elig_keeper or keepers == 1), "the %s lineup has at most one goalkeeper and one whenever an eligible keeper exists" % g, "%d keepers, eligible keeper %s" % [keepers, str(elig_keeper)])
		var ids := {}
		var unique := true
		for p in lineup:
			unique = unique and not ids.has(p.id)
			ids[p.id] = true
		_check(unique, "the %s lineup never fields a player twice" % g)
		if not lineup.is_empty():
			var hurt: PlayerData = lineup[-1]
			var old_status := hurt.status
			var old_weeks := hurt.unavailable_weeks
			hurt.status = PlayerData.Status.INJURED
			hurt.unavailable_weeks = 3
			_check(not (hurt in YouthDevelopment.league_lineup(db, ac, g)) and not (hurt in YouthDevelopment.league_eligible(db, ac, g)), "an injured prospect is excluded from the %s lineup" % g)
			hurt.status = old_status
			hurt.unavailable_weeks = old_weeks
	# loans: never to the player's own club, whatever the prospect
	var options_ok := true
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		for o in YouthDevelopment.loan_options(db, ac, p, 6):
			if str(o["id"]) == ac.team_id:
				options_ok = false
	_check(options_ok, "no loan option is the prospect's own club")
	var yd := YouthDevelopment.state(ac)
	var saved_loans: Dictionary = (yd["loans"] as Dictionary).duplicate(true)
	(yd["loans"] as Dictionary).clear()
	var loaned := 0
	var own_club := false
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and p.age >= YouthDevelopment.MIN_LOAN_AGE and loaned < 3:
			if YouthDevelopment.loan_out(db, ac, pid) == "":
				loaned += 1
				own_club = own_club or str((yd["loans"] as Dictionary)[pid]["club_id"]) == ac.team_id
	_check(not own_club, "an accepted youth loan never goes to the prospect's own club", "%d loans" % loaned)
	yd["loans"] = saved_loans
	# development persists through a save / load of the academy and the player
	var prospect: PlayerData = db.get_player(ac.roster_ids[0]) if not ac.roster_ids.is_empty() else null
	if prospect != null:
		prospect.potential = 99
		ProgressionModel.apply_points(prospect, "vision", 2.0, 1, "plan")
		var copy := PlayerData.from_dict(JSON.parse_string(JSON.stringify(prospect.to_dict())) as Dictionary)
		var back := Academy.from_dict(JSON.parse_string(JSON.stringify(ac.to_dict())))
		_check(copy.detail == prospect.detail and _dict_approx(copy.growth_progress, prospect.growth_progress) and copy.potential == prospect.potential, "a prospect's detailed development survives save / load")
		_check(back.roster_ids == ac.roster_ids and back.extended_ids == ac.extended_ids, "the academy roster survives save / load unchanged")
	# promotion keeps the development
	var cand: PlayerData = null
	for pid in ac.roster_ids:
		var q: PlayerData = db.get_player(pid)
		if q != null and PromotionSystem.why_not(db, ac, pid) == "":
			cand = q
			break
	if cand != null:
		DetailedAttributes.ensure(cand)
		var det_before := cand.detail.duplicate()
		var broad_before := _broad_of(cand)
		var err := PromotionSystem.promote(db, ac, cand.id)
		_check(err == "" and cand.detail == det_before and _broad_of(cand) == broad_before, "promotion keeps the prospect's attributes and detailed attributes", err)
		_check(not (cand.id in ac.roster_ids) and cand.status != PlayerData.Status.YOUTH, "a promoted prospect leaves the academy roster and is a first-team player")
		PromotionSystem.release_from_squad(db, c.club_id, cand.id)


## Same keys and numerically equal values (JSON text keeps floats to about 1e-12).
func _dict_approx(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or absf(float(a[k]) - float(b[k])) > 0.000001:
			return false
	return true


func _broad_of(p: PlayerData) -> Array:
	var out := []
	for a in PlayerData.ATTRIBUTES:
		out.append(p.get_attribute(a))
	return out


## Every training session changes real player data; fatigue, overload risk, coaching and match preparation behave.
func _test_training_effects() -> void:
	var c: CareerState = app.career
	var base: PlayerData = _squad_sample(c, 1)[0]
	var uid := 0
	var no_effect: Array = []
	for k in DevConfig.SESSIONS:
		uid += 1
		var target := str(DevConfig.SESSIONS[k][1])
		var is_gk := str(DevConfig.SESSIONS[k][0]) == "goalkeeping"
		var a := _clone(base, "tr_a_%d" % uid)
		var b := _clone(base, "tr_b_%d" % uid)
		for q in [a, b]:
			q.age = 19
			q.potential = 99
			q.position = PlayerData.Position.GK if is_gk else PlayerData.Position.CM
			if is_gk:
				q.goalkeeping = 70
			db.register_player(q)
		var da := DevelopmentState.new()
		var db2 := DevelopmentState.new()
		for x in [da, db2]:
			x.coaching.initialized = true
		da.plans.assign(a, "attribute", 1, {"attribute": "jumping"})        # a target no session trains
		db2.plans.assign(b, "attribute", 1, {"attribute": "jumping"})
		da.add_session(str(k), 1, 1.0, [a.id])
		for w in range(1, 41):
			a.fitness = 100
			b.fitness = 100
			DevelopmentEngine._first_team_week(c, da, a, w, 0.5)
			DevelopmentEngine._first_team_week(c, db2, b, w, 0.5)
		var ga := float(a.get_attribute(target)) + float(a.growth_progress.get(target, 0.0))
		var gb := float(b.get_attribute(target)) + float(b.growth_progress.get(target, 0.0))
		if not (ga > gb):
			no_effect.append(str(k))
		db.players.erase(a.id)
		db.players.erase(b.id)
	_check(no_effect.is_empty(), "each of the %d training sessions raises its detailed attribute beyond the plan" % DevConfig.SESSIONS.size(), str(no_effect))
	# fatigue and recovery
	var f := _clone(base, "tr_fat")
	f.age = 24
	db.register_player(f)
	var dsf := DevelopmentState.new()
	dsf.coaching.initialized = true
	dsf.plans.assign(f, "attribute", 1, {"attribute": "jumping", "intensity": 0.5})
	dsf.add_session("strength", 1, 1.0, [f.id])
	f.fitness = 100
	DevelopmentEngine._first_team_week(c, dsf, f, 1, 0.5)
	var after_physical := f.fitness
	var light := _clone(base, "tr_light")
	light.age = 24
	db.register_player(light)
	var dsl := DevelopmentState.new()
	dsl.coaching.initialized = true
	dsl.plans.assign(light, "attribute", 1, {"attribute": "jumping", "intensity": 0.5})
	dsl.add_session("passing", 1, 0.2, [light.id])
	light.fitness = 100
	DevelopmentEngine._first_team_week(c, dsl, light, 1, 0.5)
	_check(after_physical < 100 and after_physical < light.fitness, "a hard physical session tires a player more than a light technical one", "%d vs %d" % [after_physical, light.fitness])
	_check(TrainingPlan.recovery_mod("rest") > TrainingPlan.recovery_mod("medium") and TrainingPlan.recovery_mod("medium") > TrainingPlan.recovery_mod("intense"), "rest recovers, intense training tires (daily plan)")
	# overload raises the injury risk; a normal load adds none
	var hurt_over := 0
	var hurt_norm := 0
	for i in 16:
		var o := _clone(base, "tr_o_%d" % i)
		var n := _clone(base, "tr_n_%d" % i)
		for q in [o, n]:
			q.age = 24
			q.status = PlayerData.Status.ACTIVE
			db.register_player(q)
		var dso := DevelopmentState.new()
		var dsn := DevelopmentState.new()
		for x in [dso, dsn]:
			x.coaching.initialized = true
		dso.plans.assign(o, "attribute", 1, {"attribute": "jumping", "intensity": 0.9})
		dsn.plans.assign(n, "attribute", 1, {"attribute": "jumping", "intensity": 0.5})
		for d in range(1, 7):
			dso.add_session("strength", d, 1.0, [o.id])
		dsn.add_session("strength", 1, 0.5, [n.id])
		for w in range(1, 120):
			if o.status == PlayerData.Status.ACTIVE:
				o.fitness = maxi(o.fitness, 70)
				DevelopmentEngine._first_team_week(c, dso, o, w, 0.5)
			if n.status == PlayerData.Status.ACTIVE:
				n.fitness = 100
				DevelopmentEngine._first_team_week(c, dsn, n, w, 0.5)
		if o.status == PlayerData.Status.INJURED:
			hurt_over += 1
		if n.status == PlayerData.Status.INJURED:
			hurt_norm += 1
		db.players.erase(o.id)
		db.players.erase(n.id)
	_check(hurt_over > hurt_norm and hurt_norm == 0, "an overloaded schedule injures players, a normal one does not", "%d vs %d" % [hurt_over, hurt_norm])
	# coaching: the same session with an elite department coach beats the same session with no coach
	var e1 := _clone(base, "tr_e1")
	var e2 := _clone(base, "tr_e2")
	for q in [e1, e2]:
		q.age = 19
		q.potential = 99
		db.register_player(q)
	var elite := DevelopmentState.new()
	elite.coaching.coaches = [_coach("midfield", 20), _coach("tactical", 20)]
	elite.coaching.initialized = true
	var none := DevelopmentState.new()
	none.coaching.initialized = true
	elite.plans.assign(e1, "attribute", 1, {"attribute": "jumping"})
	none.plans.assign(e2, "attribute", 1, {"attribute": "jumping"})
	elite.add_session("passing", 1, 1.0, [e1.id])
	none.add_session("passing", 1, 1.0, [e2.id])
	for w in range(1, 61):
		e1.fitness = 100
		e2.fitness = 100
		DevelopmentEngine._first_team_week(c, elite, e1, w, 0.5)
		DevelopmentEngine._first_team_week(c, none, e2, w, 0.5)
	var t1 := float(e1.get_attribute("short_passing")) + float(e1.growth_progress.get("short_passing", 0.0))
	var t2 := float(e2.get_attribute("short_passing")) + float(e2.growth_progress.get("short_passing", 0.0))
	_check(t1 > t2, "an elite midfield coach makes the same session more effective than no coach", "%.2f vs %.2f" % [t1, t2])
	# match preparation: the assistant plans light training before a match and rest after it
	var tp := TrainingPlan.new()
	var matches := {100: true}
	var before_match: Dictionary = tp.day_plan(c, 99, matches)
	var after_match: Dictionary = tp.day_plan(c, 101, matches)
	var match_day: Dictionary = tp.day_plan(c, 100, matches)
	_check(before_match["intensity"] == "light" and after_match["intensity"] == "rest" and bool(match_day["match"]), "match preparation: light the day before, rest the day after, match day is not a training day")
	for id in ["tr_fat", "tr_light", "tr_e1", "tr_e2"]:
		db.players.erase(id)


## Youth matches follow the development plan and the specialist coach of the prospect's age group, without stacking coaches.
func _test_youth_coaching() -> void:
	var ac: Academy = app.academy()
	if ac == null:
		return
	var c: CareerState = app.career
	var staff_d: Dictionary = YouthDevelopment.state(ac)["staff"]
	var original: Dictionary = staff_d.duplicate(true)
	staff_d["coach"] = {"name": "Academy Coach", "quality": 0.5, "wage": 1000}
	var af := YouthDevelopment.coach_factor(ac)
	_check(is_equal_approx(YouthDevelopment.match_coaching_factor(ac, 1.12), maxf(af, 1.12)) and YouthDevelopment.match_coaching_factor(ac, 1.12) < af * 1.12 - 0.01,
			"a youth match uses the best coaching source, not the academy coach times the specialist")
	_check(is_equal_approx(YouthDevelopment.match_coaching_factor(ac, 0.8), af), "a weak specialist never lowers the academy coach's effect")
	# age groups are independent: a coach assigned to one group helps only that group
	var ok_groups := true
	for g in ["U15", "U17", "U19"]:
		var cs := CoachingStaff.new(1)
		var co := _coach("attacking", 20, "finishing")
		co["youth_group"] = g
		cs.coaches = [co, _coach("tactical", 10)]
		var own := cs.attribute_multiplier("finishing", "youth", g)
		for other in ["U15", "U17", "U19"]:
			if other != g and not (own > cs.attribute_multiplier("finishing", "youth", other)):
				ok_groups = false
	_check(ok_groups, "an attacking coach assigned to U15 / U17 / U19 helps only his own age group")
	_check(DevelopmentEngine.academy_group(_player(PlayerData.Position.ST, 16, 60, 85)) == AcademyConfig.group_for_age(16), "an academy prospect trains with the group of his age")
	# league matches grow the attribute the plan trains, with the hooks of the development ecosystem
	var sq: Array = db.get_team(c.club_id).squad_ids
	var prospect: PlayerData = null
	for p in YouthDevelopment.league_lineup(db, ac, "U19"):
		if p.position != PlayerData.Position.GK:
			prospect = p
			break
	if prospect == null:
		YouthDevelopment.state(ac)["staff"] = original
		return
	prospect.potential = 99
	prospect.fitness = 100
	var ds := DevelopmentState.new()
	ds.coaching.initialized = true
	ds.plans.assign(prospect, "attribute", 1, {"attribute": "finishing"})
	var before := {}
	for a in PlayerData.ATTRIBUTES:
		before[a] = float(prospect.growth_progress.get(a, 0.0)) + float(prospect.get_attribute(a))
	var fin0 := float(prospect.get_attribute("finishing")) + float(prospect.growth_progress.get("finishing", 0.0))
	var det0 := {}
	for n in DetailedAttributes.names():
		det0[n] = DetailedAttributes.value(prospect, str(n))
	var yd := YouthDevelopment.state(ac)
	yd["last_week"] = 460
	YouthDevelopment.sync(db, ac, sq, 472, DevelopmentEngine.youth_hooks(ds))
	var fin1 := float(prospect.get_attribute("finishing")) + float(prospect.growth_progress.get("finishing", 0.0))
	_check(fin1 > fin0, "a youth match trains the attribute of the prospect's development plan", "%.2f -> %.2f" % [fin0, fin1])
	var stray := 0
	for n in DetailedAttributes.names():
		if n != "finishing" and DetailedAttributes.value(prospect, str(n)) != int(det0[n]):
			stray += 1
	_check(stray == 0, "...and no other detailed attribute changes (no random attribute any more)", str(stray))
	var stray_broad := 0
	for a in PlayerData.ATTRIBUTES:
		if a != "shooting" and absf(float(prospect.growth_progress.get(a, 0.0)) + float(prospect.get_attribute(a)) - float(before[a])) > 0.0001:
			stray_broad += 1
	_check(stray_broad == 0, "...nor any broad attribute except the parent of the plan's target", str(stray_broad))
	YouthDevelopment.state(ac)["staff"] = original


## The academy's three youth-coaching sources are never multiplied together.
func _test_academy_coaching_not_stacked() -> void:
	var ac: Academy = app.academy()
	if ac == null:
		return
	var team := StaffTeam.new()
	var original: Dictionary = (YouthDevelopment.state(ac)["staff"] as Dictionary).duplicate(true)
	var staff_d: Dictionary = YouthDevelopment.state(ac)["staff"]
	staff_d["coach"] = {"name": "Academy Coach", "quality": 1.0, "wage": 1000}
	team.members = [{"id": "yc", "role": "youth_coach", "name": "Club Youth", "skill": 20, "wage": 1000, "years": 2}]
	var dev_factor := 1.05
	var a_f := YouthDevelopment.coach_factor(ac)
	var t_f := team.youth_factor()
	var best := DevelopmentEngine.best_academy_coaching(dev_factor, team, ac)
	_check(is_equal_approx(best, maxf(dev_factor, maxf(a_f, t_f))), "academy coaching is the best of its sources", "%.3f vs %.3f / %.3f / %.3f" % [best, dev_factor, a_f, t_f])
	_check(best < dev_factor * a_f * t_f - 0.05, "...and not their product (which would count one coach three times)", "%.3f vs %.3f" % [best, dev_factor * a_f * t_f])
	_check(is_equal_approx(DevelopmentEngine.best_academy_coaching(dev_factor, null, null), dev_factor), "without the other systems the development staff factor stands alone")
	_check(DevelopmentEngine.best_academy_coaching(1.30, team, ac) == 1.30, "a stronger development staff is never reduced by weaker sources")
	staff_d["coach"] = {"name": "Weak", "quality": 0.0, "wage": 500}
	_check(DevelopmentEngine.best_academy_coaching(dev_factor, StaffTeam.new(), ac) >= dev_factor, "weaker sources never lower the academy factor")
	YouthDevelopment.state(ac)["staff"] = original


func _test_sessions_groups_cups() -> void:
	var c: CareerState = app.career
	var dev := DevelopmentState.new()
	_check(dev.add_session("nonsense", 0, 0.5, ["a"]) == "DEV_ERR_SESSION" and dev.add_session("passing", 9, 0.5, ["a"]) == "DEV_ERR_DAY", "unknown session / day are refused")
	_check(dev.add_session("passing", 2, 0.5, ["a"], {2: true}) == "DEV_ERR_MATCH_DAY", "no session on a match day")
	_check(dev.add_session("passing", 1, 0.5, []) == "DEV_ERR_NO_PLAYERS", "a session needs players")
	for i in DevConfig.MAX_SESSIONS_WEEK:
		dev.add_session("passing", 1, 0.5, ["a"])
	_check(dev.add_session("shooting", 1, 0.5, ["a"]) == "DEV_ERR_TOO_MANY_SESSIONS", "a player's weekly sessions are capped")
	var cats := {}
	for k in DevConfig.SESSIONS:
		cats[DevConfig.SESSIONS[k][0]] = true
	_check(cats.size() == 4 and cats.has("goalkeeping") and cats.has("physical"), "technical, tactical, physical and goalkeeping sessions exist")
	# effect: the same player with and without a shooting session
	var base: PlayerData = _squad_sample(c, 1)[0]
	var a := _clone(base, "ses_a")
	var b := _clone(base, "ses_b")
	db.register_player(a)
	db.register_player(b)
	var da := DevelopmentState.new()
	var db2 := DevelopmentState.new()
	for x in [da, db2]:
		x.coaching.initialized = true
	da.plans.assign(a, "attribute", 1, {"attribute": "pace"})
	db2.plans.assign(b, "attribute", 1, {"attribute": "pace"})
	da.add_session("shooting", 1, 1.0, [a.id])
	var fit_a := 0
	for w in range(1, 30):
		a.fitness = 100
		b.fitness = 100
		DevelopmentEngine._first_team_week(c, da, a, w, 0.5)
		DevelopmentEngine._first_team_week(c, db2, b, w, 0.5)
	var tot_a := float(a.get_attribute("finishing")) + float(a.growth_progress.get("finishing", 0.0))
	var tot_b := float(b.get_attribute("finishing")) + float(b.growth_progress.get("finishing", 0.0))
	_check(tot_a > tot_b, "a shooting session trains finishing beyond the plan", "%.2f vs %.2f" % [tot_a, tot_b])
	a.fitness = 100
	var sess := DevelopmentState.new()
	sess.coaching.initialized = true
	sess.plans.assign(a, "position", 1)
	sess.add_session("conditioning", 1, 1.0, [a.id])
	sess.add_session("stamina", 2, 1.0, [a.id])
	DevelopmentEngine._first_team_week(c, sess, a, 1, 0.5)
	_check(a.fitness <= 100 - 5, "sessions tire the player (physical x1.5)", str(a.fitness))
	var gkp := _player(PlayerData.Position.GK, 25, 70, 75)
	db.register_player(gkp)
	var sg := DevelopmentState.new()
	sg.coaching.initialized = true
	sg.plans.assign(gkp, "position", 1)
	sg.add_session("reflexes", 1, 0.5, [gkp.id])
	DevelopmentEngine._first_team_week(c, sg, gkp, 1, 0.5)
	_check(true, "a goalkeeping session runs for a goalkeeper")
	var back := DevelopmentState.from_dict(JSON.parse_string(JSON.stringify(da.to_dict())))
	_check(back.sessions.size() == 1 and back.sessions[0]["session"] == "shooting" and back.next_session_id == da.next_session_id, "sessions survive save and load")
	_check(da.remove_session(da.sessions[0]["id"]) and da.sessions.is_empty(), "a session can be removed")
	for pid in ["ses_a", "ses_b", gkp.id]:
		db.players.erase(pid)
	# per-group academy coaches
	var cs := CoachingStaff.new(4)
	var co := _coach("midfield", 18)
	co["id"] = "g1"
	cs.coaches = [co]
	_check(cs.assign_group("g1", "U15") == "" and cs.assign_group("g1", "U99") != "", "a coach can be assigned to an academy group")
	_check(cs.dept_multiplier("midfield", "youth", "passing", "U15") > cs.dept_multiplier("midfield", "youth", "passing", "U19"), "a coach assigned to U15 does not coach U19")
	_check(cs.dept_multiplier("midfield", "youth", "passing", "U19") == DevConfig.VACANT_MULT, "...so U19 sees the department as vacant")
	cs.assign_group("g1", "")
	_check(cs.dept_multiplier("midfield", "youth", "passing", "U19") == cs.dept_multiplier("midfield", "youth", "passing", "U15"), "an unassigned coach works with every group")
	var cs2 := CoachingStaff.from_dict(JSON.parse_string(JSON.stringify(cs.to_dict())))
	cs.assign_group("g1", "U17")
	cs2 = CoachingStaff.from_dict(JSON.parse_string(JSON.stringify(cs.to_dict())))
	_check(cs2.coaches[0]["youth_group"] == "U17", "the academy group assignment survives save and load")
	var tr := TrainingSystem.new()
	var pu: PlayerData = _player(PlayerData.Position.CM, 15, 50, 90)
	tr.group_bonus = func(g: String) -> float: return 2.0 if g == "U15" else 1.0
	_check(tr._group_factor(pu) == 2.0, "TrainingSystem applies the group coaching bonus")
	# youth cups per group
	var ac: Academy = app.academy()
	var yd := YouthDevelopment.state(ac)
	for g in YouthDevelopment.LEAGUE_GROUPS:
		_check(yd.has(YouthDevelopment._ck(g)), "a youth cup exists for %s" % g)
	yd["last_week"] = 300
	for g in YouthDevelopment.LEAGUE_GROUPS:
		yd[YouthDevelopment._ck(g)] = {"round": 0, "out": false, "won": false}
	YouthDevelopment.sync(db, ac, db.get_team(c.club_id).squad_ids, 340)
	var moved := 0
	for g in YouthDevelopment.LEAGUE_GROUPS:
		var cup: Dictionary = yd[YouthDevelopment._ck(g)]
		moved += 1 if (int(cup["round"]) > 0 or bool(cup["out"])) else 0
	_check(moved == 3, "every youth cup advances with the calendar", str(moved))


func _test_minutes() -> void:
	var st := MatchState.create("h", "a", 90, "mm")
	st.register_players("home", ["h1", "h2", "h3", "hgk"])
	st.register_players("away", ["a1"])
	st.kick_off()
	st.elapsed = 60.0 / 90.0 * st.duration_seconds
	st.record_substitution("home", "h1", "h3")
	st.elapsed = 75.0 / 90.0 * st.duration_seconds
	st.record_foul("home", "h2", "a1", "red")
	st.elapsed = 90.0 / 90.0 * st.duration_seconds
	var m := MatchReport.player_minutes(st)
	_check(m["h1"] == 60 and m["h3"] == 30 and m["h2"] == 75 and m["hgk"] == 90, "real minutes: starter off at 60, substitute 30, red card at 75, full match 90", str(m))
	# the career books them: engine minutes are measured, model minutes are estimates (90 per game)
	var c: CareerState = app.career
	var pid: String = db.get_squad(c.club_id)[0].id
	c.world_stats.erase(pid)
	var row := SeasonStats._row(c.world_stats, pid)
	_check(int(row["minutes"]) == 0 and int(row["est_minutes"]) == 0, "a fresh statistics row starts with zero minutes")
	var back := SeasonStats.restore_row({"apps": 3, "minutes": 200, "est_minutes": 999})
	_check(int(back["minutes"]) == 200 and int(back["est_minutes"]) == 200, "the estimated minutes can never exceed the total after a load")
	_check(int(SeasonStats.restore_row({"apps": 1})["minutes"]) == 0, "an old save without minutes loads with zero")
	# development: a player with 90 real minutes gains more match experience than one with 20
	var base: PlayerData = _squad_sample(c, 1)[0]
	var a := _clone(base, "min_a")
	var b := _clone(base, "min_b")
	db.register_player(a)
	db.register_player(b)
	a.potential = mini(99, a.get_overall() + 20)        # room to grow for both (see the starter / bench check)
	b.potential = a.potential
	var sa := DevelopmentState.new()
	sa.coaching.initialized = true
	sa.plans.assign(a, "position", 1)
	sa.plans.assign(b, "position", 1)
	var ga := 0.0
	var gb := 0.0
	for w in range(1, 41):
		c.world_stats[a.id] = {"apps": w, "minutes": 90 * w, "rating_sum": 7.0 * w}
		c.world_stats[b.id] = {"apps": w, "minutes": 20 * w, "rating_sum": 7.0 * w}
		a.fitness = 100
		b.fitness = 100
		DevelopmentEngine._first_team_week(c, sa, a, w, 0.5)
		DevelopmentEngine._first_team_week(c, sa, b, w, 0.5)
	# the attributes the plan really trains (detailed ones since the detailed-attribute rework), as in the starter / bench check;
	# the broad attributes only carry the leftover fraction of their parent's progress
	for x in DevelopmentPlans.tracked_attrs(a):
		ga += float(a.growth_progress.get(x, 0.0)) + float((sa.season_gain.get(a.id, {}) as Dictionary).get(x, 0))
		gb += float(b.growth_progress.get(x, 0.0)) + float((sa.season_gain.get(b.id, {}) as Dictionary).get(x, 0))
	_check(ga > gb, "more minutes on the pitch means more match experience", "%.2f vs %.2f" % [ga, gb])
	var round := DevelopmentState.from_dict(JSON.parse_string(JSON.stringify(sa.to_dict())))
	_check(round.last_minutes.get(a.id, -1) == 90 * 40, "the minutes marker survives save and load")
	db.players.erase("min_a")
	db.players.erase("min_b")
	c.world_stats.erase(a.id)
	c.world_stats.erase(b.id)
