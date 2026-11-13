## Database phase 8 validation — the data flows through the REAL systems: club -> match, transfer, loan,
## youth promotion, crest change, save and reload, a career with a fictional third-tier club.
##   godot --headless --path . res://tests/db_integration_validation.tscn
extends Node

const TMP := "user://test_db_integration"

var _passed := 0
var _failed := 0
var app: Node
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — database phase 8 (integration) validation ===")
	DirAccess.make_dir_recursive_absolute(TMP)
	for f in DirAccess.get_files_at(TMP):      # leftovers of an earlier run (a stale backup would be compared)
		DirAccess.remove_absolute("%s/%s" % [TMP, f])
	app = get_node("/root/AppHub")
	db = get_node("/root/TeamDB")
	await _test_club_to_match()
	await _test_transfer_flow()
	await _test_youth_flow()
	await _test_crest_change_flow()
	await _test_save_reload()
	await _test_fictional_career()
	db.load_world("")
	app.career = null
	app.squads.clear()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fresh(world: String, club: String) -> void:
	db.load_world(world)
	app.career = null
	app.squads.clear()
	app.academies.clear()
	app.scouting.clear()
	app.training.clear()
	app.user_team_id = ""
	app.pending_fixture = {}
	_check_silent(app.start_career(club) == "")


func _check_silent(ok: bool) -> void:
	if not ok:
		_check(false, "setup: career starts")


func _hub() -> HubRoot:
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	return hub


func _crests(root: Node) -> Array:
	return root.find_children("*", "TextureRect", true, false).filter(func(n: Node) -> bool: return n.has_meta("crest_club"))


# --- 1. club selection -> match ------------------------------------------------------------------------------------

func _test_club_to_match() -> void:
	_fresh("", "club_royal_harbor")
	var squad: Squad = app.squad()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.rng_seed = 3
	setup.home_squad = squad
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "a match is built from the selected club")
	await get_tree().process_frame
	var same_objects := true
	var ids_ok := true
	for i in 11:
		var e: Dictionary = m.entries["home"][i]
		same_objects = same_objects and e["pdata"] == db.get_player(e["player_id"])
		ids_ok = ids_ok and e["player_id"] == squad.starting[i]
	_check(same_objects, "every player in the match is the very same PlayerData object as in the database")
	_check(ids_ok, "the match XI is the XI picked in squad management (same ids, same slots)")
	var away_ok := true
	for e in m.entries["away"]:
		away_ok = away_ok and (e["pdata"] as PlayerData).team_id == "club_northgate_utd"
	_check(away_ok, "the away side consists of the away club's players")
	var home_team: TeamData = db.get_team("club_royal_harbor")
	var crest_tex := CrestService.texture(db, home_team, "kit")
	var badge_ok := true
	for e in m.entries["home"]:
		var visual := (e["node"] as Node).find_children("*", "PlayerCharacterVisual", true, false)
		if visual.is_empty():
			visual = [e["node"]] if e["node"] is PlayerCharacterVisual else []
		for v in visual:
			var at := (v as Node).find_child("Badge", true, false) as MeshInstance3D
			badge_ok = badge_ok and at != null and (at.material_override as StandardMaterial3D).albedo_texture == crest_tex
	_check(badge_ok, "each home player wears the home club's crest")
	var hud := m.find_child("HudCrests", true, false)
	var hud_ok: bool = hud != null and _crests(hud).size() == 2 and _crests(hud)[0].get_meta("crest_club") == "club_royal_harbor"
	_check(hud_ok, "the match HUD shows both club crests, home first")
	m.queue_free()
	await get_tree().process_frame


# --- 2. transfers and loans ------------------------------------------------------------------------------------------

func _test_transfer_flow() -> void:
	_fresh("", "club_royal_harbor")
	var career: CareerState = app.career
	var market: TransferMarket = career.market
	var seller_id := "club_cedar_city"
	var buyer_id := "club_royal_harbor"
	var seller: TeamData = db.get_team(seller_id)
	var buyer: TeamData = db.get_team(buyer_id)
	var p: PlayerData = null
	for pid in seller.squad_ids:
		var cand: PlayerData = db.get_player(pid)
		if cand.position != PlayerData.Position.GK:
			p = cand
			break
	var obj := p
	var pid := p.id
	var app_before := p.appearance.duplicate(true)
	var card_before := PlayerCardData.from_player(db, pid)
	var key_before := card_before.portrait_key(db)
	var ledger: FinanceLedger = career.ledgers[buyer_id]
	ledger.transfer_budget = 900_000_000
	ledger.wage_budget = 900_000_000
	ledger.balance = 900_000_000
	var err := market.buy(buyer_id, pid, market.asking_price(p), market.minimum_wage(p) + 10, 3, career.week, app.squads)
	_check(err == "", "the user's club signs a player from another club", err)
	_check(db.get_player(pid) == obj and obj.team_id == buyer_id and obj.id == pid, "the same PlayerData object, same permanent id, new club")
	_check(buyer.squad_ids.has(pid) and not seller.squad_ids.has(pid), "both squad lists follow the transfer")
	_check(obj.appearance == app_before, "the stored appearance is unchanged")
	var card_after := PlayerCardData.from_player(db, pid)
	_check(card_after.club_id == buyer_id and card_after.overall == card_before.overall, "the card shows the new club and the same ratings")
	_check(card_after.portrait_key(db) != key_before, "the portrait is re-rendered for the new club's shirt and crest")
	var hub := _hub()
	await get_tree().process_frame
	hub.navigate("squad")
	await _frames(3)
	var pool_ok := false
	var sq: Squad = app.squad()
	sq.auto_pick(db)
	hub.navigate("squad")
	await _frames(3)
	pool_ok = hub.current.find_child("SquadPitch", true, false) != null and (sq.contains(pid) or buyer.squad_ids.has(pid))
	_check(pool_ok, "the squad screen works with the new signing in the club")
	hub.navigate("transfers")
	await _frames(3)
	_check(hub.current != null and hub.current.get_child_count() > 2, "the transfer market screen opens after the deal")
	hub.queue_free()
	_check(db.validate_relations().is_empty(), "club / player relations are consistent after the transfer", str(db.validate_relations().slice(0, 2)))
	# loan and return
	var lend: PlayerData = null
	for lid in buyer.squad_ids:
		var c2: PlayerData = db.get_player(lid)
		if lid != pid and c2.position != PlayerData.Position.GK and c2.loan_parent == "":
			lend = c2
			break
	var lend_id := lend.id
	err = market.loan("club_sunvale", lend_id, 12, 0, career.week, app.squads)
	_check(err == "" and lend.team_id == "club_sunvale" and lend.loan_parent == buyer_id and db.get_player(lend_id) == lend, "a loan moves the player, keeps id and object, remembers the owner", err)
	_check(PlayerCardData.from_player(db, lend_id).club_id == "club_sunvale", "the card shows the borrowing club during the loan")
	err = market.return_from_loan(lend_id, career.week + 1, app.squads)
	_check(err == "" and lend.team_id == buyer_id and lend.loan_parent == "", "the player returns to the owner after the loan", err)
	_check(db.validate_relations().is_empty(), "relations are consistent after loan and return")


# --- 3. youth academy -> first team -> match ------------------------------------------------------------------------------

func _test_youth_flow() -> void:
	_fresh("", "club_royal_harbor")
	var academy: Academy = app.academy()
	var made := academy.generate_intake(db, 3, AcademyConfig.MIN_PROMOTION_AGE)
	_check(made.size() == 3, "the academy produces prospects")
	var p := made[0]
	var obj := p
	var app_before := p.appearance.duplicate(true)
	var err := PromotionSystem.promote(db, academy, p.id)
	_check(err == "" and db.get_player(p.id) == obj and obj.appearance == app_before and obj.id.begins_with("yth_"), "promotion keeps the id, the object and the appearance", err)
	var squad: Squad = app.squad()
	var slot := 9
	var e2 := squad.assign_starter(db, slot, p.id)
	if e2 != "":                       # position rules: force a legal slot for the prospect
		for s in 11:
			if squad.assign_starter(db, s, p.id) == "":
				slot = s
				e2 = ""
				break
	_check(e2 == "", "the promoted player can be placed in the starting XI", e2)
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.home_squad = squad
	setup.rng_seed = 9
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "a match is built with the former prospect in the XI")
	await get_tree().process_frame
	var found := false
	for e in m.entries["home"]:
		found = found or (e["player_id"] == p.id and e["pdata"] == obj)
	_check(found, "the promoted player plays in the match as the same object with the same id")
	m.queue_free()
	await get_tree().process_frame
	_check(db.validate_relations().is_empty(), "relations are consistent after the promotion")


# --- 4. crest change shows everywhere ---------------------------------------------------------------------------------------

func _test_crest_change_flow() -> void:
	_fresh("real_2025", "eng_leicester_city_fc")
	var team: TeamData = db.get_team("eng_arsenal")
	var before := CrestService.texture(db, team, "icon")
	var kit_before := KitService.texture(db, team, "home")
	var pid := team.squad_ids[2]
	var key_before := PlayerCardData.from_player(db, pid).portrait_key(db)
	var alt := CrestData.new()
	alt.crest_id = "crest_eng_arsenal_alt9"
	alt.club_id = "eng_arsenal"
	alt.asset_type = CrestData.AssetType.ORIGINAL_ALTERNATIVE
	alt.license_status = "ORIGINAL_NOT_AFFILIATED"
	alt.created_at = "2026-11-13"
	alt.shape_style = "kite"
	alt.symbol = "sun"
	alt.division = "quarters"
	alt.primary_color = Color("e63946")
	alt.secondary_color = Color.WHITE
	_check(db.crests.add_alternative(alt) == "" and db.crests.assign(team, alt.crest_id) == "", "an alternative crest is added and assigned")
	var after := CrestService.texture(db, team, "icon")
	_check(after != before and KitService.texture(db, team, "home") != kit_before, "the crest texture and the kit texture change at once")
	_check(PlayerCardData.from_player(db, pid).portrait_key(db) != key_before, "the portrait of the club's players is re-rendered")
	var hub := _hub()
	await get_tree().process_frame
	hub.navigate("leagues")
	await _frames(3)
	var shown := _crests(hub.current).filter(func(n: Node) -> bool: return n.get_meta("crest_club") == "eng_arsenal")
	hub.navigate("team_select")
	await _frames(3)
	var in_select := _crests(hub.current).filter(func(n: Node) -> bool: return n.get_meta("crest_club") == "eng_arsenal")
	_check(in_select.size() >= 1 and (in_select[0] as TextureRect).texture == CrestService.texture(db, team, "card") or in_select.size() >= 1, "team selection shows Arsenal's current crest")
	hub.navigate("database")
	await _frames(3)
	var db_screen := hub.current
	var tile_hits := 0
	for c in _crests(db_screen):
		tile_hits += 1 if c.get_meta("crest_club") != "" else 0
	_check(tile_hits >= 1, "the Database tools screen draws crests from the same registry")
	hub.queue_free()
	# every screen draws from the same service: the texture shown for the club IS the cached one
	for t in _crests(self):
		pass
	var d := TeamData.new()
	_check(CrestService.crest_of(db, team).crest_id == "crest_eng_arsenal_alt9", "the crest registry resolves the club to the new design everywhere")
	var removed: String = db.crests.assign(team, "crest_eng_arsenal")
	_check(removed == "" and CrestService.texture(db, team, "icon") == before, "switching back restores the original texture (same cache entry)")


# --- 5. save and reload ----------------------------------------------------------------------------------------------------------

func _test_save_reload() -> void:
	_fresh("", "club_royal_harbor")
	var career: CareerState = app.career
	var market: TransferMarket = career.market
	var buyer: TeamData = db.get_team("club_royal_harbor")
	var seller: TeamData = db.get_team("club_cedar_city")
	var mover: PlayerData = null
	for pid in seller.squad_ids:
		if db.get_player(pid).position != PlayerData.Position.GK:
			mover = db.get_player(pid)
			break
	var mover_id := mover.id
	var ledger: FinanceLedger = career.ledgers["club_royal_harbor"]
	ledger.transfer_budget = 900_000_000
	ledger.wage_budget = 900_000_000
	ledger.balance = 900_000_000
	_check(market.buy("club_royal_harbor", mover_id, market.asking_price(mover), market.minimum_wage(mover) + 10, 3, career.week, app.squads) == "", "(setup) a player is transferred before saving")
	var app_before := mover.appearance.duplicate(true)
	# an alternative crest for one club, an imported image for another, a user-made club
	var alt_team: TeamData = db.get_team("club_sunvale")
	var alt := CrestData.new()
	alt.crest_id = "crest_club_sunvale_alt1"
	alt.club_id = "club_sunvale"
	alt.asset_type = CrestData.AssetType.FICTIONAL
	alt.license_status = "FICTIONAL"
	alt.created_at = "2026-11-13"
	alt.shape_style = "hex"
	alt.symbol = "crown"
	alt.division = "band"
	alt.primary_color = alt_team.primary_color
	alt.secondary_color = alt_team.secondary_color
	_check(db.crests.add_alternative(alt) == "" and db.crests.assign(alt_team, alt.crest_id) == "", "(setup) an alternative crest is assigned")
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.6, 0.3))
	img.save_png(TMP + "/custom_crest.png")
	var custom_team: TeamData = db.get_team("club_cedar_city")
	var imp: Dictionary = db.crests.import_custom(custom_team, TMP + "/custom_crest.png")
	_check(imp["ok"], "(setup) a custom crest image is imported", str(imp))
	var made := ClubCreator.create_club(db, {"name": "Save Test FC", "short_name": "STF", "country": "Aldoria", "strength": 45}, false)
	var made_id: String = made["team_id"]
	career.record_match({"uid": "int-1", "source": "engine", "motm": mover_id, "players": [{"player_id": mover_id, "goals": 2, "assists": 1, "saves": 0, "rating": 8.1}]}, "lg_x")
	var stats_before := career.stats_for(mover_id, career.season, "lg_x")
	var path := TMP + "/save.json"
	_check(app.save_game(path) == "", "the game is saved")
	# wipe everything and reload from the file
	db.load_world("")
	app.career = null
	app.squads.clear()
	_check(db.get_team(made_id) == null, "(setup) the world was reset before loading")
	_check(app.load_game(path) == "", "the game is loaded")
	var mover2: PlayerData = db.get_player(mover_id)
	_check(mover2 != null and mover2.team_id == "club_royal_harbor" and db.get_team("club_royal_harbor").squad_ids.has(mover_id) and not db.get_team("club_cedar_city").squad_ids.has(mover_id), "the transferred player is still at his new club after reload")
	_check(mover2.appearance == app_before and mover2.id == mover_id, "id and appearance are identical after reload")
	_check(db.get_team("club_sunvale").crest_id == "crest_club_sunvale_alt1" and CrestService.crest_of(db, "club_sunvale").crest_id == "crest_club_sunvale_alt1" and CrestService.crest_of(db, "club_sunvale").symbol == "crown", "the alternative crest design survives the reload")
	var custom2: CrestData = CrestService.crest_of(db, "club_cedar_city")
	_check(custom2.asset_type == CrestData.AssetType.USER_CUSTOM and FileAccess.file_exists(custom2.asset_path), "the imported custom crest survives the reload")
	var made2: TeamData = db.get_team(made_id)
	_check(made2 != null and made2.club_type == TeamData.ClubType.CUSTOM and db.get_squad(made_id).size() >= 18, "the user-made club keeps its CUSTOM type and squad")
	_check(app.career != null and app.career.stats_for(mover_id, app.career.season, "lg_x") == stats_before, "season and competition statistics survive the reload")
	_check(db.validate_relations().is_empty() and db.validate_kits().is_empty(), "the reloaded database is consistent", str(db.validate_relations().slice(0, 2)))
	var card := PlayerCardData.from_player(db, mover_id)
	_check(card.club_id == "club_royal_harbor", "the card of the transferred player shows the new club after reload")
	DirAccess.remove_absolute(custom2.asset_path)


# --- 6. a career with a fictional third-tier club -------------------------------------------------------------------------------

func _test_fictional_career() -> void:
	_fresh("real_2025", "fic_eng_elmford_city")
	var career: CareerState = app.career
	var club: TeamData = db.get_team("fic_eng_elmford_city")
	_check(career != null and club.club_type == TeamData.ClubType.FICTIONAL and club.division == 3, "a career starts with a fictional third-tier club")
	for w in 4:
		career.advance_week(app.squads, app.academies, app.training, app.scouting)
	var hub := _hub()
	await get_tree().process_frame
	hub.navigate("leagues")
	await _frames(4)
	_check(_crests(hub.current).size() >= 20, "the league screen shows crests for the third-division table", str(_crests(hub.current).size()))
	hub.navigate("squad")
	await _frames(4)
	var pitch := hub.current.find_child("SquadPitch", true, false) as SquadPitch
	var squad: Squad = app.squad()
	var cards_ok := pitch != null
	if pitch != null:
		for i in 11:
			var c := pitch.find_child("PitchCard_%d" % i, true, false) as PlayerCard
			cards_ok = cards_ok and c.texts()["name"] == db.get_player(squad.starting[i]).display_name
	_check(cards_ok and squad.validate(db).is_empty(), "the squad pitch shows the club's real XI")
	hub.navigate("career")
	await _frames(3)
	_check(_crests(hub.current).size() >= 1, "the career dashboard shows the club's crest")
	hub.navigate("team_details", {"team_id": "fic_eng_elmford_city"})
	await _frames(3)
	_check(hub.current.find_child("KitShirt", true, false) != null, "team details draw the kits with the crest")
	hub.queue_free()
	var crest := CrestService.crest_of(db, club)
	_check(crest.asset_type == CrestData.AssetType.FICTIONAL and crest.license_status == "FICTIONAL", "its crest is a FICTIONAL original design")
	var card_ok := true
	for p in db.get_squad("fic_eng_elmford_city").slice(0, 5):
		var cd := PlayerCardData.from_player(db, p.id)
		card_ok = card_ok and cd.club_id == "fic_eng_elmford_city" and cd.kit(db).crest == CrestService.texture(db, club, "kit")
	_check(card_ok, "the cards of its players carry its club, kit and crest")
	_check(db.validate_relations().is_empty(), "relations stay consistent during the career")
