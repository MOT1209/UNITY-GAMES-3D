## Database phase 3 validation — unified player database, detailed attributes, season stats:
##   godot --headless --path . res://tests/db_players_validation.tscn
extends Node

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
	print("=== KING FOOTBALL — database phase 3 (players) validation ===")
	_test_fields_and_roundtrip()
	_test_attribute_detail()
	_test_real_pack()
	_test_identity_across_transfer()
	_test_youth()
	_test_season_stats()
	_test_old_records()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db() -> TeamDatabase:
	return load("res://scripts/core/team_database.gd").new()


func _sample() -> PlayerData:
	var p := PlayerData.new()
	p.id = "tm_1"
	p.display_name = "Ada Lovelace-Smith"
	p.nationality = "England"
	p.position = PlayerData.Position.CM
	p.potential = 80
	return p


func _test_fields_and_roundtrip() -> void:
	var p := _sample()
	p.birth_year = 2001
	p.height_cm = 181
	p.weight_kg = 74
	p.secondary_positions = ["CDM", "CAM"]
	p.contract_id = "ct_1"
	var back := PlayerData.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	_check(back.to_dict() == p.to_dict(), "extended player JSON round-trip identical")
	_check(p.validate().is_empty(), "extended player is valid", str(p.validate()))
	var parts := PlayerData.split_name("Ada Lovelace-Smith")
	_check(parts == ["Ada", "Lovelace-Smith"] and PlayerData.split_name("Pelé") == ["", "Pelé"], "name split: first word / rest, single word = last name")
	p.birth_year = 1900
	p.height_cm = 250
	p.weight_kg = 10
	p.secondary_positions = ["XX", "CM"]
	_check(p.validate().size() == 5, "bad birth year, height, weight and secondary positions are reported", str(p.validate()))
	_check(PlayerData.type_for_id("tm_5") == PlayerData.PlayerType.REAL and PlayerData.type_for_id("yth_x_1") == PlayerData.PlayerType.YOUTH and PlayerData.type_for_id("gen_1") == PlayerData.PlayerType.GENERATED, "player type follows the id prefix")


func _test_attribute_detail() -> void:
	var p := _sample()
	p.pace = 80
	p.shooting = 70
	p.passing = 60
	p.dribbling = 75
	p.defending = 40
	p.physical = 65
	var d := AttributeDetail.for_player(p)
	_check(d.size() == AttributeDetail.ORDER.size() and d.size() == 18, "18 detailed attributes", str(d.size()))
	_check(d == AttributeDetail.for_player(p), "detailed attributes are deterministic")
	var ok := true
	for k in d:
		ok = ok and int(d[k]) >= 1 and int(d[k]) <= 99
	_check(ok, "all detailed attributes within 1-99")
	_check(d["pace"] == 80 and d["physicality"] == 65 and d["shooting"] == 70, "core attributes pass through unchanged")
	_check(abs(int(d["acceleration"]) - 80) <= AttributeDetail.OFFSET and abs(int(d["finishing"]) - 70) <= AttributeDetail.OFFSET, "derived attributes stay within +-6 of their parent")
	var before := p.get_overall()
	AttributeDetail.for_player(p)
	_check(p.get_overall() == before, "detailed attributes never change the overall")
	var q := _sample()
	q.id = "tm_2"
	q.pace = 80
	q.shooting = 70
	q.passing = 60
	q.dribbling = 75
	q.defending = 40
	q.physical = 65
	_check(AttributeDetail.for_player(q) != d, "a different player id gives a different offset pattern")
	var gk := _sample()
	gk.position = PlayerData.Position.GK
	gk.goalkeeping = 85
	_check(abs(AttributeDetail.value(gk, "positioning") - 85) <= AttributeDetail.OFFSET, "goalkeeper positioning follows goalkeeping")
	var h := p.get_height_cm()
	_check(h >= 160 and h <= 205 and p.get_weight_kg() >= 55, "height/weight estimate is plausible", "%d cm %d kg" % [h, p.get_weight_kg()])
	p.height_cm = 190
	_check(p.get_height_cm() == 190, "a stored height wins over the estimate")


func _test_real_pack() -> void:
	var db := _new_db()
	db.load_world("real_2025")
	_check(db.errors.is_empty() and db.players.size() == 5213, "real pack: 5213 players load", "%d %s" % [db.players.size(), db.errors.slice(0, 2)])
	var real := 0
	var gen := 0
	var no_name := 0
	var linked := 0
	for p: PlayerData in db.players.values():
		real += 1 if p.player_type == PlayerData.PlayerType.REAL else 0
		gen += 1 if p.player_type == PlayerData.PlayerType.GENERATED else 0
		no_name += 1 if p.last_name == "" else 0
		linked += 1 if p.nationality_id != "" else 0
	_check(real == 2867 and gen == 5213 - 2867, "2867 REAL and the rest GENERATED", "%d / %d" % [real, gen])
	_check(no_name == 0, "every player has a last name")
	_check(linked > 0 and db.get_player("tm_262749").nationality_id == "esp", "nationality id derived where the country is in the database", str(linked))
	var raya := db.get_player("tm_262749")
	_check(raya.display_name == "David Raya" and raya.first_name == "David" and raya.last_name == "Raya", "David Raya: first/last name derived")
	_check(raya.birth_year == 0 and raya.height_cm == 0, "no birth year or height is invented for a real player")
	var problems := db.validate_relations()
	_check(problems.is_empty(), "club/player relations still consistent", str(problems.slice(0, 2)))


func _test_identity_across_transfer() -> void:
	var db := _new_db()
	db.load_world("")
	var market := TransferMarket.new(db, {})
	for tid in ["club_sunvale", "club_cedar_city"]:
		market.ledgers[tid] = FinanceLedger.new(tid, 900_000_000, 900_000_000, 900_000_000)
	var seller: TeamData = db.get_team("club_cedar_city")
	var p: PlayerData = db.get_player(seller.squad_ids[5])
	var before_obj := p
	var before_id := p.id
	var before_app := p.appearance.duplicate(true)
	var before_name := p.display_name
	var before_detail := AttributeDetail.for_player(p)
	var err := market.buy("club_sunvale", p.id, market.asking_price(p), 5000, 3, 1)
	_check(err == "", "transfer succeeds", err)
	_check(db.get_player(before_id) == before_obj and p.team_id == "club_sunvale", "same PlayerData object, new club")
	_check(p.appearance == before_app, "appearance unchanged by the transfer")
	_check(AttributeDetail.for_player(p) == before_detail and p.display_name == before_name, "detailed attributes and names unchanged")
	_check(db.get_team("club_sunvale").squad_ids.has(before_id) and not seller.squad_ids.has(before_id), "squad lists follow the transfer")
	_check(db.validate_relations().is_empty(), "relations consistent after the transfer", str(db.validate_relations().slice(0, 2)))
	var card := PlayerCardData.from_player(db, before_id)
	_check(card.club_id == "club_sunvale" and card.player_id == before_id, "player card shows the new club for the same id")


func _test_youth() -> void:
	var db := _new_db()
	db.load_world("")
	var academy := Academy.new("club_sunvale", "Aldoria", 7)
	var made := academy.generate_intake(db, 5, AcademyConfig.MIN_PROMOTION_AGE)
	_check(made.size() == 5, "academy creates 5 prospects")
	var p := made[0]
	_check(p.id.begins_with("yth_") and p.player_type == PlayerData.PlayerType.YOUTH, "prospect has a permanent yth_ id and YOUTH type")
	_check(p.first_name != "" and p.last_name != "" and p.nationality_id == "ald", "prospect has first/last name and nationality id")
	var app := p.appearance.duplicate(true)
	var err := PromotionSystem.promote(db, academy, p.id)
	_check(err == "", "prospect is promoted", err)
	_check(db.get_player(p.id) == p and p.id == made[0].id and p.appearance == app, "promotion keeps the id, the object and the appearance")
	_check(db.get_team("club_sunvale").squad_ids.has(p.id), "promoted player is in the senior squad")
	_check(db.validate_relations().is_empty(), "relations consistent after promotion", str(db.validate_relations().slice(0, 2)))


func _test_season_stats() -> void:
	var db := _new_db()
	db.load_world("")
	var career := CareerState.start(db, "club_sunvale")
	_check(career != null, "career starts")
	var report := {"uid": "m1", "source": "engine", "motm": "pa",
			"players": [{"player_id": "pa", "goals": 2, "assists": 0, "saves": 0, "rating": 8.0},
					{"player_id": "pb", "goals": 0, "assists": 1, "saves": 0, "rating": 6.0}]}
	_check(career.record_match(report, "lg_a"), "match recorded")
	var report2 := report.duplicate(true)
	report2["uid"] = "m2"
	career.record_match(report2, "lg_a")
	var report3 := report.duplicate(true)
	report3["uid"] = "m3"
	career.record_match(report3)
	career.season = 2
	var report4 := report.duplicate(true)
	report4["uid"] = "m4"
	career.record_match(report4, "lg_a")
	_check(career.stats_for("pa", 1, "lg_a")["goals"] == 4 and career.stats_for("pa", 1, "lg_a")["apps"] == 2, "season 1 league stats: 2 apps, 4 goals")
	_check(career.stats_for("pa", 1, "friendly")["apps"] == 1, "matches without a competition count as friendly")
	_check(career.stats_for("pa", 1)["apps"] == 3 and career.stats_for("pa", 2)["apps"] == 1, "season totals sum all competitions")
	_check(career.stats_for("pa", 1, "lg_a")["motm"] == 2, "man of the match is counted per season/competition")
	_check(career.player_stats["pa"]["apps"] == 4 and career.player_stats["pa"]["goals"] == 8, "all-time counters are unchanged")
	_check(not career.record_match(report, "lg_a") and career.stats_for("pa", 1, "lg_a")["apps"] == 2, "re-recording a match is ignored")
	var back := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(career.to_dict())))
	_check(back.stats_for("pa", 1, "lg_a") == career.stats_for("pa", 1, "lg_a") and back.stats_for("pb", 2)["assists"] == 1, "season stats survive save/load")
	var old := career.to_dict()
	old.erase("season_stats")
	var back_old := CareerState.from_dict(db, old)
	_check(back_old.season_stats.is_empty() and back_old.player_stats["pa"]["apps"] == 4, "a career saved before this system loads with empty season stats")


func _test_old_records() -> void:
	var old := {"id": "gen_9", "name": "Jonas Becker", "age": 20, "nationality": "Germany", "position": "ST",
			"pace": 60, "shooting": 60, "passing": 50, "dribbling": 55, "defending": 30, "physical": 55, "potential": 70}
	var p := PlayerData.from_dict(old)
	_check(p.first_name == "Jonas" and p.last_name == "Becker" and p.player_type == PlayerData.PlayerType.GENERATED, "old player record gets names and type")
	var db := _new_db()
	db.load_countries()
	db.link_player(p)
	_check(p.nationality_id == "ger", "link_player derives the nationality id")
	p.nationality_id = "xyz"
	db.link_player(p)
	_check(p.nationality_id == "xyz", "link_player never overwrites a stored value")
	# save/restore keeps everything, and an old save (without the new keys) is linked on restore
	var db2 := _new_db()
	db2.load_world("")
	var snap := SaveManager.capture(db2)
	for pd in snap["players"]:
		for k in ["first_name", "last_name", "nationality_id", "player_type"]:
			pd.erase(k)
	var db3 := _new_db()
	db3.load_countries()
	var res := SaveManager.restore(db3, snap)
	var any: PlayerData = db3.players.values()[0]
	_check(res["ok"] and any.last_name != "" and any.nationality_id != "", "old save restores with derived names and nationality ids", str(res.get("errors", [])))
