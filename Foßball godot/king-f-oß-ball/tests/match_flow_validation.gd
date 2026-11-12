## Pause menu, results screen, in-progress match save/load, exactly-once result processing.
##   godot --headless --path . res://tests/match_flow_validation.tscn
extends Node

const SAVE := "user://test_saves/match_flow.json"
const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

var _passed := 0
var _failed := 0
var db: Node
var app: Node
var gm: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Match flow validation ===")
	db = get_node("/root/TeamDB")
	app = get_node("/root/AppHub")
	gm = get_node("/root/GameManager")
	db.reload()
	await _test_pause()
	await _test_pause_menu_buttons()
	await _test_save_restore()
	_test_damaged_saves()
	await _test_results_and_exactly_once()
	await _test_results_languages()
	for f in [SAVE, SAVE + ".bak", SAVE + ".tmp"]:
		DirAccess.remove_absolute(f)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _match(seed_value := 5, minutes := 2, human := "none", competition_id := "", match_id := "") -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = minutes
	setup.human_side = human
	setup.rng_seed = seed_value
	setup.competition_id = competition_id
	setup.match_id = match_id
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	return m


func _play(m: MatchManager) -> void:
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()


func _positions(m: MatchManager) -> Array:
	var out: Array = [m.ball.global_position]
	for side in ["home", "away"]:
		for e in m.entries[side]:
			out.append((e["node"] as Node3D).global_position)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _test_pause() -> void:
	var m := _match()
	_play(m)
	await _frames(20)
	_check(m.state.elapsed > 0.1, "the match clock runs while playing")
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(m.is_paused() and get_tree().paused, "the pause action opens the pause menu and pauses the tree")
	var frozen_t := m.state.elapsed
	var frozen_pos := _positions(m)
	var frozen_clock := m._clock
	m.ball.linear_velocity = Vector3(8, 0, 4)          # even a moving ball must freeze
	await _frames(40)
	_check(is_equal_approx(m.state.elapsed, frozen_t) and is_equal_approx(m._clock, frozen_clock), "no simulation while paused: clock frozen")
	var moved := 0
	var after := _positions(m)
	for i in after.size():
		moved += 1 if (after[i] as Vector3).distance_to(frozen_pos[i]) > 0.001 else 0
	_check(moved == 0, "no simulation while paused: ball and 22 players did not move", "%d moved" % moved)
	var ev2 := InputEventAction.new()
	ev2.action = "pause"
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not m.is_paused() and not get_tree().paused, "the pause action again resumes")
	await _frames(20)
	_check(m.state.elapsed > frozen_t, "the clock continues after resuming")
	m.queue_free()
	await get_tree().process_frame


func _test_pause_menu_buttons() -> void:
	var m := _match()
	_play(m)
	var restarted: Array = []
	var quit := [false]
	m.restart_requested.connect(func(s: MatchSetup) -> void: restarted.append(s))
	m.quit_requested.connect(func() -> void: quit[0] = true)
	m.pause_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := m.pause_menu
	var resume := menu.find_child("ResumeButton", true, false) as Button
	_check(resume != null and resume.has_focus(), "resume has keyboard/gamepad focus when the menu opens")
	_check(menu.process_mode == Node.PROCESS_MODE_ALWAYS and menu.find_child("SaveButton", true, false) != null, "menu runs while paused and offers saving")
	(menu.find_child("ControlsButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var list := menu.find_child("ControlsList", true, false) as GridContainer
	_check(list != null and list.get_child_count() >= 20, "controls reference lists the real input actions", str(list.get_child_count() if list else 0))
	(menu.find_child("BackButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	(menu.find_child("SettingsButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var diff := menu.find_child("DifficultyOption", true, false) as OptionButton
	diff.select(2)
	diff.item_selected.emit(2)
	_check(m.setup.difficulty == 2 and menu.find_child("LanguagePicker", true, false) != null, "match settings change the difficulty live and offer the language")
	(menu.find_child("BackButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	(menu.find_child("RestartButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var dialogs := menu.find_children("*", "ConfirmationDialog", true, false)
	_check(dialogs.size() == 1 and restarted.is_empty(), "restart asks for confirmation first (nothing restarted yet)")
	(dialogs[0] as ConfirmationDialog).confirmed.emit()
	_check(restarted.size() == 1 and m.abandoned and (restarted[0] as MatchSetup).home_id == TEAM_H and (restarted[0] as MatchSetup).rng_seed == 5,
			"confirmed restart hands back the kick-off setup and abandons this run")
	_check(not get_tree().paused, "the tree is unpaused after a restart")
	m.pause_match()
	await get_tree().process_frame
	(m.pause_menu.find_child("QuitButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var d2 := m.pause_menu.find_children("*", "ConfirmationDialog", true, false)
	_check(d2.size() == 1 and not quit[0], "quit asks for confirmation first")
	(d2[0] as ConfirmationDialog).confirmed.emit()
	_check(quit[0] and m.abandoned and not get_tree().paused, "confirmed quit leaves the match without a result")
	m.queue_free()
	await get_tree().process_frame


func _test_save_restore() -> void:
	var m := _match(9, 2, "home")
	_play(m)
	await _frames(40)
	# a goal, a substitution, some events
	var scorer: String = m.entries["home"][9]["player_id"]
	m.state.record_shot("home", scorer)
	m.state.goal("home", scorer)
	m.state.kick_off()
	var squad: Squad = m.sides["home"]["squad"]
	var bench_id := ""
	for id in squad.bench:
		if (db.get_player(id) as PlayerData).position != PlayerData.Position.GK:
			bench_id = id
			break
	var out_id: String = squad.starting[5]
	var applied := ManagerAI.apply([{"type": "substitute", "slot": 5, "in_id": bench_id}], "home", m.state, squad, m.sides["home"]["tactics"], db)
	_check(applied.size() == 1, "a substitution happens before saving")
	m._swap_player("home", 5, bench_id)
	await _frames(15)
	var before_state := m.state.to_dict()
	var before_pos := _positions(m)
	var before_ids: Array = []
	for side in ["home", "away"]:
		for e in m.entries[side]:
			before_ids.append(e["player_id"])
	var before_stamina := m.state.stamina.duplicate()
	var career_squad_before: Array = (app.squad().starting.duplicate() if app.squad() != null else [])
	_check(m.save_match(SAVE) == "", "the running match saves")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_check(raw is Dictionary and int(raw["version"]) == MatchSave.VERSION and raw["kind"] == "king_match", "versioned save file")
	_check(not FileAccess.get_file_as_string(SAVE).contains("PNG") and FileAccess.get_file_as_string(SAVE).length() < 400_000, "no rendering data in the save")
	m.queue_free()
	await get_tree().process_frame
	var r := MatchSave.read(db, SAVE)
	_check(r["ok"] and not r["recovered"], "the save validates", str(r["errors"]))
	var m2 := MatchManager.new()
	m2.return_to_menu_on_finish = false
	add_child(m2)
	_check(m2.restore(r["data"], db) == "", "the match is restored")
	var after_ids: Array = []
	for side in ["home", "away"]:
		for e in m2.entries[side]:
			after_ids.append(e["player_id"])
	_check(after_ids == before_ids, "same player ids in the same slots after restoring (nothing regenerated)")
	_check(m2.entries["home"][5]["player_id"] == bench_id and bench_id != out_id, "the substitute is on the pitch, not the substituted player")
	var a_state := m2.state.to_dict()
	_check(a_state["score"] == before_state["score"] and is_equal_approx(a_state["elapsed"], before_state["elapsed"]) and a_state["phase"] == before_state["phase"]
			and a_state["half"] == before_state["half"], "score, clock, half and phase restored")
	_check(JSON.stringify(a_state["events"]) == JSON.stringify(before_state["events"]), "events restored exactly (incl. goal, shot, substitution)")
	_check(JSON.stringify(a_state["stats"]) == JSON.stringify(before_state["stats"]), "statistics restored exactly")
	var same_stamina := true
	for k in before_stamina:
		same_stamina = same_stamina and absf(float(m2.state.stamina[k]) - float(before_stamina[k])) < 1e-6
	_check(same_stamina, "stamina restored")
	var after_pos := _positions(m2)
	var worst := 0.0
	for i in after_pos.size():
		worst = maxf(worst, (after_pos[i] as Vector3).distance_to(before_pos[i]))
	_check(worst < 0.05, "ball and all 22 players are back where they were", "worst %.4f m" % worst)
	var kick_off_lineup: Array = m2.initial_setup_dict["home_squad"]["starting"]
	_check(kick_off_lineup[5] == out_id, "restart data still describes the kick-off lineup", "%s vs %s (bench %s)" % [str(kick_off_lineup[5]), out_id, bench_id])
	_check(app.squad() == null or app.squad().starting == career_squad_before, "the match never rewrote the career lineup")
	m2.pause_match()
	await _frames(3)
	var t := m2.state.elapsed
	await _frames(10)
	_check(is_equal_approx(m2.state.elapsed, t), "a restored match waits (paused) until the player resumes")
	m2.resume_match()
	await _frames(30)
	_check(m2.state.elapsed > t and m2.state.score["home"] == 1, "after resuming the restored match plays on")
	m2.queue_free()
	await get_tree().process_frame


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _good_save() -> Dictionary:
	var m := _match(3)
	_play(m)
	var d := m.capture()
	m.queue_free()
	return d


func _test_damaged_saves() -> void:
	var good := _good_save()
	_check(MatchSave.validate(good, db).is_empty(), "a fresh capture validates")
	# atomic write + backup recovery
	DirAccess.remove_absolute(SAVE)
	DirAccess.remove_absolute(SAVE + ".bak")
	_check(MatchSave.write(good, SAVE) == "" and MatchSave.write(good, SAVE) == "" and FileAccess.file_exists(SAVE + ".bak"), "writes are atomic and keep a backup")
	_write(SAVE, "{ this is not json")
	var r := MatchSave.read(db, SAVE)
	_check(r["ok"] and r["recovered"], "a corrupted file recovers from the backup")
	_write(SAVE + ".bak", "")
	r = MatchSave.read(db, SAVE)
	_check(not r["ok"] and not (r["errors"] as Array).is_empty(), "with no usable copy loading fails cleanly with a reason")
	DirAccess.remove_absolute(SAVE)
	DirAccess.remove_absolute(SAVE + ".bak")
	_check(not MatchSave.read(db, SAVE)["ok"] and not MatchSave.exists(SAVE), "no save at all is reported, not a crash")
	# invalid content
	var cases := {
		"missing section": func(d: Dictionary) -> void: d.erase("ball"),
		"unknown phase": func(d: Dictionary) -> void: d["state"]["phase"] = 9,
		"finished match": func(d: Dictionary) -> void: d["state"]["phase"] = 3,
		"result already processed": func(d: Dictionary) -> void: d["state"]["result_processed"] = true,
		"clock beyond the match": func(d: Dictionary) -> void: d["state"]["elapsed"] = d["state"]["duration"] + 5.0,
		"score without goals": func(d: Dictionary) -> void: d["state"]["score"]["home"] = 4,
		"NaN position": func(d: Dictionary) -> void: d["players"][3]["pos"][0] = NAN,
		"position out of range": func(d: Dictionary) -> void: d["ball"]["pos"][1] = 99999.0,
		"unknown player": func(d: Dictionary) -> void: d["players"][2]["player_id"] = "ghost",
		"duplicate player": func(d: Dictionary) -> void: d["players"][1]["player_id"] = d["players"][0]["player_id"],
		"missing player": func(d: Dictionary) -> void: d["players"].pop_back(),
		"unknown team": func(d: Dictionary) -> void: d["setup"]["home_id"] = "nowhere_fc",
		"wrong kind": func(d: Dictionary) -> void: d["kind"] = "career",
	}
	for name in cases:
		var d: Dictionary = good.duplicate(true)
		(cases[name] as Callable).call(d)
		_check(not MatchSave.validate(d, db).is_empty(), "rejected: %s" % name)
	var newer := good.duplicate(true)
	newer["version"] = MatchSave.VERSION + 3
	_check(MatchSave.migrate(newer).has("error"), "a newer save version is refused")
	var old := good.duplicate(true)
	old["version"] = 0
	old.erase("initial_setup")
	old.erase("flow")
	var mig := MatchSave.migrate(old)
	_check(not mig.has("error") and mig["version"] == MatchSave.VERSION and mig.has("initial_setup") and mig.has("flow"), "version 0 migrates to the current format")
	_check(MatchSave.validate(mig, db).is_empty(), "a migrated save validates")


func _fixture_career() -> Dictionary:
	app.user_team_id = ""
	app.career = null
	app.squads.clear()
	app.academies.clear()
	app.pending_fixture = {}
	app.start_career(TEAM_H)
	var comp := Competition.create_league("flow_league", "Flow League", [TEAM_H, TEAM_A, "club_cedar_city", "club_sunvale"], true)
	app.career.register_competition(comp)
	var f: Dictionary = {}
	for x in comp.fixtures:
		if x["home"] == TEAM_H and x["away"] == TEAM_A:
			f = x
			break
	return {"comp": comp, "fixture": f}


func _test_results_and_exactly_once() -> void:
	var fc := _fixture_career()
	var comp: Competition = fc["comp"]
	var f: Dictionary = fc["fixture"]
	app.pending_fixture = {"competition_id": comp.id, "match_id": f["match_id"]}
	var rev_before: int = (app.career.ledger().entries as Array).filter(func(e: Dictionary) -> bool: return e["category"] == "match_revenue").size()
	var m := _match(21, 2, "home", comp.id, f["match_id"])
	var finished := [0]
	m.match_finished.connect(func(_r: MatchResult) -> void: finished[0] += 1)
	_play(m)
	var scorer: String = m.entries["home"][9]["player_id"]
	var passer: String = m.entries["home"][8]["player_id"]
	m.state.record_pass("home", passer)
	m.state.record_owner("home", scorer)
	m.state.record_shot("home", scorer)
	m.state.goal("home", scorer)
	m.state.kick_off()
	m.state.record_possession("home", 30.0)
	m.state.record_possession("away", 10.0)
	m.state.half = 2
	m.state.elapsed = m.state.duration_seconds - 0.01
	await _frames(12)                                  # the engine reaches full time and finishes by itself
	_check(m.state.phase == MatchState.Phase.FINISHED and finished[0] == 1, "full time reached, match_finished emitted once")
	_check(m.results_view != null and m.results_view.find_child("ContinueButton", true, false) != null, "the results screen is shown")
	var score := m.results_view.find_child("ScoreLabel", true, false) as Label
	_check(score.text == "1 - 0", "results show the real score", score.text)
	_check(score.text_direction == Control.TEXT_DIRECTION_LTR, "regression: the score label is forced left-to-right (an Arabic label used to show 0 - 1 for 1 - 0)")
	_check(m.results_view.find_child("OutcomeLabel", true, false).text == Loc.t("RESULT_WIN"), "outcome for the human side: win")
	_check(m.results_view.find_child("Scorers", true, false) != null and m.results_view.find_child("TeamStats", true, false) != null
			and m.results_view.find_child("ManOfTheMatch", true, false) != null, "scorers, team statistics and man of the match are shown")
	var stats_grid := m.results_view.find_child("TeamStats", true, false) as GridContainer
	var texts: Array = stats_grid.get_children().map(func(c: Node) -> String: return (c as Label).text)
	_check("75.0%" in texts and "25.0%" in texts, "possession on screen comes from the measured possession time", str(texts))
	_check(not texts.any(func(t: String) -> bool: return "oul" in t or "ard" in t or "Foul" in t), "no foul/card statistics are shown (not measured)")
	_check(gm.last_match_report["uid"] == m.state.uid and gm.last_match_report["scorers"][0]["assist_id"] == passer, "the report (with the assist) is published before the signals")
	# career / competition updated exactly once
	var played: Dictionary = comp.get_fixture(f["match_id"])
	_check(played["played"] and comp.standings()[0]["team_id"] == TEAM_H and comp.tables["main"].rows[TEAM_H]["points"] == 3, "competition standings updated (3 points for the winner)")
	var rev_after: int = (app.career.ledger().entries as Array).filter(func(e: Dictionary) -> bool: return e["category"] == "match_revenue").size()
	_check(rev_after == rev_before + 1, "match revenue booked exactly once", "%d -> %d" % [rev_before, rev_after])
	_check(app.career.match_log.size() == 1 and app.career.player_stats.has(scorer) and app.career.player_stats[scorer]["goals"] == 1, "career records hold the match and the scorer's totals")
	# duplicate delivery of the same result must change nothing
	var balance: int = app.career.ledger().balance
	var res := MatchResult.make(f["match_id"], TEAM_H, TEAM_A, 1, 0)
	gm.emit_signal("match_finished", res)
	gm.emit_signal("match_finished", res)
	app.pending_fixture = {"competition_id": comp.id, "match_id": f["match_id"]}
	gm.emit_signal("match_finished", res)
	_check(comp.tables["main"].rows[TEAM_H]["points"] == 3 and comp.tables["main"].rows[TEAM_H]["played"] == 1, "duplicate results do not change the table")
	_check(app.career.ledger().balance == balance and app.career.match_log.size() == 1 and app.career.player_stats[scorer]["apps"] == 1,
			"duplicate results do not change finances, match log or player totals")
	m._finish()
	_check(finished[0] == 1, "_finish() is idempotent")
	var closed := [false]
	m.results_closed.connect(func() -> void: closed[0] = true)
	(m.results_view.find_child("ContinueButton", true, false) as Button).pressed.emit()
	_check(closed[0], "Continue closes the results")
	# career survives save/load with the records
	var data: Dictionary = app.career.to_dict()
	var c2 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(data, "", true, true)))
	_check(c2.match_log.size() == 1 and c2.player_stats[scorer]["goals"] == 1 and c2.record_match(c2.match_log[0]) == false, "match records survive career save/load and stay idempotent")
	m.queue_free()
	await get_tree().process_frame
	# abandoned match: no result
	var m2 := _match(22, 2, "home", comp.id, "flow_league_other")
	m2.quit_match()
	_check(m2.abandoned and m2.report.is_empty() and not m2.state.result_processed, "an abandoned match records no result")
	m2.queue_free()
	await get_tree().process_frame
	app.career = null
	app.user_team_id = ""
	app.pending_fixture = {}


func _test_results_languages() -> void:
	var m := _match(23, 2, "home")
	_play(m)
	var s: String = m.entries["home"][9]["player_id"]
	m.state.record_shot("home", s)
	m.state.goal("home", s)
	m.state.kick_off()
	m.state.half = 2
	m.state.elapsed = m.state.duration_seconds - 0.01
	await _frames(12)
	for lang in ["ar", "de", "en"]:
		Loc.set_language(lang, false)
		var v := MatchResultsView.create(m.report, db)
		add_child(v)
		await get_tree().process_frame
		var labels := v.find_children("*", "Label", true, false)
		var leaked := labels.filter(func(l: Label) -> bool: return l.text.begins_with("RESULT_") or l.text.begins_with("PAUSE_"))
		_check(leaked.is_empty() and v.find_child("ScoreLabel", true, false) != null, "[%s] results screen shows no untranslated keys" % lang, str(leaked.size()))
		v.queue_free()
		var live := _match(31, 2, "none")
		_play(live)
		live.pause_match()
		await get_tree().process_frame
		var bad := live.pause_menu.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("PAUSE_"))
		_check(bad.is_empty() and live.pause_menu.find_children("*", "Button", true, false).size() >= 5, "[%s] pause menu is translated" % lang)
		live.resume_match()
		live.queue_free()
	Loc.set_language("en", false)
	m.queue_free()
	await get_tree().process_frame
