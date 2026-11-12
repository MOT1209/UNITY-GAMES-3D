## Database phase 5 validation — kits and visual identity: kit validation/repair, club colours kept,
## crest on the 3D shirt (outfield, goalkeeper, match scene), portrait cache key:
##   godot --headless --path . res://tests/db_kits_validation.tscn
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
	print("=== KING FOOTBALL — database phase 5 (kits) validation ===")
	_test_repair_rules()
	_test_loaded_worlds()
	_test_user_choices()
	_test_team_kit()
	_test_3d_shirt()
	_test_portrait_key()
	await _test_match_scene()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db(world: String) -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.load_world(world)
	return db


func _team(home: String, away: String, gk: String, number := "ffffff") -> TeamData:
	var t := TeamData.new()
	t.id = "k_club"
	t.display_name = "K"
	t.short_name = "K"
	t.country = "England"
	var mk := func(main: String, num: String) -> Dictionary:
		return {"main": main, "secondary": "000000", "accent": "ffffff", "shorts": "000000", "socks": main, "number": num, "pattern": "solid"}
	t.kits = {"home": mk.call(home, number), "away": mk.call(away, number), "goalkeeper": mk.call(gk, number)}
	return t


func _test_repair_rules() -> void:
	var ok := _team("c8102e", "c8102e", "2ecc71")
	ok.kits["home"]["secondary"] = "ffffff"
	_check(KitEditor.problems(ok).size() >= 1, "identical home and away kits are a problem")
	var fixes := KitEditor.repair(ok)
	_check(not fixes.is_empty() and KitEditor.problems(ok).is_empty(), "repair removes every problem", str(KitEditor.problems(ok)))
	_check(not KitEditor.kits_clash(ok.kits["home"], ok.kits["away"]), "the repaired away kit differs from the home kit")
	_check(ok.kits["home"]["main"] == "c8102e", "the club's home colour is never touched")
	var green := _team("2ecc71", "ffffff", "2ecc71")
	KitEditor.repair(green)
	_check(not KitEditor.kits_clash(green.kits["home"], green.kits["goalkeeper"]), "a goalkeeper kit that matches the home kit is replaced")
	_check(green.kits["goalkeeper"]["main"] != "2ecc71", "goalkeeper main colour changed")
	var white := _team("ffffff", "101010", "f1c40f", "ffffff")
	_check(not KitEditor.problems(white).is_empty(), "a white number on a white shirt is a problem")
	KitEditor.repair(white)
	_check(CrestRenderer.contrast(Color.from_string(white.kits["home"]["number"], Color.WHITE), Color.WHITE) >= 3.0, "the number colour is changed to be readable")
	var fine := _team("c8102e", "ffffff", "f1c40f", "ffffff")
	fine.kits["away"]["number"] = "000000"
	fine.kits["goalkeeper"]["number"] = "000000"
	var before := fine.kits.duplicate(true)
	_check(KitEditor.problems(fine).is_empty() and KitEditor.repair(fine).is_empty() and fine.kits == before, "a good kit set is left exactly as it is")
	_check(KitEditor.readable_on(Color.BLACK) == Color.WHITE and KitEditor.readable_on(Color.WHITE) != Color.WHITE, "readable_on picks white on dark and dark on white")


func _test_loaded_worlds() -> void:
	for world in ["", "real_2025"]:
		var db := _new_db(world)
		_check(db.validate_kits().is_empty(), "[%s] every club has valid, distinguishable kits after loading" % ("default" if world == "" else world), str(db.validate_kits().slice(0, 3)))
	var db := _new_db("real_2025")
	_check(not db.kit_repairs.is_empty(), "the real pack needed kit repairs (%d clubs), reported in kit_repairs" % db.kit_repairs.size())
	var own := 0
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var main := Color.from_string(str(t.kits["home"]["main"]), Color.WHITE)
		own += 1 if main.is_equal_approx(t.primary_color) or main.is_equal_approx(t.secondary_color) else 0
	_check(own == 198, "every home kit keeps the club's own colours (no brand colour forced): %d/198" % own, str(own))
	var gold := 0
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		gold += 1 if Color.from_string(str(t.kits["home"]["main"]), Color.WHITE).is_equal_approx(UIKit.GOLD) else 0
	_check(gold == 0, "no club wears the game's UI gold as its shirt colour", str(gold))
	var unreadable := 0
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		for slot in t.kits:
			var k: Dictionary = t.kits[slot]
			unreadable += 1 if CrestRenderer.contrast(Color.from_string(str(k["number"]), Color.WHITE), Color.from_string(str(k["main"]), Color.WHITE)) < 3.0 else 0
	_check(unreadable == 0, "every shirt number is readable on its shirt", str(unreadable))


func _test_user_choices() -> void:
	# a player's own kit choice is not overridden when a save is restored
	var db := _new_db("")
	var t: TeamData = db.get_team("club_sunvale")
	KitEditor.set_field(t, "away", "main", t.kits["home"]["main"])
	var snap := SaveManager.capture(db)
	var db2 := _new_db("")
	var res := SaveManager.restore(db2, snap)
	_check(res["ok"] and db2.get_team("club_sunvale").kits["away"]["main"] == t.kits["home"]["main"], "restoring a save keeps the player's own (even clashing) kit choice")


func _test_team_kit() -> void:
	var db := _new_db("real_2025")
	var ars: TeamData = db.get_team("eng_arsenal")
	var k := TeamKit.for_team(db, ars, "home")
	_check(k.crest != null and k.crest == CrestService.texture(db, ars, "kit"), "TeamKit.for_team carries the club's crest texture")
	_check(k.jersey.is_equal_approx(Color.from_string(str(ars.kits["home"]["main"]), Color.WHITE)), "and the club's own shirt colour")
	_check(TeamKit.from_dict({}).crest == null, "a plain kit has no crest")
	var nat := _new_db("")
	_check(TeamKit.for_team(nat, nat.get_team("nat_aldoria"), "home").crest == null, "a national team shirt has no club crest")


func _dress(kit: TeamKit, keeper: bool) -> PlayerCharacterVisual:
	var path := PlayerPortraitRenderer.KEEPER_SCENE if keeper else PlayerPortraitRenderer.OUTFIELD_SCENE
	var v := (load(path) as PackedScene).instantiate() as PlayerCharacterVisual
	v.kit = kit
	add_child(v)
	v.apply_kit()
	return v


func _badge(v: Node) -> MeshInstance3D:
	var sk := v.find_child("Skeleton3D", true, false) as Skeleton3D
	var at := sk.get_node_or_null("KF_Crest")
	return at.get_node_or_null("Badge") as MeshInstance3D if at != null else null


func _test_3d_shirt() -> void:
	var db := _new_db("real_2025")
	var kit := TeamKit.for_team(db, db.get_team("eng_arsenal"), "home")
	var v := _dress(kit, false)
	var b := _badge(v)
	_check(b != null, "the outfield player shows a crest badge on the shirt")
	_check(b != null and (b.material_override as StandardMaterial3D).albedo_texture == kit.crest, "the badge shows this club's crest")
	var at := v.find_child("KF_Crest", true, false) as BoneAttachment3D
	_check(at != null and at.bone_name == PlayerCharacterVisual.CREST_BONE, "the badge is attached to the chest bone (follows the animation)")
	_check(b != null and b.position == PlayerCharacterVisual.CREST_OFFSET and b.position.x < 0.0, "on the wearer's left chest")
	v.apply_kit()
	_check(v.find_children("KF_Crest", "BoneAttachment3D", true, false).size() == 1, "applying the kit twice keeps exactly one badge")
	v.kit = TeamKit.new()
	v.apply_kit()
	_check(_badge(v) == null, "a kit without crest removes the badge")
	var keeper := _dress(TeamKit.for_team(db, db.get_team("eng_arsenal"), "goalkeeper", Color(0.1, 0.75, 0.3)), true)
	_check(_badge(keeper) != null, "the goalkeeper wears the crest too")
	var other := _dress(TeamKit.for_team(db, db.get_team("eng_chelsea_fc"), "home"), false)
	_check((_badge(other).material_override as StandardMaterial3D).albedo_texture != (b.material_override as StandardMaterial3D).albedo_texture if b != null else false, "two clubs show different badges")
	for n in [v, keeper, other]:
		n.queue_free()


func _test_portrait_key() -> void:
	var db := _new_db("real_2025")
	var team: TeamData = db.get_team("eng_arsenal")
	var pid := team.squad_ids[5]
	var key := PlayerCardData.from_player(db, pid).portrait_key(db)
	_check(key == PlayerCardData.from_player(db, pid).portrait_key(db), "the portrait cache key is stable")
	var alt := CrestData.new()
	alt.crest_id = "crest_eng_arsenal_alt"
	alt.club_id = "eng_arsenal"
	alt.asset_type = CrestData.AssetType.ORIGINAL_ALTERNATIVE
	alt.license_status = "ORIGINAL_NOT_AFFILIATED"
	alt.created_at = "2026-11-12"
	alt.shape_style = "hex"
	alt.symbol = "sun"
	alt.division = "band"
	alt.primary_color = Color.RED
	alt.secondary_color = Color.WHITE
	db.crests.add_alternative(alt)
	db.crests.assign(team, alt.crest_id)
	_check(PlayerCardData.from_player(db, pid).portrait_key(db) != key, "a changed crest changes the portrait key (no stale shirt badge)")


func _test_match_scene() -> void:
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 5
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	_check(err == "", "a match builds", err)
	await get_tree().process_frame
	var visuals := m.find_children("*", "PlayerCharacterVisual", true, false)
	var with_badge := 0
	for v in visuals:
		with_badge += 1 if _badge(v) != null else 0
	_check(visuals.size() >= 22 and with_badge == visuals.size(), "every player in the match (%d) wears the club crest" % visuals.size(), "%d/%d" % [with_badge, visuals.size()])
	var home_tex: Texture2D = CrestService.texture(db, "club_royal_harbor", "kit")
	var seen_home := false
	for v in visuals:
		var b := _badge(v)
		seen_home = seen_home or (b != null and (b.material_override as StandardMaterial3D).albedo_texture == home_tex)
	_check(seen_home, "the home side wears the home club's crest")
	m.queue_free()
	await get_tree().process_frame
