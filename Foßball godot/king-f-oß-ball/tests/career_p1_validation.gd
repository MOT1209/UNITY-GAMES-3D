## Career P1 validation (fictional default world, fast): core flows, the integrity validator (including fault injection),
## the performance-critical data structures, save / load at every stage, resume determinism, corrupt and incomplete saves
## and migration from every supported historical save version.
##   godot --headless --path . res://tests/career_p1_validation.tscn
## The long-term runs (10 seasons in both worlds, the real data pack, performance measurements) are in
## `career_p1_long_validation`.
extends Node

const CLUB := "club_royal_harbor"

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
	print("=== KING FOOTBALL — Career P1 validation (core, integrity, save, migration) ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	_test_overall_cache()
	_test_competition_index()
	_test_ledger_compaction()
	_test_new_career()
	_test_weekly_progression()
	_test_match_simulation()
	_test_cup()
	_test_stats_real_vs_estimated()
	_test_season_completion()
	_test_playoff_rounds()
	_test_validator_detects_faults()
	_test_save_stages()
	_test_resume_determinism()
	_test_corrupt_and_missing_fields()
	_test_migrations()
	await _test_async_week()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- helpers -----------------------------------------------------------------------------------------

func _career() -> CareerState:
	db.load_world("")
	var c := CareerState.start(db, CLUB)
	c.add_default_league()
	return c


func _play(c: CareerState, weeks: int) -> void:
	for i in weeks:
		c.advance_week()


func _fingerprint(c: CareerState) -> String:
	var ids: Array = db.players.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		var p: PlayerData = db.players[id]
		parts.append("%s|%s|%d|%d|%d|%d|%d|%d|%d|%d" % [id, p.team_id, p.age, p.status, p.unavailable_weeks, p.contract_years,
				p.salary, p.pace, p.shooting, p.goalkeeping])
	return JSON.stringify(c.to_dict(), "", true).sha256_text().substr(0, 16) + "/" + "\n".join(parts).sha256_text().substr(0, 16)


## capture -> JSON text -> parse -> migrate -> restore into `db`; returns {ok, errors, career}.
func _save_reload(c: CareerState) -> Dictionary:
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(), "user_team_id": c.club_id})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	var res := SaveManager.restore(db, parsed)
	if not res["ok"]:
		return {"ok": false, "errors": res["errors"], "career": null}
	return {"ok": true, "errors": [], "career": CareerState.from_dict(db, res["extras"]["career"])}


func _audit(c: CareerState) -> Dictionary:
	return CareerValidator.validate(c, true)


func _clean(c: CareerState) -> bool:
	var a := _audit(c)
	return (a["errors"] as Array).is_empty() and (a["warnings"] as Array).is_empty()


func _audit_text(c: CareerState) -> String:
	var a := _audit(c)
	return str((a["errors"] as Array).slice(0, 3)) + str((a["warnings"] as Array).slice(0, 3))


func _ref_overall(p: PlayerData) -> int:
	var w: Dictionary = PlayerData.OVERALL_WEIGHTS[p.position]
	var total := 0.0
	for a in w:
		total += float(p.get_attribute(a)) * float(w[a])
	return clampi(roundi(total), PlayerData.MIN_RATING, PlayerData.MAX_RATING)


func _engine_report(c: CareerState, fixture: Dictionary, uid: String, hg: int, ag: int) -> Dictionary:
	var rows: Array = []
	var home := db.get_squad(fixture["home"])
	var away := db.get_squad(fixture["away"])
	for i in 11:
		rows.append({"player_id": home[i].id, "side": "home", "rating": 7.5, "goals": 1 if i == 9 else 0, "assists": 1 if i == 8 else 0,
				"saves": 0, "yellow": 0, "red": 0, "fouled": 0, "shots": 0, "shots_on_target": 0, "passes": 10, "passes_ok": 8, "own_goals": 0,
				"fouls": 0, "offsides": 0})
		rows.append({"player_id": away[i].id, "side": "away", "rating": 6.0, "goals": 0, "assists": 0, "saves": 0, "yellow": 1 if i == 3 else 0,
				"red": 0, "fouled": 0, "shots": 0, "shots_on_target": 0, "passes": 10, "passes_ok": 7, "own_goals": 0, "fouls": 0, "offsides": 0})
	return {"version": 1, "source": "engine", "uid": uid, "match_id": fixture["match_id"], "home_id": fixture["home"], "away_id": fixture["away"],
			"home_goals": hg, "away_goals": ag, "outcome_home": 1, "players": rows, "motm": home[9].id, "scorers": [], "team_stats": {}}


# --- data structures (performance-critical code) ----------------------------------------------------------

func _test_overall_cache() -> void:
	var p: PlayerData = db.get_squad(CLUB)[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad := 0
	for i in 400:
		match i % 4:
			0: p.set(PlayerData.ATTRIBUTES[rng.randi() % 7], rng.randi_range(1, 99))
			1: p.position = rng.randi() % 12 as PlayerData.Position
			2: p.pace = rng.randi_range(1, 99)
			3: p.goalkeeping += 1
		if p.get_overall() != _ref_overall(p):
			bad += 1
	_check(bad == 0, "get_overall() (cached) equals the weight formula after 400 mutations by property, set() and position changes", str(bad))
	var copy := p.duplicate() as PlayerData
	copy.shooting = 99
	copy.position = PlayerData.Position.ST
	_check(copy.get_overall() == _ref_overall(copy) and p.get_overall() == _ref_overall(p), "a duplicate has its own overall: the original is not affected")
	var back := PlayerData.from_dict(p.to_dict())
	_check(back.get_overall() == p.get_overall(), "an overall survives to_dict / from_dict")
	var same := true
	for q in db.players.values():
		same = same and (q as PlayerData).get_overall() == _ref_overall(q)
	_check(same, "every player of the world: cached overall == formula (%d players)" % db.players.size())


func _results_for(c: Competition, fixtures: Array, seed_value: int) -> void:
	for f in fixtures:
		var r := MatchResult.make(f["match_id"], f["home"], f["away"], (seed_value + f["round"]) % 4, (seed_value * 3 + f["round"]) % 3)
		if f["stage"] == "ko" and r.home_goals == r.away_goals:
			r = MatchResult.make(f["match_id"], f["home"], f["away"], 1, 1, 4, 3)
		var err := c.submit_result(r)
		if err != "":
			print("   submit_result: ", err)


func _test_competition_index() -> void:
	var teams := ["a", "b", "c", "d", "e", "f"]
	var lg := Competition.create_league("t_lg", "T", teams, true)
	_check(lg.fixtures.size() == 30 and lg.pending_fixtures().size() == 30 and lg.max_round() == 10, "indexed league: 30 fixtures, 30 pending, 10 rounds")
	_check(lg.get_fixture(lg.fixtures[7]["match_id"]) == lg.fixtures[7] and lg.get_fixture("nope").is_empty(), "get_fixture finds by id, unknown ids give {}")
	var first: Dictionary = lg.fixtures[0]
	_check(lg.submit_result(MatchResult.make(first["match_id"], first["home"], first["away"], 2, 1)) == "" and lg.pending_fixtures().size() == 29,
			"a result removes exactly one pending fixture")
	_check(lg.submit_result(MatchResult.make(first["match_id"], first["home"], first["away"], 2, 1)) != "" and lg.pending_fixtures().size() == 29,
			"the same fixture cannot be played twice")
	_check(lg.submit_result(MatchResult.make(first["match_id"], first["away"], first["home"], 2, 1)) != "", "a result for other teams is refused")
	var order := lg.pending_fixtures().duplicate()
	order.reverse()                                          # play the rest back to front: the cursor must not skip anything
	for f in order:
		lg.submit_result(MatchResult.make(f["match_id"], f["home"], f["away"], 1, 0))
	_check(lg.is_finished() and lg.pending_fixtures().is_empty() and lg.champion_id != "", "all 30 played in reverse order: finished with a champion")
	var rows := lg.standings()
	var total_played := 0
	for r in rows:
		total_played += int(r["played"])
	_check(total_played == 60, "league table: every club played 10 games (60 appearances)")
	var back := Competition.from_dict(JSON.parse_string(JSON.stringify(lg.to_dict(), "", true)))
	_check(back.pending_fixtures().is_empty() and back.is_finished() and back.max_round() == 10 and back.get_fixture(first["match_id"])["played"],
			"a reloaded competition rebuilds its index")
	_check(back.rules["win"] is int and back.rules["draw"] is int and back.rules["groups"] is int, "rules come back as ints (JSON floats are restored)")
	var ko := Competition.create_knockout("t_ko", "K", ["a", "b", "c", "d", "e", "f", "g", "h"], false)
	_check(ko.pending_fixtures().size() == 4, "knockout of 8: 4 quarter-finals")
	_results_for(ko, ko.pending_fixtures(), 1)
	var semis := ko.pending_fixtures()
	_check(semis.size() == 2 and ko.get_fixture(semis[0]["match_id"]) == semis[0], "fixtures created after a round are found by the index")
	_results_for(ko, semis, 2)
	_results_for(ko, ko.pending_fixtures(), 3)
	_check(ko.is_finished() and ko.champion_id != "" and ko.runner_up_id != "" and ko.results.size() == 7, "knockout of 8 plays 7 matches")
	var dup := Competition.create_league("t_dup", "D", ["x", "y"], true)
	dup.fixtures.append(dup.fixtures[0].duplicate(true))      # a damaged fixture list: the validator reports it, the index stays safe
	_check(dup.get_fixture(dup.fixtures[0]["match_id"]) == dup.fixtures[0] and dup.pending_fixtures().size() == 3, "a duplicated fixture id resolves to the first fixture")


func _test_ledger_compaction() -> void:
	var l := FinanceLedger.new("x", 1_000_000, 500_000, 90_000)
	var cats := ["salary", "sponsorship", "match_revenue", "competition_reward", "transfer_in"]
	for i in 400:
		var cat: String = cats[i % 5]
		var amount := (-(1000 + i)) if cat in ["salary", "transfer_in"] else (500 + 3 * i)
		l.record(cat, amount, "t%d" % i, i % 46 + 1, "FIN_X", [i, "n"])
	var balance := l.balance
	var totals := {}
	for c in FinanceLedger.CATEGORIES:
		totals[c] = l.total(c)
	_check(l.compact(1000) == 0 and l.entries.size() == 400, "a short ledger is left alone")
	var folded := l.compact(50)
	_check(folded > 0 and l.entries.size() <= 50 + FinanceLedger.CATEGORIES.size(), "compaction keeps the newest 50 entries plus one summary per category", str(l.entries.size()))
	_check(l.balance == balance and l.is_consistent(), "balance and audit are unchanged by compaction")
	var same := true
	for c in FinanceLedger.CATEGORIES:
		same = same and l.total(c) == totals[c]
	_check(same, "every category total is unchanged by compaction")
	var ids := {}
	for e in l.entries:
		ids[e["id"]] = true
	_check(ids.size() == l.entries.size() and l.next_entry_id > ids.keys().max(), "entry ids stay unique and never reused")
	_check(l.entries[0].get("key", "") == "FIN_SUMMARY" and Loc.has_key("FIN_SUMMARY", "en"), "summaries carry a translation key that exists")
	for i in 100:
		l.record("sponsorship", 10 + i, "more", 1, "FIN_SPONSORSHIP")
	l.compact(50)
	_check(l.entries.size() <= 50 + FinanceLedger.CATEGORIES.size() and l.is_consistent(), "a second compaction merges old summaries (bounded)")
	var back := FinanceLedger.from_dict(JSON.parse_string(JSON.stringify(l.to_dict(), "", true)))
	_check(JSON.stringify(back.to_dict(), "", true) == JSON.stringify(l.to_dict(), "", true), "a compacted ledger round-trips exactly (args stay ints)")


# --- core flows -----------------------------------------------------------------------------------------

func _test_new_career() -> void:
	var c := _career()
	_check(c.club_id == CLUB and c.season == 1 and c.week == 0, "new career: managed club, season 1, week 0")
	_check(c.ledgers.size() == db.list_teams(TeamData.Category.CLUB).size() and c.club_levels.size() == c.ledgers.size(), "every club gets a ledger and a base level")
	_check(c.pyramids.size() == 1 and c.competitions.size() == 2, "the default world gets a league and a cup")
	var lg := c.competitions["fic_league_s1"] as Competition
	_check(lg.fixtures.size() == 56 and lg.max_round() == 14, "8 clubs: 56 league fixtures in 14 rounds")
	_check(_clean(c), "a new career passes the full integrity audit", _audit_text(c))
	_check(CareerState.start(db, "no_such_club") == null and CareerState.start(db, "nat_aldoria") == null, "starting with an unknown club or a national team is refused")
	_check(not c.add_default_league(), "the default league is added only once")


func _test_weekly_progression() -> void:
	var c := _career()
	var lg := c.competitions["fic_league_s1"] as Competition
	var played_by_week := {}
	var total_auto := 0
	var user_pending_seen := 0
	for w in 46:
		var before := lg.results.size()
		var info := c.advance_week()
		_check_week(c, info, w + 1)
		played_by_week[w + 1] = lg.results.size() - before
		user_pending_seen += (info["user_fixtures"] as Array).filter(func(f: Dictionary) -> bool: return f["competition_id"] == "fic_league_s1").size()
		total_auto += (info["auto_played"] as Array).filter(func(mid: String) -> bool: return mid.begins_with("fic_league_s1")).size()
		if w in [0, 1, 11, 22, 45]:
			_check(_clean(c), "audit after week %d is clean" % (w + 1), _audit_text(c))
	var info := c.advance_week()
	_check(info.get("blocked", false) and c.week == 46 and info["simulated"] == 0, "week 47 is refused: nothing is played or paid")
	_check(lg.results.size() == 56 and lg.is_finished(), "every league match is played exactly once (56 results)", str(lg.results.size()))
	_check(user_pending_seen == 14 and total_auto == 14, "the user's 14 league matches wait in their week and are simulated the week after", "%d / %d" % [user_pending_seen, total_auto])
	var rows := lg.standings()
	var played := 0
	var points := 0
	var gf := 0
	var ga := 0
	for r in rows:
		played += int(r["played"])
		points += int(r["points"])
		gf += int(r["gf"])
		ga += int(r["ga"])
		_check_row(r)
	_check(played == 112 and gf == ga, "table: 112 appearances (14 per club) and goals for == goals against", "%d %d %d" % [played, gf, ga])
	var wins := 0
	var draws := 0
	for r in rows:
		wins += int(r["won"])
		draws += int(r["drawn"])
	_check(points == 3 * wins + draws and points == 3 * 56 - draws / 2, "points: 3 per win and 1 per draw (each draw is in two rows)", "%d %d %d" % [points, wins, draws])


func _check_row(r: Dictionary) -> void:
	if int(r["won"]) + int(r["drawn"]) + int(r["lost"]) != int(r["played"]) or int(r["gf"]) - int(r["ga"]) != int(r["gd"]) \
			or int(r["points"]) != 3 * int(r["won"]) + int(r["drawn"]):
		_check(false, "table row of %s is consistent" % r["team_id"], str(r))


func _check_week(c: CareerState, info: Dictionary, expect_week: int) -> void:
	if c.week != expect_week or info["week"] != expect_week:
		_check(false, "advance_week moves the calendar by exactly one week", "%d / %d" % [c.week, expect_week])


func _test_match_simulation() -> void:
	_career()
	var teams := db.list_teams(TeamData.Category.CLUB)
	var f := {"match_id": "m_x", "home": teams[0].id, "away": teams[1].id, "stage": "league", "round": 1, "group": "", "played": false}
	var a := MatchSimulator.result(db, f, 7)
	var b := MatchSimulator.result(db, f, 7)
	_check(a.to_dict() == b.to_dict(), "the same fixture and seed always give the same result")
	var ratings := {}
	var cached := MatchSimulator.result(db, f, 7, ratings)
	_check(cached.to_dict() == a.to_dict() and ratings.size() == 2, "a rating cache gives the identical result")
	var differs := false
	for s in 30:
		differs = differs or MatchSimulator.result(db, f, s).to_dict() != a.to_dict()
	_check(differs, "other seeds give other results")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var total := 0
	for i in 4000:
		total += MatchSimulator.goals(rng, 0)
	var mean := float(total) / 4000.0
	_check(mean > 1.15 and mean < 1.45, "goals per team for equal strength: mean %.2f (model 1.3)" % mean)
	var strong_wins := 0
	var weak_wins := 0
	for i in 1500:
		var hg := MatchSimulator.goals(rng, 10)
		var ag := MatchSimulator.goals(rng, -10)
		strong_wins += 1 if hg > ag else 0
		weak_wins += 1 if ag > hg else 0
	_check(strong_wins > 2 * weak_wins, "a 20-point stronger side wins more than twice as often (%d vs %d)" % [strong_wins, weak_wins])
	var ko_ok := true
	for i in 300:
		var kf := {"match_id": "ko_%d" % i, "home": teams[0].id, "away": teams[1].id, "stage": "ko", "round": 1, "group": "", "played": false}
		var r := MatchSimulator.result(db, kf, i)
		ko_ok = ko_ok and r.validate().is_empty() and r.winner_id() != ""
	_check(ko_ok, "knockout results always have a winner (penalties after a draw) and are valid")


func _test_cup() -> void:
	var c := _career()
	var cup := c.competitions["fic_cup_s1"] as Competition
	_check(cup.type == Competition.Type.KNOCKOUT and cup.pending_fixtures().size() == 4, "cup of 8: four first-round matches")
	var weeks_of_rounds := {}
	for w in 46:
		var before := cup.results.size()
		c.advance_week()
		if cup.results.size() != before:
			weeks_of_rounds[w + 1] = cup.results.size() - before
	_check(cup.is_finished() and cup.champion_id != "" and cup.results.size() == 7, "the cup finishes with a champion after 7 matches")
	_check(weeks_of_rounds.keys().size() >= 3 and weeks_of_rounds.keys().min() >= 5 and weeks_of_rounds.keys().max() <= 18,
			"cup rounds are played in their weeks (5, 11, 17): %s" % str(weeks_of_rounds))
	var bracket := cup.bracket()
	var chain_ok := bracket.size() == 3
	for r in range(1, bracket.size()):
		var winners: Array = (bracket[r - 1] as Array).map(func(m: Dictionary) -> String: return m["winner"])
		var entrants: Array = []
		for m in bracket[r]:
			entrants.append(m["home"])
			entrants.append(m["away"])
		winners.sort()
		entrants.sort()
		chain_ok = chain_ok and winners == entrants
	_check(chain_ok, "every round is played by exactly the winners of the round before")
	_check(c.club_history.filter(func(h: Dictionary) -> bool: return h.get("key", "") == "rewards_paid_fic_cup_s1").size() == 1, "cup prize money is paid once")
	var rewarded := (c.ledgers[cup.champion_id] as FinanceLedger).entries.any(func(e: Dictionary) -> bool:
		return e["category"] == "competition_reward" and int(e["amount"]) == 1_000_000)
	_check(rewarded, "the cup champion received the winner's prize")
	_check(_clean(c), "audit after the cup is clean", _audit_text(c))


func _test_stats_real_vs_estimated() -> void:
	var c := _career()
	_play(c, 10)
	var all_est := not c.world_stats.is_empty()
	var goals := 0
	for pid in c.world_stats:
		var r: Dictionary = c.world_stats[pid]
		all_est = all_est and r["apps"] == r["est_apps"] and r["goals"] == r["est_goals"] and r["assists"] == r["est_assists"] \
				and r["clean_sheets"] == r["est_clean_sheets"] and is_equal_approx(r["rating_sum"], r["est_rating_sum"])
		goals += int(r["goals"])
	_check(all_est, "simulated matches are recorded as estimates only (est_* == totals)")
	_check(c.player_stats.is_empty() and c.season_stats.is_empty() and c.match_log.is_empty(),
			"estimates never enter the measured statistics (player_stats / season_stats / match_log stay empty)")
	var model_goals := 0
	for cid in c.competitions:
		for mid in (c.competitions[cid] as Competition).results:
			var res: Dictionary = (c.competitions[cid] as Competition).results[mid]
			model_goals += int(res["hg"]) + int(res["ag"])
	_check(goals == model_goals, "goals in the model statistics == goals of all simulated results (recorded exactly once)", "%d vs %d" % [goals, model_goals])
	# a real engine match of the user
	var lg := c.competitions["fic_league_s1"] as Competition
	var fx := {}
	for f in lg.pending_fixtures():
		if f["home"] == CLUB:
			fx = f
			break
	_check(not fx.is_empty(), "the user has a pending home match")
	var est_before := 0
	var apps_before := 0
	for pid in c.world_stats:
		est_before += int(c.world_stats[pid]["est_apps"])
		apps_before += int(c.world_stats[pid]["apps"])
	var rep := _engine_report(c, fx, "uid_test_1", 2, 0)
	_check(c.record_match(rep, lg.id), "an engine report is recorded")
	_check(not c.record_match(rep.duplicate(true), lg.id), "the same report is not recorded twice")
	var err := c.submit_result(lg.id, MatchResult.make(fx["match_id"], fx["home"], fx["away"], 2, 0))
	var est_after := 0
	var apps_after := 0
	for pid in c.world_stats:
		est_after += int(c.world_stats[pid]["est_apps"])
		apps_after += int(c.world_stats[pid]["apps"])
	_check(err == "" and est_after == est_before, "the model adds nothing for a match that has an engine report", "%d -> %d" % [est_before, est_after])
	_check(apps_after - apps_before == 22, "the engine report counted exactly 22 appearances (11 per side)", str(apps_after - apps_before))
	var scorer_id: String = db.get_squad(CLUB)[9].id
	var row: Dictionary = c.world_stats[scorer_id]
	_check(row["apps"] - row["est_apps"] >= 1 and row["goals"] - row["est_goals"] == 1, "real = total - estimated separates the engine goal from model goals")
	_check(c.player_stats[scorer_id]["goals"] == 1 and c.stats_for(scorer_id, 1)["goals"] == 1 and c.stats_for(scorer_id, 1, lg.id)["apps"] == 1,
			"measured statistics hold exactly the engine match (all-time, season, competition)")
	_check(c.match_log.size() == 1 and c.has_engine_report(fx["match_id"]), "the report is in the match log")
	_check(_clean(c), "audit with a real match recorded is clean", _audit_text(c))
	var half := {"apps": 4, "est_apps": 1}
	_check(is_equal_approx(SeasonStats.estimated_share(half), 0.25) and SeasonStats.estimated_share({"apps": 0}) == 0.0, "estimated_share = est_apps / apps (0 without appearances)")
	# awards say what they were ranked on
	_play(c, 36)
	c.end_season()
	var basis := {}
	for a in c.award_history:
		basis[a["awards"]["basis"]] = true
	_check(c.award_history.size() == 1 and basis.has("mixed") and int(c.award_history[0]["awards"]["estimated_percent"]) > 90 and int(c.award_history[0]["awards"]["estimated_percent"]) < 100,
			"awards are labelled 'mixed' with the estimated share (%s %s%%)" % [str(basis.keys()), str(c.award_history[0]["awards"]["estimated_percent"])])
	var c2 := _career()
	_play(c2, 46)
	c2.end_season()
	_check(c2.award_history[0]["awards"]["basis"] == "model" and int(c2.award_history[0]["awards"]["estimated_percent"]) == 100, "a season with no engine match is labelled 'model' (100 %)")
	# a report that carries no uid is keyed by its match id: recorded once
	var c3 := _career()
	_play(c3, 3)
	var fx3 := {}
	for f in (c3.competitions["fic_league_s1"] as Competition).pending_fixtures():
		if f["home"] == CLUB:
			fx3 = f
			break
	var nouid := _engine_report(c3, fx3, "", 0, 0)
	_check(c3.record_match(nouid, "fic_league_s1") and not c3.record_match(nouid.duplicate(true), "fic_league_s1") and c3.player_stats[db.get_squad(CLUB)[0].id]["apps"] == 1,
			"a report without a uid is keyed by its match id (recorded once, not double counted)")
	# a legacy world_stats block (no est_ fields) cannot be split: it says so
	var d := c2.to_dict()
	d["world_stats"] = {"p1": {"apps": 4, "goals": 2, "assists": 1, "clean_sheets": 0, "rating_sum": 26.0}}
	d["world_stats_legacy"] = false
	var legacy := CareerState.from_dict(db, d)
	_check(legacy.world_stats_legacy and legacy.world_stats["p1"]["est_apps"] == 0, "a legacy season (no est_ fields) is flagged: its numbers are not claimed to be measured")


func _test_season_completion() -> void:
	var c := _career()
	_play(c, 46)
	_check(c.week == 46 and _clean(c), "week 46 reached with a clean audit", _audit_text(c))
	var lg := c.competitions["fic_league_s1"] as Competition
	var champion := lg.champion_id
	var res := c.end_season()
	_check(c.season == 2 and c.week == 0 and res["season"] == 2, "end_season starts season 2, week 0")
	_check(not c.competitions.has("fic_league_s1") and not c.competitions.has("fic_cup_s1") and c.competitions.has("fic_league_s2") and c.competitions.has("fic_cup_s2"),
			"last season's competitions are replaced by this season's (no leak)")
	_check(c.world_stats.is_empty() and c.yellow_counts.is_empty() and not c.world_stats_legacy, "season statistics restart")
	_check(c.events.any(func(e: Dictionary) -> bool: return e["kind"] == "champion" and e["args"][0] == champion), "the champion is in the world log")
	var fresh := c.competitions["fic_league_s2"] as Competition
	_check(fresh.results.is_empty() and fresh.pending_fixtures().size() == 56 and fresh.season == 2, "the new league has all 56 fixtures unplayed")
	_check(_clean(c), "next season starts with a clean audit", _audit_text(c))
	var ages_ok := true
	for p in db.get_squad(CLUB):
		ages_ok = ages_ok and p.age >= 15
	_check(ages_ok and c.club_history.any(func(h: Dictionary) -> bool: return h["key"] == "season_1"), "season 1 is in the club history")
	_play(c, 46)
	c.end_season()
	_check(c.season == 3 and _clean(c), "a second season rolls over cleanly", _audit_text(c))
	_check(c.club_history.filter(func(h: Dictionary) -> bool: return str(h["key"]).begins_with("season_")).size() == 2, "club history has one entry per finished season")


func _test_playoff_rounds() -> void:
	# A play-off of 6 teams has three knockout rounds but only two reserved weeks: every round must still be played by week 46.
	db.load_world("")
	var ids: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	var def := LeagueDef.from_dict("t", {"country": "x", "name": "N", "divisions": [
			{"id": "d1", "name": "D1", "tier": 1, "team_ids": ids.slice(0, 2), "promote": 0, "relegate": 2},
			{"id": "d2", "name": "D2", "tier": 2, "team_ids": ids.slice(2, 8), "promote": 1, "relegate": 0, "playoff": {"from": 2, "to": 6, "spots": 1}}]})
	var c := _career()
	c.pyramids.clear()
	c.competitions.clear()
	var pyr := LeaguePyramid.create(def, 1)
	pyr.build_season(c.competitions, db)
	c.pyramids["t"] = pyr
	c.club_id = ids[0]
	for w in 46:
		c.advance_week()
	var po: Competition = c.competitions.get(pyr.comp.get("po:d2", ""))
	_check(po != null and po.fixtures.size() == 4 and po.is_finished(), "a 5-team play-off (three rounds: 2 + 2 + 1 matches... 4 in all) is finished by the end of week 46, no round left for end_season")
	var left := 0
	for cid in pyr.comp.values():
		left += (c.competitions[cid] as Competition).pending_fixtures().size()
	_check(left == 0, "no unplayed fixture is left in week 46", str(left))
	_check((CareerValidator.validate(c, false)["errors"] as Array).is_empty(), "week 46 audit passes with play-offs", str(CareerValidator.validate(c, false)["errors"].slice(0, 2)))
	# 6 teams -> three rounds in a bigger division
	var rounds := {}
	for f in po.fixtures:
		rounds[f["round"]] = true
	_check(rounds.size() == 3, "the play-off really had three rounds", str(rounds.keys()))


# --- the validator ---------------------------------------------------------------------------------------

func _expect_error(name: String, mutate: Callable, needle: String, weeks := 12) -> void:
	var c := _career()
	_play(c, weeks)
	mutate.call(c)
	var errs: Array = CareerValidator.validate(c, false)["errors"]
	var hit := errs.any(func(e: String) -> bool: return e.contains(needle))
	_check(hit, "validator detects: " + name, str(errs.slice(0, 2)))


func _expect_warning(name: String, mutate: Callable, needle: String, weeks := 12) -> void:
	var c := _career()
	_play(c, weeks)
	mutate.call(c)
	var audit := CareerValidator.validate(c, false)
	var hit: bool = (audit["warnings"] as Array).any(func(e: String) -> bool: return e.contains(needle))
	_check(hit and (audit["errors"] as Array).is_empty(), "validator warns (does not block): " + name, str(audit["warnings"].slice(0, 2)) + str(audit["errors"].slice(0, 2)))


func _test_validator_detects_faults() -> void:
	var c := _career()
	_play(c, 12)
	_check(_clean(c), "(control) a career after 12 weeks is clean", _audit_text(c))
	_expect_error("a duplicated match id", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		lg.fixtures[5]["match_id"] = lg.fixtures[6]["match_id"], "twice")
	_expect_error("a league table that disagrees with its results", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		lg.tables["main"].rows[CLUB]["points"] += 1, "table row")
	_expect_error("a played fixture without a result", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		lg.results.erase(lg.results.keys()[0]), "no result")
	_expect_error("a result for a fixture that does not exist", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		lg.results["ghost"] = MatchResult.make("ghost", "a", "b", 1, 0).to_dict(), "unknown match")
	_expect_error("a player in two squads", func(c: CareerState) -> void:
		var other: TeamData = db.get_team("club_sunvale")
		other.squad_ids.append(db.get_squad(CLUB)[0].id), "two squads")
	_expect_error("a squad that lists a missing player", func(c: CareerState) -> void:
		(db.get_team(CLUB) as TeamData).squad_ids.append("ghost_player"), "missing player")
	_expect_error("a retired player still in a squad", func(c: CareerState) -> void:
		db.get_squad(CLUB)[0].status = PlayerData.Status.RETIRED, "retired")
	_expect_error("a league system pointing at a missing competition", func(c: CareerState) -> void:
		(c.pyramids["fictional"] as LeaguePyramid).comp["fic_league"] = "nope", "missing competition")
	_expect_error("a ledger that does not add up", func(c: CareerState) -> void:
		(c.ledgers[CLUB] as FinanceLedger).balance += 1, "does not add up")
	_expect_error("a ledger entry id used twice", func(c: CareerState) -> void:
		var l: FinanceLedger = c.ledgers[CLUB]
		l.entries[1]["id"] = l.entries[0]["id"], "twice")
	_expect_error("a fixture the calendar forgot (due, unplayed)", func(c: CareerState) -> void:
		c.week = 30, "was due in week", 3)
	_expect_error("estimated statistics larger than the total", func(c: CareerState) -> void:
		var pid: String = c.world_stats.keys()[0]
		c.world_stats[pid]["est_goals"] = int(c.world_stats[pid]["goals"]) + 5, "estimated part")
	_expect_error("a duplicated report in the match log", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		var fx: Dictionary = {}
		for f in lg.pending_fixtures():
			if f["home"] == CLUB:
				fx = f
				break
		var rep := _engine_report(c, fx, "dup_uid", 1, 0)
		c.record_match(rep, lg.id)
		c.match_log.append(rep.duplicate(true)), "twice")
	_expect_warning("a player who scored more in the log than his totals say", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		var fx: Dictionary = {}
		for f in lg.pending_fixtures():
			if f["home"] == CLUB:
				fx = f
				break
		c.record_match(_engine_report(c, fx, "u2", 1, 0), lg.id)
		c.player_stats[db.get_squad(CLUB)[9].id]["goals"] = 0, "more appearances or goals")
	_expect_warning("statistics that disagree with the season buckets", func(c: CareerState) -> void:
		var lg: Competition = c.competitions["fic_league_s1"]
		var fx: Dictionary = {}
		for f in lg.pending_fixtures():
			if f["home"] == CLUB:
				fx = f
				break
		c.record_match(_engine_report(c, fx, "u3", 1, 0), lg.id)
		c.player_stats[db.get_squad(CLUB)[0].id]["apps"] += 2, "season buckets")
	_expect_error("an unknown managed club", func(c: CareerState) -> void:
		c.club_id = "no_such_club", "does not exist")
	_expect_error("a week outside the season", func(c: CareerState) -> void:
		c.week = 60, "outside")
	_expect_error("a transfer id used twice", func(c: CareerState) -> void:
		c.market.history.append({"id": 1, "week": 1, "kind": "x", "player_id": "a", "from": "", "to": "", "fee": 0, "salary": 0, "years": 1})
		c.market.history.append({"id": 1, "week": 1, "kind": "x", "player_id": "a", "from": "", "to": "", "fee": 0, "salary": 0, "years": 1}), "twice")
	_expect_error("a negative salary", func(c: CareerState) -> void:
		db.get_squad(CLUB)[0].salary = -5, "negative")
	_expect_error("a division whose league has other clubs", func(c: CareerState) -> void:
		var pyr: LeaguePyramid = c.pyramids["fictional"]
		pyr.divisions[0]["team_ids"] = (pyr.divisions[0]["team_ids"] as Array).slice(0, 7) + ["club_ghost"], "different clubs")
	_expect_error("a finished league that still has unplayed fixtures", func(c: CareerState) -> void:
		(c.competitions["fic_league_s1"] as Competition).stage = "finished", "finished")
	# a pristine copy is still clean afterwards (the mutations above work on separate careers)
	var d := _career()
	_play(d, 5)
	_check(_clean(d), "(control) an unmodified career is still clean")
	# the shape layer
	var shape: Array[String] = CareerValidator.check_shape({"season": [1], "ledgers": 5, "competitions": {"x": {"fixtures": [{"match_id": 3}]}}})
	_check(shape.size() >= 3, "shape check names wrong types instead of crashing", str(shape.slice(0, 3)))
	_check(CareerValidator.check_shape("x").size() == 1 and CareerValidator.check_shape(d.to_dict()).is_empty(), "shape check accepts a real career and refuses a non-object")


# --- save / load -----------------------------------------------------------------------------------------

func _test_save_stages() -> void:
	for stage in [0, 1, 12, 30, 46, 47]:
		var c := _career()
		if stage == 47:
			_play(c, 46)
			c.end_season()
			_play(c, 7)
		else:
			_play(c, stage)
		var before := JSON.stringify(c.to_dict(), "", true)
		var fp_before := _fingerprint(c)
		var r := _save_reload(c)
		var ok: bool = r["ok"]
		_check(ok, "save at week %s (season %d) validates and restores" % [str(c.week), c.season], str(r["errors"]))
		if not ok:
			continue
		var c2: CareerState = r["career"]
		_check(JSON.stringify(c2.to_dict(), "", true) == before and _fingerprint(c2) == fp_before, "week %d: career and players are identical after save + load" % c.week)
		_check(_clean(c2), "week %d: the reloaded career passes the audit" % c.week, _audit_text(c2))
	# through a real file, with the atomic writer
	var c := _career()
	_play(c, 20)
	var path := "user://p1_test/save_stage.json"
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
	_check(SaveManager.write_file(path, data) == "", "the save file is written (atomically)")
	var rd := SaveManager.read_file(path)
	var res := SaveManager.restore(db, rd["data"]) if rd["ok"] else {"ok": false}
	_check(rd["ok"] and res["ok"] and JSON.stringify(CareerState.from_dict(db, res["extras"]["career"]).to_dict(), "", true) == JSON.stringify(c.to_dict(), "", true),
			"a career written to and read from a file is unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_resume_determinism() -> void:
	# continuous 40 weeks vs 20 weeks + save + reload + 20 weeks: identical in every byte of career and players
	var a := _career()
	_play(a, 40)
	var fp_a := _fingerprint(a)
	var b := _career()
	_play(b, 20)
	var r := _save_reload(b)
	_check(r["ok"], "(resume) the mid-season save restores", str(r["errors"]))
	if r["ok"]:
		var b2: CareerState = r["career"]
		_play(b2, 20)
		_check(_fingerprint(b2) == fp_a, "a career saved at week 20 and resumed plays the same 20 weeks as one that never stopped")
	# two reloads in a row at different weeks
	var c := _career()
	_play(c, 8)
	var r1 := _save_reload(c)
	var c1: CareerState = r1["career"]
	_play(c1, 12)
	var r2 := _save_reload(c1)
	var c2: CareerState = r2["career"]
	_play(c2, 20)
	_check(_fingerprint(c2) == fp_a, "two save / load cycles (weeks 8 and 20) do not change the simulation")
	# the season rollover after a reload (both careers must start from the same saved state: they share one database)
	var d := _career()
	_play(d, 46)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.capture(db, {}, {}, {}, {}, {"career": d.to_dict()}), "", true, true))
	d.end_season()
	var fp_continuous := _fingerprint(d)
	var res := SaveManager.restore(db, saved)
	var d2 := CareerState.from_dict(db, res["extras"]["career"])
	d2.end_season()
	_check(_fingerprint(d2) == fp_continuous, "ending the season after a reload gives exactly the same next season (players, ledgers, awards, events)")


func _valid_save_dict() -> Dictionary:
	var c := _career()
	_play(c, 14)
	var fx := {}
	for f in (c.competitions["fic_league_s1"] as Competition).pending_fixtures():
		if f["home"] == CLUB:
			fx = f
			break
	c.record_match(_engine_report(c, fx, "uid_save", 1, 0), "fic_league_s1")
	return JSON.parse_string(JSON.stringify(SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(), "user_team_id": CLUB}), "", true, true))


func _try_corrupt(name: String, mutate: Callable) -> void:
	var d := _valid_save_dict()
	mutate.call(d)
	var players_before := db.players.size()
	var sample: PlayerData = db.players.values()[0]
	var errs := SaveManager.validate(SaveManager.migrate(d))
	var res := SaveManager.restore(db, d)
	var untouched: bool = db.players.size() == players_before and db.players.values()[0] == sample
	_check(not errs.is_empty() and not res["ok"] and untouched, "refused cleanly, database untouched: " + name, str(errs.slice(0, 1)))


func _test_corrupt_and_missing_fields() -> void:
	_try_corrupt("competitions is not an object", func(d: Dictionary) -> void: d["extras"]["career"]["competitions"] = "x")
	_try_corrupt("season is a list", func(d: Dictionary) -> void: d["extras"]["career"]["season"] = [1])
	_try_corrupt("career block is a list", func(d: Dictionary) -> void: d["extras"]["career"] = [])
	_try_corrupt("extras is a number", func(d: Dictionary) -> void: d["extras"] = 5)
	_try_corrupt("a ledger entry lost its amount", func(d: Dictionary) -> void:
		d["extras"]["career"]["ledgers"][CLUB]["entries"][0].erase("amount"))
	_try_corrupt("a fixture lost its round", func(d: Dictionary) -> void:
		d["extras"]["career"]["competitions"]["fic_league_s1"]["fixtures"][0].erase("round"))
	_try_corrupt("a table row is a string", func(d: Dictionary) -> void:
		d["extras"]["career"]["competitions"]["fic_league_s1"]["tables"]["main"]["rows"][CLUB] = "x")
	_try_corrupt("the managed club does not exist", func(d: Dictionary) -> void: d["extras"]["career"]["club_id"] = "no_such_club")
	_try_corrupt("two fixtures share a match id", func(d: Dictionary) -> void:
		var fx: Array = d["extras"]["career"]["competitions"]["fic_league_s1"]["fixtures"]
		fx[3]["match_id"] = fx[4]["match_id"])
	_try_corrupt("a table disagrees with its results", func(d: Dictionary) -> void:
		d["extras"]["career"]["competitions"]["fic_league_s1"]["tables"]["main"]["rows"][CLUB]["points"] = 99)
	_try_corrupt("a league system points at a missing competition", func(d: Dictionary) -> void:
		d["extras"]["career"]["pyramids"]["fictional"]["comp"]["fic_league"] = "gone")
	_try_corrupt("the week is out of range", func(d: Dictionary) -> void: d["extras"]["career"]["week"] = 99)
	_try_corrupt("the managed club lost its ledger", func(d: Dictionary) -> void: d["extras"]["career"]["ledgers"].erase(CLUB))
	_try_corrupt("a competition refers to a club that does not exist", func(d: Dictionary) -> void:
		d["extras"]["career"]["competitions"]["fic_cup_s1"]["teams"][0] = "club_ghost")
	_try_corrupt("a duplicate player id in the database part", func(d: Dictionary) -> void: d["players"].append(d["players"][0].duplicate(true)))
	_try_corrupt("a squad references a missing player", func(d: Dictionary) -> void: d["teams"][0]["squad"].append("ghost"))
	# a player in two squads, and statistics of a match report that disagree with the totals
	_try_corrupt("a player is in two squads", func(d: Dictionary) -> void:
		d["teams"][0]["squad"].append(d["teams"][1]["squad"][0]))
	# optional blocks may be absent (older saves): defaults, no crash, the career keeps playing
	for key in ["world_stats", "manager", "club_levels", "events", "award_history", "season_stats", "yellow_counts", "continental", "released",
			"match_log", "club_history", "player_stats", "market", "world_stats_legacy"]:
		var d := _valid_save_dict()
		d["extras"]["career"].erase(key)
		var errs := SaveManager.validate(SaveManager.migrate(d))
		var res := SaveManager.restore(db, d)
		var ok: bool = errs.is_empty() and res["ok"]
		_check(ok, "an older save without '%s' loads with defaults" % key, str(errs.slice(0, 2)))
		if ok:
			var c := CareerState.from_dict(db, res["extras"]["career"])
			_play(c, 6)
			var survived := c.week == 20 and (CareerValidator.validate(c, false)["errors"] as Array).is_empty()
			if survived:
				_play(c, 26)
				c.end_season()
				survived = c.season == 2
			_check(survived, "...and then plays on to the next season ('%s' missing)" % key)
	# values the old code accepted but make no sense are repaired or refused, never trusted: negative counters
	var d2 := _valid_save_dict()
	for pid in d2["extras"]["career"]["player_stats"]:
		d2["extras"]["career"]["player_stats"][pid]["apps"] = -3
		break
	_check(not SaveManager.validate(SaveManager.migrate(d2)).is_empty(), "negative statistics are refused")
	# warnings (not errors) are reported without blocking: a counter that disagrees with the season buckets
	var d3 := _valid_save_dict()
	for pid in d3["extras"]["career"]["player_stats"]:
		d3["extras"]["career"]["player_stats"][pid]["apps"] += 1
		break
	var res3 := SaveManager.restore(db, d3)
	_check(res3["ok"] and not (res3["warnings"] as Array).is_empty(), "an inconsistency that does not stop play is loaded and reported as a warning", str(res3.get("warnings", []).slice(0, 1)))


func _strip_to_version(d: Dictionary, version: int) -> Dictionary:
	var out := d.duplicate(true)
	out["save_version"] = version
	if version <= 2:
		out.erase("crests")
		for t in out["teams"]:
			for k in ["club_type", "country_id", "crest_id"]:
				t.erase(k)
		for p in out["players"]:
			for k in ["first_name", "last_name", "nationality_id", "player_type"]:
				p.erase(k)
		var career: Dictionary = out["extras"]["career"]
		career.erase("season_stats")        # v3 added season- and competition-aware statistics
	if version <= 1:
		for p in out["players"]:
			p.erase("appearance")
	if version == 0:
		for k in ["academies", "scouting", "training", "squads", "extras"]:
			out.erase(k)
	return out


func _test_migrations() -> void:
	var v3 := _valid_save_dict()
	var career_v3: Dictionary = v3["extras"]["career"]
	var any_pid := str(career_v3["player_stats"].keys()[0])
	for version in [2, 1, 0]:
		var old := _strip_to_version(v3, version)
		_check(int(old["save_version"]) == version and (version > 2 or not (old["players"][0] as Dictionary).has("first_name")),
				"(fixture) the v%d save really is in the old format" % version)
		var m := SaveManager.migrate(old)
		_check(not m.has("error") and m["save_version"] == SaveManager.SAVE_VERSION, "v%d migrates to v%d" % [version, SaveManager.SAVE_VERSION])
		_check(JSON.stringify(SaveManager.migrate(m)) == JSON.stringify(m), "v%d: migrating the result again changes nothing" % version)
		# every value that existed in the old save is unchanged
		var same_players := true
		for i in old["players"].size():
			for k in old["players"][i]:
				same_players = same_players and JSON.stringify(old["players"][i][k]) == JSON.stringify(m["players"][i].get(k))
		_check(same_players, "v%d: every player value that existed is unchanged (%d players)" % [version, old["players"].size()])
		var same_teams := true
		for i in old["teams"].size():
			for k in old["teams"][i]:
				same_teams = same_teams and JSON.stringify(old["teams"][i][k]) == JSON.stringify(m["teams"][i].get(k))
		_check(same_teams, "v%d: every club value that existed is unchanged" % version)
		if version == 1 or version == 0:
			var appearance_ok := true
			for p in m["players"]:
				appearance_ok = appearance_ok and not (p["appearance"] as Dictionary).is_empty()
			_check(appearance_ok, "v%d: players without an appearance get one derived from their id" % version)
		_check(m["players"][0]["first_name"] != "" or m["players"][0]["last_name"] != "", "v%d: identity fields are derived from the display name" % version)
		var errs := SaveManager.validate(m)
		_check(errs.is_empty(), "v%d: the migrated save validates" % version, str(errs.slice(0, 2)))
		var res := SaveManager.restore(db, old)
		_check(res["ok"], "v%d: the migrated save restores" % version, str(res.get("errors", [])))
		if not res["ok"]:
			continue
		# the restored world equals the world the v3 save described
		var identical: bool = db.players.size() == v3["players"].size() and db.teams.size() == v3["teams"].size()
		for pd in v3["players"]:
			var p: PlayerData = db.get_player(str(pd["id"]))
			identical = identical and p != null and p.team_id == str(pd["team_id"]) and p.age == int(pd["age"]) and p.contract_years == int(pd["contract_years"]) \
					and p.salary == int(pd["salary"]) and p.get_overall() == _ref_overall(p)
		for td in v3["teams"]:
			identical = identical and (db.get_team(str(td["id"])) as TeamData).squad_ids.size() == (td["squad"] as Array).size()
		_check(identical, "v%d: after restoring, every player (team, age, contract, salary) and every squad equals the original" % version)
		if version == 0:
			_check(res["extras"].is_empty() and res["squads"].is_empty(), "v0: a save without extras has no career and loads without one")
			continue
		var c := CareerState.from_dict(db, res["extras"]["career"])
		var sameStats := JSON.stringify(c.player_stats[any_pid]) == JSON.stringify(CareerState.from_dict(db, career_v3).player_stats[any_pid])
		_check(sameStats, "v%d: all-time statistics are unchanged" % version)
		if version <= 2:
			var legacy := c.stats_for(any_pid, 0)
			_check(legacy["apps"] == c.player_stats[any_pid]["apps"] and legacy["goals"] == c.player_stats[any_pid]["goals"],
					"v%d: the all-time counters became a season-0 'legacy' bucket (nothing lost)" % version)
		_check(c.week == career_v3["week"] and c.season == career_v3["season"] and c.club_id == CLUB, "v%d: season, week and club are unchanged" % version)
		_check((CareerValidator.validate(c, false)["errors"] as Array).is_empty(), "v%d: the migrated career passes the integrity audit" % version,
				str((CareerValidator.validate(c, false)["errors"] as Array).slice(0, 2)))
		_play(c, 32)
		c.end_season()
		_check(c.season == 2 and _clean(c), "v%d: the migrated career plays a full season and rolls over" % version, _audit_text(c))
	# a career block from before later systems existed: only the oldest fields
	var ancient := _strip_to_version(v3, 2)
	var career: Dictionary = ancient["extras"]["career"]
	for k in ["world_stats", "world_stats_legacy", "award_history", "events", "manager", "yellow_counts", "continental", "club_levels", "match_log"]:
		career.erase(k)
	var rs := SaveManager.restore(db, ancient)
	_check(rs["ok"], "a v2 career without manager, world statistics, awards, events and levels still loads", str(rs.get("errors", [])))
	if rs["ok"]:
		var c := CareerState.from_dict(db, rs["extras"]["career"])
		_play(c, 46)
		c.end_season()
		_check(c.season == 2 and not c.manager.objective.is_empty(), "...and the board sets an objective, the season plays and rolls over")
	_check(SaveManager.migrate({"save_version": 4}).has("error") and SaveManager.migrate({"save_version": 99}).has("error"), "saves from a newer game are refused")
	_check(SaveManager.migrate({"save_version": -1}).has("error") or SaveManager.migrate({"save_version": -1}).get("save_version", 0) == 3,
			"a negative version number is handled (refused or migrated) without a crash")


# --- non-blocking week -------------------------------------------------------------------------------------

func _test_async_week() -> void:
	var a := _career()
	_play(a, 14)
	var fp_sync := _fingerprint(a)
	var b := _career()
	var frames0 := Engine.get_process_frames()
	var first_info := await b.advance_week_async()
	var frames_one_week := Engine.get_process_frames() - frames0
	_check(first_info["week"] == 1 and frames_one_week >= 6, "one async week hands control back between phases (%d frames)" % frames_one_week)
	for i in 13:
		await b.advance_week_async()
	_check(_fingerprint(b) == fp_sync, "14 async weeks give exactly the same career as 14 synchronous weeks")
	# busy guard
	var c := _career()
	c.advance_week_async()
	var second := await c.advance_week_async()
	_check(second.get("busy", false) and second.get("blocked", false), "a second week requested while one is running is refused (busy)")
	while c._advancing:
		await get_tree().process_frame
	_check(c.week == 1, "...and only one week was played")
	# the blocked season end
	for i in 45:
		c.advance_week()
	var blocked := await c.advance_week_async()
	_check(blocked.get("blocked", false) and not blocked.has("busy") and not c._advancing, "async week 47 is refused and leaves no busy flag behind")
	# the hub path: AppHub.advance_week_async, the signal, and the guards while a week runs
	var app := get_node("/root/AppHub")
	db.load_world("")
	app.career = CareerState.start(db, CLUB)
	app.career.add_default_league()
	app.user_team_id = CLUB
	app.advance_week_async()
	_check(app.is_advancing(), "AppHub reports a week in progress")
	var busy_path := "user://p1_test/busy.json"
	var busy_err: String = app.save_game(busy_path)
	_check(busy_err != "" and not FileAccess.file_exists(busy_path), "saving while a week is simulated is refused (no half-written state)")
	_check(app.load_game(busy_path) != "", "loading while a week is simulated is refused")
	var info: Dictionary = await app.week_advanced
	_check(info["week"] == 1 and not app.is_advancing() and app.career.week == 1, "week_advanced fires with the summary, the hub is idle again")
	_check(app.save_game(busy_path) == "", "saving works again afterwards")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(busy_path))
	app.career = null
	app.user_team_id = ""
