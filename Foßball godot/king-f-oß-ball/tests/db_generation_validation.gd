## Database phase 6 validation — deterministic generation of the fictional third divisions:
## names, clubs, squads, leagues, youth, crests, reproducibility of the shipped data:
##   godot --headless --path . res://tests/db_generation_validation.tscn
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
	print("=== KING FOOTBALL — database phase 6 (generation) validation ===")
	_test_name_index()
	_test_name_bank()
	_test_determinism()
	_test_shipped_equals_regenerated()
	_test_world()
	_test_squads()
	_test_names_in_world()
	_test_youth()
	_test_crests()
	_test_season()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db(world: String, skip_fictional := false) -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.skip_fictional_layer = skip_fictional
	db.load_world(world)
	return db


func _test_name_index() -> void:
	_check(NameIndex.normalize("Álvaro  Peña-Núñez") == "alvaro pena nunez" and NameIndex.normalize("D'Angelo") == "dangelo", "names are normalised (accents, case, hyphens, apostrophes)")
	_check(NameIndex.distance("marcos", "marco") == 1 and NameIndex.distance("abc", "abc") == 0 and NameIndex.distance("kitten", "sitting") == 3, "edit distance")
	var idx := NameIndex.new()
	idx.add("Marcos Gil")
	_check(idx.check("marcos gil") != "" and "duplicate" in idx.check("MARCOS GIL"), "an exact duplicate is found (case ignored)")
	_check("too similar" in idx.check("Marco Gil"), "a name one letter apart is 'too similar'")
	_check(idx.check("Álvaro Gil") == "" and idx.check("Marcos Pérez") == "", "different names are free")
	_check(idx.check("Marcos Gill") != "", "a trailing extra letter is caught")
	var conflicts := NameIndex.find_conflicts(["Jon Reed", "Ann Lee", "jon reid", "Jon Reed"])
	_check(conflicts.size() == 2, "find_conflicts reports a look-alike and a duplicate", str(conflicts))
	var big := NameIndex.new()
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 3000:
		var n := NameBank.random_name(rng, NameBank.COUNTRIES[i % 5])
		if big.check(n) == "":
			big.add(n)
	var ms := Time.get_ticks_msec() - t0
	print("[PERF] indexed %d names with look-alike checks in %d ms" % [big.size(), ms])
	_check(big.size() > 2000 and ms < 15000, "indexing thousands of names stays fast (%d ms)" % ms)


func _test_name_bank() -> void:
	for c in NameBank.COUNTRIES:
		var pool: Dictionary = NameBank.POOLS[c]
		_check((pool["first"] as Array).size() >= 60 and (pool["last"] as Array).size() >= 60 and NameBank.combinations(c) >= 3800, "%s: %d first x %d last names = %d combinations" % [c, (pool["first"] as Array).size(), (pool["last"] as Array).size(), NameBank.combinations(c)])
	var idx := NameIndex.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	var dup := false
	for i in 500:
		var n := NameBank.unique_name(rng, "Italy", idx)
		dup = dup or seen.has(n)
		seen[n] = true
	_check(not dup, "unique_name gives 500 different Italian names")
	_check(YouthGenerator.pool_for("England")["first"] == NameBank.POOLS["England"]["first"], "the youth generator uses the same country name pools")


func _test_determinism() -> void:
	var used1 := {"names": NameIndex.new(), "places": {}, "shorts": {}, "ids": {}}
	var used2 := {"names": NameIndex.new(), "places": {}, "shorts": {}, "ids": {}}
	var a := ClubGenerator.generate_club(7, "Germany", 3, 3, "ger_d3", used1, "ger_cup")
	var b := ClubGenerator.generate_club(7, "Germany", 3, 3, "ger_d3", used2, "ger_cup")
	_check(a == b, "the same seed, country and index give the same club")
	var c := ClubGenerator.generate_club(8, "Germany", 3, 3, "ger_d3", {"names": NameIndex.new(), "places": {}, "shorts": {}, "ids": {}}, "ger_cup")
	_check(c["name"] != a["name"] or c["primary"] != a["primary"], "another seed gives another club")
	var s1 := ClubGenerator.generate_squad(a, NameIndex.new())
	var s2 := ClubGenerator.generate_squad(a, NameIndex.new())
	var same := s1.size() == s2.size()
	for i in s1.size():
		same = same and s1[i].to_dict() == s2[i].to_dict()
	_check(same and s1.size() == ClubGenerator.SQUAD_SIZE, "the same club gives the same %d players" % ClubGenerator.SQUAD_SIZE)
	_check(PlayerAppearance.generate(PlayerAppearance.seed_for(s1[0].id)) == PlayerAppearance.generate(PlayerAppearance.seed_for(s2[0].id)), "generated players get a deterministic appearance")


func _test_shipped_equals_regenerated() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/generation/config.json"))
	var base := _new_db("real_2025", true)
	_check(base.teams.size() == 198 and base.players.size() == 5213, "the real data underneath is unchanged (198 clubs, 5213 players)", "%d/%d" % [base.teams.size(), base.players.size()])
	var cups := {}
	for key in WorldGenerator.cup_keys():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/real_2025/leagues/%s.json" % key))
		cups[key] = str(d["cup"]["id"])
	var regen := WorldGenerator.generate(base, int(cfg["world_seed"]), int(cfg["per_country"]), cups)
	_check(regen["clubs"].size() == 100 and regen["manifest"]["players"] == 2800, "regeneration gives 100 clubs and 2800 players")
	var all_same := true
	var first_diff := ""
	for entry in regen["clubs"]:
		var id: String = (entry["team"] as TeamData).id
		var file: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/real_2025/fictional/clubs/%s.json" % id))
		var fresh: Variant = JSON.parse_string(JSON.stringify(WorldGenerator.club_file(entry, int(cfg["world_seed"]))))
		if typeof(file) != TYPE_DICTIONARY or file != fresh:
			all_same = false
			first_diff = id
			break
	_check(all_same, "every shipped fictional club file equals a fresh deterministic generation", first_diff)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/real_2025/fictional/manifest.json"))
	_check(manifest["world_seed"] == cfg["world_seed"] and manifest["clubs"] == 100 and manifest["players"] == 2800, "the manifest records seed, club and player counts")
	var other := WorldGenerator.generate(base, int(cfg["world_seed"]) + 1, 20, cups)
	_check((other["clubs"][0]["team"] as TeamData).display_name != (regen["clubs"][0]["team"] as TeamData).display_name or (other["clubs"][0]["team"] as TeamData).primary_color != (regen["clubs"][0]["team"] as TeamData).primary_color, "a different seed gives a different world")
	var smaller := WorldGenerator.generate(base, int(cfg["world_seed"]), 10, cups)
	_check(smaller["clubs"].size() == 50, "the size per country is configurable (10 -> 50 clubs)")


func _test_world() -> void:
	var db := _new_db("real_2025")
	_check(db.errors.is_empty(), "the pack with the fictional layer loads without errors", str(db.errors.slice(0, 3)))
	_check(db.teams.size() == 298 and db.players.size() == 8013, "298 clubs and 8013 players (the target scale: 250-350 clubs, 8,000-12,000 players)")
	var fictional := db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.club_type == TeamData.ClubType.FICTIONAL)
	_check(fictional.size() == 100 and fictional.all(func(t: TeamData) -> bool: return not t.is_real and t.id.begins_with("fic_")), "100 fictional clubs, none marked real, all with a fic_ id")
	var real_clubs := db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.is_real)
	_check(real_clubs.size() == 198, "198 real clubs coexist with them")
	_check(db.leagues.size() == 5, "all 5 leagues are valid with 3 divisions each")
	var tiers_ok := true
	for key in db.leagues:
		var lg: LeagueDef = db.leagues[key]
		tiers_ok = tiers_ok and lg.divisions.size() == 3 and (lg.divisions[2]["team_ids"] as Array).size() == 20 and int(lg.divisions[2]["promote"]) == int(lg.divisions[1]["relegate"])
	_check(tiers_ok, "each league: tier 3 has 20 clubs and promotes as many as tier 2 relegates")
	var in_div := {}
	var multi := false
	for key in db.leagues:
		for dv in (db.leagues[key] as LeagueDef).divisions:
			for tid in dv["team_ids"]:
				multi = multi or in_div.has(tid)
				in_div[tid] = dv["id"]
	_check(not multi and in_div.size() == 298, "every club is in exactly one division")
	var linked := fictional.all(func(t: TeamData) -> bool: return t.division == 3 and t.league_id.ends_with("_d3"))
	_check(linked, "fictional clubs are linked to their third division")
	var problems := db.validate_relations()
	_check(problems.is_empty(), "club / player / league / country relations are consistent", str(problems.slice(0, 3)))
	_check(db.validate_kits().is_empty(), "all kits are valid")
	var rivals_ok := true
	for t: TeamData in fictional:
		rivals_ok = rivals_ok and t.rival_club_ids.size() == 2 and not t.rival_club_ids.has(t.id)
	_check(rivals_ok, "every fictional club has two rivals inside its division")
	var money_ok := true
	for t: TeamData in fictional:
		money_ok = money_ok and t.budget > 0 and t.wage_budget > 0 and t.weekly_expenses > 0 and t.stadium_capacity >= 2500 and t.founding_year >= 1885 and t.city != ""
	_check(money_ok, "fictional clubs have finances, stadium, city and founding year")


func _test_squads() -> void:
	var db := _new_db("real_2025")
	var ok := true
	var shape_ok := true
	var ages_ok := true
	var valid_ok := true
	var foreign := 0
	var total := 0
	var detail := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.club_type != TeamData.ClubType.FICTIONAL:
			continue
		var sq := db.get_squad(t.id)
		ok = ok and sq.size() == 28
		var pos := {}
		var nums := {}
		for p in sq:
			pos[p.position] = int(pos.get(p.position, 0)) + 1
			nums[p.shirt_number] = true
			ages_ok = ages_ok and p.age >= 17 and p.age <= 36
			valid_ok = valid_ok and p.validate().is_empty() and p.potential >= p.get_overall() and p.player_type == PlayerData.PlayerType.GENERATED and p.id.begins_with("gen_fic_")
			foreign += 1 if p.nationality != t.country else 0
			total += 1
		var gk := int(pos.get(PlayerData.Position.GK, 0))
		var def := int(pos.get(PlayerData.Position.CB, 0)) + int(pos.get(PlayerData.Position.LB, 0)) + int(pos.get(PlayerData.Position.RB, 0))
		var att := int(pos.get(PlayerData.Position.ST, 0)) + int(pos.get(PlayerData.Position.LW, 0)) + int(pos.get(PlayerData.Position.RW, 0))
		shape_ok = shape_ok and gk == 3 and def >= 9 and att >= 5 and nums.size() == 28
		if not shape_ok and detail == "":
			detail = "%s gk %d def %d att %d" % [t.id, gk, def, att]
	_check(ok, "every fictional club has a squad of 28")
	_check(shape_ok, "balanced squads: 3 goalkeepers, 9+ defenders, 5+ forwards, unique shirt numbers", detail)
	_check(ages_ok and valid_ok, "ages 17-36, valid attributes, potential >= overall, GENERATED type, gen_fic_ ids")
	var share := float(foreign) / float(total)
	_check(share > 0.12 and share < 0.28, "about a fifth of the players have another nationality (%.0f %%)" % (share * 100.0))
	# strength ladder: tier 1 > tier 2 > tier 3 in team rating
	var sums := {1: 0.0, 2: 0.0, 3: 0.0}
	var counts := {1: 0, 2: 0, 3: 0}
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		sums[t.division] += db.get_team_rating(t.id)
		counts[t.division] += 1
	var avg1: float = sums[1] / counts[1]
	var avg2: float = sums[2] / counts[2]
	var avg3: float = sums[3] / counts[3]
	print("[INFO] average team rating by tier: %.1f / %.1f / %.1f" % [avg1, avg2, avg3])
	_check(avg1 > avg2 + 3.0 and avg2 > avg3 + 2.0, "the strength ladder holds: tier 1 > tier 2 > tier 3 (%.1f / %.1f / %.1f)" % [avg1, avg2, avg3])
	var spread := 0
	var ovs: Array[int] = []
	for p: PlayerData in db.players.values():
		if p.id.begins_with("gen_fic_"):
			ovs.append(p.get_overall())
	ovs.sort()
	spread = ovs[ovs.size() - 1] - ovs[0]
	_check(spread >= 25 and ovs[ovs.size() / 2] > 35 and ovs[ovs.size() / 2] < 65, "realistic attribute spread (overall %d-%d, median %d)" % [ovs[0], ovs[ovs.size() - 1], ovs[ovs.size() / 2]])


func _test_names_in_world() -> void:
	var db := _new_db("real_2025")
	var real_names := NameIndex.new()
	var club_real := NameIndex.new()
	var fic_clubs: Array[TeamData] = []
	for t: TeamData in db.teams.values():
		if t.club_type == TeamData.ClubType.FICTIONAL and t.id.begins_with("fic_"):
			fic_clubs.append(t)
		else:
			club_real.add(t.display_name)
	for p: PlayerData in db.players.values():
		if not p.id.begins_with("gen_fic_"):
			real_names.add(p.display_name)
	var dupes := 0
	var similar := 0
	var own := NameIndex.new()
	for p: PlayerData in db.players.values():
		if not p.id.begins_with("gen_fic_"):
			continue
		dupes += 1 if own.check(p.display_name) != "" else 0
		own.add(p.display_name)
		similar += 1 if real_names.check(p.display_name) != "" else 0
	_check(dupes == 0, "no two generated players share (or nearly share) a name", str(dupes))
	_check(similar == 0, "no generated player has the name of (or nearly of) an existing real or older generated player", str(similar))
	var club_dupes := 0
	var club_similar := 0
	var shorts := {}
	var places := {}
	var own_clubs := NameIndex.new()
	for t in fic_clubs:
		club_dupes += 1 if own_clubs.check(t.display_name) != "" else 0
		own_clubs.add(t.display_name)
		club_similar += 1 if club_real.check(t.display_name) != "" else 0
		shorts[t.short_name] = true
		places[t.city.to_lower()] = true
	_check(club_dupes == 0 and club_similar == 0, "fictional club names are unique and none matches a real club", "%d/%d" % [club_dupes, club_similar])
	var all_shorts := {}
	for t: TeamData in db.teams.values():
		all_shorts[t.short_name] = true
	_check(all_shorts.size() == db.teams.size() or all_shorts.size() >= db.teams.size() - 10, "short codes are (almost) unique across all clubs: %d codes for %d clubs" % [all_shorts.size(), db.teams.size()])
	_check(shorts.size() == 100 and places.size() == 100, "100 different short codes and 100 different places among the fictional clubs")


func _test_youth() -> void:
	var db := _new_db("real_2025")
	var club: TeamData = db.get_team("fic_eng_elmford_city")
	_check(club != null, "a fictional club can be looked up")
	var academy := Academy.new(club.id, club.country, 11)
	var made := academy.generate_intake(db, 12, AcademyConfig.MIN_PROMOTION_AGE)
	_check(made.size() == 12, "the academy of a fictional club creates 12 prospects")
	var pool: Dictionary = NameBank.POOLS["England"]
	var names_ok := true
	for p in made:
		var parts := PlayerData.split_name(p.display_name)
		names_ok = names_ok and parts[0] in pool["first"] and parts[1] in pool["last"] and p.nationality == "England" and p.id.begins_with("yth_") and p.player_type == PlayerData.PlayerType.YOUTH
	_check(names_ok, "prospects get English names and nationality, yth_ ids and the YOUTH type")
	var p0 := made[0]
	var app := p0.appearance.duplicate(true)
	var err := PromotionSystem.promote(db, academy, p0.id)
	_check(err == "" and db.get_player(p0.id) == p0 and p0.appearance == app and db.get_team(club.id).squad_ids.has(p0.id), "promotion to the first team keeps identity and appearance", err)
	_check(db.validate_relations().is_empty(), "relations stay consistent after promotion", str(db.validate_relations().slice(0, 2)))


func _test_crests() -> void:
	var db := _new_db("real_2025")
	var ok := true
	var designs := {}
	for t: TeamData in db.teams.values():
		if t.id.begins_with("fic_"):
			var c := db.crests.get_crest("crest_" + t.id)
			ok = ok and c != null and c.asset_type == CrestData.AssetType.FICTIONAL and c.license_status == "FICTIONAL" and t.crest_id == c.crest_id
			designs[c.signature() if c != null else t.id] = true
	_check(ok and designs.size() == 100, "every fictional club has its own FICTIONAL crest (100 different designs)")
	_check(db.crests.validate(db).is_empty(), "crest validation is clean with 298 clubs", str(db.crests.validate(db).slice(0, 2)))


func _test_season() -> void:
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var c := CareerState.start(db, "fic_eng_elmford_city")
	_check(c != null and c.pyramids.has("england") and (c.pyramids["england"] as LeaguePyramid).divisions.size() == 3, "a career with a fictional club starts in a 3-division pyramid")
	var eng: LeaguePyramid = c.pyramids["england"]
	var sizes_before: Array = eng.divisions.map(func(d: Dictionary) -> int: return (d["team_ids"] as Array).size())
	var d3_before: Array = (eng.divisions[2]["team_ids"] as Array).duplicate()
	var t0 := Time.get_ticks_msec()
	for w in CareerState.WEEKS_PER_SEASON:
		c.advance_week()
	var res := c.end_season()
	print("[PERF] one full season of 15 divisions simulated in %d ms" % (Time.get_ticks_msec() - t0))
	var sum: Dictionary = res["leagues"]["england"]
	var d3_order: Array = sum["tables"]["eng_d3"]
	var promoted: Array = sum["promoted"]
	_check(d3_order.size() == 20 and d3_order.slice(0, 3).all(func(t: String) -> bool: return t in promoted), "the top 3 of the third division are promoted")
	var d2_order: Array = sum["tables"]["eng_d2"]
	_check(d2_order.slice(21).all(func(t: String) -> bool: return t in sum["relegated"]), "the bottom 3 of the second division go down")
	var sizes_after: Array = (c.pyramids["england"] as LeaguePyramid).divisions.map(func(d: Dictionary) -> int: return (d["team_ids"] as Array).size())
	_check(sizes_after == sizes_before, "division sizes are unchanged after promotion and relegation (%s)" % str(sizes_after))
	var d2_now: Array = ((c.pyramids["england"] as LeaguePyramid).divisions[1]["team_ids"] as Array)
	_check(d3_order[0] in d2_now and d3_order[0] in d3_before, "the third-division champion now plays in the second division")
	db.load_world("")
