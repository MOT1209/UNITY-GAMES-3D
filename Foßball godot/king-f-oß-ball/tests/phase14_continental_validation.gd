## Continental cup: qualification, calendar, simulation, persistence, next season.
##   godot --headless --path . res://tests/phase14_continental_validation.tscn
extends Node

const PACK := "real_2025"
const USER_CLUB := "eng_leicester_city_fc"

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
	print("=== KING FOOTBALL — Continental cup validation ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	var plain := CareerState.start(db, "club_royal_harbor")
	_check(plain != null and plain.continental == null, "a world without leagues has no continental cup")
	db.load_world(PACK)
	_test_cup()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_cup() -> void:
	var c := CareerState.start(db, USER_CLUB)
	_check(c.continental != null and c.continental.comp_id == "continental_s1", "a career in the data pack starts with a continental cup")
	var teams := ContinentalCup.qualifiers(c)
	var unique := {}
	for t in teams:
		unique[t] = true
	_check(teams.size() == 16 and unique.size() == 16, "16 different clubs qualify")
	var tops := {}
	for k in c.pyramids:
		for t in (c.pyramids[k] as LeaguePyramid).divisions[0]["team_ids"]:
			tops[t] = k
	_check(teams.all(func(t: String) -> bool: return tops.has(t)), "all qualifiers play in a top division")
	var per_country := {}
	for t in teams:
		per_country[tops[t]] = int(per_country.get(tops[t], 0)) + 1
	_check(per_country.size() == 5 and per_country.values().all(func(n: int) -> bool: return n >= 3), "every country sends at least its best three clubs", str(per_country))
	var strongest := ""
	var best := -1
	for t in tops:
		if db.get_team_rating(t) > best:
			best = db.get_team_rating(t)
			strongest = t
	_check(strongest in teams, "the strongest club of the world is in")
	var cup: Competition = c.continental.competition(c)
	_check(cup != null and cup.type == Competition.Type.GROUP_KNOCKOUT and cup.groups.size() == 4 and cup.groups.values().all(func(g: Array) -> bool: return g.size() == 4), "four groups of four")
	_check(cup.fixtures.size() == 24 and cup.fixtures.all(func(f: Dictionary) -> bool: return f["stage"] == "group"), "24 group matches over three match-days")
	var seeds := cup.groups.values().map(func(g: Array) -> String: return g[0])
	var top4 := teams.slice(0, 4)
	_check(seeds.all(func(s: String) -> bool: return s in top4), "the four strongest clubs are the group seeds (no two seeds meet in the groups)")
	_check(c.continental.week_of(cup.fixtures[0]) == 8 and ContinentalCup.KO_WEEKS[0] == 26 and ContinentalCup.KO_WEEKS[2] == 38, "the calendar: group match-days in weeks 8, 14, 20, knockouts in 26, 32, 38")
	# play the season up to week 22: the group stage must be complete except for the user's own matches
	for w in 22:
		c.advance_week()
	var group_pending := cup.pending_fixtures().filter(func(f: Dictionary) -> bool: return f["stage"] == "group")
	var only_mine := group_pending.all(func(f: Dictionary) -> bool: return f["home"] == USER_CLUB or f["away"] == USER_CLUB)
	_check(only_mine, "after week 20 every group match is played except the user's", str(group_pending.size()))
	_check(cup.stage in ["knockout", "groups"], "the cup is running")
	var user_in := USER_CLUB in teams
	if user_in:
		_check(group_pending.size() <= 3, "the user's pending matches are at most their own three")
	# persistence in the middle of the cup
	var saved := c.to_dict()
	var back := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(saved)))
	_check(back.continental != null and back.continental.comp_id == "continental_s1" and (back.continental.competition(back) as Competition).results.size() == cup.results.size(),
			"the cup and its results survive save / load")
	# finish the season
	for w in 24:
		c.advance_week()
	var res := c.end_season()
	var champion: String = res["continental_champion"]
	_check(champion != "" and champion in teams, "the season ends with a champion drawn from the qualifiers", champion)
	_check(cup.stage == "finished" and cup.champion_id == champion and cup.fixtures.filter(func(f: Dictionary) -> bool: return f["stage"] == "ko").size() == 7,
			"the knockout has 4 + 2 + 1 matches and is finished")
	var news := NewsFeed.build(c, 300)
	_check(news.any(func(n: Dictionary) -> bool: return n["key"] == "NEWS_CONTINENTAL_CHAMPION" and (n["args"] as Array)[0] == db.get_team(champion).display_name), "the champion is in the news")
	_check(Loc.t("NEWS_CONTINENTAL_CHAMPION") != "NEWS_CONTINENTAL_CHAMPION", "the news text is translated")
	# next season
	_check(c.season == 2 and c.continental != null and c.continental.comp_id == "continental_s2", "season 2 starts with a new cup")
	var next_teams := ContinentalCup.qualifiers(c, {})
	var c2: Competition = c.continental.competition(c)
	var next_set := {}
	for g in c2.groups.values():
		for t in g:
			next_set[t] = true
	_check(next_set.size() == 16, "the new cup has 16 clubs")
	var ok_ledger := true
	for id in c.ledgers:
		if not (c.ledgers[id] as FinanceLedger).is_consistent():
			ok_ledger = false
	_check(ok_ledger, "all ledgers stay consistent after the cup's prize money")
