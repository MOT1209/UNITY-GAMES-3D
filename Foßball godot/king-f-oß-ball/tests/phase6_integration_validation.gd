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
	await _test_goalkeeper_in_match()
	await _test_real_kits()
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
	var facing_ok: bool = absf(absf(wrapf(gk_home.rotation.y, -PI, PI)) - PI) < 0.7 and absf(wrapf(gk_away.rotation.y, -PI, PI)) < 0.7
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
	await _frames(3)             # let the old match leave the tree before the next one starts


## Calm everybody down so only the keeper interacts with the shot.
func _park_outfield(m: MatchManager) -> void:
	for side in m.entries:
		for e in m.entries[side]:
			if e["slot"] != 0:
				(e["node"] as Node3D).global_position = Vector3(30.0 if side == "home" else -30.0, 0.05, -20.0)


## Fires a shot at the goal at z = goal_z (+/-52.5) aimed at x = target_x and
## returns {goal, dive, catch} counts observed for `gk`.
func _shoot(m: MatchManager, gk: TeamGoalkeeper, goal_z: float, target_x: float, speed: float, from_dist := 30.5) -> Dictionary:
	var counts := {"goal": 0, "dive": 0, "catch": 0, "trig": 0}
	var arena := m.arena_root.get_node("Arena")
	var on_trig := func(_id: StringName, _b: Node3D) -> void: counts["trig"] += 1
	arena.goal_entered.connect(on_trig)
	var on_goal := func(_s: String, _p: String) -> void: counts["goal"] += 1
	var on_dive := func(_d: int) -> void: counts["dive"] += 1
	var on_catch := func() -> void: counts["catch"] += 1
	m.goal_scored.connect(on_goal)
	gk.dived.connect(on_dive)
	gk.ball_caught.connect(on_catch)
	_park_outfield(m)            # AI outfielders would otherwise run in and touch the ball
	m.state.phase = MatchState.Phase.PLAYING
	var from_z: float = signf(goal_z) * (absf(goal_z) - from_dist)
	m.ball.reset_ball(Vector3(target_x * 5.0, 0.3, from_z))
	await _frames(2)
	m.ball.apply_kick(Vector3(target_x - target_x * 5.0, 0.0, goal_z - from_z).normalized(), speed, 0.0)
	await _frames(150)
	arena.goal_entered.disconnect(on_trig)
	counts["ball"] = str(m.ball.global_position)
	m.goal_scored.disconnect(on_goal)
	gk.dived.disconnect(on_dive)
	gk.ball_caught.disconnect(on_catch)
	return counts


func _test_goalkeeper_in_match() -> void:
	var m := _real_match("none")
	_check(await _wait_phase(m, MatchState.Phase.PLAYING, 900), "keeper match reaches PLAYING")
	var gk_e: Dictionary = m.entries["home"][0]
	var gk := gk_e["node"] as TeamGoalkeeper
	_check(gk != null and gk_e["ai"] == null, "slot 0 is the real TeamGoalkeeper (no parallel PlayerAI keeper)")
	_check(m.entries["away"][0]["node"] is TeamGoalkeeper, "both teams use the real TeamGoalkeeper")
	_check(gk.attribute_modifiers != null and gk.attribute_modifiers.data == gk_e["pdata"], "keeper carries his own goalkeeping rating")
	_park_outfield(m)
	gk.reset_to(Vector3(0.0, 0.05, 50.0), -1.0)
	# Reaction: a hard shot into the corner makes the keeper dive.
	var r1 := await _shoot(m, gk, 52.5, 1.5, 26.0)
	_check(r1["dive"] >= 1 and r1["goal"] == 0, "keeper dives and saves a hard shot to the corner", str(r1))
	# Save: a hard shot straight at him is caught/held, not a goal.
	gk.reset_to(Vector3(0.0, 0.05, 50.0), -1.0)
	var r2 := await _shoot(m, gk, 52.5, 0.0, 26.0)
	_check(r2["catch"] >= 1 and r2["goal"] == 0, "keeper catches a shot straight at him", str(r2))
	# Goals still count: keeper out of position -> the same shot scores.
	gk.reset_to(Vector3(40.0, 0.05, 20.0), -1.0)      # far from his goal: cannot get back in time
	var r3 := await _shoot(m, gk, 52.5, 1.5, 28.0, 12.0)
	_check(r3["goal"] == 1 and r3["trig"] >= 1, "a REAL shot past an out-of-position keeper scores (arena trigger sees the real ball)", str(r3))
	# Second half: the home keeper defends the OTHER goal (-Z) and still reacts there.
	m.state.half = 2
	m.state.phase = MatchState.Phase.PLAYING
	m._place_team("home")
	m._place_team("away")
	_park_outfield(m)
	_check(gk.global_position.z < -40.0, "home keeper moved to the swapped goal for the second half")
	var r4 := await _shoot(m, gk, -52.5, 1.5, 26.0)
	_check(r4["dive"] >= 1 and r4["goal"] == 0, "second half: keeper dives and saves at the swapped goal", str(r4))
	m.queue_free()
	await _frames(3)             # let the old match leave the tree before the next one starts


## Jersey/shorts/socks colour actually shown on a spawned player's model.
func _model_color(node: Node, suffix: String) -> Color:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name.ends_with(suffix):
				return mat.albedo_color
	return Color(-1, -1, -1)


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _test_real_kits() -> void:
	var db: TeamDatabase = get_node("/root/TeamDB")
	var m := _real_match("none")
	var home: TeamData = db.get_team("club_royal_harbor")
	var away: TeamData = db.get_team("club_northgate_utd")
	var home_kit: Dictionary = home.kits[m.sides["home"]["kit"]]
	var away_kit: Dictionary = away.kits[m.sides["away"]["kit"]]
	var h_out: Node = m.entries["home"][5]["node"]
	var a_out: Node = m.entries["away"][5]["node"]
	var jersey_h := _model_color(h_out, "Jersey")
	var shorts_h := _model_color(h_out, "Shorts")
	var socks_h := _model_color(h_out, "Socks")
	_check(_same(jersey_h, Color.from_string(home_kit["main"], Color.BLACK)), "home outfielder wears the home kit jersey", str(jersey_h))
	_check(_same(shorts_h, Color.from_string(home_kit["shorts"], Color.BLACK)), "home shorts come from kit data", str(shorts_h))
	_check(_same(socks_h, Color.from_string(home_kit["socks"], Color.BLACK)), "home socks come from kit data", str(socks_h))
	_check(not _same(jersey_h, shorts_h), "kit is no longer one flat tint (jersey != shorts)")
	_check(_same(_model_color(a_out, "Jersey"), Color.from_string(away_kit["main"], Color.BLACK)), "away outfielder wears the away team's selected kit")
	_check(not _same(jersey_h, _model_color(a_out, "Jersey")), "the two teams are visually distinguishable")
	var gk_h: Node = m.entries["home"][0]["node"]
	var gk_kit: Dictionary = home.kits["goalkeeper"]
	_check(_same(_model_color(gk_h, "Jersey"), Color.from_string(gk_kit["main"], Color.BLACK)), "keeper wears the goalkeeper kit slot")
	_check(not _same(_model_color(gk_h, "Jersey"), jersey_h) or _same(Color.from_string(gk_kit["main"], Color.BLACK), jersey_h),
			"keeper is dressed differently from the outfield (unless the data says otherwise)")
	var pd: PlayerData = m.entries["home"][5]["pdata"]
	var vis := h_out.get_node("VisualRoot") as PlayerCharacterVisual
	_check(vis.number == (pd.shirt_number if pd.shirt_number > 0 else 6), "shirt number comes from player data")
	# Home/away selection: the away team never wears a colour that clashes with the home kit.
	_check(not KitEditor.kits_clash(home_kit, away_kit), "away kit chosen without clashing with home")
	m.queue_free()
	await _frames(3)             # let the old match leave the tree before the next one starts
