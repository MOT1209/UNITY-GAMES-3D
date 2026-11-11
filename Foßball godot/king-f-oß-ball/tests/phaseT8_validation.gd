## Phase T8 validation — fixtures, tables, leagues, knockouts, groups:
##   godot --headless --path . res://tests/phaseT8_validation.tscn
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
	print("=== KING FOOTBALL — Phase T8 validation ===")
	_test_match_result()
	_test_fixture_generator()
	_test_table()
	_test_league()
	_test_knockout()
	_test_third_place_and_byes()
	_test_group_knockout()
	_test_validation_and_persistence()
	_test_promotion_relegation()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _teams(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("t%d" % (i + 1))
	return out


## Deterministic scores. Knockout draws get a penalty winner.
func _result_for(f: Dictionary, salt: int) -> MatchResult:
	var h := (salt * 7 + 3) % 4
	var a := (salt * 5 + 1) % 4
	if f["stage"] == "ko" or f["stage"] == "third":
		if h == a:
			return MatchResult.make(f["match_id"], f["home"], f["away"], h, a, 5, 4)
	return MatchResult.make(f["match_id"], f["home"], f["away"], h, a)


func _play_all(c: Competition) -> int:
	var played := 0
	var guard := 0
	while not c.is_finished() and guard < 500:
		guard += 1
		var pending := c.pending_fixtures()
		if pending.is_empty():
			break
		var f: Dictionary = pending[0]
		var err := c.submit_result(_result_for(f, played))
		if err != "":
			print("  play error: ", err)
			break
		played += 1
	return played


func _test_match_result() -> void:
	_check(MatchResult.make("m", "a", "b", 2, 1).winner_id() == "a", "home win")
	_check(MatchResult.make("m", "a", "b", 0, 1).winner_id() == "b", "away win")
	_check(MatchResult.make("m", "a", "b", 1, 1).winner_id() == "", "draw has no winner")
	_check(MatchResult.make("m", "a", "b", 1, 1, 3, 4).winner_id() == "b", "penalties decide a draw")
	_check(MatchResult.make("m", "a", "b", 1, 1, 3, 4).loser_id() == "a", "loser from penalties")
	_check(MatchResult.make("m", "a", "a", 1, 0).validate().size() > 0, "same team on both sides rejected")
	_check(MatchResult.make("m", "a", "b", -1, 0).validate().size() > 0, "negative goals rejected")
	_check(MatchResult.make("m", "a", "b", 2, 0, 3, 1).validate().size() > 0, "penalties on a decided match rejected")
	_check(MatchResult.make("m", "a", "b", 1, 1, 3, 3).validate().size() > 0, "level shoot-out rejected")
	_check(MatchResult.make("", "a", "b", 1, 0).validate().size() > 0, "missing match id rejected")
	var r := MatchResult.make("m", "a", "b", 2, 2, 4, 3)
	_check(MatchResult.from_dict(JSON.parse_string(JSON.stringify(r.to_dict()))).to_dict() == r.to_dict(), "result round-trip")


func _test_fixture_generator() -> void:
	for n in [4, 6, 8, 5, 7]:
		var teams := _teams(n)
		var rounds := FixtureGenerator.round_robin(teams, true)
		var even: int = n + (n % 2)
		_check(rounds.size() == 2 * (even - 1), "%d teams: %d rounds" % [n, 2 * (even - 1)], str(rounds.size()))
		var total := 0
		var pair_home := {}
		var per_round_ok := true
		for rd in rounds:
			var seen := {}
			for m in rd:
				total += 1
				if seen.has(m["home"]) or seen.has(m["away"]) or m["home"] == m["away"]:
					per_round_ok = false
				seen[m["home"]] = true
				seen[m["away"]] = true
				pair_home["%s>%s" % [m["home"], m["away"]]] = pair_home.get("%s>%s" % [m["home"], m["away"]], 0) + 1
		_check(total == n * (n - 1), "%d teams: %d matches" % [n, n * (n - 1)], str(total))
		_check(per_round_ok, "%d teams: nobody plays twice in a round" % n)
		var each_once := true
		for a in teams:
			for b in teams:
				if a != b and pair_home.get("%s>%s" % [a, b], 0) != 1:
					each_once = false
		_check(each_once, "%d teams: every ordered pair (home/away) exactly once" % n)
	var single := FixtureGenerator.round_robin(_teams(4), false)
	_check(single.size() == 3 and single[0].size() == 2, "single round robin shape")
	_check(FixtureGenerator.round_robin(["a"], true).is_empty(), "one team has no fixtures")
	var rounds := FixtureGenerator.round_robin(_teams(6), false)
	var max_home_streak := 0
	for t in _teams(6):
		var streak := 0
		var best := 0
		for rd in rounds:
			for m in rd:
				if m["home"] == t:
					streak += 1
					best = maxi(best, streak)
				elif m["away"] == t:
					streak = 0
		max_home_streak = maxi(max_home_streak, best)
	_check(max_home_streak <= 3, "no extreme home/away streaks", str(max_home_streak))


func _test_table() -> void:
	var t := LeagueTable.new(["a", "b", "c"])
	_check(t.apply_result(MatchResult.make("m1", "a", "b", 3, 1)) == "", "apply result")
	_check(t.rows["a"]["points"] == 3 and t.rows["b"]["points"] == 0, "win = 3 points")
	_check(t.rows["a"]["gd"] == 2 and t.rows["b"]["gd"] == -2, "goal difference")
	t.apply_result(MatchResult.make("m2", "b", "c", 1, 1))
	_check(t.rows["b"]["points"] == 1 and t.rows["c"]["points"] == 1 and t.rows["b"]["drawn"] == 1, "draw = 1 point each")
	_check(t.apply_result(MatchResult.make("m1", "a", "b", 0, 0)) != "", "duplicate match id rejected")
	_check(t.rows["a"]["played"] == 1, "duplicate did not change the table")
	_check(t.apply_result(MatchResult.make("m3", "a", "zz", 1, 0)) != "", "unknown team rejected")
	var rk := t.ranking()
	_check(rk[0]["team_id"] == "a", "leader first")
	_check(t.position_of("a") == 1 and t.position_of("nobody") == -1, "position_of")
	# Tie-breaks: points equal, goal difference decides, then goals scored, then id.
	var tb := LeagueTable.new(["x", "y", "z", "w"])
	tb.apply_result(MatchResult.make("a", "x", "w", 2, 0))   # x: 3pts gd+2 gf2
	tb.apply_result(MatchResult.make("b", "y", "z", 4, 2))   # y: 3pts gd+2 gf4
	tb.apply_result(MatchResult.make("c", "z", "w", 0, 0))
	var order := tb.ranking().map(func(r: Dictionary) -> String: return r["team_id"])
	_check(order[0] == "y" and order[1] == "x", "goals scored breaks gd tie", str(order))
	var eq := LeagueTable.new(["b", "a"])
	_check(eq.ranking()[0]["team_id"] == "a", "id is the final deterministic tie-break")
	var rt := LeagueTable.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	_check(rt.rows == t.rows and rt.apply_result(MatchResult.make("m1", "a", "b", 1, 0)) != "", "table round-trip keeps processed ids")


func _test_league() -> void:
	var c := Competition.create_league("lg", "Test League", _teams(4), true)
	_check(c.fixtures.size() == 12, "4-team double league has 12 fixtures")
	_check(c.stage == "league" and not c.is_finished(), "league starts in league stage")
	var first: Dictionary = c.fixtures[0]
	_check(c.submit_result(MatchResult.make("nope", "t1", "t2", 1, 0)) != "", "unknown match rejected")
	_check(c.submit_result(MatchResult.make(first["match_id"], first["away"], first["home"], 1, 0)) != "", "swapped teams rejected")
	_check(c.submit_result(MatchResult.make(first["match_id"], first["home"], first["away"], 2, 0)) == "", "valid result accepted")
	_check(c.submit_result(MatchResult.make(first["match_id"], first["home"], first["away"], 2, 0)) != "", "same fixture cannot be played twice")
	_check(c.pending_fixtures().size() == 11, "pending fixtures decrease")
	var played := _play_all(c)
	_check(played == 11 and c.is_finished(), "league completes after all fixtures", str(played))
	var table := c.standings()
	var total_points := 0
	var total_played := 0
	var gf := 0
	var ga := 0
	for row in table:
		total_points += row["points"]
		total_played += row["played"]
		gf += row["gf"]
		ga += row["ga"]
		_check(row["played"] == 6, "%s played 6" % row["team_id"])
		_check(row["won"] + row["drawn"] + row["lost"] == row["played"], "%s W+D+L = played" % row["team_id"])
	_check(gf == ga, "goals for equal goals against league-wide")
	var draws := 0
	for row in table:
		draws += row["drawn"]
	var draw_matches := draws / 2
	_check(total_points == 3 * (12 - draw_matches) + 2 * draw_matches, "league points consistent with results")
	_check(c.champion_id == table[0]["team_id"], "champion = table leader")
	_check(c.runner_up_id == table[1]["team_id"], "runner-up = second place")
	_check(c.history.size() == 1 and c.history[0]["champion"] == c.champion_id, "competition history recorded")
	_check(c.awards().has("best_attack"), "league awards include best attack")
	_check(c.results.size() == 12, "12 stored results (no duplicates)")
	var after := c.submit_result(MatchResult.make(first["match_id"], first["home"], first["away"], 1, 1))
	_check(after != "", "finished league rejects further results")
	var odd := Competition.create_league("odd", "Odd", _teams(5), false)
	_check(odd.fixtures.size() == 10, "5-team single league has 10 fixtures")
	_play_all(odd)
	var all_four := true
	for row in odd.standings():
		if row["played"] != 4:
			all_four = false
	_check(odd.is_finished() and all_four, "odd-sized league completes (byes)")


func _test_knockout() -> void:
	var c := Competition.create_knockout("ko", "Cup", _teams(8), false)
	_check(c.fixtures.size() == 4 and c.stage == "knockout", "8-team cup starts with 4 quarter-finals")
	_check(c.fixtures[0]["home"] == "t1" and c.fixtures[0]["away"] == "t8", "seeded pairing 1 v 8")
	var f: Dictionary = c.fixtures[0]
	_check(c.submit_result(MatchResult.make(f["match_id"], f["home"], f["away"], 1, 1)) != "", "knockout draw without penalties rejected")
	_check(not f["played"], "rejected result changes nothing")
	_check(c.submit_result(MatchResult.make(f["match_id"], f["home"], f["away"], 1, 1, 4, 5)) == "", "penalty win accepted")
	var rounds_seen := 1
	var guard := 0
	var played := 1
	while not c.is_finished() and guard < 50:
		guard += 1
		for p in c.pending_fixtures():
			c.submit_result(_result_for(p, played + 10))
			played += 1
	_check(c.is_finished(), "cup finishes")
	_check(c.results.size() == 7, "8-team cup plays exactly 7 matches", str(c.results.size()))
	_check(c.champion_id != "" and c.runner_up_id != "" and c.champion_id != c.runner_up_id, "champion and runner-up differ")
	var br := c.bracket()
	_check(br.size() == 3 and br[0].size() == 4 and br[1].size() == 2 and br[2].size() == 1, "bracket has 4/2/1 matches")
	var final: Dictionary = br[2][0]
	_check(final["winner"] == c.champion_id, "final winner is the champion")
	var seen_loser := {}
	for rd in br:
		for m in rd:
			var loser: String = m["home"] if m["winner"] == m["away"] else m["away"]
			_check(not seen_loser.has(loser), "eliminated team %s never plays again" % loser)
			seen_loser[loser] = true
	_check(c.history.size() == 1, "cup history recorded")
	var two := Competition.create_knockout("f", "Final", _teams(2), false)
	_check(two.fixtures.size() == 1, "2-team cup is a single final")


func _test_third_place_and_byes() -> void:
	var c := Competition.create_knockout("c3", "Cup3", _teams(8), true)
	_play_all(c)
	_check(c.is_finished() and c.results.size() == 8, "cup with third-place match plays 8 matches", str(c.results.size()))
	_check(c.third_id != "", "third place decided")
	var distinct := {c.champion_id: 1, c.runner_up_id: 1, c.third_id: 1}
	_check(distinct.size() == 3, "top three are different teams")
	var b6 := Competition.create_knockout("c6", "Cup6", _teams(6), false)
	_check(b6.fixtures.size() == 2, "6-team cup: 2 play-in matches, 2 byes")
	var bye_pair := [b6.fixtures[0]["home"], b6.fixtures[0]["away"], b6.fixtures[1]["home"], b6.fixtures[1]["away"]]
	_check(not ("t1" in bye_pair) and not ("t2" in bye_pair), "top seeds receive byes")
	_play_all(b6)
	_check(b6.is_finished() and b6.results.size() == 5, "6-team cup plays 5 matches", str(b6.results.size()))
	var b3 := Competition.create_knockout("c5", "Cup5", _teams(5), true)
	_play_all(b3)
	_check(b3.is_finished() and b3.champion_id != "", "5-team cup completes")
	var b7 := Competition.create_knockout("c7", "Cup7", _teams(7), false)
	_play_all(b7)
	_check(b7.is_finished() and b7.results.size() == 6, "7-team cup plays 6 matches", str(b7.results.size()))


func _test_group_knockout() -> void:
	var c := Competition.create_group_knockout("gk", "World Cup", _teams(8), 2, true)
	_check(c.stage == "groups" and c.fixtures.size() == 12, "2 groups of 4 = 12 group fixtures")
	_check(c.groups["A"].size() == 4 and c.groups["B"].size() == 4, "teams split into groups")
	var in_two := false
	for t in c.groups["A"]:
		if t in c.groups["B"]:
			in_two = true
	_check(not in_two, "team is in only one group")
	var cross_group := false
	for f in c.fixtures:
		if (f["home"] in c.groups["A"]) != (f["away"] in c.groups["A"]):
			cross_group = true
	_check(not cross_group, "group fixtures stay inside groups")
	# Knockout stage must not exist before groups end.
	var pending_before := c.pending_fixtures().size()
	for f in c.fixtures.duplicate():
		if not f["played"]:
			c.submit_result(_result_for(f, c.results.size()))
	_check(c.stage == "knockout" or c.stage == "finished", "knockout starts after the groups", c.stage)
	_check(pending_before == 12, "all 12 group fixtures were pending")
	var a_rank := c.standings("A")
	var b_rank := c.standings("B")
	var semi: Array = c.pending_fixtures()
	_check(semi.size() == 2, "two semi-finals", str(semi.size()))
	_check(semi[0]["home"] == a_rank[0]["team_id"] and semi[0]["away"] == b_rank[1]["team_id"], "A1 plays B2")
	_check(semi[1]["home"] == b_rank[0]["team_id"] and semi[1]["away"] == a_rank[1]["team_id"], "B1 plays A2")
	_play_all(c)
	_check(c.is_finished(), "group + knockout tournament finishes")
	_check(c.results.size() == 12 + 2 + 2, "12 group + 2 semis + final + third = 16", str(c.results.size()))
	_check(c.third_id != "" and c.champion_id != "", "champion and third place decided")
	var g8 := Competition.create_group_knockout("g8", "Big Cup", _teams(16), 4, false)
	_play_all(g8)
	_check(g8.is_finished() and g8.results.size() == 24 + 4 + 2 + 1, "16 teams / 4 groups: 24 + QF 4 + SF 2 + F 1", str(g8.results.size()))


func _test_validation_and_persistence() -> void:
	_check(Competition.validate_setup(Competition.Type.LEAGUE, ["a", "a"]) != "", "duplicate registration rejected")
	_check(Competition.validate_setup(Competition.Type.LEAGUE, ["a"]) != "", "single team rejected")
	_check(Competition.validate_setup(Competition.Type.LEAGUE, _teams(4)) == "", "valid league setup")
	_check(Competition.validate_setup(Competition.Type.GROUP_KNOCKOUT, _teams(8), 3) != "", "odd group count rejected")
	_check(Competition.validate_setup(Competition.Type.GROUP_KNOCKOUT, _teams(9), 2) != "", "uneven groups rejected")
	_check(Competition.validate_setup(Competition.Type.GROUP_KNOCKOUT, _teams(18), 6) != "", "non power-of-two qualifiers rejected")
	_check(Competition.validate_setup(Competition.Type.GROUP_KNOCKOUT, _teams(8), 2) == "", "valid group setup")
	# Save mid-competition, reload, finish: identical to playing straight through.
	var a := Competition.create_group_knockout("p", "P", _teams(8), 2, true)
	var b := Competition.create_group_knockout("p", "P", _teams(8), 2, true)
	var n := 0
	for i in 8:
		var f: Dictionary = a.pending_fixtures()[0]
		var r := _result_for(f, n)
		a.submit_result(r)
		b.submit_result(r)
		n += 1
	var reloaded := Competition.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	_check(reloaded.results.size() == 8 and reloaded.stage == a.stage, "mid-competition save/load keeps state")
	var dup := reloaded.get_fixture(reloaded.results.keys()[0])
	_check(reloaded.submit_result(MatchResult.make(dup["match_id"], dup["home"], dup["away"], 0, 0)) != "", "reloaded competition still rejects duplicate results")
	_play_all(a)
	_play_all(reloaded)
	_check(reloaded.is_finished() and reloaded.champion_id == a.champion_id, "reloaded competition ends with the same champion")
	_check(reloaded.to_dict()["results"] == a.to_dict()["results"], "identical results after reload")
	var ko := Competition.create_knockout("kk", "KK", _teams(4), false)
	var pending := ko.pending_fixtures()
	ko.submit_result(_result_for(pending[0], 1))
	var ko2 := Competition.from_dict(JSON.parse_string(JSON.stringify(ko.to_dict())))
	ko2.submit_result(_result_for(ko2.pending_fixtures()[0], 2))
	_check(ko2.pending_fixtures().size() == 1 and ko2.pending_fixtures()[0]["stage"] == "ko", "knockout continues after reload (final created)")


func _test_promotion_relegation() -> void:
	var upper := Competition.create_league("u", "Upper", _teams(4), false)
	var lower := Competition.create_league("l", "Lower", ["l1", "l2", "l3", "l4"], false)
	_play_all(upper)
	_play_all(lower)
	var pr := Competition.promotion_relegation(upper, lower, 1)
	_check(pr["relegated"].size() == 1 and pr["promoted"].size() == 1, "one up, one down")
	_check(pr["relegated"][0] == upper.standings()[3]["team_id"], "bottom of upper relegated")
	_check(pr["promoted"][0] == lower.standings()[0]["team_id"], "winner of lower promoted")
	_check(pr["upper"].size() == 4 and pr["lower"].size() == 4, "league sizes preserved")
	_check(pr["upper"].has(pr["promoted"][0]) and pr["lower"].has(pr["relegated"][0]), "teams moved between leagues")
	var all_ids := {}
	for t in pr["upper"] + pr["lower"]:
		all_ids[t] = true
	_check(all_ids.size() == 8, "no team lost or duplicated")
