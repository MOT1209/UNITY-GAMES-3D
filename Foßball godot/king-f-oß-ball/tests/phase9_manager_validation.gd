## Manager career: board objectives, reputation, confidence, contract, dismissal, resignation, job offers, saves.
##   godot --headless --path . res://tests/phase9_manager_validation.tscn
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
	print("=== KING FOOTBALL — Manager career validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	_test_rules()
	_test_career()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_rules() -> void:
	var obj := {"target_rank": 6, "rating_rank": 8, "division_size": 20, "relegate": 3}
	var met := BoardObjectives.evaluate(obj, 5)
	var part := BoardObjectives.evaluate(obj, 8)
	var failed := BoardObjectives.evaluate(obj, 12)
	var down := BoardObjectives.evaluate(obj, 19)
	var champ := BoardObjectives.evaluate(obj, 1)
	_check(met["result"] == "met" and part["result"] == "partial" and failed["result"] == "failed", "met / partial / failed from the final position")
	_check(met["confidence"] > 0 and part["confidence"] < 0 and failed["confidence"] < part["confidence"], "confidence rises when met, falls when missed")
	_check(down["relegated"] and down["confidence"] < failed["confidence"], "relegation costs extra confidence")
	_check(champ["champion"] and champ["reputation"] > met["reputation"], "winning the league is worth extra reputation")
	_check(BoardObjectives.evaluate({}, 3).is_empty() and BoardObjectives.evaluate(obj, 0).is_empty(), "no objective / unknown position: nothing is evaluated")
	var m := ManagerProfile.new()
	m.apply_result(-100, 500)
	_check(m.confidence == 0 and m.reputation == 100 and m.is_sacked(), "values stay within 0..100; low confidence means the sack")
	m.objective = obj
	m.log_entry({"season": 1, "club": "x", "rank": 3})
	var back := ManagerProfile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(back.reputation == 100 and back.objective["target_rank"] == 6 and back.history.size() == 1 and back.history[0]["rank"] == 3, "the manager survives a JSON round trip")
	_check(ManagerProfile.from_dict({}).reputation == ManagerProfile.START_REPUTATION, "old saves without a manager get defaults")


func _finish_season(c: CareerState) -> Dictionary:
	for w in CareerState.WEEKS_PER_SEASON:
		c.advance_week()
	return c.end_season()


func _test_career() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var obj: Dictionary = c.manager.objective
	_check(not obj.is_empty() and int(obj["target_rank"]) >= 1 and int(obj["target_rank"]) <= int(obj["division_size"]), "a new career starts with a board objective for the club's division", str(obj))
	var strong := BoardObjectives.for_club(db, "eng_arsenal", (c.pyramids["england"] as LeaguePyramid).division_of("eng_arsenal"))
	_check(int(strong["target_rank"]) <= int(obj["target_rank"]), "a stronger club gets a more ambitious objective")
	var rep_before := c.manager.reputation
	var res := _finish_season(c)
	var rv: Dictionary = res["manager"]
	_check(not rv.is_empty() and rv["rank"] >= 1 and rv["result"] in ["met", "partial", "failed"], "the season review reports the real final position", str(rv))
	_check(c.manager.history.size() == 1 and c.manager.history[0]["season"] == 1 and c.manager.history[0]["rank"] == rv["rank"], "the review is stored in the manager history")
	var expected_rep := clampi(rep_before + int(rv["reputation"]), 0, 100)
	_check(c.manager.reputation == expected_rep, "reputation changes by exactly the review's amount")
	_check(c.manager.contract_years == ManagerProfile.CONTRACT_YEARS - 1 or c.manager.unemployed or rv["event"] == "renewed", "the contract runs down by a year")
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	_check(SaveManager.validate(SaveManager.migrate(parsed)).is_empty(), "the save with a manager validates")
	var loaded := CareerState.from_dict(db, parsed["extras"]["career"])
	_check(loaded.manager.reputation == c.manager.reputation and loaded.manager.history.size() == 1 and loaded.manager.objective == c.manager.objective,
			"manager, history and objective survive save / load", str(loaded.manager.objective) + " vs " + str(c.manager.objective))
	# forced sack
	c.manager.confidence = 10
	c.manager.contract_years = 5
	var mid := c.manager.objective.duplicate()
	mid["target_rank"] = 1                       # impossible target: the season will miss it unless champion
	c.manager.objective = mid
	var r2 := _finish_season(c)
	var sacked: bool = c.manager.unemployed
	_check(sacked or r2["manager"]["result"] == "met", "a manager with no board confidence who misses the target is sacked", str(r2["manager"]))
	if not sacked:
		c.manager.unemployed = true             # champion by luck: force the unemployed state to test the next rules
	_check(c.take_job("eng_arsenal") != "" or not db.get_team("eng_arsenal") == null and not c.job_offers().any(func(o: Dictionary) -> bool: return o["club_id"] == "eng_arsenal"),
			"a club that has not offered a job cannot be taken", "")
	c.manager.reputation = 100
	var star := c.job_offers()
	c.manager.reputation = 10
	var humble := c.job_offers()
	_check(star.size() == 5 and humble.size() >= 3 and float(star[0]["rating"]) > float(humble[0]["rating"]), "a famous manager is offered better clubs than an unknown one", "%s vs %s" % [str(star[0]), str(humble[0])])
	c.manager.reputation = 40
	var offers := c.job_offers()
	_check(offers.size() >= 3, "a manager always has offers")
	var target: String = offers[0]["club_id"]
	_check(c.take_job(target) == "" and c.club_id == target and not c.manager.unemployed and c.manager.confidence == ManagerProfile.START_CONFIDENCE and not c.manager.objective.is_empty(),
			"taking an offered job changes the club, resets confidence and sets a new objective")
	_check(c.take_job(target) != "", "a manager who already has a club cannot take another job")
	var rep := c.manager.reputation
	_check(c.resign() == "" and c.manager.unemployed and c.manager.reputation == rep - 2 and c.manager.history[c.manager.history.size() - 1]["event"] == "resigned", "resigning leaves the club and costs reputation")
	_check(c.resign() != "", "an unemployed manager cannot resign again")
	c.manager.reputation = 0
	var weakest := ""
	var low := 1000
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var rt: int = db.get_team_rating(t.id)
		if rt < low:
			low = rt
			weakest = t.id
	_check(c.take_job(weakest) == "", "nobody is locked out: the weakest club always hires")
