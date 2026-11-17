## Career phase C3 (first part): personality (C3.1), morale reasons (C3.2) and the team atmosphere (C3.5).
##   godot --headless --path . res://tests/dressing_room_validation.tscn
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
	print("=== KING FOOTBALL — Dressing room validation (C3: personality, morale, atmosphere) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_personality()
	_test_morale_log()
	await _test_weekly_flow()
	_test_atmosphere()
	await _test_ui()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _squad() -> Array:
	var s: Array = app.db.get_squad("club_desert_kings")
	return s.filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)


func _test_personality() -> void:
	var p: PlayerData = _squad()[0]
	var a := PlayerPersonality.for_player(p)
	var b := PlayerPersonality.for_player(p)
	_check(a == b, "a personality is deterministic (same id, same traits)")
	_check(a.size() == PlayerPersonality.TRAITS.size() and a.values().all(func(v: int) -> bool: return v >= 0 and v <= 20), "seven traits, each 0-20")
	var distinct := {}
	var sum := 0.0
	var all: Array = app.db.get_squad("club_desert_kings")
	for q: PlayerData in all:
		distinct[str(PlayerPersonality.for_player(q))] = true
		sum += PlayerPersonality.trait_value(q, "ambition")
	_check(distinct.size() > all.size() / 2, "players differ from each other", "%d of %d" % [distinct.size(), all.size()])
	var mean := sum / all.size()
	_check(mean > 6.0 and mean < 14.0, "traits are centred (mean ambition %.1f)" % mean)
	var clone := PlayerData.from_dict(p.to_dict())
	_check(PlayerPersonality.for_player(clone) == a, "a player keeps his personality through a save round trip (nothing stored)")
	var pro := PlayerData.from_dict(p.to_dict())
	var lazy := PlayerData.from_dict(p.to_dict())
	pro.id = "x_pro"
	lazy.id = "x_lazy"
	var best := ""
	var worst := ""
	for i in 200:
		pro.id = "probe%d" % i
		if PlayerPersonality.trait_value(pro, "professionalism") >= 16 and best == "":
			best = pro.id
		if PlayerPersonality.trait_value(pro, "professionalism") <= 4 and worst == "":
			worst = pro.id
	pro.id = best
	lazy.id = worst
	_check(best != "" and worst != "", "extreme personalities exist")
	_check(PlayerPersonality.training_factor(pro) > 1.0 and PlayerPersonality.training_factor(lazy) < 1.0 and PlayerPersonality.training_factor(pro) <= 1.1,
			"professionalism speeds up or slows down training (within 10%)")


func _test_morale_log() -> void:
	var m := MoraleSystem.new()
	var p: PlayerData = _squad()[0]
	p.morale = 70
	m.apply(p, 3, "MORALE_WIN", 1, 5)
	m.apply(p, -20, "MORALE_LOSS", 1, 6)
	_check(p.morale == 65, "one event moves morale by at most %d" % MoraleSystem.BIG_MOVE, str(p.morale))
	var r := m.reasons(p.id)
	_check(r.size() == 2 and r[0]["key"] == "MORALE_LOSS" and int(r[0]["delta"]) == -8, "reasons are listed newest first with the delta that was applied")
	p.morale = 100
	_check(m.apply(p, 5, "MORALE_WIN", 1, 7) == 0 and m.reasons(p.id).size() == 2, "no reason is logged when nothing moved")
	for i in 10:
		p.morale = 50
		m.apply(p, 2, "MORALE_WIN", 1, 8 + i)
	_check(m.reasons(p.id).size() == MoraleSystem.LOG_MAX, "the log is bounded")
	var back := MoraleSystem.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(back.reasons(p.id) == m.reasons(p.id), "reasons survive a save round trip")
	_check(MoraleSystem.from_dict({}).log.is_empty(), "an old save without morale reasons loads")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_weekly_flow() -> void:
	var c: CareerState = app.career
	for p in _squad():
		p.morale = 70
	var seen_win := false
	var seen_loss := false
	var guard := 0
	while guard < 60 and not (seen_win and seen_loss):
		guard += 1
		_simulate_due()
		await app.advance_week_async()
		_simulate_due()
		for p in _squad():
			for r in c.morale.reasons(p.id):
				seen_win = seen_win or r["key"] == "MORALE_WIN"
				seen_loss = seen_loss or r["key"] == "MORALE_LOSS"
	_check(seen_win or seen_loss, "results after matches leave reasons in the log", "after %d weeks" % guard)
	var moved := 0
	for p in _squad():
		if not c.morale.reasons(p.id).is_empty():
			moved += 1
	_check(moved > 0, "players' morale has reasons after playing weeks (%d of %d)" % [moved, _squad().size()])
	for p in _squad():
		p.morale = 95
	var m2 := MoraleSystem.new()
	var c2: CareerState = c
	var before := c.morale
	c.morale = m2
	c.morale.weekly(c, "")
	_check(_squad().all(func(p: PlayerData) -> bool: return p.morale < 95), "very high morale drifts back toward normal")
	for p in _squad():
		p.morale = 30
	c.morale.weekly(c, "")
	var top14: Array = _squad()
	top14.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	top14 = top14.slice(0, 14)
	_check(top14.all(func(p: PlayerData) -> bool: return p.morale > 30), "very low morale of the regulars recovers")
	c.manager.style = "motivator"
	for p in _squad():
		p.morale = 30
	c.morale.weekly(c, "")
	var motivated: int = top14[0].morale
	c.manager.style = "tactical"
	for p in _squad():
		p.morale = 30
	c.morale.weekly(c, "")
	_check(motivated >= top14[0].morale, "a motivator manager recovers morale at least as fast", "%d vs %d" % [motivated, top14[0].morale])
	c.morale = before
	# the career saves and loads the log
	var pid: String = _squad()[0].id
	c.morale.apply(_squad()[0], 3, "MORALE_WIN", c.season, c.week)
	var d := c.to_dict()
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(d)))
	_check(back.morale.reasons(pid) == c.morale.reasons(pid), "the career saves and restores morale reasons")


func _test_atmosphere() -> void:
	var c: CareerState = app.career
	for p in app.db.get_squad(c.club_id):
		p.morale = 95
	var great := MoraleSystem.atmosphere(app.db, c.club_id)
	for p in app.db.get_squad(c.club_id):
		p.morale = 20
	var bad := MoraleSystem.atmosphere(app.db, c.club_id)
	_check(great["key"] == "ATMOSPHERE_EXCELLENT" and bad["key"] == "ATMOSPHERE_POOR", "the atmosphere is named from the squad's morale")
	_check(float(great["factor"]) <= 1.03 + 0.0001 and float(bad["factor"]) >= 0.97 - 0.0001 and float(great["factor"]) > float(bad["factor"]), "the atmosphere changes performance by at most 3%")
	for p in app.db.get_squad(c.club_id):
		p.morale = 70
	_check(is_equal_approx(float(MoraleSystem.atmosphere(app.db, c.club_id)["factor"]), 1.0), "a normal squad has a neutral atmosphere")
	# measured on simulated matches: a happy squad scores more than an unhappy one
	var goals := {}
	for level in [95, 20]:
		for p in app.db.get_squad(c.club_id):
			p.morale = level
		c._atmosphere_week = -1
		var mods := c.style_mods()
		var gf := 0
		for i in 600:
			var g := {"match_id": "a%d" % i, "stage": "league", "home": c.club_id, "away": "club_royal_harbor"}
			gf += MatchSimulator.result(app.db, g, i, {}, [], mods).home_goals
		goals[level] = gf
	_check(goals[95] > goals[20], "a happy squad scores more than an unhappy one over 600 matches", str(goals))
	for p in app.db.get_squad(c.club_id):
		p.morale = 70
	c._atmosphere_week = -1


func _test_ui() -> void:
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var p: PlayerData = _squad()[0]
	app.career.morale.apply(p, 3, "MORALE_WIN", 1, 1)
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("player_profile", {"player_id": p.id})
		await get_tree().process_frame
		_check(hub.current.find_child("PersonalityPanel", true, false) != null and hub.current.find_child("MoraleReason", true, false) != null, "the profile shows personality and morale reasons (%s)" % lang)
		_check(hub.current.find_child("PTalk_praise", true, false) != null, "the profile has talk buttons (%s)" % lang)
		hub.navigate("career")
		await get_tree().process_frame
		_check(hub.current.find_child("DashAtmosphere", true, false) != null, "the dashboard shows the team atmosphere (%s)" % lang)
	Loc.set_language("en", false)
	hub.navigate("player_profile", {"player_id": p.id})
	await get_tree().process_frame
	var rel_before: int = app.career.relations.rel(p.id)
	(hub.current.find_child("PTalk_praise", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(app.career.relations.rel(p.id) > rel_before, "a talk button on the profile changes the relationship")
	hub.queue_free()
