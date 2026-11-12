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
	await _test_generated_animations()
	await _test_faces()
	await _test_kit_patterns()
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


func _skeleton_of(n: Node) -> Skeleton3D:
	return n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _test_generated_animations() -> void:
	for keeper in [false, true]:
		var label := "goalkeeper" if keeper else "outfield"
		var v := _dressed(TeamKit.new(), PlayerLook.new(), 7, keeper)
		await get_tree().process_frame
		var ap := v.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var sk := _skeleton_of(v)
		var missing := PlayerAnimationLibrary.CLIPS.filter(func(c: String) -> bool: return not ap.has_animation(c))
		_check(missing.is_empty(), "%s: all generated clips installed" % label, str(missing))
		_check(PlayerAnimationLibrary.install(ap, sk).is_empty(), "%s: install() is idempotent" % label)
		var bad_paths := 0
		var bad_values := 0
		for c in PlayerAnimationLibrary.CLIPS:
			var a := ap.get_animation(c)
			for t in a.get_track_count():
				if sk.find_bone(String(a.track_get_path(t)).get_slice(":", 1)) < 0:
					bad_paths += 1
				for k in a.track_get_key_count(t):
					var val: Variant = a.track_get_key_value(t, k)
					if val is Quaternion and (not (val as Quaternion).is_finite() or absf((val as Quaternion).length() - 1.0) > 0.01):
						bad_values += 1
					if val is Vector3 and not (val as Vector3).is_finite():
						bad_values += 1
			_check(a.loop_mode == (Animation.LOOP_NONE if c in PlayerAnimationLibrary.ONE_SHOTS else Animation.LOOP_LINEAR), "%s: %s loop mode" % [label, c])
		_check(bad_paths == 0 and bad_values == 0, "%s: every track targets a real bone with finite, normalised keys" % label, "%d / %d" % [bad_paths, bad_values])
		_check(ap.get_animation("Sprint").length < ap.get_animation("Run").length, "%s: Sprint cadence is faster than Run" % label)
		_check(ap.get_animation("Pass").length < ap.get_animation("Kick").length, "%s: Pass is shorter than Kick" % label)
		_check(ap.get_animation("Celebrate").length < 2.5 and ap.get_animation("Disappointed").length < 2.5, "%s: reactions fit inside the 2.5 s goal pause" % label)
		# celebrate really raises the hips (a hop) and the arms
		var cel := ap.get_animation("Celebrate")
		var hips := cel.find_track(NodePath(String(cel.track_get_path(0)).get_slice(":", 0) + ":Hips"), Animation.TYPE_POSITION_3D)
		var top := 0.0
		for k in cel.track_get_key_count(hips):
			top = maxf(top, (cel.track_get_key_value(hips, k) as Vector3).y)
		_check(top > sk.get_bone_rest(sk.find_bone("Hips")).origin.y + 0.1, "%s: Celebrate contains a jump" % label)
		# kick kinds
		v.play_kick(&"pass")
		_check(ap.current_animation == "Pass", "%s: pass kick plays Pass" % label)
		v.play_kick(&"shot")
		_check(ap.current_animation == "Shoot", "%s: shot plays Shoot" % label)
		v.play_kick(&"lob")
		_check(ap.current_animation == "LongPass", "%s: lob plays LongPass" % label)
		v.play_kick()
		_check(ap.current_animation == "Kick", "%s: default kick unchanged" % label)
		v.queue_free()
	var v2 := _dressed(TeamKit.new(), PlayerLook.new(), 10)
	await get_tree().process_frame
	var ap2 := v2.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	v2.set_speed(9.0)
	_check(ap2.current_animation == "Sprint", "high speed -> Sprint")
	v2.set_speed(6.0)
	_check(ap2.current_animation == "Run", "run speed still -> Run (existing behaviour kept)")
	v2.set_dribbling(true)
	v2.set_speed(5.0)
	_check(ap2.current_animation == "Dribble", "ball at feet while running -> Dribble")
	v2.set_dribbling(false)
	v2.set_speed(0.0)
	_check(v2.play_reaction("Celebrate") and ap2.current_animation == "Celebrate" and v2.is_busy(), "celebration starts and blocks locomotion updates")
	v2.set_speed(6.0)
	_check(ap2.current_animation == "Celebrate", "locomotion does not interrupt a reaction")
	v2.set_speed(0.0)
	_check(not v2.play_reaction("Nope"), "unknown reaction is refused")
	v2.queue_free()
	var v3 := _dressed(TeamKit.new(), PlayerLook.new(), 11)
	await get_tree().process_frame
	var ap3 := v3.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	v3.set_speed(5.0)
	_check(not v3.play_reaction("FirstTouch"), "first touch is skipped while running (no frozen sprinter)")
	v3.set_speed(0.0)
	_check(v3.play_reaction("FirstTouch"), "first touch plays when standing")
	await get_tree().create_timer(ap3.get_animation("FirstTouch").length + 0.5).timeout
	_check(not v3.is_busy() and ap3.current_animation == "Idle", "after a one-shot the player returns to Idle")
	v3.queue_free()


func _test_faces() -> void:
	var c := FaceBuilder.counts()
	_check(c["face"] >= 5 and c["eyes"] >= 5 and c["brows"] >= 5 and c["nose"] >= 4 and c["mouth"] >= 5 and c["eye_color"] >= 5, "face variant tables are populated", str(c))
	var faces := {}
	for i in 200:
		var a := PlayerAppearance.generate(PlayerAppearance.seed_for("f%d" % i))
		faces["%d%d%d%d%d%d" % [a["face"], a["eyes"], a["brows"], a["nose"], a["mouth"], a["eye_color"]]] = true
	_check(faces.size() >= 150, "200 players -> at least 150 distinct faces", str(faces.size()))
	# v1 record (no face fields) upgrades without touching existing fields
	var v1 := PlayerAppearance.generate(4242)
	for k in PlayerAppearance.FACE_KEYS:
		v1.erase(k)
	v1["v"] = 1
	var up := PlayerAppearance.upgrade(v1)
	var same_body := true
	for k in v1:
		if k != "v" and up[k] != v1[k]:
			same_body = false
	_check(same_body and up["v"] == PlayerAppearance.VERSION and PlayerAppearance.is_valid(up), "v1 -> v2 upgrade keeps every existing field")
	_check(PlayerAppearance.upgrade(v1) == up, "face upgrade is deterministic")
	var pd := PlayerData.new()
	pd.id = "legacy_face"
	pd.appearance = v1.duplicate()
	var ensured := PlayerAppearance.ensure(pd)
	_check(PlayerAppearance.is_valid(ensured) and ensured["skin"] == v1["skin"] and ensured["hair_style"] == v1["hair_style"], "ensure() upgrades a stored v1 record in place")
	# rendering side
	for keeper in [false, true]:
		var label := "goalkeeper" if keeper else "outfield"
		var look := PlayerLook.new()
		look.face_shape = 1
		look.eyes = 2
		look.brows = 3
		look.nose = 1
		look.mouth = 3
		look.eye_color = 2
		var v := _dressed(TeamKit.new(), look, 9, keeper)
		await get_tree().process_frame
		var sk := _skeleton_of(v)
		var attach := sk.get_node_or_null(FaceBuilder.ATTACH_NAME)
		_check(attach != null and attach is BoneAttachment3D and attach.bone_name == "Head", "%s: face attached to the Head bone" % label)
		var face_mesh: MeshInstance3D = attach.get_node_or_null("Face") if attach != null else null
		_check(attach != null and attach.get_child_count() == 1 and face_mesh != null and face_mesh.mesh.get_surface_count() == 1
				and (face_mesh.mesh as ArrayMesh).surface_get_array_len(0) >= 8 * 24, "%s: eyes, brows, nose and mouth merged into ONE mesh" % label)
		var again := _dressed(TeamKit.new(), look, 9, keeper)
		await get_tree().process_frame
		var other: MeshInstance3D = _skeleton_of(again).get_node(FaceBuilder.ATTACH_NAME).get_node("Face")
		_check(other.mesh == face_mesh.mesh, "%s: identical faces share one cached mesh" % label)
		again.queue_free()
		_check(sk.get_bone_pose_scale(sk.find_bone("Head")).is_equal_approx(FaceBuilder.SHAPES[1]), "%s: head shape applied" % label)
		var hidden := false
		for mi in v.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for s in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s)
				if mat != null and mat.resource_name.ends_with("Dark"):
					var o := m.get_surface_override_material(s) as StandardMaterial3D
					hidden = o != null and o.albedo_color.a == 0.0
		_check(hidden, "%s: baked face features are hidden" % label)
		v.apply_look()      # re-applying must not stack faces
		_check(sk.get_children().filter(func(n: Node) -> bool: return n.name.begins_with(FaceBuilder.ATTACH_NAME)).size() <= 2, "%s: re-applying the look does not accumulate face nodes" % label)
		FaceBuilder.clear(v)
		await get_tree().process_frame
		_check(sk.get_node_or_null(FaceBuilder.ATTACH_NAME) == null and sk.get_bone_pose_scale(sk.find_bone("Head")).is_equal_approx(Vector3.ONE), "%s: clear() restores the original head" % label)
		v.queue_free()
	var plain := _dressed(TeamKit.new(), PlayerLook.new(), 9)
	await get_tree().process_frame
	_check(_skeleton_of(plain).get_node_or_null(FaceBuilder.ATTACH_NAME) == null, "a look without face data keeps the model's original face")
	plain.queue_free()
	var odd := PlayerLook.new()
	odd.face_shape = 99
	odd.eyes = -5
	odd.brows = 400
	odd.mouth = 77
	var vo := _dressed(TeamKit.new(), odd, 9)
	await get_tree().process_frame
	_check(vo.is_inside_tree(), "out-of-range face indices are clamped, not fatal")
	vo.queue_free()


func _jersey_material(root: Node) -> StandardMaterial3D:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name.ends_with("Jersey"):
				return mat
	return null


func _test_kit_patterns() -> void:
	var flat := _dressed(TeamKit.from_dict({"main": "c8102e", "secondary": "ffffff", "pattern": "solid"}), PlayerLook.new(), 7)
	await get_tree().process_frame
	var jm := _jersey_material(flat)
	_check(jm != null and jm.albedo_texture == null and not jm.uv1_triplanar and jm.albedo_color.is_equal_approx(Color("c8102e")), "solid kit: flat colour, no texture")
	for pat in ["stripes", "hoops", "halves", "sash", "checks"]:
		var k := TeamKit.from_dict({"main": "c8102e", "secondary": "ffffff", "pattern": pat})
		_check(k.pattern == pat, "pattern '%s' is read from the kit data" % pat)
		var v := _dressed(k, PlayerLook.new(), 7)
		await get_tree().process_frame
		var m := _jersey_material(v)
		var tex := m.albedo_texture as Texture2D if m != null else null
		_check(m != null and tex != null and m.uv1_triplanar, "pattern '%s' is rendered on the jersey (triplanar texture)" % pat)
		if tex != null:
			var img := tex.get_image()
			var colours := {}
			for y in range(0, KitPattern.SIZE, 4):
				for x in range(0, KitPattern.SIZE, 4):
					colours[img.get_pixel(x, y).to_html(false)] = true
			_check(colours.has("c8102e") and colours.has("ffffff") and colours.size() == 2, "pattern '%s' uses exactly the club's two colours" % pat, str(colours.keys()))
		v.queue_free()
	var a := KitPattern.texture("hoops", Color("c8102e"), Color.WHITE)
	_check(a == KitPattern.texture("hoops", Color("c8102e"), Color.WHITE) and a != KitPattern.texture("hoops", Color.BLACK, Color.WHITE), "pattern textures are cached per pattern and colour pair")
	_check(TeamKit.from_dict({"main": "c8102e", "pattern": "polkadot"}).pattern == "solid", "an unknown pattern falls back to solid")
	var cap := _dressed(TeamKit.new(), PlayerLook.new(), 9)
	await get_tree().process_frame
	var sk := _skeleton_of(cap)
	cap.set_captain(true)
	cap.set_captain(true)
	_check(sk.get_children().filter(func(n: Node) -> bool: return n.name == "KF_Armband").size() == 1, "the captain's armband is added once")
	cap.set_captain(false)
	await get_tree().process_frame
	_check(sk.get_node_or_null("KF_Armband") == null, "and removed again")
	flat.queue_free()
	cap.queue_free()
