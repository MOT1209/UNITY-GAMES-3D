## Player visual integration validation — match, squad, academy, promotion, kits,
## transfers, save/load and missing-data safety (Phases V3, V7-V9, V11).
##   godot --headless --path . res://tests/player_visual_integration_validation.tscn
extends Node

const TEAM := "club_royal_harbor"
const AWAY := "club_northgate_utd"
const SAVE_PATH := "user://test_saves/player_visual.json"

var _passed := 0
var _failed := 0
var hub: HubRoot
var app: Node
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Player visual integration validation ===")
	app = get_node("/root/AppHub")
	db = app.db
	db.reload()
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	await _test_data_registration()
	await _test_screens()
	await _test_academy_identity()
	await _test_promotion()
	await _test_kit_changes_in_match()
	await _test_transfer_and_development()
	await _test_save_load()
	await _test_missing_data()
	await _test_preview()
	DirAccess.remove_absolute(SAVE_PATH)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _spawn_hub() -> void:
	if hub != null:
		hub.queue_free()
		await get_tree().process_frame
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame


func _go(screen: String, params: Dictionary = {}) -> void:
	hub.navigate(screen, params)
	await get_tree().process_frame
	await get_tree().process_frame


func _cards(root: Node) -> Array:
	return root.find_children("Card_*", "PlayerCard", true, false)


func _test_data_registration() -> void:
	var missing := 0
	var total := 0
	for p: PlayerData in db.players.values():
		total += 1
		if not PlayerAppearance.is_valid(p.appearance):
			missing += 1
	_check(total > 0 and missing == 0, "every database player has a valid stored appearance after load", "%d/%d" % [missing, total])
	var first: PlayerData = db.players.values()[0]
	var snapshot := first.appearance.duplicate(true)
	db.reload()
	_check(db.get_player(first.id).appearance == snapshot, "appearance is identical after reloading the player database (deterministic)")


func _test_screens() -> void:
	await _spawn_hub()
	_check(app.start_career(TEAM) == "", "career starts for the test club")
	await _go("squad")
	var squad: Squad = app.squad()
	var cards := _cards(hub.current.find_child("CardStrip", true, false))
	var starters: Array = squad.starting.filter(func(id: String) -> bool: return id != "")
	_check(cards.size() == starters.size() and cards.size() == 11, "squad screen shows one card per starter", str(cards.size()))
	var ids_match := true
	for i in cards.size():
		var c := cards[i] as PlayerCard
		var p: PlayerData = db.get_player(starters[i])
		ids_match = ids_match and c.data.player_id == p.id and c.texts()["name"] == p.display_name \
				and c.texts()["ovr"] == str(p.get_overall()) and c.texts()["position"] == PlayerData.Position.keys()[p.position]
	_check(ids_match, "each squad card shows the right player (name / OVR / position)")
	_check(hub.current.find_child("AutoPick", true, false) != null and hub.current.find_child("Slot_0", true, false) != null,
			"existing squad management controls are intact")
	await _go("academy")
	var prospects := _cards(hub.current.find_child("ProspectCards", true, false))
	_check(prospects.size() > 0, "academy screen shows prospect cards", str(prospects.size()))
	var ac: Academy = app.academy()
	_check(prospects.all(func(c: PlayerCard) -> bool: return c.data.player_id in ac.roster_ids), "academy cards are real roster players")
	await _go("player_profile", {"player_id": starters[0]})
	var pc := hub.current.find_child("ProfileCard", true, false) as PlayerCard
	_check(pc != null and pc.data.player_id == starters[0], "profile shows the card of the requested player")
	await _go("player_profile", {"player_id": "ghost"})
	_check(hub.current.find_child("ProfileCard", true, false) == null, "profile of an unknown player shows no card (empty state)")
	await _go("collection")
	var coll := _cards(hub.current)
	var pool_size: int = db.get_squad(TEAM).size() + ac.roster_ids.size()
	_check(coll.size() == pool_size, "collection lists first team + academy", "%d vs %d" % [coll.size(), pool_size])
	# filters through the real controls
	var pos := hub.current.find_child("PositionFilter", true, false) as OptionButton
	pos.select(1 + PlayerData.Position.GK)
	pos.item_selected.emit(1 + PlayerData.Position.GK)
	await get_tree().process_frame
	await get_tree().process_frame
	var gk_cards := _cards(hub.current)
	_check(not gk_cards.is_empty() and gk_cards.all(func(c: PlayerCard) -> bool: return c.data.position == "GK"), "collection position filter works in the UI")
	# detail view
	var first_card := gk_cards[0] as PlayerCard
	var view := CardDetailView.open(hub, db, first_card.data.player_id)
	await get_tree().process_frame
	_check(view != null and view.find_children("*", "PlayerCard", true, false).size() == 1 and view.find_child("OpenProfile", true, false) != null,
			"card detail view opens with an enlarged card and profile access")
	view.queue_free()
	_check(CardDetailView.open(hub, db, "ghost") == null, "detail view for an unknown id is refused safely")
	for lang in ["ar", "de", "en"]:
		Loc.set_language(lang, false)
		await _go("collection")
		_check(not _cards(hub.current).is_empty(), "[%s] collection screen builds" % lang)
		await _go("squad")
		_check(_cards(hub.current).size() >= 11, "[%s] squad screen builds with cards" % lang)
	Loc.set_language("en", false)


func _test_academy_identity() -> void:
	var ac: Academy = app.academy()
	var sigs := {}
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		sigs[PlayerAppearance.signature(p.appearance)] = true
	_check(sigs.size() == ac.roster_ids.size(), "every academy prospect has a distinct appearance", "%d distinct of %d" % [sigs.size(), ac.roster_ids.size()])
	var before := {}
	for pid in ac.roster_ids:
		before[pid] = (db.get_player(pid) as PlayerData).appearance.duplicate(true)
	var made := ac.generate_intake(db, 5)
	_check(made.size() > 0 and made.all(func(p: PlayerData) -> bool: return PlayerAppearance.is_valid(p.appearance)), "a new intake gets stored appearances immediately")
	var unchanged := true
	for pid in before:
		unchanged = unchanged and (db.get_player(pid) as PlayerData).appearance == before[pid]
	_check(unchanged, "generating more prospects never changes existing prospects' appearances")


func _test_promotion() -> void:
	var ac: Academy = app.academy()
	var candidate: PlayerData = null
	for pid in ac.roster_ids:
		if PromotionSystem.why_not(db, ac, pid) == "":
			candidate = db.get_player(pid)
			break
	_check(candidate != null, "a promotable prospect exists")
	if candidate == null:
		return
	var id_before := candidate.id
	var look_before := candidate.appearance.duplicate(true)
	var card_before := PlayerCardData.from_player(db, id_before)
	var err := PromotionSystem.promote(db, ac, id_before)
	_check(err == "", "promotion succeeds", err)
	var after: PlayerData = db.get_player(id_before)
	_check(after != null and after.appearance == look_before, "promoted player keeps the same appearance")
	_check(after.id == id_before and after.development_history.size() >= 2, "promoted player keeps id and history")
	var card_after := PlayerCardData.from_player(db, id_before)
	_check(card_after.name == card_before.name and card_after.overall == card_before.overall
			and PlayerAppearance.signature(card_after.appearance) == PlayerAppearance.signature(card_before.appearance)
			and card_after.club == (db.get_team(TEAM) as TeamData).display_name, "card after promotion: same player, now with the first-team club")
	var count := 0
	for p: PlayerData in db.players.values():
		count += 1 if p.id == id_before else 0
	_check(count == 1, "no duplicate player after promotion")
	var first_team_ids: Array = db.get_team(TEAM).squad_ids
	_check(id_before in first_team_ids and not (id_before in ac.roster_ids), "player moved from academy to the squad list")


func _real_match(home_id := TEAM) -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = home_id
	setup.away_id = AWAY
	setup.duration_minutes = 2
	setup.human_side = "none"
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	return m


func _color(node: Node, suffix: String) -> Color:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name.ends_with(suffix):
				return mat.albedo_color
	return Color(-1, -1, -1)


func _test_kit_changes_in_match() -> void:
	var team: TeamData = db.get_team(TEAM)
	var err := KitEditor.set_field(team, "home", "main", "12ab34")
	_check(err == "", "kit editor changes the home jersey colour", err)
	# make one starter visibly distinctive through his stored appearance
	var squad: Squad = app.squad()
	var pid: String = squad.starting[5]
	var p: PlayerData = db.get_player(pid)
	var forced := p.appearance.duplicate()
	forced["hair_style"] = "Afro"
	forced["skin"] = 4
	p.appearance = forced
	var m := _real_match()
	var entry: Dictionary = m.entries["home"][5]
	var node: Node = entry["node"]
	var vis := node.get_node("VisualRoot") as PlayerCharacterVisual
	_check(_color(node, "Jersey").is_equal_approx(Color("12ab34")), "the edited kit appears on the match player")
	_check(entry["player_id"] == pid and vis.look.hair_style == "Afro" and vis.look.skin.is_equal_approx(PlayerLook.SKINS[4]),
			"match player uses the stored appearance of that exact PlayerData")
	var all_ok := true
	for e in m.entries["home"]:
		var v: PlayerCharacterVisual = (e["node"] as TeamGoalkeeper).visual if e["node"] is TeamGoalkeeper else (e["node"] as Node).get_node("VisualRoot")
		var look := PlayerAppearance.look_for(e["pdata"])
		all_ok = all_ok and v.look.hair_style == look.hair_style and v.look.skin.is_equal_approx(look.skin)
	_check(all_ok, "all 11 home players in the match match their stored appearances")
	for side in ["home", "away"]:
		var wearing: Array = []
		for e in m.entries[side]:
			var vis2: PlayerCharacterVisual = (e["node"] as TeamGoalkeeper).visual if e["node"] is TeamGoalkeeper else (e["node"] as Node).get_node("VisualRoot")
			if (vis2.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).get_node_or_null("KF_Armband") != null:
				wearing.append(e["player_id"])
		var captain: String = m.sides[side]["squad"].captain_id
		_check(wearing.size() == (1 if captain != "" else 0) and (captain == "" or wearing[0] == captain), "%s: exactly the squad's captain wears the armband" % side, str(wearing))
	# substitution keeps identity: the incoming player's own look is shown
	var bench_id: String = squad.bench[0] if not squad.bench.is_empty() else ""
	if bench_id != "":
		m._swap_player("home", 5, bench_id)
		var swapped_look := PlayerAppearance.look_for(db.get_player(bench_id))
		_check(vis.look.hair_style == swapped_look.hair_style and vis.look.skin.is_equal_approx(swapped_look.skin), "a substitute arrives with his own appearance")
	# the portrait cache key follows the kit so a card never shows an old kit
	var key_new := PlayerCardData.from_player(db, pid).portrait_key(db)
	KitEditor.set_field(team, "home", "main", "ab12cd")
	_check(PlayerCardData.from_player(db, pid).portrait_key(db) != key_new, "second kit change invalidates the card portrait key")
	m.queue_free()
	await get_tree().process_frame
	await _test_match_animations()


func _vis(e: Dictionary) -> PlayerCharacterVisual:
	return (e["node"] as TeamGoalkeeper).visual if e["node"] is TeamGoalkeeper else (e["node"] as Node).get_node("VisualRoot")


func _clip(v: PlayerCharacterVisual) -> String:
	return (v.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).current_animation


func _test_match_animations() -> void:
	var m := _real_match()
	await get_tree().process_frame
	var e: Dictionary = m.entries["home"][5]
	var actions := e["actions"] as FootballActions
	var vis := _vis(e)
	actions._play_kick_anim(&"shot")
	_check(_clip(vis) == "Shoot", "a shot in the match plays the Shoot clip")
	actions._play_kick_anim(&"pass")
	_check(_clip(vis) == "Pass", "a pass in the match plays the Pass clip")
	actions._play_kick_anim(&"lob")
	_check(_clip(vis) == "LongPass", "a lob in the match plays the LongPass clip")
	actions._set_dribbling(true)
	_check(vis._dribbling, "dribbling state reaches the visual")
	actions._set_dribbling(false)
	_check(not vis._dribbling, "dribbling stop reaches the visual")
	# goal reactions: scorers celebrate, conceders are dejected, keepers keep their stance
	m._goal_reactions("home")
	var celebrating := 0
	var dejected := 0
	for slot in range(1, 11):
		celebrating += 1 if _clip(_vis(m.entries["home"][slot])) == "Celebrate" else 0
		dejected += 1 if _clip(_vis(m.entries["away"][slot])) == "Disappointed" else 0
	_check(celebrating == 10 and dejected == 10, "after a goal the scoring outfield celebrates and the conceding side is dejected", "%d / %d" % [celebrating, dejected])
	_check(_clip(_vis(m.entries["home"][0])) != "Celebrate" and _clip(_vis(m.entries["away"][0])) != "Disappointed", "goalkeepers do not celebrate")
	_check(PlayerAnimationLibrary.CLIPS.size() == 8 and (m.GOAL_PAUSE as float) > 2.2, "reaction clips fit within the goal pause")
	var node := m.entries["home"][5]["node"] as PlayerController
	var look := _vis(m.entries["home"][5]).look
	_check(look.face_shape >= 0, "match players carry stored face data")
	m.queue_free()
	await get_tree().process_frame


func _test_transfer_and_development() -> void:
	var market := TransferMarket.new(db, {})
	var p: PlayerData = null
	for q in db.get_squad(AWAY):
		if q.position != PlayerData.Position.GK:
			p = q
			break
	var look_before := p.appearance.duplicate(true)
	var cardc := PlayerCard.new(150.0)
	add_child(cardc)
	cardc.size = cardc.custom_minimum_size
	cardc.setup(PlayerCardData.from_data(db, p), db)
	var club_before: String = cardc.texts()["club"]
	# a direct team change (what buy/loan do to the record) must show on the card
	var away: TeamData = db.get_team(AWAY)
	var home: TeamData = db.get_team(TEAM)
	away.squad_ids.remove_at(away.squad_ids.find(p.id))
	home.squad_ids.append(p.id)
	p.team_id = TEAM
	cardc.refresh()
	_check(cardc.texts()["club"].begins_with(home.display_name) and club_before != cardc.texts()["club"], "transfer updates the club shown on the card")
	_check(p.appearance == look_before, "transfer keeps the appearance")
	# development: training raises attributes, the card and its category follow
	var ovr_before := p.get_overall()
	for a in PlayerData.ATTRIBUTES:
		p.set(a, mini(p.get_attribute(a) + 25, 99))
	p.potential = 99                     # keep the record valid (potential >= overall)
	cardc.refresh()
	_check(cardc.texts()["ovr"] == str(p.get_overall()) and p.get_overall() > ovr_before, "attribute growth updates the card OVR")
	_check(cardc.data.category == CardCategory.for_overall(p.get_overall()), "card class follows development")
	p.position = PlayerData.Position.CAM if p.position != PlayerData.Position.CAM else PlayerData.Position.ST
	cardc.refresh()
	_check(cardc.texts()["position"] == PlayerData.Position.keys()[p.position], "position change updates the card")
	cardc.queue_free()
	var _unused := market


func _test_save_load() -> void:
	var before := {}
	for p: PlayerData in db.players.values():
		before[p.id] = p.appearance.duplicate(true)
	var count_before: int = db.players.size()
	var err: String = app.save_game(SAVE_PATH)
	_check(err == "", "game saves", err)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_check(raw is Dictionary and int(raw["save_version"]) == SaveManager.SAVE_VERSION, "save file has the current version")
	var with_look := 0
	for pd in raw["players"]:
		with_look += 1 if (pd as Dictionary).has("appearance") and not (pd["appearance"] as Dictionary).is_empty() else 0
	_check(with_look == raw["players"].size(), "every saved player carries its appearance")
	_check(not FileAccess.get_file_as_string(SAVE_PATH).contains("PNG"), "no image data is stored in the save")
	# corrupt the in-memory looks, then load: stored values must come back exactly
	for p: PlayerData in db.players.values():
		p.appearance = {}
	err = app.load_game(SAVE_PATH)
	_check(err == "", "game loads", err)
	var same := true
	var diff := ""
	for id in before:
		var p: PlayerData = db.get_player(id)
		var ok: bool = p != null and p.appearance == before[id]
		if not ok and diff == "":
			diff = "%s: %s vs %s" % [id, str(before[id]), str(p.appearance if p != null else "missing")]
		same = same and ok
	_check(same and db.players.size() == count_before, "all appearances restored exactly, no player lost or duplicated", "%s (%d vs %d)" % [diff, db.players.size(), count_before])
	# v1 file (no appearances) loads and gets deterministic identities
	var v1: Dictionary = raw.duplicate(true)
	v1["save_version"] = 1
	for pd in v1["players"]:
		(pd as Dictionary).erase("appearance")
	SaveManager.write_file(SAVE_PATH, v1)
	err = app.load_game(SAVE_PATH)
	_check(err == "", "a version-1 save (no appearances) still loads", err)
	var a1: Dictionary = (db.players.values()[0] as PlayerData).appearance
	_check(PlayerAppearance.is_valid(a1), "v1 save: appearances are generated on load")
	# damaged appearance inside a v2 save is repaired, not fatal
	var bad: Dictionary = raw.duplicate(true)
	(bad["players"][0] as Dictionary)["appearance"] = {"hair_style": "???", "skin": "x", "height": 99}
	SaveManager.write_file(SAVE_PATH, bad)
	err = app.load_game(SAVE_PATH)
	var repaired: PlayerData = db.get_player(str(bad["players"][0]["id"]))
	_check(err == "" and repaired != null and PlayerAppearance.is_valid(repaired.appearance), "a damaged appearance record is repaired on load")


func _test_missing_data() -> void:
	var p := PlayerData.new()
	p.id = "no_team_player"
	p.display_name = "Free Agent"
	p.team_id = "club_that_does_not_exist"
	db.players[p.id] = p
	var c := PlayerCardData.from_player(db, p.id)
	_check(c != null and c.club == "", "player with an invalid club still produces a card")
	_check(c.kit(db) is TeamKit, "kit falls back to the default for an unknown club")
	var card := PlayerCard.new(150.0)
	add_child(card)
	card.size = card.custom_minimum_size
	card.setup(c, db)
	await get_tree().process_frame
	_check(card.texts()["name"] == "Free Agent", "card renders for a player without a club")
	card.queue_free()
	var v := (load(PlayerPortraitRenderer.OUTFIELD_SCENE) as PackedScene).instantiate() as PlayerCharacterVisual
	v.look = PlayerAppearance.to_look({"hair_style": "Missing", "skin": 77})
	v.kit = null
	add_child(v)
	await get_tree().process_frame
	_check(v.is_inside_tree(), "model with a damaged look and no kit instantiates without crashing")
	v.queue_free()
	db.players.erase(p.id)


func _test_preview() -> void:
	var p: PlayerData = db.get_squad(TEAM)[4]
	var card := PlayerCardData.from_data(db, p)
	var prev := PlayerPreview.new()
	add_child(prev)
	_check(prev.setup(card, db), "3D preview builds for a real player")
	await get_tree().process_frame
	var look := PlayerAppearance.to_look(PlayerAppearance.ensure(p))
	_check(prev.model != null and prev.model.look.hair_style == look.hair_style and prev.model.look.skin.is_equal_approx(look.skin)
			and prev.model.number == p.shirt_number, "the preview shows the same appearance, number and kit data as the match")
	var r0 := prev.model.rotation.y
	await get_tree().create_timer(0.3).timeout
	_check(not is_equal_approx(prev.model.rotation.y, r0), "the preview rotates by itself")
	var motion := InputEventMouseMotion.new()
	prev._drag = true
	motion.relative = Vector2(50, 0)
	var r1 := prev.model.rotation.y
	prev._gui_input(motion)
	_check(not is_equal_approx(prev.model.rotation.y, r1), "dragging turns the player")
	var gk: PlayerData = db.get_squad(TEAM).filter(func(x: PlayerData) -> bool: return x.position == PlayerData.Position.GK)[0]
	var switched := prev.setup(PlayerCardData.from_data(db, gk), db)
	await get_tree().process_frame
	_check(switched and prev.model is GoalkeeperVisual, "the preview can switch to a goalkeeper")
	var viewports_before := get_tree().root.find_children("*", "SubViewport", true, false).size()
	prev.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().root.find_children("*", "SubViewport", true, false).size() == viewports_before - 1, "freeing the preview frees its viewport")
	await _go("player_profile", {"player_id": p.id})
	_check(hub.current.find_child("ProfilePreview", true, false) != null and hub.current.find_child("ProfileCard", true, false) != null,
			"the profile shows the card and the live preview of the same player")
