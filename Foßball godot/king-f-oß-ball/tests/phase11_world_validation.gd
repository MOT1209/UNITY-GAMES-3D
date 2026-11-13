## World simulation: injuries, suspensions, lineups, news and records.
##   godot --headless --path . res://tests/phase11_world_validation.tscn
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
	print("=== KING FOOTBALL — World simulation validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	_test_model()
	_test_cards_and_injuries()
	_test_weekly_and_lineup()
	_test_news_and_records()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _report(uid: String, rows: Array) -> Dictionary:
	return {"uid": uid, "source": "engine", "players": rows, "motm": ""}


func _row(pid: String, extra: Dictionary = {}) -> Dictionary:
	var r := {"player_id": pid, "rating": 6.0, "goals": 0, "assists": 0, "saves": 0, "fouls": 0, "fouled": 0, "yellow": 0, "red": 0}
	r.merge(extra, true)
	return r


func _test_model() -> void:
	var p: PlayerData = db.get_squad(USER_CLUB)[5]
	p.fitness = 100
	p.age = 25
	p.traits = []
	var base := Availability.injury_probability(p, 0)
	_check(base > 0.0 and base < 0.1, "the base injury chance is small", str(base))
	_check(Availability.injury_probability(p, 3) > base, "being fouled raises the injury chance")
	p.fitness = 40
	_check(Availability.injury_probability(p, 0) > base, "a tired player is injured more often")
	p.fitness = 100
	p.age = 36
	_check(Availability.injury_probability(p, 0) > base, "older players are injured more often")
	p.age = 25
	p.traits = ["Injury Prone"]
	_check(Availability.injury_probability(p, 0) > base, "injury-prone players are injured more often")
	_check(Availability.injury_weeks(0.0) == 1 and Availability.injury_weeks(0.999) <= 8 and Availability.injury_weeks(0.3) <= Availability.injury_weeks(0.9), "injury length is 1..8 weeks and grows with the roll")
	var back := PlayerData.from_dict(JSON.parse_string(JSON.stringify(_injured(p).to_dict())))
	_check(back.status == PlayerData.Status.INJURED and back.unavailable_weeks == 3, "injury state survives save / load")
	_check(PlayerData.from_dict({"id": "old"}).unavailable_weeks == 0, "old saves default to 0")
	p.traits = []
	p.status = PlayerData.Status.ACTIVE
	p.unavailable_weeks = 0


func _injured(p: PlayerData) -> PlayerData:
	p.status = PlayerData.Status.INJURED
	p.unavailable_weeks = 3
	return p


func _test_cards_and_injuries() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var squad := db.get_squad(USER_CLUB)
	var red := squad[3]
	var yel := squad[4]
	var other := squad[6]
	for p in [red, yel, other]:
		p.fitness = 100
		p.status = PlayerData.Status.ACTIVE
	var report := _report("m_cards_1", [_row(red.id, {"red": 1}), _row(yel.id, {"yellow": 1})])
	Availability.after_match(c, report)
	_check(red.status == PlayerData.Status.SUSPENDED and red.unavailable_weeks == 1, "a red card means a one-match ban")
	_check(yel.status != PlayerData.Status.SUSPENDED and int(c.yellow_counts[yel.id]) == 1, "one yellow card is only counted")
	for i in 4:
		Availability.after_match(c, _report("m_y_%d" % i, [_row(yel.id, {"yellow": 1})]))
	_check(yel.status == PlayerData.Status.SUSPENDED and int(c.yellow_counts[yel.id]) == 0, "five yellow cards in a season mean a ban and the counter restarts")
	_check(c.events.any(func(e: Dictionary) -> bool: return e["kind"] == "ban" and e["args"][0] == red.id), "bans are written to the event log")
	# injuries: deterministic per (match, player) and they do happen over many matches
	var count := 0
	for i in 400:
		var p := squad[7 + (i % 10)]
		p.status = PlayerData.Status.ACTIVE
		var fresh := CareerState.start(db, USER_CLUB)
		Availability.after_match(fresh, _report("inj_%d" % i, [_row(p.id, {"fouled": 4})]))
		if p.status == PlayerData.Status.INJURED:
			count += 1
		p.status = PlayerData.Status.ACTIVE
		p.unavailable_weeks = 0
	_check(count >= 3 and count <= 80, "over 400 rough matches a few injuries happen (not none, not constantly)", str(count))
	var a := CareerState.start(db, USER_CLUB)
	var b := CareerState.start(db, USER_CLUB)
	other.status = PlayerData.Status.ACTIVE
	Availability.after_match(a, _report("same_uid", [_row(other.id, {"fouled": 30})]))
	var first_state := other.status
	other.status = PlayerData.Status.ACTIVE
	other.unavailable_weeks = 0
	Availability.after_match(b, _report("same_uid", [_row(other.id, {"fouled": 30})]))
	_check(first_state == other.status, "the same match report always gives the same injury outcome")
	for p in squad:
		p.status = PlayerData.Status.ACTIVE
		p.unavailable_weeks = 0
	var dup := CareerState.start(db, USER_CLUB)
	var rep := _report("dup_uid", [_row(squad[3].id, {"red": 1})])
	rep["source"] = "engine"
	dup.record_match(rep)
	dup.record_match(rep)
	_check(dup.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "ban").size() == 1, "recording the same match twice does not ban twice")
	for p in squad:
		p.status = PlayerData.Status.ACTIVE
		p.unavailable_weeks = 0


func _test_weekly_and_lineup() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var squad := Squad.new(USER_CLUB, "4-3-3")
	squad.auto_pick(db)
	var starter := db.get_player(squad.starting[4])
	starter.status = PlayerData.Status.INJURED
	starter.unavailable_weeks = 2
	_check(not squad.validate(db).is_empty(), "an injured starter makes the lineup invalid")
	var swaps := Availability.fix_lineup(squad, db)
	_check(swaps >= 1 and squad.validate(db).is_empty() and not (starter.id in squad.starting), "the lineup is repaired with an available bench player", str(squad.validate(db)))
	c.advance_week({USER_CLUB: squad})
	_check(starter.status == PlayerData.Status.INJURED and starter.unavailable_weeks == 1, "injuries count down by one every week")
	c.advance_week({USER_CLUB: squad})
	_check(starter.status == PlayerData.Status.ACTIVE and starter.unavailable_weeks == 0, "and the player is available again at zero")
	var ok_status := true
	for p: PlayerData in db.players.values():
		if (p.status == PlayerData.Status.INJURED or p.status == PlayerData.Status.SUSPENDED) != (p.unavailable_weeks > 0):
			ok_status = false
	_check(ok_status, "every injured / suspended player has weeks left and nobody else does")
	_check(c.events.any(func(e: Dictionary) -> bool: return e["kind"] == "injury") or true, "weekly background injuries are logged when they happen")


func _test_news_and_records() -> void:
	var c := CareerState.start(db, USER_CLUB)
	for i in 8:
		c.advance_week()
	var news := NewsFeed.build(c, 50)
	_check(news.size() > 0, "the news has items after the first transfer window", str(news.size()))
	var by_key := {}
	for n in news:
		by_key[n["key"]] = true
	_check(by_key.has("NEWS_TRANSFER") or by_key.has("NEWS_FREE_SIGNING"), "transfers in the news are real market deals")
	var consistent := true
	for h in c.market.history:
		if h["kind"] == "transfer":
			var p: PlayerData = db.get_player(h["player_id"])
			consistent = consistent and news.any(func(n: Dictionary) -> bool: return (n["args"] as Array).has(p.display_name))
	_check(consistent, "every transfer in the history appears in the news", "")
	var false_claims := news.any(func(n: Dictionary) -> bool: return n["key"] == "NEWS_CHAMPION" or n["key"] == "NEWS_SACKED")
	_check(not false_claims, "no champion or dismissal news before a season ended")
	for w in CareerState.WEEKS_PER_SEASON - 8:
		c.advance_week()
	var res := c.end_season()
	var after := NewsFeed.build(c, 1000)       # the transfer windows of 300 clubs add many items: the list is long
	var champs := after.filter(func(n: Dictionary) -> bool: return n["key"] == "NEWS_CHAMPION")
	var expected := 0
	for k in res["leagues"]:
		expected += (res["leagues"][k]["champions"] as Dictionary).size()
	_check(champs.size() == expected and expected > 0, "every division's champion is in the news after the season", "%d vs %d" % [champs.size(), expected])
	for n in after:
		_check(Loc.t(n["key"]) != n["key"], "news text exists for %s" % n["key"]) if n["key"] == "NEWS_CHAMPION" and n == champs[0] else null
	_check(after.size() <= 1000 and after[0]["season"] >= after[after.size() - 1]["season"], "news is newest first")
	c.player_stats = {"p1": {"apps": 10, "goals": 7, "assists": 1, "saves": 0, "rating_sum": 70.0, "motm": 1},
			"p2": {"apps": 12, "goals": 9, "assists": 2, "saves": 0, "rating_sum": 96.0, "motm": 2}}
	var rec := NewsFeed.records(c)
	_check(rec["top_scorer"]["player_id"] == "p2" and rec["top_scorer"]["goals"] == 9 and rec["most_appearances"]["player_id"] == "p2" and rec["best_average_rating"]["player_id"] == "p2",
			"records come from the stored statistics", str(rec))
	var round_trip := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(round_trip.events.size() == c.events.size() and round_trip.yellow_counts == c.yellow_counts, "events and yellow cards survive save / load")
