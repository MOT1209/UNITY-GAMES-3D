## Career phase C4 (logic part): team talks, touchline shouts, opponent report, press conference.
##   godot --headless --path . res://tests/matchday_manager_validation.tscn
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
	print("=== KING FOOTBALL — Matchday validation (C4 logic) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_shouts()
	_test_team_talk()
	await _test_report()
	_test_press()
	await _test_ui()
	await _test_press_ui()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _squad() -> Array:
	return app.db.get_squad("club_desert_kings").filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)


func _set_morale(v: int) -> void:
	for p in app.db.get_squad("club_desert_kings"):
		p.morale = v


func _test_shouts() -> void:
	var base := TacticsPreset.new()
	var s := Matchday.new()
	_check(not s.shout("scream", 10), "an unknown shout is refused")
	_check(s.shout("hold_lead", 60), "a shout is accepted")
	var t := s.effective_tactics(base, 61)
	_check(t.defensive_line < base.defensive_line and t.mentality < base.mentality, "'hold the lead' drops the defensive line and the mentality")
	_check(base.defensive_line == 50 and base.mentality == TacticsPreset.Mentality.BALANCED, "the base tactics are never changed")
	_check(not s.shout("press_high", 62), "a second shout during the cooldown is refused")
	var gone := s.effective_tactics(base, 60 + Matchday.SHOUT_DURATION_MIN)
	_check(gone.defensive_line == 50 and gone.pressing == 50, "the effect ends after %d minutes" % Matchday.SHOUT_DURATION_MIN)
	_check(s.shout("press_high", 60 + Matchday.SHOUT_COOLDOWN_MIN), "after the cooldown the next shout works")
	var up := s.effective_tactics(base, 67)
	_check(up.pressing > base.pressing and up.defensive_line > base.defensive_line, "'press high' raises pressing and the line")
	var maxed := TacticsPreset.new()
	maxed.pressing = 95
	maxed.defensive_line = 95
	_check(s.effective_tactics(maxed, 67).pressing == 100, "values are clamped to 0-100")
	# the AI really reads it: a higher defensive line puts the team targets further up the pitch
	var low := Matchday.new()
	low.shout("hold_lead", 10)
	var high := Matchday.new()
	high.shout("press_high", 10)
	var ball := Vector3(0, 0, 0)
	var t_low := TeamAI.formation_targets("home", "4-4-2", low.effective_tactics(base, 11), ball, false)
	var t_high := TeamAI.formation_targets("home", "4-4-2", high.effective_tactics(base, 11), ball, false)
	var sum_low := 0.0
	var sum_high := 0.0
	for i in range(1, 11):
		sum_low += absf(t_low[i].z)
		sum_high += absf(t_high[i].z)
	_check(not is_equal_approx(sum_low, sum_high), "TeamAI places the team differently under the two shouts", "%f vs %f" % [sum_low, sum_high])


func _test_team_talk() -> void:
	var c: CareerState = app.career
	_set_morale(75)
	var calm := Matchday.team_talk(c, "calm", 0.5)
	_check(calm["reactions"].size() == _squad().size() and int(calm["total"]) > 0, "a calm talk raises morale")
	_set_morale(40)
	var tense_before := MoraleSystem.average(app.db, c.club_id)
	var pressured := Matchday.team_talk(c, "pressure", 1.0)
	_check(int(pressured["total"]) < 0 and MoraleSystem.average(app.db, c.club_id) < tense_before, "a pressure talk to a tense squad before a final lowers morale", str(pressured["total"]))
	_set_morale(40)
	var motivated := Matchday.team_talk(c, "motivate", 1.0)
	_check(int(motivated["total"]) > int(pressured["total"]), "motivating a tense squad is better than pressuring it")
	_set_morale(80)
	var happy_pressure := Matchday.team_talk(c, "pressure", 0.2)
	_check(int(happy_pressure["total"]) > int(pressured["total"]), "the same talk lands better on a confident squad")
	_check(Matchday.team_talk(c, "shout", 1.0)["reactions"].is_empty(), "an unknown talk does nothing")
	var logged := false
	for p in _squad():
		for r in c.morale.reasons(p.id):
			logged = logged or str(r["key"]).begins_with("MORALE_TALK_")
	_check(logged, "the talk is logged as a morale reason")
	var moods := {}
	for r in motivated["reactions"]:
		moods[r["mood"]] = true
	_set_morale(70)


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_report() -> void:
	var c: CareerState = app.career
	var guard := 0
	while guard < 12:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	var opp := "club_royal_harbor"
	var form := Matchday.opponent_report(c, opp)["form"] as Array
	_check(form.size() > 0 and form.size() <= 5 and form.all(func(x: String) -> bool: return x in ["W", "D", "L"]), "the report shows the opponent's recent form (%s)" % "".join(form))
	c.delegation.quality = 0.0
	c.manager.style = "attacking"
	var low := Matchday.opponent_report(c, opp)
	c.delegation.quality = 1.0
	c.manager.style = "tactical"
	var high := Matchday.opponent_report(c, opp)
	_check(int(high["detail_level"]) > int(low["detail_level"]), "a better assistant with a tactical manager gives a more detailed report")
	_check((low["xi"] as Array).is_empty() or int(low["detail_level"]) >= 2, "a poor report hides details")
	_check((high["xi"] as Array).size() == 11 and high["danger"] != "" and high["strongest"] != "" and high["weakest"] != "" and high["style"] != "", "a full report names the XI, the danger man, the lines and the style")
	var xi: Array = high["xi"]
	var danger: PlayerData = app.db.get_player(high["danger"])
	_check(danger != null and danger.id in xi and danger.position != PlayerData.Position.GK, "the dangerous player is an outfield player of the XI")
	_check(high["strongest"] != high["weakest"] or int((high["lines"] as Dictionary)[high["strongest"]]) == int((high["lines"] as Dictionary)[high["weakest"]]), "strongest and weakest line differ (or tie)")
	c.delegation.quality = 0.5
	c.manager.style = "tactical"


func _test_press() -> void:
	var c: CareerState = app.career
	_check(Matchday.press_due(0, 4) and Matchday.press_due(1, 1, true) and not Matchday.press_due(1, 0), "press conferences only follow big matches")
	c.manager.confidence = 50
	c.fan_mood = 60
	_set_morale(70)
	var calm := Matchday.press_answer(c, "calm")
	_check(c.manager.confidence == 51 and int(calm["board"]) == 1, "a calm answer pleases the board")
	var bold := Matchday.press_answer(c, "confident")
	_check(c.fan_mood == 61 and _squad()[0].morale == 72, "a confident answer lifts fans and squad")
	var crit := Matchday.press_answer(c, "critical")
	_check(_squad()[0].morale == 70 and c.fan_mood == 60, "criticism hurts the squad and the fans", "%d %d" % [_squad()[0].morale, c.fan_mood])
	var ev := Matchday.press_answer(c, "evasive")
	_check(c.fan_mood == 59 and int(ev["board"]) == 0, "dodging costs fan goodwill")
	_check(int(Matchday.press_answer(c, "rude")["board"]) == 0 and c.fan_mood == 59, "an unknown tone changes nothing")
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.fan_mood == c.fan_mood, "fan mood is saved")


func _test_ui() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("career")
		await get_tree().process_frame
		_check(hub.current.find_child("MatchPrep", true, false) != null and hub.current.find_child("Talk_calm", true, false) != null, "the career screen shows match preparation (%s)" % lang)
	Loc.set_language("en", false)
	var c: CareerState = app.career
	for p in app.db.get_squad(c.club_id):
		p.morale = 50
	var avg := MoraleSystem.average(app.db, c.club_id)
	(hub.current.find_child("Talk_motivate", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(MoraleSystem.average(app.db, c.club_id) != avg, "a team talk button changes morale")
	hub.queue_free()


## C4.4: a heavy result opens a press conference on the career screen; answering applies the effects and clears it.
func _test_press_ui() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("career")
	await get_tree().process_frame
	_check(hub.current.find_child("PressConference", true, false) == null, "no press conference without a big result")
	c.pending_press = {"opponent": "club_royal_harbor", "score": "0-4", "week": c.week}
	c.inbox.add("press:%d:%d" % [c.season, c.week], c.season, c.week, "media", "INBOX_PRESS_DUE", ["0-4"], {"needs_decision": true})
	hub.navigate("career")
	await get_tree().process_frame
	for lang in ["ar", "en", "de"]:
		Loc.set_language(lang, false)
		hub.navigate("career")
		await get_tree().process_frame
		_check(hub.current.find_child("PressConference", true, false) != null and hub.current.find_child("Press_confident", true, false) != null, "the press conference is shown (%s)" % lang)
	Loc.set_language("en", false)
	var conf := c.manager.confidence
	(hub.current.find_child("Press_calm", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_check(c.pending_press.is_empty() and c.manager.confidence == conf + 1, "answering applies the effect and closes the conference")
	_check(not c.inbox.pending_decisions().any(func(m: Dictionary) -> bool: return str(m["uid"]).begins_with("press:")), "the inbox decision is resolved")
	_check(Matchday.press_due(0, 4) and not Matchday.press_due(2, 1), "a 0-4 result is press-worthy, 2-1 is not")
	hub.queue_free()
