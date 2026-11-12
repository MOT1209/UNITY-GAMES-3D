## Integration audit validation — career calendar ↔ academy training/scouting,
## over-age prospects, unicode club ids, half-time, goalkeeper, kits.
##   godot --headless --path . res://tests/phase6_integration_validation.tscn
extends Node

const TEAM := "club_royal_harbor"
const SAVE_PATH := "user://test_saves/phase6.json"

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
	print("=== KING FOOTBALL — Phase 6 integration validation ===")
	_test_calendar_sync()
	_test_calendar_save_load()
	_test_over_age()
	_test_unicode_ids()
	await _test_half_time()
	DirAccess.remove_absolute(SAVE_PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


## Career + academy + training + scouting for TEAM, as AppHub builds them.
func _world(db: TeamDatabase) -> Dictionary:
	var career := CareerState.start(db, TEAM)
	var ac := Academy.new(TEAM, "Aldoria", 5)
	ac.budget = 200000
	ac.generate_intake(db, 12)
	var plan := TrainingSystem.new()
	plan.set_group_focus("U15", "dribbling")
	plan.set_group_focus("U17", "passing")
	plan.set_group_focus("U19", "shooting")
	var sc := ScoutingSystem.new(9)
	sc.add_scout("s1", "Scout", 0.8, 100)
	return {"career": career, "academies": {TEAM: ac}, "training": {TEAM: plan},
			"scouting": {TEAM: sc}, "squads": {}}


func _step(w: Dictionary) -> Dictionary:
	return (w["career"] as CareerState).advance_week(w["squads"], w["academies"], w["training"], w["scouting"])


func _test_calendar_sync() -> void:
	var db := _db()
	var w := _world(db)
	var career: CareerState = w["career"]
	var plan: TrainingSystem = w["training"][TEAM]
	_check(career != null and plan.week == 0, "fresh career: training has not run")
	_step(w)
	_check(plan.week == 1 and career.week == 1, "one career week = one training week")
	for i in 4:
		_step(w)
	_check(plan.week == career.week and plan.week == 5, "training follows the calendar over 5 weeks")
	# Duplicate progression: re-syncing the same calendar week is a no-op.
	var ac: Academy = w["academies"][TEAM]
	var dup := plan.sync_to_calendar(db, ac, career.absolute_week())
	_check(dup.is_empty() and plan.week == 5, "same career week never trains twice")
	# Free training: the only way to move training is the calendar. Advancing the
	# career without passing the academy systems must not train.
	career.advance_week()
	_check(plan.week == 5, "career advance without academy systems leaves training untouched")
	# ...but the next full tick only owes the missing weeks (no unlimited free weeks).
	_step(w)
	_check(plan.week == 5 + 2 and plan.calendar_week == career.absolute_week(), "catch-up is exact, not unlimited")
	# Real progression: someone actually improved over the weeks.
	var changed := 0
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if not p.growth_progress.is_empty():   # weekly growth is fractional; it accumulates before an attribute point lands
			changed += 1
	_check(changed > 0, "calendar-driven training produced real development")
	# Scouting follows the same clock.
	var sc: ScoutingSystem = w["scouting"][TEAM]
	var mission_err := sc.start_mission(ac, "s1", "Zamoria", 2)
	_check(mission_err == "", "start scouting mission", mission_err)
	var found := 0
	for i in 3:
		found += (_step(w)["found_ids"] as Array).size()
	_check(found >= 1 and sc.calendar_week == career.absolute_week(), "scouting discovers prospects on the calendar")
	# Season rollover keeps the clock monotonic (absolute week continues).
	var before := career.absolute_week()
	career.end_season(w["academies"])
	_step(w)
	_check(career.absolute_week() > before - 1 and plan.calendar_week == career.absolute_week(),
			"season rollover keeps training in sync")
	db.free()


func _test_calendar_save_load() -> void:
	var db := _db()
	var w := _world(db)
	var career: CareerState = w["career"]
	for i in 3:
		_step(w)
	var plan: TrainingSystem = w["training"][TEAM]
	var data := SaveManager.capture(db, w["academies"], w["scouting"], w["training"], {},
			{"career": career.to_dict()})
	_check(SaveManager.write_file(SAVE_PATH, data) == "", "write save")
	var rd := SaveManager.read_file(SAVE_PATH)
	var db2 := _db()
	db2.clear()
	var res := SaveManager.restore(db2, rd["data"])
	_check(res["ok"], "restore", str(res["errors"]))
	var plan2: TrainingSystem = res["training"][TEAM]
	var career2 := CareerState.from_dict(db2, res["extras"]["career"])
	_check(plan2.week == plan.week and plan2.calendar_week == plan.calendar_week, "training clock saved/loaded")
	var w2 := {"career": career2, "academies": res["academies"], "training": res["training"],
			"scouting": res["scouting"], "squads": {}}
	_step(w2)
	_check(plan2.week == plan.week + 1, "after load, one career week still trains exactly one week")
	db.free()
	db2.free()


func _accounted(db: TeamDatabase, ac: Academy) -> int:
	var seen := {}
	for g in AcademyConfig.group_ids():
		for p in ac.group_players(db, g):
			seen[p.id] = true
	for pid in ac.over_age_ids(db):
		seen[pid] = true
	for p in ac.extended_players(db):
		seen[p.id] = true
	return seen.size()


func _test_over_age() -> void:
	var db := _db()
	var w := _world(db)
	var career: CareerState = w["career"]
	var ac: Academy = w["academies"][TEAM]
	var plan: TrainingSystem = w["training"][TEAM]
	# Force a known cohort: five 19-year-olds (will turn 20 at season end).
	var ids: Array[String] = []
	for i in ac.roster_ids.size():
		var p: PlayerData = db.get_player(ac.roster_ids[i])
		p.age = 19 if i < 5 else 15           # deterministic cohort
		if i < 5:
			ids.append(p.id)
	_check(ac.over_age_ids(db).is_empty(), "nobody is over-age before the season ends")
	var roster_size := ac.roster_ids.size()
	var res := career.end_season(w["academies"])
	var over := ac.over_age_ids(db)
	_check(over.size() == 5 and res["over_age"].size() == 5, "season end surfaces the over-age cohort (%d)" % over.size())
	_check(ac.roster_ids.size() == roster_size, "no player left the academy roster")
	_check(_accounted(db, ac) == ac.roster_ids.size(), "every roster player is reachable (group, over-age or extended)")
	_check(plan.focus_for(db.get_player(ids[0])) == "shooting", "over-age prospects keep following the oldest group's plan")
	# Decisions.
	var squad_before: int = db.get_team(TEAM).squad_ids.size()
	_check(PromotionSystem.promote(db, ac, ids[0]) == "", "over-age prospect promoted to the first team")
	_check(ids[0] in db.get_team(TEAM).squad_ids and db.get_team(TEAM).squad_ids.size() == squad_before + 1
			and not (ids[0] in ac.roster_ids), "promoted over-age player is in the squad, not the academy")
	_check(PromotionSystem.release_youth(db, ac, ids[1]) == "", "over-age prospect released")
	_check(db.get_player(ids[1]).team_id == "" and not (ids[1] in ac.roster_ids), "released player is a free agent, not in the roster")
	_check(ac.keep_extended(db, ids[2]) == "", "over-age prospect kept for development")
	_check(ac.over_age_ids(db).size() == 2 and ac.extended_players(db).size() == 1, "decisions update the lists (2 pending, 1 kept)")
	_check(ac.keep_extended(db, ids[2]) != "", "cannot keep the same player twice")
	_check(ac.keep_extended(db, ac.group_players(db, "U17")[0].id) != "", "cannot keep a player who is not over-age")
	db.get_player(ids[3]).age = 25
	_check(ac.keep_extended(db, ids[3]) != "", "players past the extended age limit must be promoted or released")
	_check(_accounted(db, ac) == ac.roster_ids.size(), "still no inaccessible players after decisions")
	# Save / load keeps the decisions.
	var data := SaveManager.capture(db, w["academies"], w["scouting"], w["training"], {}, {})
	_check(SaveManager.write_file(SAVE_PATH, data) == "", "write save with over-age decisions")
	var db2 := _db()
	db2.clear()
	var restored := SaveManager.restore(db2, SaveManager.read_file(SAVE_PATH)["data"])
	_check(restored["ok"], "restore with over-age decisions", str(restored["errors"]))
	var ac2: Academy = restored["academies"][TEAM]
	_check(ac2.extended_ids == ac.extended_ids and ac2.over_age_ids(db2) == ac.over_age_ids(db),
			"extended + over-age lists survive save/load")
	_check(_accounted(db2, ac2) == ac2.roster_ids.size(), "everyone reachable after load")
	# Extension runs out: age 20 -> 21 keeps, 22 returns for a decision.
	var kept_id: String = ids[2]
	career.end_season(w["academies"])
	_check(kept_id in ac.extended_ids, "kept player stays extended at age 21")
	career.end_season(w["academies"])
	_check(not (kept_id in ac.extended_ids) and kept_id in ac.over_age_ids(db),
			"extension expires past the limit and the player needs a decision again")
	db.free()
	db2.free()


func _club(db: TeamDatabase, club_name: String, persist := false) -> Dictionary:
	return ClubCreator.create_club(db, {"name": club_name, "short_name": "TST", "country": "Aldoria",
			"strength": 50, "seed": 3}, persist)


func _id_is_safe(id: String) -> bool:
	for i in id.length():
		var c := id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return id.begins_with("club_")


func _test_unicode_ids() -> void:
	var db := _db()
	var names := ["ريال الخليج", "Köln United", "Straße FC", "Royal Harbor Test", "FC البحر 1", "اتحاد جدة", "A.B", "A B"]
	var ids := {}
	for n in names:
		var r := _club(db, n)
		_check(r["ok"], "create club '%s'" % n, str(r["error"]))
		if not r["ok"]:
			continue
		ids[n] = r["team_id"]
		var team: TeamData = db.get_team(r["team_id"])
		_check(team.display_name == n, "display name preserved exactly: %s" % n)
		_check(_id_is_safe(r["team_id"]), "id is ASCII/filename-safe for '%s'" % n, r["team_id"])
	var unique := {}
	for k in ids:
		unique[ids[k]] = true
	_check(unique.size() == ids.size(), "all generated ids are distinct (%d)" % ids.size())
	_check(ids.get("Royal Harbor Test", "") == "club_royal_harbor_test", "plain English names keep the legacy id")
	_check(ids.get("A.B", "") != ids.get("A B", ""), "'A.B' and 'A B' no longer collide")
	_check(str(ids.get("Köln United", "")).begins_with("club_koeln_united_"), "German name gets a readable hint + hash")
	_check(str(ids.get("FC البحر 1", "")).begins_with("club_fc_1_"), "mixed-language name keeps its ASCII hint")
	# Arabic-only names used to produce an empty slug (rejected); they now work and differ.
	_check(ids.get("ريال الخليج", "") != ids.get("اتحاد جدة", ""), "different Arabic names get different ids")
	# Stability: same name -> same id on a fresh database.
	var db_b := _db()
	_check(_club(db_b, "ريال الخليج")["team_id"] == ids["ريال الخليج"], "ids are stable across runs")
	# True duplicates are still rejected (case-insensitive).
	_check(not _club(db, "köln united")["ok"], "duplicate name rejected (case-insensitive)")
	_check(not _club(db, "ريال الخليج")["ok"], "duplicate Arabic name rejected")
	# Invalid names.
	_check(not _club(db, "   ")["ok"] and not _club(db, "!!!")["ok"], "blank / punctuation-only names rejected")
	_check(not _club(db, "x".repeat(ClubCreator.MAX_NAME_LENGTH + 1))["ok"], "over-long names rejected")
	# Persistence: Arabic name survives export -> TeamDB load exactly.
	var r := _club(db, "نادي الأمل", true)
	_check(r["ok"], "persisted Arabic club", str(r["error"]))
	var db_c := _db()
	var loaded: TeamData = db_c.get_team(r["team_id"])
	_check(loaded != null and loaded.display_name == "نادي الأمل", "Arabic display name reloads byte-exact from disk")
	_check(ClubCreator.delete_user_club(db, r["team_id"]) == "", "cleanup: delete persisted test club")
	db.free()
	db_b.free()
	db_c.free()


func _real_match(human_side := "home") -> MatchManager:
	var db: TeamDatabase = get_node("/root/TeamDB")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = human_side
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	return m


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_phase(m: MatchManager, phase: MatchState.Phase, max_frames: int) -> bool:
	for i in max_frames:
		if m.state.phase == phase:
			return true
		await get_tree().physics_frame
	return m.state.phase == phase


func _test_half_time() -> void:
	var m := _real_match("home")
	_check(await _wait_phase(m, MatchState.Phase.PLAYING, 900), "real match reaches PLAYING")
	var gk_home: Node3D = m.entries["home"][0]["node"]
	var gk_away: Node3D = m.entries["away"][0]["node"]
	_check(m.frame_side("home") == "home" and gk_home.global_position.z > 30.0 and gk_away.global_position.z < -30.0,
			"first half: home keeper defends +Z, away keeper -Z")
	# Go to half time.
	m.state.elapsed = m.state.duration_seconds / 2.0 - 0.02
	_check(await _wait_phase(m, MatchState.Phase.HALF_TIME, 120), "half-time is reached")
	_check(m.state.half == 1, "still first half during the break")
	# The break plus kickoff reset.
	_check(await _wait_phase(m, MatchState.Phase.KICKOFF, 600) and m.state.half == 2, "second half begins after the break")
	await _frames(120)
	_check(m.frame_side("home") == "away" and m.frame_side("away") == "home", "frames swap in the second half")
	_check(gk_home.global_position.z < -30.0 and gk_away.global_position.z > 30.0,
			"second half: keepers swapped ends (home now defends -Z)", "%s / %s" % [gk_home.global_position, gk_away.global_position])
	var wrong_half := 0
	for e in m.entries["home"]:
		if e["slot"] != 0 and (e["node"] as Node3D).global_position.z > 2.0 and m.state.phase == MatchState.Phase.KICKOFF:
			wrong_half += 1
	for e in m.entries["away"]:
		if e["slot"] != 0 and (e["node"] as Node3D).global_position.z < -2.0 and m.state.phase == MatchState.Phase.KICKOFF:
			wrong_half += 1
	_check(wrong_half == 0, "everyone starts the second half in their own (swapped) half", str(wrong_half))
	var facing_ok: bool = absf(wrapf(gk_home.rotation.y, -PI, PI)) < 0.7 and absf(absf(wrapf(gk_away.rotation.y, -PI, PI)) - PI) < 0.7
	_check(facing_ok, "teams face their new attacking direction", "%f / %f" % [gk_home.rotation.y, gk_away.rotation.y])
	# Goal attribution after the swap: ball in goal N (-Z) now scores for AWAY.
	m.state.kick_off()
	m._on_goal_entered(&"N", m.ball)
	_check(m.state.score["away"] == 1 and m.state.score["home"] == 0, "second half: goal N scores for the away team")
	m.state.kick_off()
	m._on_goal_entered(&"S", m.ball)
	_check(m.state.score["home"] == 1, "second half: goal S scores for the home team")
	# While playing in the swapped frame the keepers still guard THEIR (new) goals.
	_check(await _wait_phase(m, MatchState.Phase.PLAYING, 900), "second half play resumes after goals")
	await _frames(240)
	_check(gk_home.global_position.z < -35.0 and gk_away.global_position.z > 35.0,
			"AI keepers guard the swapped goals during play", "%s / %s" % [gk_home.global_position, gk_away.global_position])
	m.queue_free()
