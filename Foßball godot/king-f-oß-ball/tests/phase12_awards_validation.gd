## Season statistics and awards.
##   godot --headless --path . res://tests/phase12_awards_validation.tscn
extends Node

const PACK := "real_2025"
const USER_CLUB := "eng_leicester_city_fc"
var CHE := ""
var LIV := ""

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
	print("=== KING FOOTBALL — Awards validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	var top: Array = db.leagues["england"].divisions[0]["team_ids"]
	CHE = top[3]
	LIV = top[4]
	_test_awards_rules()
	_test_simulated_stats()
	_test_engine_report()
	_test_full_season()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _by_pos(team: String, pos: int, n: int) -> Array:
	return db.get_squad(team).filter(func(p: PlayerData) -> bool: return p.position == pos).slice(0, n)


func _test_awards_rules() -> void:
	var team := "eng_arsenal"
	var sq := db.get_squad(team)
	var st: PlayerData = _by_pos(team, PlayerData.Position.ST, 1)[0]
	var gk: PlayerData = _by_pos(team, PlayerData.Position.GK, 1)[0]
	var stats := {}
	for p in sq:
		stats[p.id] = {"apps": 20, "goals": 0, "assists": 0, "clean_sheets": 0, "rating_sum": 20 * 6.0}
	stats[st.id] = {"apps": 20, "goals": 18, "assists": 3, "clean_sheets": 0, "rating_sum": 20 * 7.5}
	stats[gk.id] = {"apps": 20, "goals": 0, "assists": 0, "clean_sheets": 9, "rating_sum": 20 * 7.0}
	var a := SeasonAwards.compute(db, stats, [team])
	_check(a["golden_boot"] == st.id and a["golden_boot_goals"] == 18, "the golden boot goes to the top scorer")
	_check(a["player_of_the_season"] == st.id and a["best_goalkeeper"] == gk.id, "player of the season is the best average rating, goalkeeper of the season the best keeper")
	var young := sq.filter(func(p: PlayerData) -> bool: return p.age <= 21 and p.position != PlayerData.Position.GK)
	if not young.is_empty():
		stats[young[0].id]["rating_sum"] = 20 * 7.2
		a = SeasonAwards.compute(db, stats, [team])
		_check(a["best_young_player"] == young[0].id, "the best young player is at most 21 years old")
	_check((a["team_of_the_season"] as Array).size() == 11 and (a["team_of_the_season"] as Array).has(st.id) and (a["team_of_the_season"] as Array).has(gk.id), "the team of the season has 11 players with the best of each line")
	_check(SeasonAwards.compute(db, stats, [team]) == a, "the same statistics always give the same awards")
	stats[st.id]["apps"] = 3
	var low := SeasonAwards.compute(db, stats, [team])
	_check(low["player_of_the_season"] != st.id and low["golden_boot"] == st.id, "rating awards need 10 appearances, the golden boot does not")
	_check(SeasonAwards.compute(db, stats, [CHE])["golden_boot"] != st.id, "only players of the given clubs are considered")
	_check(SeasonAwards.compute(db, {}, [team])["golden_boot"] == "", "no statistics, no award")


func _test_simulated_stats() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var r := MatchResult.make("sim_a", "eng_arsenal", CHE, 3, 1)
	SeasonStats.record_simulated(c, r)
	var goals := 0
	var apps := 0
	for pid in c.world_stats:
		goals += c.world_stats[pid]["goals"]
		apps += c.world_stats[pid]["apps"]
	_check(goals == 4 and apps == 22, "a 3-1 match gives exactly 4 goals and 22 appearances", "%d goals %d apps" % [goals, apps])
	var gk_clean := false
	for pid in c.world_stats:
		var p: PlayerData = db.get_player(pid)
		if p.position == PlayerData.Position.GK and c.world_stats[pid]["clean_sheets"] > 0:
			gk_clean = true
		if p.position == PlayerData.Position.GK:
			_check(c.world_stats[pid]["goals"] == 0, "goalkeepers do not score in the model")
	_check(not gk_clean, "no clean sheet in a 3-1 match")
	var c2 := CareerState.start(db, USER_CLUB)
	SeasonStats.record_simulated(c2, r)
	_check(c2.world_stats == c.world_stats, "the model is deterministic per match")
	var c3 := CareerState.start(db, USER_CLUB)
	SeasonStats.record_simulated(c3, MatchResult.make("sim_b", "eng_arsenal", CHE, 0, 0))
	var clean := 0
	for pid in c3.world_stats:
		clean += c3.world_stats[pid]["clean_sheets"]
	_check(clean == 2, "a 0-0 gives both goalkeepers a clean sheet")


func _test_engine_report() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var gk: PlayerData = _by_pos(USER_CLUB, PlayerData.Position.GK, 1)[0]
	var st: PlayerData = _by_pos(USER_CLUB, PlayerData.Position.ST, 1)[0]
	var rep := {"uid": "mu_awards_1", "source": "engine", "match_id": "eng_a1", "home_id": USER_CLUB, "away_id": CHE, "home_goals": 2, "away_goals": 0,
			"players": [{"player_id": gk.id, "side": "home", "rating": 7.5, "goals": 0, "assists": 0, "saves": 3, "fouls": 0, "fouled": 0, "yellow": 0, "red": 0},
					{"player_id": st.id, "side": "home", "rating": 8.2, "goals": 2, "assists": 0, "saves": 0, "fouls": 0, "fouled": 0, "yellow": 0, "red": 0}], "motm": st.id}
	c.record_match(rep)
	_check(c.world_stats[st.id]["goals"] == 2 and c.world_stats[gk.id]["clean_sheets"] == 1 and c.world_stats[gk.id]["apps"] == 1, "a real engine report feeds the season statistics (goals, clean sheet)")
	c.record_match(rep)
	_check(c.world_stats[st.id]["goals"] == 2, "the same report is not counted twice")
	var comp := Competition.create_league("aw_league", "L", [USER_CLUB, CHE, "eng_arsenal", LIV], false)
	c.register_competition(comp)
	var f: Dictionary = {}
	for x in comp.fixtures:
		if x["match_id"] == "eng_a1":
			f = x
	_check(f.is_empty(), "(sanity) the report's match id is not a fixture of this league")


func _test_full_season() -> void:
	var c := CareerState.start(db, USER_CLUB)
	for w in CareerState.WEEKS_PER_SEASON:
		c.advance_week()
	var snapshot := c.world_stats.duplicate(true)
	var goals := 0
	for pid in snapshot:
		goals += int(snapshot[pid]["goals"])
	var goals_in_results := 0
	for cid in c.competitions:
		var comp: Competition = c.competitions[cid]
		for mid in comp.results:
			var rr := MatchResult.from_dict(comp.results[mid])
			goals_in_results += rr.home_goals + rr.away_goals
	_check(goals > 1000 and goals == goals_in_results, "every goal of the season's results is credited to a player", "%d vs %d" % [goals, goals_in_results])
	var res := c.end_season()
	_check(c.world_stats.is_empty(), "the season statistics restart for the new season")
	_check(c.award_history.size() == c.pyramids.size() and c.pyramids.size() == 5, "awards are computed for every country's top division", str(c.award_history.size()))
	var england: Dictionary = {}
	for a in c.award_history:
		if a["key"] == "england":
			england = a["awards"]
	var top_ids: Array = (c.pyramids["england"] as LeaguePyramid).divisions[0]["team_ids"]
	var recomputed := SeasonAwards.compute(db, snapshot, top_ids)
	_check(england == recomputed and england["golden_boot"] != "" and (england["team_of_the_season"] as Array).size() == 11, "the stored awards equal a recomputation from the season's statistics", str(england))
	var boot: PlayerData = db.get_player(england["golden_boot"])
	_check(int(snapshot[boot.id]["goals"]) == int(england["golden_boot_goals"]) and int(england["golden_boot_goals"]) >= 8, "the golden boot total is the player's real season total", str(england["golden_boot_goals"]))
	var news := NewsFeed.build(c, 300)
	_check(news.any(func(n: Dictionary) -> bool: return n["key"] == "NEWS_AWARD_GOLDEN_BOOT"), "the awards appear in the news")
	for key in ["NEWS_AWARD_GOLDEN_BOOT", "NEWS_AWARD_PLAYER_OF_THE_SEASON", "NEWS_AWARD_BEST_GOALKEEPER", "NEWS_AWARD_BEST_YOUNG_PLAYER"]:
		_check(Loc.t(key) != key, "translation exists: %s" % key)
	var loaded := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(loaded.award_history.size() == c.award_history.size() and loaded.award_history[0]["awards"]["golden_boot"] == c.award_history[0]["awards"]["golden_boot"], "awards survive save / load")
	_check(res["season"] == 2, "the season rolled over")
