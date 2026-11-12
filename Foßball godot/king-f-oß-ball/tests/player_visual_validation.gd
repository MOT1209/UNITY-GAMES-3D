## Player visual validation — base character, skeleton, appearance, kits, animation,
## resilience and instancing cost (Phases V1-V4, V10, V11).
##   godot --headless --path . res://tests/player_visual_validation.tscn
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
	print("=== KING FOOTBALL — Player visual validation ===")
	await _test_base_character()
	_test_appearance_generation()
	_test_appearance_robustness()
	await _test_kits_and_look()
	await _test_animation()
	await _test_instancing()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _aabb_of(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _test_base_character() -> void:
	for spec in [["outfield", PlayerPortraitRenderer.OUTFIELD_SCENE, ["Idle", "Walk", "Run", "Kick"]],
			["goalkeeper", PlayerPortraitRenderer.KEEPER_SCENE,
			["Idle", "Walk", "Run", "Kick", "Ready", "DiveLeft", "DiveRight", "CatchHigh", "CatchLow", "Throw"]]]:
		var packed := load(spec[1]) as PackedScene
		_check(packed != null, "%s character scene loads" % spec[0])
		var node := packed.instantiate() as Node3D
		add_child(node)
		await get_tree().process_frame
		var skeletons: Array = node.find_children("*", "Skeleton3D", true, false)
		_check(skeletons.size() == 1, "%s has exactly one Skeleton3D" % spec[0])
		if skeletons.size() == 1:
			var sk := skeletons[0] as Skeleton3D
			_check(sk.get_bone_count() == 18, "%s skeleton has the shared 18-bone rig" % spec[0], str(sk.get_bone_count()))
		var aps: Array = node.find_children("*", "AnimationPlayer", true, false)
		_check(aps.size() == 1, "%s has one AnimationPlayer" % spec[0])
		if aps.size() == 1:
			var missing := (spec[2] as Array).filter(func(c: String) -> bool: return not (aps[0] as AnimationPlayer).has_animation(c))
			_check(missing.is_empty(), "%s has every required clip" % spec[0], str(missing))
		var box := _aabb_of(node)
		_check(box.size.y > 1.6 and box.size.y < 2.1, "%s has a realistic height (m)" % spec[0], "%.2f" % box.size.y)
		_check(box.position.y > -0.1 and box.position.y < 0.1, "%s stands on the origin (feet at y=0)" % spec[0], "%.2f" % box.position.y)
		node.queue_free()


func _test_appearance_generation() -> void:
	var a1 := PlayerAppearance.generate(12345)
	var a2 := PlayerAppearance.generate(12345)
	_check(a1 == a2, "same seed -> identical appearance")
	_check(PlayerAppearance.seed_for("yth_club_00001") == PlayerAppearance.seed_for("yth_club_00001"), "seed_for is stable")
	var signatures := {}
	for i in 200:
		signatures[PlayerAppearance.signature(PlayerAppearance.generate(PlayerAppearance.seed_for("p%d" % i)))] = true
	_check(signatures.size() >= 190, "200 players -> at least 190 distinct appearances", str(signatures.size()))
	var same_as_legacy := true
	for s in 300:
		var l1 := PlayerAppearance.to_look(PlayerAppearance.generate(s, s % 2 == 0))
		var l2 := PlayerLook.random(s, s % 2 == 0)
		if l1.skin != l2.skin or l1.hair != l2.hair or l1.boots != l2.boots or l1.hair_style != l2.hair_style \
				or l1.beard != l2.beard or not absf(l1.height - l2.height) < 0.0006 or not absf(l1.build - l2.build) < 0.0006:
			same_as_legacy = false
	_check(same_as_legacy, "stored appearance reproduces the pre-existing PlayerLook for 300 seeds (no visual change for old players)")
	var styles := {}
	var beards := 0
	for i in 400:
		var a := PlayerAppearance.generate(i * 7919)
		styles[a["hair_style"]] = true
		beards += 1 if a["beard"] else 0
	_check(styles.size() == PlayerLook.HAIR_STYLES.size(), "all hair styles incl. bald occur", str(styles.keys()))
	_check(beards > 0, "beards occur")
	# player-level: stability across ensure() calls and JSON round trip
	var p := PlayerData.new()
	p.id = "test_player_1"
	p.display_name = "Test"
	var first := PlayerAppearance.ensure(p).duplicate(true)
	var second := PlayerAppearance.ensure(p)
	_check(first == second, "ensure() does not change an existing appearance")
	var round_trip := PlayerData.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	_check(PlayerAppearance.signature(round_trip.appearance) == PlayerAppearance.signature(p.appearance),
			"appearance survives to_dict/JSON/from_dict")
	_check(PlayerAppearance.is_valid(round_trip.appearance), "round-tripped appearance is valid")
	var changed_generator := p.appearance.duplicate()
	changed_generator["skin"] = (int(p.appearance["skin"]) + 1) % PlayerLook.SKINS.size()
	p.appearance = changed_generator
	PlayerAppearance.ensure(p)
	_check(p.appearance["skin"] == changed_generator["skin"], "a stored (valid) value always wins over regeneration")


func _test_appearance_robustness() -> void:
	var junk := PlayerAppearance.sanitize({"skin": 99, "hair": -4, "boots": "x", "hair_style": "Mohawk9", "height_pm": 5000, "build_pm": -100, "beard": "yes"})
	_check(junk["skin"] == PlayerLook.SKINS.size() - 1 and junk["hair"] == 0 and junk["hair_style"] == "Short",
			"sanitize clamps indices and replaces unknown hair styles")
	_check(junk["height_pm"] == 1120 and junk["build_pm"] == 900, "sanitize clamps body proportions")
	var p := PlayerData.new()
	p.id = "broken"
	p.appearance = {"hair_style": "Nonsense", "skin": 3}
	var fixed := PlayerAppearance.ensure(p)
	_check(PlayerAppearance.is_valid(fixed) and fixed["skin"] == 3 and fixed["hair_style"] in PlayerLook.HAIR_STYLES,
			"damaged appearance is repaired and keeps its valid fields")
	_check(PlayerAppearance.ensure(null).is_empty(), "ensure(null) is safe")
	var look := PlayerAppearance.to_look({})
	_check(look != null and look.hair_style == "Short", "empty appearance dictionary still yields a look")
	# old (v1) save without appearance is migrated deterministically
	var legacy := {"save_version": 1, "teams": [], "players": [{"id": "old_1", "name": "Old", "position": "GK"}],
			"academies": {}, "scouting": {}, "training": {}, "squads": {}, "extras": {}}
	var m := SaveManager.migrate(legacy)
	_check(m["save_version"] == SaveManager.SAVE_VERSION and m["players"][0].has("appearance"), "v1 save migrates and gains appearances")
	var m2 := SaveManager.migrate(legacy)
	_check(m["players"][0]["appearance"] == m2["players"][0]["appearance"], "migration is deterministic")
	_check(not (legacy["players"][0] as Dictionary).has("appearance"), "migration does not mutate the source data")


func _dressed(kit: TeamKit, look: PlayerLook, number: int, keeper := false) -> PlayerCharacterVisual:
	var v := (load(PlayerPortraitRenderer.KEEPER_SCENE if keeper else PlayerPortraitRenderer.OUTFIELD_SCENE) as PackedScene).instantiate() as PlayerCharacterVisual
	v.kit = kit
	v.look = look
	v.number = number
	add_child(v)
	return v


func _surface_color(root: Node, suffix: String) -> Color:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name.ends_with(suffix):
				return mat.albedo_color
	return Color(-1, -1, -1)


func _test_kits_and_look() -> void:
	var red := TeamKit.new()
	red.jersey = Color("#cc1111")
	red.shorts = Color("#111111")
	var blue := TeamKit.new()
	blue.jersey = Color("#1133cc")
	var look := PlayerAppearance.to_look(PlayerAppearance.generate(77))
	var v1 := _dressed(red, look, 9)
	var v2 := _dressed(blue, look, 9)
	await get_tree().process_frame
	_check(_surface_color(v1, "Jersey").is_equal_approx(Color("#cc1111")), "kit colour is applied to the jersey")
	_check(_surface_color(v2, "Jersey").is_equal_approx(Color("#1133cc")), "a second kit does not leak into the first (own materials)")
	_check(_surface_color(v1, "Shorts").is_equal_approx(Color("#111111")), "shorts colour applied")
	_check(_surface_color(v1, "Skin").is_equal_approx(look.skin), "skin tone of the appearance wins over the kit default")
	var visible_hair := v1.find_children("*_Hair_*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return (m as MeshInstance3D).visible)
	_check(visible_hair.size() == (0 if look.hair_style == "Bald" else 1), "exactly the chosen hair mesh is visible", look.hair_style)
	var rig := v1.find_child("*_Rig", true, false) as Node3D
	_check(rig == null or (is_equal_approx(rig.scale.y, look.height) and is_equal_approx(rig.scale.x, look.build)), "height/build applied to the rig")
	var tall := PlayerLook.new()
	tall.height = 1.1
	var short := PlayerLook.new()
	short.height = 0.95
	var vt := _dressed(red, tall, 5)
	var vs := _dressed(red, short, 5)
	await get_tree().process_frame
	_check(_aabb_of(vt).size.y > _aabb_of(vs).size.y + 0.1, "height variation changes the silhouette")
	var gk_kit := TeamKit.new()
	gk_kit.jersey = Color("#22aa44")
	var gk := _dressed(gk_kit, look, 1, true)
	await get_tree().process_frame
	_check(_surface_color(gk, "Jersey").is_equal_approx(Color("#22aa44")), "goalkeeper kit applies to the goalkeeper model")
	_check(not gk.find_children("*", "MeshInstance3D", true, false).is_empty() and gk is GoalkeeperVisual, "goalkeeper model uses the goalkeeper visual")
	for n in [v1, v2, vt, vs, gk]:
		n.queue_free()


func _test_animation() -> void:
	var v := _dressed(TeamKit.new(), PlayerLook.new(), 10)
	await get_tree().process_frame
	var player := v.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_check(player.current_animation == "Idle", "starts in Idle")
	v.set_speed(1.5)
	_check(player.current_animation == "Walk", "slow speed -> Walk")
	v.set_speed(6.0)
	_check(player.current_animation == "Run", "fast speed -> Run")
	v.set_speed(0.0)
	_check(player.current_animation == "Idle", "stopped -> Idle")
	v.play_kick()
	v.set_speed(6.0)
	_check(player.current_animation == "Kick", "a kick is not interrupted by locomotion updates")
	_check(player.playback_default_blend_time >= 0.0 and v.anim_fade >= 0.1, "locomotion clips cross-fade (no snapping)")
	v.set_speed(5.0)  # still kicking, ignored
	v.queue_free()


func _test_instancing() -> void:
	var db: Node = get_node("/root/TeamDB")
	var team: TeamData = db.list_teams(TeamData.Category.CLUB)[0]
	var players: Array = db.get_squad(team.id)
	var t0 := Time.get_ticks_msec()
	var nodes: Array = []
	for i in 22:
		var p: PlayerData = players[i % players.size()]
		nodes.append(_dressed(TeamKit.new(), PlayerAppearance.look_for(p), p.shirt_number, p.position == PlayerData.Position.GK))
	await get_tree().process_frame
	var ms := Time.get_ticks_msec() - t0
	print("[INFO] 22 dressed players instanced in %d ms" % ms)
	_check(nodes.size() == 22 and ms < 5000, "22 players instance and dress quickly", "%d ms" % ms)
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for n in nodes:
		n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Performance.get_monitor(Performance.OBJECT_COUNT) < objects_before, "freeing 22 players releases their objects")
