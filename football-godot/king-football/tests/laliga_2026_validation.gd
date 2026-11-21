## LaLiga 2026-27 data pack (`real_2026`) validation.
##   godot --headless --path . res://tests/laliga_2026_validation.tscn
## Loads the pack explicitly and restores the default world at the end, so other suites are unaffected.
extends Node

const PACK := "real_2026"
const OLD_PACK := "real_2025"
const USER_CLUB := "esp_racing_santander"      # promoted for 2026-27

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
	print("=== KING FOOTBALL — LaLiga 2026-27 pack validation ===")
	db = get_node("/root/TeamDB")
	_test_listed()
	_test_pack_loads()
	_test_clubs_and_squads()
	_test_known_players()
	_test_player_records()
	_test_market_and_search()
	_test_season()
	_test_save_load()
	_test_old_pack_still_loads()
	await _test_screens()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_listed() -> void:
	var info: Array = TeamDatabase.available_packs().filter(func(p: Dictionary) -> bool: return p["id"] == PACK)
	_check(info.size() == 1, "real_2026 pack is listed in the world choice")
	_check(info.size() == 1 and str(info[0].get("season", "")) == "2026-27", "pack season is 2026-27")


func _test_pack_loads() -> void:
	db.load_world(PACK)
	_check(db.errors.is_empty(), "pack loads without errors", str(db.errors.slice(0, 5)))
	_check(db.pack_id == PACK and db.is_consistent().is_empty(), "pack is the active, consistent world", str(db.is_consistent()))
	_check(db.leagues.keys() == ["spain"], "Spain is the only country of this pack (other leagues follow)", str(db.leagues.keys()))
	var lg: LeagueDef = db.leagues["spain"]
	_check(lg.validate(db).is_empty(), "Spain league validates", str(lg.validate(db)))
	_check(lg.divisions.size() == 2 and (lg.divisions[0]["team_ids"] as Array).size() == 20 and (lg.divisions[1]["team_ids"] as Array).size() == 22,
			"LaLiga 20 clubs, Segunda División 22 clubs")


func _test_clubs_and_squads() -> void:
	var d1: Array = (db.leagues["spain"] as LeagueDef).divisions[0]["team_ids"]
	var expected := ["esp_athletic_club", "esp_atletico_de_madrid", "esp_barcelona", "esp_ca_osasuna", "esp_deportivo_alaves",
			"esp_deportivo_la_coruna", "esp_elche_cf", "esp_getafe_cf", "esp_levante_ud", "esp_malaga_cf", "esp_racing_santander",
			"esp_rayo_vallecano", "esp_rc_celta", "esp_rcd_espanyol", "esp_real_betis", "esp_real_madrid_c_f", "esp_real_sociedad",
			"esp_sevilla", "esp_valencia_cf", "esp_villarreal"]
	var got := d1.duplicate()
	got.sort()
	_check(got == expected, "the 20 LaLiga 2026-27 clubs (Racing, Deportivo and Málaga promoted)", str(got))
	_check(not d1.has("esp_rcd_mallorca") and not d1.has("esp_girona_fc") and not d1.has("esp_real_oviedo"),
			"Mallorca, Girona and Oviedo (relegated in 2025-26) are not in LaLiga")
	var bad := []
	var no_mgr := []
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var squad := db.get_squad(t.id)
		var gks := squad.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
		var numbers := {}
		var dup_number := false
		for p in squad:
			dup_number = dup_number or numbers.has(p.shirt_number) or p.shirt_number <= 0
			numbers[p.shirt_number] = true
		if squad.size() < 18 or squad.size() > TransferMarket.MAX_SQUAD or gks < 2 or dup_number or not t.is_real:
			bad.append("%s(%d,%dgk,dup=%s)" % [t.id, squad.size(), gks, dup_number])
		if t.manager_name == "" or t.stadium_name == "":
			no_mgr.append(t.id)
		if t.league_id == "":
			bad.append(t.id + " has no league")
	_check(bad.is_empty(), "every club: 18-30 players, 2+ keepers, unique shirt numbers, real, in a league", str(bad))
	_check(no_mgr.is_empty(), "every club has a manager and a stadium", str(no_mgr))
	_check(db.get_team("esp_real_madrid_c_f").stadium_capacity > 50000, "stadium capacity is loaded")


func _named(name: String) -> Array:
	return db.players.values().filter(func(p: PlayerData) -> bool: return p.display_name == name)


func _test_known_players() -> void:
	# Spot checks against the clubs' official 2026-27 squads (via the Wikipedia squad tables the pack is built from).
	var cases := [["Kylian Mbappé", "esp_real_madrid_c_f", 10], ["Ibrahima Konaté", "esp_real_madrid_c_f", 16],
			["Marc Cucurella", "esp_real_madrid_c_f", 17], ["Lamine Yamal", "esp_barcelona", 10],
			["Unai Simón", "esp_athletic_club", 1], ["Nico Williams", "esp_athletic_club", 10]]
	for c in cases:
		var found := _named(c[0])
		_check(found.size() == 1 and (found[0] as PlayerData).team_id == c[1] and (found[0] as PlayerData).shirt_number == c[2],
				"%s is at %s with #%d" % c, str(found.map(func(p: PlayerData) -> String: return "%s #%d" % [p.team_id, p.shirt_number])))
	var mgr := db.get_team("esp_real_madrid_c_f").manager_name
	_check(mgr != "", "Real Madrid manager loaded (%s)" % mgr)


func _test_player_records() -> void:
	var real := 0
	var with_height := 0
	var with_birth := 0
	var sec := 0
	var bad_type := []
	for p: PlayerData in db.players.values():
		if p.player_type == PlayerData.PlayerType.REAL:
			real += 1
		elif bad_type.size() < 5:
			bad_type.append(p.id)
		with_height += 1 if p.height_cm > 0 else 0
		with_birth += 1 if p.birth_year > 1970 else 0
		sec += 1 if not p.secondary_positions.is_empty() else 0
	var n := db.players.size()
	_check(n > 1000, "over 1,000 real players in the pack", str(n))
	_check(real == n, "every player is a REAL player (no generated names)", str(bad_type))
	_check(with_birth == n, "every player has a birth year", "%d/%d" % [with_birth, n])
	_check(with_height >= n * 0.95, "95%+ have a real height", "%d/%d" % [with_height, n])
	_check(sec > n * 0.2, "secondary positions are filled where the source lists them", "%d/%d" % [sec, n])
	var wp: Array = db.players.keys().filter(func(k: String) -> bool: return k.begins_with("wp_"))
	_check(wp.size() > 0 and wp.all(func(k: String) -> bool: return PlayerData.type_for_id(k) == PlayerData.PlayerType.REAL),
			"players without a transfermarkt id (wp_) are typed REAL")
	var p0: PlayerData = db.players.values()[0]
	var round_trip := PlayerData.from_dict(JSON.parse_string(JSON.stringify(p0.to_dict())))
	_check(round_trip.height_cm == p0.height_cm and round_trip.secondary_positions == p0.secondary_positions and round_trip.birth_year == p0.birth_year,
			"new identity fields survive a save round trip")


func _test_market_and_search() -> void:
	var tm := TransferMarket.new(db)
	var found := tm.search({"name": "Mbappé"})
	_check(found.size() == 1 and found[0].team_id == "esp_real_madrid_c_f", "transfer search finds a real LaLiga player")
	_check(tm.asking_price(found[0]) > 50_000_000, "asking price reflects the market value", str(tm.asking_price(found[0])))
	_check(db.get_team_rating("esp_real_madrid_c_f") > db.get_team_rating("esp_racing_santander"), "Real Madrid rated above promoted Racing")
	_check(db.get_team_rating("esp_racing_santander") > db.get_team_rating("esp_cd_eldense"), "a LaLiga club rated above a Segunda club")


func _test_season() -> void:
	var c := CareerState.start(db, USER_CLUB)
	_check(c != null and c.pyramids.has("spain"), "career starts with a 2026-27 LaLiga club")
	_check(CareerDate.season_year(c.season) == 2026, "first career season is 2026-27")
	var esp: LeaguePyramid = c.pyramids["spain"]
	var liga: Competition = c.competitions[esp.comp["esp_d1"]]
	_check(liga.fixtures.size() == 380, "LaLiga has 380 fixtures", str(liga.fixtures.size()))
	for w in CareerState.WEEKS_PER_SEASON:
		c.advance_week()
	var res := c.end_season()
	var sum: Dictionary = res["leagues"]["spain"]
	var table: Array = sum["tables"]["esp_d1"]
	_check(table.size() == 20 and (sum["relegated"] as Array) == table.slice(17), "bottom three of LaLiga are relegated")
	_check((sum["promoted"] as Array).size() == 3 and not ("esp_real_sociedad_b" in sum["promoted"]) and not ("esp_rc_celta_fortuna" in sum["promoted"]),
			"three clubs promoted; reserve sides never go up", str(sum["promoted"]))
	_check((esp.divisions[0]["team_ids"] as Array).size() == 20 and (esp.divisions[1]["team_ids"] as Array).size() == 22, "division sizes kept after the season")


func _test_save_load() -> void:
	var c := CareerState.start(db, USER_CLUB)
	for w in 10:
		c.advance_week()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(),
			"world": {"pack_id": db.pack_id, "pack_version": str(db.pack_info.get("version", ""))}}), "", true, true))      # as AppHub saves it
	var mbappe_before: String = (_named("Kylian Mbappé")[0] as PlayerData).team_id
	var res := SaveManager.restore(db, snapshot)
	var c2 := CareerState.from_dict(db, res["extras"]["career"])
	_check(c2 != null and c2.week == c.week and c2.season == c.season and db.pack_id == PACK, "mid-season 2026-27 career round-trips",
			"week %s/%s season %s/%s pack %s" % [c2.week if c2 else -1, c.week, c2.season if c2 else -1, c.season, db.pack_id])
	_check((_named("Kylian Mbappé")[0] as PlayerData).team_id == mbappe_before, "players keep their clubs after loading")
	_check(db.get_team("esp_real_madrid_c_f").manager_name != "", "manager name survives save/load")


func _test_old_pack_still_loads() -> void:
	db.load_world(OLD_PACK)
	_check(db.errors.is_empty() and db.pack_id == OLD_PACK and db.leagues.size() == 5, "the 2025-26 pack still loads (old saves stay playable)")
	db.load_world(PACK)


var hub: HubRoot


func _test_screens() -> void:
	var app: Node = get_node("/root/AppHub")
	_check(app.switch_world(PACK) == "" and db.pack_id == PACK, "switching the world to LaLiga 2026-27 works")
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("team_details", {"team_id": "esp_real_madrid_c_f"})
	await get_tree().process_frame
	var text := _all_text(hub.current)
	_check(text.find(db.get_team("esp_real_madrid_c_f").manager_name) >= 0, "team page shows the manager")
	_check(text.find("Mbappé") >= 0, "team page lists the real squad")
	var mbappe: PlayerData = _named("Kylian Mbappé")[0]
	hub.navigate("player_profile", {"player_id": mbappe.id})
	await get_tree().process_frame
	text = _all_text(hub.current)
	_check(text.find("#10") >= 0 and text.find("%d" % mbappe.height_cm) >= 0, "player profile shows number and height")
	hub.queue_free()
	await get_tree().process_frame
	app.switch_world("")


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for ch in n.get_children():
		out += _all_text(ch)
	return out
