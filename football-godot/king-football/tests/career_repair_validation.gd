## PR #88 repair: dashboard wage bill with loans, the empty-results leak, the next-point estimate with saved progress,
## seasonal vs cumulative growth, and money texts that keep a difference visible.
##   godot --headless --path . res://tests/career_repair_validation.tscn
extends Node

const CareerScreenScript := preload("res://scripts/ui/screens/career_screen.gd")

var _passed := 0
var _failed := 0
var app: Node
var db: Node
var _used := {}


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Career repair validation (PR #88) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	db = get_node("/root/TeamDB")
	Loc.set_language("en", false)
	_test_wages()
	await _test_results_leak()
	_test_next_point()
	_test_growth()
	_test_money_texts()
	await _test_screens()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ------------------------------------------------------------------------------------------------- FIX 01

## Moves `p` from `from_id` to `to_id` on loan with the borrower paying `split` % (`split` < 0: a broken record).
func _loan(m: TransferMarket, p: PlayerData, from_id: String, to_id: String, split: int) -> void:
	var a: TeamData = db.get_team(from_id)
	var b: TeamData = db.get_team(to_id)
	a.squad_ids.erase(p.id)
	b.squad_ids.append(p.id)
	p.team_id = to_id
	p.loan_parent = from_id
	var rec := {"from": from_id, "to": to_id, "type": TransferOffer.LOAN}
	if split >= 0:
		rec["wage_split"] = split
	m.loans[p.id] = rec


func _unloan(m: TransferMarket, p: PlayerData, from_id: String, to_id: String) -> void:
	(db.get_team(to_id) as TeamData).squad_ids.erase(p.id)
	(db.get_team(from_id) as TeamData).squad_ids.append(p.id)
	p.team_id = from_id
	p.loan_parent = ""
	m.loans.erase(p.id)


func _test_wages() -> void:
	var c: CareerState = app.career
	var m: TransferMarket = c.market
	var me := c.club_id
	var other := ""
	for tid in db.teams:
		if tid != me and (db.get_team(tid) as TeamData).squad_ids.size() > 3:
			other = tid
			break
	var base_me := m.weekly_wages(me)
	var base_other := m.weekly_wages(other)
	var saved_loans := m.loans.duplicate(true)
	m.loans.clear()
	_check(CareerScreenScript.dashboard_wages(c) == base_me and m.wage_bill(me) == base_me, "[wage] no loans: dashboard = plain squad salaries", "%d vs %d" % [CareerScreenScript.dashboard_wages(c), base_me])
	var mine: PlayerData = db.get_player((db.get_team(me) as TeamData).squad_ids[0])
	var theirs: PlayerData = db.get_player((db.get_team(other) as TeamData).squad_ids[0])
	var theirs2: PlayerData = db.get_player((db.get_team(other) as TeamData).squad_ids[1])
	mine.salary = 40_000
	theirs.salary = 4_000
	theirs2.salary = 10_001
	base_me = m.weekly_wages(me)
	base_other = m.weekly_wages(other)
	# borrower pays 100%: the lender pays nothing, the borrower everything
	_loan(m, theirs, other, me, 100)
	_check(m.wage_bill(me) == base_me + 4_000 and m.wage_bill(other) == base_other - 4_000, "[wage] borrower pays 100%",
			"%d / %d" % [m.wage_bill(me), m.wage_bill(other)])
	# parent (lender) pays 100%: the borrower pays nothing
	m.loans[theirs.id]["wage_split"] = 0
	_check(m.wage_bill(me) == base_me and m.wage_bill(other) == base_other, "[wage] parent club pays 100%", "%d / %d" % [m.wage_bill(me), m.wage_bill(other)])
	# 25% (the CodeRabbit case: salary 4000, share 25% -> the borrower pays 1000)
	m.loans[theirs.id]["wage_split"] = 25
	_check(m.wage_bill(me) == base_me + 1_000 and m.wage_bill(other) == base_other - 1_000, "[wage] 25% share: 1000 of 4000 for the borrower")
	_check(CareerScreenScript.dashboard_wages(c) == m.wage_bill(me), "[wage] the dashboard shows the loan-adjusted wage bill (finance screen figure)")
	# 50 / 50 on an odd salary: both parts add up to the salary, nothing is counted twice or lost
	_loan(m, theirs2, other, me, 50)
	var total_before: int = base_me + base_other
	_check(m.wage_bill(me) + m.wage_bill(other) == total_before, "[wage] 50/50 on 10,001: both clubs together pay exactly the salaries",
			"%d vs %d" % [m.wage_bill(me) + m.wage_bill(other), total_before])
	_check(m.wage_bill(me) == base_me + 1_000 + 5_000, "[wage] 50/50: the borrower pays the rounded-down half", str(m.wage_bill(me)))
	# my player out on loan with 60% paid by the borrower: I still pay 40%
	_loan(m, mine, me, other, 60)
	_check(m.wage_bill(me) == base_me - 40_000 + 1_000 + 5_000 + 16_000, "[wage] multiple loans: own player out (40% retained) + two borrowed",
			str(m.wage_bill(me)))
	_check(m.wage_bill(me) + m.wage_bill(other) == total_before, "[wage] multiple loans: no double counting across both clubs")
	_check(CareerScreenScript.dashboard_wages(c) == m.wage_bill(me), "[wage] dashboard total = wage_bill with three loans")
	# broken records: missing split = borrower pays all; out of range is clamped; text is ignored
	m.loans[theirs.id].erase("wage_split")
	m.loans[theirs2.id]["wage_split"] = 250
	m.loans[mine.id]["wage_split"] = "abc"
	_check(m.wage_bill(me) == base_me - 40_000 + 4_000 + 10_001 and m.wage_bill(me) + m.wage_bill(other) == total_before,
			"[wage] missing / out-of-range / non-numeric split: safe defaults, totals still consistent", str(m.wage_bill(me)))
	m.loans["ghost_player"] = {"from": other, "to": me, "wage_split": 50}
	m.loans["bad_record"] = "not a loan"
	_check(m.wage_bill(me) + m.wage_bill(other) == total_before, "[wage] loans of unknown players / non-dictionary records are skipped")
	_check(TransferMarket.loan_wage_split({}) == 100 and TransferMarket.loan_wage_split({"wage_split": -5}) == 0 and TransferMarket.lender_part(4_000, {"wage_split": 25}) == 3_000,
			"[wage] loan_wage_split / lender_part defaults and clamps")
	m.loans.erase("ghost_player")
	m.loans.erase("bad_record")
	_unloan(m, theirs, other, me)
	_unloan(m, theirs2, other, me)
	_unloan(m, mine, me, other)
	m.loans = saved_loans


# ------------------------------------------------------------------------------------------------- FIX 02

func _test_results_leak() -> void:
	var c: CareerState = app.career
	_check(CareerCalendar.recent_results(c, 5).is_empty(), "[leak] a new career has no results (empty state)")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("career")
	await get_tree().process_frame
	var screen: Node = hub.current
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 25:
		var card: Control = screen._form_card(c)
		card.free()
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(after == before, "[leak] 25 empty-results cards leave no orphan nodes", "orphans %d -> %d" % [before, after])
	# populated: play the first match week so results exist, then rebuild again
	for i in 12:
		if not CareerCalendar.recent_results(c, 5).is_empty():
			break
		app.advance_week()
	var res := CareerCalendar.recent_results(c, 5)
	_check(not res.is_empty(), "[leak] results exist after a few weeks", str(c.week))
	before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var lines_ok := true
	for i in 25:
		var card: Control = screen._form_card(c)
		lines_ok = lines_ok and card.find_child("DashResults", true, false) != null
		card.free()
	after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(after == before and lines_ok, "[leak] 25 populated cards: results shown, no orphan nodes", "orphans %d -> %d" % [before, after])
	hub.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------------------------------------- FIX 03

## A first-team outfield player without a plan, made young with room to grow, on a fresh balanced plan.
func _planned(c: CareerState) -> PlayerData:
	for p: PlayerData in db.get_squad(c.club_id):
		if _used.has(p.id) or p.position == PlayerData.Position.GK or p.status != PlayerData.Status.ACTIVE:
			continue
		p.age = 19
		p.potential = mini(p.get_overall() + 15, 99)
		p.fitness = 100
		_used[p.id] = true
		c.development.plans.plans.erase(p.id)                     # a fresh plan (the career may have given every player one)
		if c.development.plans.assign(p, "balanced", c.absolute_week()) == "":
			return p
	return null


func _test_next_point() -> void:
	var c: CareerState = app.career
	var plans: DevelopmentPlans = c.development.plans
	var p := _planned(c)
	var fq := DevelopmentEngine.facility_quality(c)
	var pr := plans.progress(p, fq)
	var lead := str(pr["lead_attr"])
	var full := float(pr["weeks_per_point"])
	_check(lead != "" and full > 0.0, "[next] the plan has a lead attribute and a weekly rate", "%s %f" % [lead, full])
	p.growth_progress[lead] = 0.0
	_check(is_equal_approx(float(plans.progress(p, fq)["next_point_weeks"]), full), "[next] zero saved progress: the full-point interval")
	p.growth_progress[lead] = 0.5
	_check(is_equal_approx(float(plans.progress(p, fq)["next_point_weeks"]), full * 0.5), "[next] half a point saved: half the interval")
	p.growth_progress[lead] = 0.95
	var near := float(plans.progress(p, fq)["next_point_weeks"])
	_check(is_equal_approx(near, full * 0.05), "[next] 0.95 saved: only the last 5% remains", "%f vs %f" % [near, full])
	for bad: Variant in [-0.4, "x", NAN]:
		p.growth_progress[lead] = bad
		_check(is_equal_approx(float(plans.progress(p, fq)["next_point_weeks"]), full), "[next] broken saved progress (%s) counts as zero" % str(bad))
	p.growth_progress.erase(lead)
	_check(is_equal_approx(float(plans.progress(p, fq)["next_point_weeks"]), full), "[next] missing saved progress counts as zero")
	# the estimate matches the engine: apply the exact weekly amount the estimate assumes until the point arrives
	p.growth_progress[lead] = 0.6
	var est := ceili(float(plans.progress(p, fq)["next_point_weeks"]) - 0.0001)
	var per_week := 1.0 / full
	var before := p.get_attribute(lead)
	var weeks := 0
	while p.get_attribute(lead) == before and weeks < 500:
		ProgressionModel.apply_points(p, lead, per_week, c.absolute_week(), "train")
		weeks += 1
	_check(weeks == est, "[next] the estimate (%d weeks) matches the weeks the progress model needs (%d)" % [est, weeks])
	# a loaded career keeps the saved progress and gives the same estimate
	p.growth_progress[lead] = 0.7
	var want := float(plans.progress(p, fq)["next_point_weeks"])
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true))
	var c2 := CareerState.from_dict(db, parsed)
	_check(c2.development.plans.plans.has(p.id), "[next] the plan survives save / load")
	var got := float(c2.development.plans.progress(p, fq)["next_point_weeks"])
	_check(is_equal_approx(got, want), "[next] after loading: the same estimate from the same saved progress", "%f vs %f" % [got, want])
	var round_trip := PlayerData.from_dict(p.to_dict())
	_check(is_equal_approx(float(round_trip.growth_progress.get(lead, 0.0)), 0.7), "[next] growth_progress is part of the player save")


# ------------------------------------------------------------------------------------------------- FIX 04

func _test_growth() -> void:
	var c: CareerState = app.career
	var dev: DevelopmentState = c.development
	var plans: DevelopmentPlans = dev.plans
	var p := _planned(c)
	var plan: Dictionary = plans.plan_for(p.id)
	_check(int(plan.get("season_start_overall", -1)) == p.get_overall(), "[growth] a new plan records the season baseline")
	var pr := plans.progress(p)
	var g := DevelopmentPlans.growth_summary(dev, p, pr)
	_check(int(g["season_points"]) == 0 and int(g["total_overall"]) == 0 and int(g["total_points"]) == 0 and bool(g["season_known"]),
			"[growth] no development yet: season 0, total 0")
	# a season with growth: two whole points through the weekly engine path
	var lead := str(pr["lead_attr"])
	dev.season_gain.erase(p.id)
	var start_attr := p.get_attribute(lead)
	var gained := DevelopmentEngine._apply(dev, p, lead, 2.0, c.absolute_week(), "train")
	g = DevelopmentPlans.growth_summary(dev, p, plans.progress(p))
	_check(gained == 2 and int(g["season_points"]) == 2 and int(g["total_points"]) == 2, "[growth] two points this season: season 2, total 2",
			"gained %d, %s" % [gained, str(g)])
	# the season boundary for this player in the order of CareerState.end_season: the season report clears the season
	# counters, the yearly growth of the ending season follows, then the new season takes its baseline
	var season0 := c.season
	DevelopmentEngine.season_end(c, dev, 0.5)
	p.growth_progress[lead] = 0.0
	ProgressionModel.apply_points(p, lead, 1.0, c.absolute_week(), "season_development")   # the yearly growth (PlayerLifecycle) of the season that ended
	c.season += 1
	plans.mark_season_start(db.get_player)
	_check(plans.plans.has(p.id), "[growth] the planned player keeps the plan over the season change")
	pr = plans.progress(p)
	g = DevelopmentPlans.growth_summary(dev, p, pr)
	var plan2: Dictionary = plans.plan_for(p.id)
	_check(int(plan2["season_start_overall"]) == p.get_overall(), "[growth] the new season's baseline is the overall after the yearly growth")
	_check(int(g["season_points"]) == 0 and int(g["season_overall"]) == 0, "[growth] new season, no development yet: season +0 / 0 points", str(g))
	_check(int(g["total_points"]) == p.get_attribute(lead) - int((plan2["start_attrs"] as Dictionary)[lead]) + _other_gains(p, plan2, lead)
			and int(g["total_overall"]) == p.get_overall() - int(plan2["start_overall"]), "[growth] cumulative growth survives the season change", str(g))
	_check(p.get_attribute(lead) >= start_attr + 3, "[growth] the season's attribute gains are still in the player")
	# old save without a season baseline: seasonal overall is unknown (not mixed with cumulative), points still shown
	plan2.erase("season_start_overall")
	var parsed := JSON.parse_string(JSON.stringify(plans.to_dict())) as Dictionary
	var loaded := DevelopmentPlans.from_dict(parsed)
	var g_old := DevelopmentPlans.growth_summary(dev, p, loaded.progress(p))
	_check(not bool(g_old["season_known"]) and int(g_old["total_overall"]) == int(g["total_overall"]), "[growth] save without a season baseline: season overall unknown, total unchanged")
	plans.mark_season_start(db.get_player)
	var reloaded := DevelopmentPlans.from_dict(JSON.parse_string(JSON.stringify(plans.to_dict())) as Dictionary)
	_check(int(reloaded.plan_for(p.id).get("season_start_overall", -1)) == p.get_overall(), "[growth] the season baseline survives save / load")
	# switching the plan keeps both baselines
	var before_total := int(plans.progress(p)["overall_change"])
	plans.assign(p, "long_term", c.absolute_week())
	_check(int(plans.plan_for(p.id).get("season_start_overall", -1)) == p.get_overall() and int(plans.progress(p)["overall_change"]) == before_total,
			"[growth] a plan switch keeps the season and the cumulative baseline")
	# the real rollover wires the baseline: after CareerState.end_season every plan starts the new season at the overall now
	c.end_season()
	var wired := c.season == season0 + 2 and not plans.plans.is_empty()
	for pid in plans.plans:
		var q: PlayerData = db.get_player(pid)
		wired = wired and q != null and int((plans.plans[pid] as Dictionary).get("season_start_overall", -1)) == q.get_overall()
	_check(wired, "[growth] CareerState.end_season sets the new season's baseline of every plan", "%d plans" % plans.plans.size())


func _other_gains(p: PlayerData, plan: Dictionary, skip: String) -> int:
	var s := 0
	for a in (plan["weights"] as Dictionary):
		if a != skip:
			s += p.get_attribute(a) - int((plan["start_attrs"] as Dictionary).get(a, p.get_attribute(a)))
	return s


# ------------------------------------------------------------------------------------------------- money texts

func _test_money_texts() -> void:
	var near := Loc.f("ERR_WAGE_BUDGET_ROOM", [204_123, 204_124])
	_check(near.find(Loc.num(204_123)) >= 0 and near.find(Loc.num(204_124)) >= 0, "[money] amounts that round alike are shown exactly", near)
	var far := Loc.f("ERR_WAGE_BUDGET_ROOM", [204_123, 450_000])
	_check(far.find(Loc.money(204_123)) >= 0 and far.find(Loc.money(450_000)) >= 0 and far.find("K") >= 0, "[money] different amounts stay K / M", far)
	var same := Loc.f("ERR_TRANSFER_BUDGET", [1_200_000, 1_200_000])
	_check(same.find(Loc.money(1_200_000)) >= 0, "[money] equal amounts stay K / M", same)


# ------------------------------------------------------------------------------------------------- screens

func _test_screens() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var p := _planned(c)
	var lead := str(c.development.plans.progress(p)["lead_attr"])
	p.growth_progress[lead] = 0.9
	for lang in ["en", "ar", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("player_profile", {"player_id": p.id})
		await get_tree().process_frame
		var total := hub.current.find_child("DevTotal", true, false) as Label
		var season := hub.current.find_child("DevSeason", true, false) as Label
		var nxt := hub.current.find_child("DevNext", true, false) as Label
		_check(total != null and season != null and nxt != null and total.text != season.text, "[ui %s] the profile shows season and total growth separately" % lang)
		hub.navigate("career")
		await get_tree().process_frame
		var w := hub.current.find_child("DashWages", true, false) as Label
		_check(w != null and w.text == Loc.money(c.market.wage_bill(c.club_id)), "[ui %s] dashboard wages = wage_bill" % lang, w.text if w != null else "missing")
	Loc.set_language("en", false)
	hub.navigate("player_profile", {"player_id": p.id})
	await get_tree().process_frame
	var expected := maxi(ceili(float(c.development.plans.progress(p, DevelopmentEngine.facility_quality(c))["next_point_weeks"])), 1)
	var nl := hub.current.find_child("DevNext", true, false) as Label
	_check(nl != null and nl.text == Loc.f("PROFILE_DEV_NEXT", expected), "[ui] the next-point line uses the saved progress", nl.text if nl != null else "missing")
	# open and close the dashboard repeatedly: no orphan nodes stay behind
	hub.navigate("career")
	await get_tree().process_frame
	await get_tree().process_frame
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 10:
		hub.navigate("squad")
		await get_tree().process_frame
		hub.navigate("career")
		await get_tree().process_frame
	await get_tree().process_frame
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(after <= before, "[ui] dashboard opened / closed 10 times: no orphan nodes", "%d -> %d" % [before, after])
	_check(app.week_advanced.get_connections().size() <= 1, "[ui] no duplicate week_advanced connections", str(app.week_advanced.get_connections().size()))
	hub.queue_free()
	await get_tree().process_frame
