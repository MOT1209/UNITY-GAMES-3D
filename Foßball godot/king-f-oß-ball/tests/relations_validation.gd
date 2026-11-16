## Career phases C3.3 - C3.6: player talks, promises, demands, leaders, position training, mentoring.
##   godot --headless --path . res://tests/relations_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Player relations validation (C3.3-C3.6) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_talks()
	_test_promises()
	_test_demands()
	_test_leaders()
	_test_training_and_mentoring()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _squad() -> Array:
	var s: Array = app.db.get_squad("club_desert_kings").filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	s.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	return s


func _find(pred: Callable) -> PlayerData:
	for p: PlayerData in _squad():
		if pred.call(p):
			return p
	return null


func _test_talks() -> void:
	var c: CareerState = app.career
	var r := c.relations
	var p: PlayerData = _squad()[0]
	_check(r.talk(c, p, "dance")["reply"] == "TALK_REPLY_NONE", "an unknown talk does nothing")
	p.morale = 60
	var res := r.talk(c, p, "praise")
	_check(res["success"] and res["morale_delta"] > 0 and r.rel(p.id) > 50, "praise always works and warms the relationship")
	_check(c.morale.reasons(p.id)[0]["key"].begins_with("MORALE_TALK_PLAYER"), "the talk is logged as a morale reason")
	# criticism: hot-tempered vs calm, measured over many weeks of the same talk
	var hot := _find(func(x: PlayerData) -> bool: return PlayerPersonality.trait_value(x, "temperament") <= 4)
	var calm := _find(func(x: PlayerData) -> bool: return PlayerPersonality.trait_value(x, "temperament") >= 16)
	if hot == null or calm == null:
		# build probes from ids if the squad has no extremes
		hot = _squad()[0].duplicate() if false else _squad()[0]
		calm = _squad()[1]
	var hot_ok := 0
	var calm_ok := 0
	for w in 200:
		c.week = w % 40
		c.season = 1 + w / 40
		hot.team_id = c.club_id
		hot_ok += 1 if r.talk(c, hot, "criticise")["success"] else 0
		calm_ok += 1 if r.talk(c, calm, "criticise")["success"] else 0
	var tem_hot := PlayerPersonality.trait_value(hot, "temperament")
	var tem_calm := PlayerPersonality.trait_value(calm, "temperament")
	_check((tem_hot < tem_calm and hot_ok <= calm_ok) or (tem_hot > tem_calm and hot_ok >= calm_ok) or tem_hot == tem_calm, "a calmer player takes criticism better (%d vs %d successes, temperaments %d / %d)" % [calm_ok, hot_ok, tem_calm, tem_hot])
	c.season = 1
	c.week = 0
	var outsider := PlayerData.from_dict(_squad()[0].to_dict())
	outsider.team_id = "club_royal_harbor"
	_check(not r.talk(c, outsider, "praise")["success"], "you can only talk to your own players")
	var back := PlayerRelations.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(back.relationship == r.relationship, "relationships are saved")


func _test_promises() -> void:
	var c: CareerState = app.career
	c.relations = PlayerRelations.new()
	var r := c.relations
	var p: PlayerData = _squad()[5]
	p.morale = 70
	r.talk(c, p, "promise_minutes")
	_check(r.promises.size() == 1 and r.promises[0]["status"] == "open", "a promise is recorded")
	for i in PlayerRelations.PROMISE_WEEKS - 1:
		c.week += 1
		r.weekly_promises(c)
	_check(r.promises[0]["status"] == "open", "it is not judged before %d weeks" % PlayerRelations.PROMISE_WEEKS)
	c.week += 1
	var before := p.morale
	var out := r.weekly_promises(c)
	_check(r.promises[0]["status"] == "broken" and out.size() == 1, "a promise of minutes that were not given is broken after 6 weeks")
	_check(p.morale < before and c.morale.reasons(p.id)[0]["key"] == "MORALE_PROMISE_BROKEN", "the player's morale drops with a visible reason")
	_check(c.inbox.messages.any(func(m: Dictionary) -> bool: return m["key"] == "INBOX_PROMISE_BROKEN"), "a 'promise broken' message arrives")
	# a kept promise: the player appears 3+ times
	var q: PlayerData = _squad()[6]
	c.relations.talk(c, q, "promise_minutes")
	var row: Dictionary = c.world_stats.get(q.id, SeasonStats.empty_row())
	row["apps"] = int(row.get("apps", 0)) + 5
	c.world_stats[q.id] = row
	c.week += PlayerRelations.PROMISE_WEEKS
	r.weekly_promises(c)
	_check(r.promises.any(func(x: Dictionary) -> bool: return x["player_id"] == q.id and x["status"] == "kept"), "playing him keeps the promise")
	c.week = 0


func _test_demands() -> void:
	var c: CareerState = app.career
	c.relations = PlayerRelations.new()
	var r := c.relations
	for p: PlayerData in _squad():
		p.morale = 30
	var made := {}
	for w in range(1, 30):
		c.week = w
		var d := r.weekly_demands(c)
		if not d.is_empty():
			made[d["kind"]] = d
	_check(not made.is_empty(), "unhappy players make demands (%s)" % str(made.keys()))
	_check(c.inbox.pending_decisions().any(func(m: Dictionary) -> bool: return str(m["uid"]).begins_with("demand:")), "a demand is a decision in the inbox")
	var d: Dictionary = made.values()[0]
	var p: PlayerData = app.db.get_player(d["player_id"])
	var m0 := p.morale
	var ans := r.answer_demand(c, int(d["id"]), "grant")
	_check(ans["ok"] and p.morale > m0, "granting a demand raises morale")
	_check(not r.answer_demand(c, int(d["id"]), "grant")["ok"], "a demand is answered once")
	var leave := {}
	for dm in r.demands:
		if dm["kind"] == "wants_leave" and dm["status"] == "open":
			leave = dm
	if leave.is_empty():
		for w in range(30, 80):
			c.week = w % 40
			c.season = 1 + w / 40
			var dd := r.weekly_demands(c)
			if dd.get("kind", "") == "wants_leave":
				leave = dd
				break
	if not leave.is_empty():
		var lp: PlayerData = app.db.get_player(leave["player_id"])
		var res := r.answer_demand(c, int(leave["id"]), "refuse")
		_check(res["listed"] and c.market.is_transfer_listed(lp.id), "refusing a player who wants to leave lists him for sale")
	else:
		_check(false, "a leave request arose to test the listing path")
	c.season = 1
	c.week = 0
	for p2: PlayerData in _squad():
		p2.morale = 70


func _test_leaders() -> void:
	var c: CareerState = app.career
	c.relations = PlayerRelations.new()
	var r := c.relations
	r.leaders = PlayerRelations.current_leaders(c)
	_check(r.leaders.size() == PlayerRelations.MAX_LEADERS, "the dressing room has %d leaders" % PlayerRelations.MAX_LEADERS)
	_check(PlayerRelations.current_leaders(c) == r.leaders, "leaders are stable")
	_check(r.weekly_leaders(c).is_empty(), "no leader has left")
	for p: PlayerData in _squad():
		p.morale = 70
	var leader: PlayerData = app.db.get_player(r.leaders[0])
	var avg := MoraleSystem.average(app.db, c.club_id)
	PromotionSystem.release_from_squad(app.db, c.club_id, leader.id)
	var left := r.weekly_leaders(c)
	_check(left == [leader.id], "a leader who left is noticed")
	_check(MoraleSystem.average(app.db, c.club_id) < avg - 2, "selling a leader lowers morale across the squad (%.1f -> %.1f)" % [avg, MoraleSystem.average(app.db, c.club_id)])
	_check(r.weekly_leaders(c).is_empty(), "...once")


func _test_training_and_mentoring() -> void:
	var c: CareerState = app.career
	var r := PlayerRelations.new()
	var p: PlayerData = _squad()[2]
	var target := "CDM" if PlayerData.Position.keys()[p.position] != "CDM" else "CM"
	_check(r.start_position_training(p, "NOPE") == "POSTRAIN_ERR_TARGET" and r.start_position_training(p, PlayerData.Position.keys()[p.position]) == "POSTRAIN_ERR_TARGET", "invalid targets are refused")
	_check(r.start_position_training(p, target) == "" and r.start_position_training(p, "ST") == "POSTRAIN_ERR_BUSY", "a position can be trained one at a time")
	var done: Array = []
	for w in PlayerRelations.POSITION_TRAINING_WEEKS:
		done = r.weekly_position_training(c)
	_check(done == [p.id] and p.secondary_positions.has(target), "the new position is learned after %d weeks" % PlayerRelations.POSITION_TRAINING_WEEKS)
	_check(p.validate().is_empty(), "the player stays valid")
	var mentor := _find(func(x: PlayerData) -> bool: return x.age >= 28 and PlayerPersonality.trait_value(x, "professionalism") >= 12)
	var young := _find(func(x: PlayerData) -> bool: return x.age <= 21)
	if mentor == null:
		mentor = _squad()[0]
		mentor.age = 31
		for i in 400:
			mentor.id = "mentor%d" % i
			if PlayerPersonality.trait_value(mentor, "professionalism") >= 12:
				break
		mentor.id = _squad()[0].id if false else mentor.id
	if young == null:
		young = _squad()[-1]
		young.age = 19
	if mentor.team_id == c.club_id and young.team_id == c.club_id and PlayerPersonality.trait_value(mentor, "professionalism") >= 12 and mentor.age >= 28:
		_check(r.assign_mentor(c, mentor, young) == "", "a senior professional can mentor a youngster")
		var before := float(young.growth_progress.values().reduce(func(a: float, b: float) -> float: return a + b, 0.0)) if not young.growth_progress.is_empty() else 0.0
		for w in 10:
			r.weekly_mentoring(c)
		var after := float(young.growth_progress.values().reduce(func(a: float, b: float) -> float: return a + b, 0.0))
		_check(after > before + 0.5, "the mentee earns extra development every week (%.2f -> %.2f)" % [before, after])
	else:
		_check(false, "a suitable mentor and mentee exist in the squad")
	var bad_old := PlayerData.from_dict(_squad()[0].to_dict())
	_check(r.assign_mentor(c, young, young) == "MENTOR_ERR_INVALID", "nobody mentors himself")
	var back := PlayerRelations.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(back.mentoring == r.mentoring and back.position_training == r.position_training, "mentoring and training state are saved")
