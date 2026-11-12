## League pyramid + real data pack validation.
##   godot --headless --path . res://tests/league_pyramid_validation.tscn
## Loads the `real_2025` pack explicitly (the default world stays fictional) and restores the
## default world at the end, so other suites are unaffected.
extends Node

const PACK := "real_2025"
const SAVE_PATH := "user://test_saves/pyramid.json"
const USER_CLUB := "eng_leicester_city_fc"      # a Championship club

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
	print("=== KING FOOTBALL — League pyramid validation ===")
	db = get_node("/root/TeamDB")
	_test_default_world_untouched()
	_test_pack_loads()
	_test_league_def_validation()
	_test_calendar()
	_test_weekly_play_and_user_fixture()
	_test_three_seasons()
	_test_save_load()
	_test_reserve_rule()
	await _test_screens()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_default_world_untouched() -> void:
	db.reload()
	_check(db.pack_id == "" and db.leagues.is_empty() and db.get_team("club_royal_harbor") != null,
			"headless start loads the default fictional world")
	_check(TeamDatabase.available_packs().any(func(p: Dictionary) -> bool: return p["id"] == PACK), "real pack is listed")


func _test_pack_loads() -> void:
	db.load_world(PACK)
	_check(db.errors.is_empty(), "pack loads without errors", str(db.errors.slice(0, 5)))
	_check(db.pack_id == PACK and db.get_team("club_royal_harbor") == null, "pack replaces the fictional world")
	_check(db.leagues.keys().size() == 5 and ["england", "spain", "germany", "italy", "france"].all(func(k: String) -> bool: return db.leagues.has(k)),
			"five countries", str(db.leagues.keys()))
	var sizes := {}
	for k in db.leagues:
		for d in (db.leagues[k] as LeagueDef).divisions:
			sizes[d["id"]] = (d["team_ids"] as Array).size()
	_check(sizes == {"eng_d1": 20, "eng_d2": 24, "esp_d1": 20, "esp_d2": 22, "ger_d1": 18, "ger_d2": 18,
			"ita_d1": 20, "ita_d2": 20, "fra_d1": 18, "fra_d2": 18}, "division sizes", str(sizes))
	_check(db.list_teams(TeamData.Category.CLUB).size() == 198, "198 clubs")
	for k in db.leagues:
		_check((db.leagues[k] as LeagueDef).validate(db).is_empty(), "%s league validates" % k)
	var bad := []
	for t: TeamData in db.list_teams():
		var squad := db.get_squad(t.id)
		var gks := squad.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
		if squad.size() < 18 or squad.size() > 30 or gks < 2 or not t.is_real or t.logo_path != "":
			bad.append(t.id)
	_check(bad.is_empty(), "every club: 18-30 players, 2+ keepers, real flag, no logo", str(bad))
	_check(db.get_player("tm_342229") != null or db.players.keys().any(func(k: String) -> bool: return k.begins_with("tm_")),
			"real (transfermarkt) players present")
	var haaland: Array = db.players.values().filter(func(p: PlayerData) -> bool: return p.display_name == "Erling Haaland")
	_check(haaland.size() == 1 and (haaland[0] as PlayerData).team_id == "eng_manchester_city", "a known real player is at his real club")
	_check(db.get_team_rating("eng_manchester_city") > db.get_team_rating("eng_leicester_city_fc"), "top-flight club rated above a second-tier club")
	_check(PlayerAppearance.is_valid((db.players.values()[0] as PlayerData).appearance), "pack players get stored appearances")


func _test_league_def_validation() -> void:
	var good: LeagueDef = db.leagues["england"]
	_check(good.validate(db).is_empty(), "shipped England league validates")
	var d := {"country": "X", "divisions": [
		{"id": "a", "tier": 1, "team_ids": ["eng_arsenal", "eng_burnley", "eng_fulham", "eng_everton"], "promote": 0, "relegate": 2},
		{"id": "b", "tier": 2, "team_ids": ["eng_arsenal", "nope", "eng_watford_fc", "eng_millwall_fc"], "promote": 1, "relegate": 0}]}
	var errs := LeagueDef.from_dict("x", d).validate(db)
	_check(errs.any(func(e: String) -> bool: return "two divisions" in e), "duplicate team detected")
	_check(errs.any(func(e: String) -> bool: return "unknown team" in e), "unknown team detected")
	_check(errs.any(func(e: String) -> bool: return "relegates" in e), "promote/relegate mismatch detected")


func _career() -> CareerState:
	return CareerState.start(db, USER_CLUB)


func _test_calendar() -> void:
	var c := _career()
	var pyr: LeaguePyramid = c.pyramids["england"]
	_check(c.competitions.size() == 15, "career registers 2 leagues + 1 cup per country (5 countries)", str(c.competitions.size()))
	var bad := 0
	var per_week := {}
	for role in pyr.comp:
		var comp: Competition = c.competitions[pyr.comp[role]]
		for f in comp.fixtures:
			var w := pyr.week_of(role, comp, f)
			if w < 1 or w > CareerState.WEEKS_PER_SEASON:
				bad += 1
	_check(bad == 0, "every fixture is scheduled inside the 46-week season")
	var pl: Competition = c.competitions[pyr.comp["eng_d1"]]
	var weeks := {}
	for f in pl.fixtures:
		var key := "%s_%d" % [f["home"], pyr.week_of("eng_d1", pl, f)]
		weeks[key] = weeks.get(key, 0) + 1
	_check(weeks.values().all(func(n: int) -> bool: return n == 1), "a 20-team division never plays a club twice in one week")
	var cup: Competition = c.competitions[pyr.comp["cup"]]
	_check(cup.ko_teams.size() == 20 and cup.fixtures.size() == 12, "cup: 44 clubs -> 20 byes for the top flight, 12 first-round ties",
			"%d byes, %d ties" % [cup.ko_teams.size(), cup.fixtures.size()])


func _test_weekly_play_and_user_fixture() -> void:
	var c := _career()
	var user_pending := 0
	var user_auto := 0
	for w in 6:
		var info := c.advance_week()
		user_pending += (info["user_fixtures"] as Array).size()
		user_auto += (info["auto_played"] as Array).size()
		if w == 0:
			var uf: Array = info["user_fixtures"]
			_check(uf.size() >= 1 and uf.all(func(x: Dictionary) -> bool: return x["home"] == USER_CLUB or x["away"] == USER_CLUB),
					"week 1: the user's league match(es) are left to the user", str(uf.size()))
			var f: Dictionary = info["user_fixtures"][0]
			var comp: Competition = c.competitions[f["competition_id"]]
			_check(not comp.get_fixture(f["match_id"])["played"], "the user's fixture is not auto-simulated in its week")
			var others := comp.fixtures.filter(func(x: Dictionary) -> bool: return int(x["round"]) == 1 and x["match_id"] != f["match_id"])
			_check(others.all(func(x: Dictionary) -> bool: return x["played"]), "all other round-1 matches of the division were simulated")
	_check(user_auto >= 4, "an unplayed user fixture is simulated once its week has passed (no stall)", str(user_auto))
	# Playing it ourselves: quick-sim in its week
	var info := c.advance_week()
	var f: Dictionary = info["user_fixtures"][0]
	var r := MatchSimulator.result(db, c.competitions[f["competition_id"]].get_fixture(f["match_id"]), 7)
	_check(c.submit_result(f["competition_id"], r) == "", "the user's fixture can be played in its week")
	var next := c.advance_week()
	_check(not (next["auto_played"] as Array).has(f["match_id"]), "a fixture the user played is not simulated again")


func _sizes(c: CareerState) -> Dictionary:
	var out := {}
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			out[d["id"]] = (d["team_ids"] as Array).size()
	return out


func _test_three_seasons() -> void:
	var c := _career()
	var start_sizes := _sizes(c)
	var all_before := {}
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			for t in d["team_ids"]:
				all_before[t] = true
	for s in 3:
		for w in CareerState.WEEKS_PER_SEASON:
			c.advance_week()
		var open := 0
		for cid in c.competitions:
			open += (c.competitions[cid] as Competition).pending_fixtures().size()
		_check(open <= 2, "season %d: after 46 weeks only the user's last fixtures can be open" % (s + 1), str(open))
		var eng: LeaguePyramid = c.pyramids["england"]
		var pl: Competition = c.competitions[eng.comp["eng_d1"]]
		var champ: Competition = c.competitions[eng.comp["eng_d2"]]
		var res := c.end_season()
		var sum: Dictionary = res["leagues"]["england"]
		var pl_order: Array = sum["tables"]["eng_d1"]
		var ch_order: Array = sum["tables"]["eng_d2"]
		_check((sum["relegated"] as Array) == pl_order.slice(17), "season %d: bottom 3 of the Premier League go down" % (s + 1))
		var promoted: Array = sum["promoted"]
		_check(promoted.size() == 3 and promoted.slice(0, 2) == ch_order.slice(0, 2), "season %d: top 2 of the Championship go up" % (s + 1))
		var po_winner: String = sum["playoff_winners"].get("eng_d2", "")
		_check(po_winner != "" and po_winner in ch_order.slice(2, 6) and promoted[2] == po_winner, "season %d: play-off winner (3rd-6th) takes the third spot" % (s + 1))
		_check(_sizes(c) == start_sizes, "season %d: division sizes unchanged" % (s + 1))
		var after := {}
		var dup := false
		for k in c.pyramids:
			for d in (c.pyramids[k] as LeaguePyramid).divisions:
				for t in d["team_ids"]:
					dup = dup or after.has(t)
					after[t] = true
		_check(not dup and after.keys().size() == all_before.keys().size() and after.keys().all(func(t: String) -> bool: return all_before.has(t)),
				"season %d: no club lost or duplicated" % (s + 1))
		_check(sum["relegated"].all(func(t: String) -> bool: return t in eng.divisions[1]["team_ids"]) and
				promoted.all(func(t: String) -> bool: return t in eng.divisions[0]["team_ids"]), "season %d: memberships updated" % (s + 1))
		_check(sum["cup_winner"] != "" and sum["champions"]["eng_d1"] == pl_order[0], "season %d: cup and league champions recorded" % (s + 1))
		_check(not c.competitions.has(pl.id) and not c.competitions.has(champ.id) and c.competitions.has(eng.comp["eng_d1"]),
				"season %d: old competitions archived, new season created" % (s + 1))
		var played_once := true
		for f in pl.fixtures:
			played_once = played_once and f["played"]
		_check(played_once and pl.results.size() == pl.fixtures.size(), "season %d: every league fixture played exactly once" % (s + 1))
		var esp: Dictionary = res["leagues"]["spain"]
		_check((esp["promoted"] as Array).size() == 3 and (esp["relegated"] as Array).size() == 3, "season %d: Spain promotes and relegates 3" % (s + 1))
		_check_relegation_playoff(res["leagues"]["germany"], "ger_d1", "ger_d2", 3, 3, s + 1)
		_check_relegation_playoff(res["leagues"]["france"], "fra_d1", "fra_d2", 3, 5, s + 1)
		var ita: Dictionary = res["leagues"]["italy"]
		var serie_b: Array = ita["tables"]["ita_d2"]
		var ita_po: String = ita["playoff_winners"].get("ita_d2", "")
		_check((ita["relegated"] as Array).size() == 3 and (ita["promoted"] as Array).size() == 3 and ita_po in serie_b.slice(2, 8),
				"season %d: Italy — 3 down, top 2 + play-off winner (3rd-8th) up" % (s + 1))
	_check(c.season == 4 and (c.pyramids["england"] as LeaguePyramid).history.size() == 3, "three seasons recorded")


## Germany / France: 2 go down directly; the lower division's play-off winner meets the 16th.
func _check_relegation_playoff(sum: Dictionary, d1: String, d2: String, po_from: int, po_to: int, season_no: int) -> void:
	var up: Array = sum["tables"][d1]
	var low: Array = sum["tables"][d2]
	var rp: Dictionary = sum["relegation_playoffs"].get(d2, {})
	var direct_ok: bool = (sum["relegated"] as Array).slice(0, 2) == up.slice(up.size() - 2) and (sum["promoted"] as Array).slice(0, 2) == low.slice(0, 2)
	var rp_ok: bool = not rp.is_empty() and rp["upper"] == up[15] and rp["lower"] in low.slice(po_from - 1, po_to) and rp["winner"] in [rp["upper"], rp["lower"]]
	var moved: bool = rp.get("winner", "") == rp.get("lower", "x")
	var counts_ok: bool = (sum["promoted"] as Array).size() == (3 if moved else 2) and (sum["relegated"] as Array).size() == (3 if moved else 2)
	var follow_ok: bool = (not moved) or (rp["upper"] in sum["relegated"] and rp["lower"] in sum["promoted"])
	_check(direct_ok and rp_ok and counts_ok and follow_ok, "season %d: %s relegation play-off (16th vs %d-%d) applied" % [season_no, d1, po_from, po_to],
			str(rp))


func _test_save_load() -> void:
	var c := _career()
	for w in 20:
		c.advance_week()
	var d := c.to_dict()
	var c2 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(d, "", true, true)))
	_check(c2.pyramids.size() == 5 and c2.competitions.size() == c.competitions.size(), "mid-season career round-trips")
	var e1: LeaguePyramid = c.pyramids["england"]
	var e2: LeaguePyramid = c2.pyramids["england"]
	var t1 := (c.competitions[e1.comp["eng_d1"]] as Competition).standings()
	var t2 := (c2.competitions[e2.comp["eng_d1"]] as Competition).standings()
	_check(JSON.stringify(t1) == JSON.stringify(t2), "tables identical after load")
	for w in CareerState.WEEKS_PER_SEASON - 20:
		c.advance_week()
		c2.advance_week()
	var s1 := c.end_season()
	var s2 := c2.end_season()
	_check(JSON.stringify(s1["leagues"]) == JSON.stringify(s2["leagues"]), "loaded career finishes the season identically (deterministic)")
	var c3 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true)))
	var a := JSON.stringify((c3.pyramids["england"] as LeaguePyramid).divisions)
	var b := JSON.stringify(e1.divisions)
	_check(a == b, "memberships survive a save after the rollover", _first_diff(a, b))


func _test_reserve_rule() -> void:
	var c := CareerState.start(db, "esp_real_madrid_c_f")
	var esp: LeaguePyramid = c.pyramids["spain"]
	var seg: Competition = c.competitions[esp.comp["esp_d2"]]
	# Force Real Sociedad B to win every second-tier match.
	for f in seg.fixtures:
		var b_home: bool = f["home"] == "esp_real_sociedad_b"
		var b_away: bool = f["away"] == "esp_real_sociedad_b"
		var r := MatchResult.make(f["match_id"], f["home"], f["away"], 3 if b_home else (0 if b_away else 1), 0 if b_home else (3 if b_away else 1))
		c.submit_result(seg.id, r)
	_check(seg.standings()[0]["team_id"] == "esp_real_sociedad_b", "the reserve team tops the second tier")
	var res := c.end_season()
	var sum: Dictionary = res["leagues"]["spain"]
	var in_top: bool = "esp_real_sociedad_b" in esp.divisions[0]["team_ids"]
	_check(not in_top and not ("esp_real_sociedad_b" in sum["promoted"]), "a reserve team is never promoted into its parent's division")
	_check((sum["promoted"] as Array).size() == 3, "the next eligible clubs go up instead")


func _first_diff(a: String, b: String) -> String:
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			return "at %d: %s | %s" % [i, a.substr(maxi(0, i - 60), 120), b.substr(maxi(0, i - 60), 120)]
	return "lengths %d vs %d" % [a.length(), b.length()]


var hub: HubRoot


func _press(node_name: String) -> bool:
	var b := hub.current.find_child(node_name, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _go(id: String, p: Dictionary = {}) -> void:
	hub.navigate(id, p)
	await get_tree().process_frame


func _select(opt_name: String, index: int) -> void:
	var o := hub.current.find_child(opt_name, true, false) as OptionButton
	o.select(index)
	o.item_selected.emit(index)
	await get_tree().process_frame


func _test_screens() -> void:
	var app: Node = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_choice: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	_check(app.switch_world(PACK) == "" and db.pack_id == PACK and app.career == null, "switching the world loads the pack and clears the old state")
	_check(app.switch_world("nope") != "", "unknown pack is refused")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	await _go("team_select")
	_check(hub.current.find_child("LeagueOption", true, false) != null and hub.current.find_child("DivisionOption", true, false) != null,
			"team selection offers country and division")
	await _select("DivisionOption", 1)
	_check(hub.current.find_child("Career_eng_leicester_city_fc", true, false) != null and
			hub.current.find_child("Career_eng_arsenal", true, false) == null, "division filter lists only that division's clubs")
	_check(_press("Career_eng_leicester_city_fc"), "career starts from the division list")
	await get_tree().process_frame
	_check(app.career != null and app.career.pyramids.size() == 5, "career has all five pyramids")
	await _go("career")
	_check(hub.current.find_child("DivisionLine", true, false) != null and hub.current.find_child("MyFixtures", true, false) != null,
			"career dashboard shows the division and the user's matches")
	_check(_press("AdvanceWeek"), "advance week")
	await get_tree().process_frame
	var sims: Array = hub.current.find_children("SimMine_*", "Button", true, false)
	var plays: Array = hub.current.find_children("PlayMine_*", "Button", true, false)
	_check(not sims.is_empty() and sims.size() == plays.size(), "this week's own match can be played in 3D or quick-simulated", str(sims.size()))
	if not sims.is_empty():
		var mid := String(sims[0].name).trim_prefix("SimMine_")
		(sims[0] as Button).pressed.emit()
		await get_tree().process_frame
		var played := false
		for cid in app.career.competitions:
			var f: Dictionary = (app.career.competitions[cid] as Competition).get_fixture(mid)
			if not f.is_empty():
				played = f["played"]
		_check(played, "quick-sim records the user's match")
	await _go("leagues")
	var table := hub.current.find_child("LeagueTable", true, false) as GridContainer
	_check(table != null and table.get_child_count() == 9 * 25, "leagues screen shows the 24-club table", str(table.get_child_count() if table else -1))
	await _select("CountryOption", 4)
	table = hub.current.find_child("LeagueTable", true, false) as GridContainer
	_check(table != null and table.get_child_count() == 9 * 21, "switching to Spain shows LaLiga")
	await _select("CountryOption", 2)
	table = hub.current.find_child("LeagueTable", true, false) as GridContainer
	_check(table != null and table.get_child_count() == 9 * 19, "switching to Germany shows the 18-club Bundesliga")
	for lang in ["ar", "de", "en"]:
		Loc.set_language(lang, false)
		await _go("leagues")
		_check(hub.current.find_child("LeagueTable", true, false) != null, "[%s] leagues screen builds" % lang)
		await _go("career")
		_check(hub.current.find_child("MyFixtures", true, false) != null, "[%s] career dashboard builds" % lang)
		await _go("settings")
		_check(hub.current.find_child("WorldOption", true, false) != null, "[%s] settings offer the game world" % lang)
	Loc.set_language("en", false)
	app.career.end_season(app.academies)
	await _go("leagues")
	_check(hub.current.find_child("LastSeason", true, false) != null, "leagues screen shows last season's movements")
	hub.queue_free()
	app.switch_world("")
	_check(db.pack_id == "" and db.get_team("club_royal_harbor") != null, "switching back restores the fictional world")
	if had_cfg:
		TeamDatabase.save_pack_choice(saved_choice)
