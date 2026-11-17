## Phases K3 / S / H: daily life, training plan, event engine, live match, radar projection, team centre.
##   godot --headless --path . res://tests/daily_sim_validation.tscn
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s%s" % [name, (" — " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — daily life / event simulation validation ===")
	var db: Node = get_node("/root/TeamDB")
	var app: Node = get_node("/root/AppHub")
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_daily_life(app)
	_test_training_plan(app)
	_test_event_engine(app.db)
	_test_live_match(app.db)
	_test_radar_projection()
	_test_team_center(app)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_daily_life(app: Node) -> void:
	var c: CareerState = app.career
	var p: PlayerData = app.db.get_squad(c.club_id)[0]
	p.status = PlayerData.Status.ACTIVE
	p.fitness = 50
	var young := DailyLife.recovery(_with_age(p, 20))
	var old := DailyLife.recovery(_with_age(p, 34))
	_check(young > old, "young players recover faster than old ones", "%.1f > %.1f" % [young, old])
	_check(DailyLife.recovery(p, TrainingPlan.recovery_mod("rest")) > DailyLife.recovery(p, TrainingPlan.recovery_mod("intense")), "a rest day recovers more than an intense one")
	_check(DailyLife.match_fatigue("CM") > DailyLife.match_fatigue("GK"), "a midfielder tires more than a goalkeeper in a match")
	var f0 := p.fitness
	DailyLife.day(c, CareerDate.jdn_of(1, 1, 0))
	_check(p.fitness > f0, "fitness recovers on a day (%d -> %d)" % [f0, p.fitness])
	p.status = PlayerData.Status.INJURED
	p.unavailable_days = 2
	p.unavailable_weeks = 1
	DailyLife.day(c, CareerDate.jdn_of(1, 1, 1))
	_check(p.status == PlayerData.Status.INJURED and p.unavailable_days == 1, "an injury counts down by one day")
	DailyLife.day(c, CareerDate.jdn_of(1, 1, 2))
	_check(p.status == PlayerData.Status.ACTIVE and p.unavailable_weeks == 0, "the player is available the day it reaches 0")
	var dd := c.to_dict()
	var c2 := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(dd)))
	_check(c2.day == c.day and c2.training.to_dict() == c.training.to_dict(), "day and training plan survive a save")


func _with_age(p: PlayerData, age: int) -> PlayerData:
	var q := PlayerData.new()
	q.age = age
	q.physical = p.physical
	return q


func _test_training_plan(app: Node) -> void:
	var c: CareerState = app.career
	var days := CareerCalendar.season_days(c)
	_check(not days.is_empty(), "the season has user match days")
	var md := int(days[0]["jdn"])
	var plan := c.training.day_plan(c, md)
	_check(plan["match"] and plan["intensity"] == "match", "a match day is a match day")
	_check(c.training.day_plan(c, md + 1)["intensity"] == "rest" or CareerCalendar.season_days(c).any(func(e: Dictionary) -> bool: return int(e["jdn"]) == md + 1),
			"the day after a match is rest (unless another match)")
	_check(c.training.day_plan(c, md - 1)["intensity"] == "light" or CareerCalendar.season_days(c).any(func(e: Dictionary) -> bool: return int(e["jdn"]) == md - 1),
			"the day before a match is light")
	var free := md + 20
	while days.any(func(e: Dictionary) -> bool: return abs(int(e["jdn"]) - free) <= 2):
		free += 1
	_check(c.training.day_plan(c, free)["intensity"] == "intense" and c.training.day_plan(c, free)["auto"], "a free day is planned intense by the assistant")
	_check(c.training.set_day(free, "rest", "fitness") == "" and c.training.day_plan(c, free)["intensity"] == "rest" and not c.training.day_plan(c, free)["auto"],
			"the user can override a day")
	_check(c.training.set_day(free, "nonsense") != "", "a bad intensity is refused")
	c.training.set_day(free, "")
	_check(c.training.day_plan(c, free)["auto"], "clearing the override gives the assistant's plan back")
	_check(c.training.day_plan(c, md)["match"], "match days cannot be overridden away")


func _test_event_engine(db: Node) -> void:
	var ids: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	ids.sort()
	var ok_sum := true
	var det := true
	for i in 40:
		var h: String = ids[i % ids.size()]
		var a: String = ids[(i + 3) % ids.size()]
		var hg := i % 5
		var ag := (i * 3) % 4
		var r1 := MatchEventEngine.distribute(db, h, a, hg, ag, "m%d" % i)
		var r2 := MatchEventEngine.distribute(db, h, a, hg, ag, "m%d" % i)
		det = det and JSON.stringify(r1) == JSON.stringify(r2)
		var gh := 0
		var ga := 0
		for ev in r1["events"]:
			if ev["type"] == "goal":
				if ev["side"] == "home":
					gh += 1
				else:
					ga += 1
		ok_sum = ok_sum and gh == hg and ga == ag
		ok_sum = ok_sum and (r1["lineups"]["home"] as Array).size() == 11
	_check(ok_sum, "the scorers of every match add up to the team's goals (40 matches)")
	_check(det, "the same seed gives the same record")
	var r := MatchEventEngine.distribute(db, ids[0], ids[1], 3, 0, "x")
	var gk_ok := true
	for ev in r["events"]:
		if ev["type"] == "goal":
			var pl: PlayerData = db.get_player(str(ev["player_id"]))
			gk_ok = gk_ok and pl != null and pl.position != PlayerData.Position.GK
	_check(gk_ok, "a goalkeeper never scores")
	var fw := 0
	var total := 0
	for i in 200:
		var rr := MatchEventEngine.distribute(db, ids[i % ids.size()], ids[(i + 1) % ids.size()], 2, 1, "f%d" % i, true, true, [], [], true)
		for ev in rr["events"]:
			if ev["type"] == "goal":
				total += 1
				var pl: PlayerData = db.get_player(str(ev["player_id"]))
				if pl.position in [PlayerData.Position.ST, PlayerData.Position.LW, PlayerData.Position.RW]:
					fw += 1
	_check(float(fw) / maxf(total, 1.0) >= 0.4, "forwards score at least 40 % of the goals", "%.0f %%" % (100.0 * fw / maxf(total, 1.0)))


func _test_live_match(db: Node) -> void:
	var ids: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	ids.sort()
	var live := MatchEventEngine.LiveMatch.new(db, ids[0], ids[1], 5)
	var goals := 0
	while not live.finished():
		for ev in live.step():
			if ev["type"] == "goal":
				goals += 1
	_check(live.minute == 90 and goals == int(live.score["home"]) + int(live.score["away"]), "a live match runs 90 minutes and its goal events equal the score", str(live.score))
	var att_goals := 0
	var def_goals := 0
	for s in 60:
		var a := MatchEventEngine.LiveMatch.new(db, ids[0], ids[1], 100 + s)
		a.mentality["home"] = 1
		var d := MatchEventEngine.LiveMatch.new(db, ids[0], ids[1], 100 + s)
		d.mentality["home"] = -1
		while not a.finished():
			a.step()
		while not d.finished():
			d.step()
		att_goals += int(a.score["home"])
		def_goals += int(d.score["home"])
	_check(att_goals > def_goals, "an attacking mentality scores more than a defensive one (60 matches)", "%d vs %d" % [att_goals, def_goals])
	var l2 := MatchEventEngine.LiveMatch.new(db, ids[0], ids[1], 9)
	var on_id: String = (l2.xi["home"][3] as PlayerData).id
	var bench: PlayerData = null
	for p: PlayerData in db.get_squad(ids[0]):
		if not (p.id in (l2.xi["home"] as Array).map(func(q: PlayerData) -> String: return q.id)) and p.position != PlayerData.Position.GK:
			bench = p
			break
	_check(bench != null and l2.substitute("home", on_id, bench.id) == "" and int(l2.subs_used["home"]) == 1, "a substitution works")
	var rec := l2.record()
	_check(rec.has("events") and rec.has("ratings") and (rec["lineups"]["home"] as Array).has(bench.id), "the live record holds the lineup after the substitution")


func _test_radar_projection() -> void:
	var r := Rect2(Vector2(10, 10), Vector2(240, 150))
	_check(MatchRadar.project(0.0, 0.0, r).is_equal_approx(r.get_center()), "the centre spot is the centre of the radar")
	_check(MatchRadar.project(0.0, -PitchSpace.HALF_LENGTH, r).x == r.position.x and MatchRadar.project(0.0, PitchSpace.HALF_LENGTH, r).x == r.end.x,
			"the goal lines are the left and right edges")
	_check(MatchRadar.project(-PitchSpace.HALF_WIDTH, 0.0, r).y == r.position.y and MatchRadar.project(PitchSpace.HALF_WIDTH, 0.0, r).y == r.end.y,
			"the touchlines are the top and bottom edges")


func _test_team_center(app: Node) -> void:
	var c: CareerState = app.career
	var squad: Array = app.db.get_squad(c.club_id)
	c.season_stats[squad[0].id] = {"1:fic_league_s1": {"apps": 3, "goals": 2, "assists": 1, "saves": 0, "rating_sum": 21.0, "motm": 0, "yellow": 1, "red": 0, "clean_sheets": 0}}
	c.sim_comp_stats[squad[0].id] = {"1:fic_cup_s1": {"apps": 1, "goals": 1, "assists": 0, "saves": 0, "rating_sum": 7.5, "motm": 0, "yellow": 0, "red": 0, "clean_sheets": 0}}
	var t: Dictionary = load("res://scripts/ui/screens/team_center_screen.gd").totals(c, squad[0].id, 1)
	_check(t["apps"] == 4 and t["goals"] == 3 and t["assists"] == 1 and t["cards"] == 1 and t["est_apps"] == 1, "team centre totals = the sum of every competition", str(t))
	_check(absf(float(t["rating"]) - 28.5 / 4.0) < 0.01, "the average rating weighs every match")
	var rows: Array = load("res://scripts/ui/screens/team_center_screen.gd").table_rows(c, app.db, "goals", true)
	var sorted := true
	for i in range(1, rows.size()):
		sorted = sorted and int(rows[i - 1]["goals"]) >= int(rows[i]["goals"])
	_check(sorted and rows[0]["goals"] == 3, "sorting by goals puts the top scorer first")
	rows = load("res://scripts/ui/screens/team_center_screen.gd").table_rows(c, app.db, "name", false)
	var by_name := true
	for i in range(1, rows.size()):
		by_name = by_name and str(rows[i - 1]["name"]) <= str(rows[i]["name"])
	_check(by_name, "sorting by name works")
