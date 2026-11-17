## Phase S acceptance (SLOW): 10,000 simulated matches in the real pack (random home / away pairs inside a country).
##   goals per match 2.4-2.8, home win 42-46 %, draw 24-28 %, six or more goals <= 4 %, a 10-point stronger side wins 55-65 %.
##   godot --headless --path . res://tests/event_sim_validation.tscn
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s — %s" % [name, detail])
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	var app: Node = get_node("/root/AppHub")
	app.switch_world("real_2025")
	var db: Node = app.db
	var clubs: Array = db.list_teams(TeamData.Category.CLUB)
	var by_country := {}
	for t: TeamData in clubs:
		if not by_country.has(t.country):
			by_country[t.country] = []
		by_country[t.country].append(t.id)
	var countries: Array = by_country.keys().filter(func(k: String) -> bool: return (by_country[k] as Array).size() >= 8)
	countries.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var ratings := {}
	var n := 10000
	var goals := 0
	var hw := 0
	var dr := 0
	var big := 0
	var strong_n := 0
	var strong_w := 0
	var strong_d := 0
	for i in n:
		var list: Array = by_country[countries[rng.randi() % countries.size()]]
		var h: String = list[rng.randi() % list.size()]
		var a: String = list[rng.randi() % list.size()]
		if h == a:
			continue
		var f := {"match_id": "es%d" % i, "home": h, "away": a, "stage": "league", "group": "", "round": 1}
		var r := MatchSimulator.result(db, f, 7, ratings)
		goals += r.home_goals + r.away_goals
		hw += 1 if r.home_goals > r.away_goals else 0
		dr += 1 if r.home_goals == r.away_goals else 0
		big += 1 if r.home_goals + r.away_goals >= 6 else 0
		var diff := MatchSimulator.rating_of(db, h, ratings) - MatchSimulator.rating_of(db, a, ratings)
		if absi(diff) >= 10:
			strong_n += 1
			var sw := (r.home_goals > r.away_goals) == (diff > 0) and r.home_goals != r.away_goals
			strong_w += 1 if sw else 0
			strong_d += 1 if r.home_goals == r.away_goals else 0
	print("  %d matches: %.2f goals, home %.1f %% draw %.1f %%, 6+ goals %.1f %%, stronger (>=10) wins %.1f %% of %d (draws %.1f %%)" % [n, float(goals) / n,
			100.0 * hw / n, 100.0 * dr / n, 100.0 * big / n, 100.0 * strong_w / maxf(strong_n, 1.0), strong_n, 100.0 * strong_d / maxf(strong_n, 1.0)])
	_check(float(goals) / n >= 2.4 and float(goals) / n <= 2.8, "goals per match 2.4-2.8", "%.2f" % (float(goals) / n))
	_check(100.0 * hw / n >= 42.0 and 100.0 * hw / n <= 46.0, "home wins 42-46 %", "%.1f %%" % (100.0 * hw / n))
	_check(100.0 * dr / n >= 24.0 and 100.0 * dr / n <= 28.0, "draws 24-28 %", "%.1f %%" % (100.0 * dr / n))
	_check(100.0 * big / n <= 4.0, "six or more goals in at most 4 % of matches", "%.1f %%" % (100.0 * big / n))
	_check(strong_n > 100 and 100.0 * strong_w / maxf(strong_n, 1.0) >= 55.0 and 100.0 * strong_w / maxf(strong_n, 1.0) <= 70.0, "a 10-point stronger side wins 55-70 %", "%.1f %%" % (100.0 * strong_w / maxf(strong_n, 1.0)))
	var determ := MatchSimulator.result(db, {"match_id": "d1", "home": clubs[0].id, "away": clubs[1].id, "stage": "league", "group": "", "round": 1}, 5)
	var determ2 := MatchSimulator.result(db, {"match_id": "d1", "home": clubs[0].id, "away": clubs[1].id, "stage": "league", "group": "", "round": 1}, 5)
	_check(determ.home_goals == determ2.home_goals and determ.away_goals == determ2.away_goals, "the same seed gives the same score", "")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
