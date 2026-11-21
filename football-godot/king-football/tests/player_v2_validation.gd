## Character model v2 (Blender pipeline) validation.
##   godot --headless --path . res://tests/player_v2_validation.tscn
## Checks the GLBs exported by tools/blender/build_player_v2.py against the game's model contract, measures foot
## sliding of the locomotion clips, and runs the model through the real match scenes (outfield + keeper).
extends Node

const OUTFIELD := "res://assets/models/characters/v2/player_v2.glb"
const KEEPER := "res://assets/models/characters/v2/goalkeeper_v2.glb"
const V1_OUTFIELD := "res://assets/models/characters/player.glb"
const V1_BONES := ["Root", "Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R",
		"LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]
const CLIPS := ["Idle", "Walk", "Jog", "Run", "Sprint", "Dribble", "TurnLeft", "TurnRight", "Accelerate", "Decelerate",
		"Pass", "Shoot", "LongPass", "Kick", "FirstTouch", "BallControl", "Tackle", "SlideTackle", "Jump", "Header"]
const KEEPER_CLIPS := ["Ready", "DiveLeft", "DiveRight", "CatchHigh", "CatchLow", "Throw"]
const MATERIALS := ["Skin", "Hair", "Jersey", "Trim", "Shorts", "Socks", "Boots", "Dark", "Number"]

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
	print("=== KING FOOTBALL — Player model v2 validation ===")
	for spec in [[OUTFIELD, "P_", false], [KEEPER, "G_", true]]:
		_test_contract(spec[0], spec[1], spec[2])
	_test_v1_joints_kept()
	await _test_foot_sliding()
	await _test_match_scenes()
	await _test_classic_unchanged()
	await _test_performance()
	PlayerCharacterVisual.model_override = ""
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _inst(path: String) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	add_child(n)
	return n


func _skeleton(n: Node) -> Skeleton3D:
	return n.find_child("Skeleton3D", true, false) as Skeleton3D


func _anim(n: Node) -> AnimationPlayer:
	return n.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _test_contract(path: String, prefix: String, keeper: bool) -> void:
	var tag := "keeper" if keeper else "outfield"
	_check(ResourceLoader.exists(path), "%s v2 GLB is imported" % tag)
	if not ResourceLoader.exists(path):
		return
	var n := _inst(path)
	var sk := _skeleton(n)
	_check(sk != null and sk.get_bone_count() == 50, "%s: one skeleton with 50 deform bones" % tag, str(sk.get_bone_count() if sk else -1))
	_check(_anim(n) != null, "%s: one AnimationPlayer" % tag)
	if sk == null or _anim(n) == null:          # every check below needs the rig: stop here, the failures are recorded
		n.queue_free()
		return
	var missing := V1_BONES.filter(func(b: String) -> bool: return sk.find_bone(b) < 0)
	_check(missing.is_empty(), "%s: every v1 bone name exists (face/hair builders, generated clips)" % tag, str(missing))
	var extra := ["Shoulder_L", "Shoulder_R", "Toes_L", "Toes_R", "Thumb2_L", "Index3_L", "Pinky3_R", "Middle3_R"]
	_check(extra.all(func(b: String) -> bool: return sk.find_bone(b) >= 0), "%s: shoulders, toes and finger bones" % tag)
	_check(sk.find_bone("IK_Foot_L") < 0 and sk.find_bone("Pole_Knee_L") < 0, "%s: IK control bones are not exported (baked)" % tag)
	_check(n.find_child("*_Rig", true, false) != null, "%s: armature node named *_Rig" % tag)
	var ap := _anim(n)
	var want: Array = CLIPS + (KEEPER_CLIPS if keeper else [])
	var absent := want.filter(func(c: String) -> bool: return not ap.has_animation(c))
	_check(absent.is_empty(), "%s: %d clips present" % [tag, want.size()], str(absent))
	var bad_tracks := []
	var bad_keys := 0
	var short := []
	for clip in want:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		if a.length < 0.3:
			short.append(clip)
		for t in a.get_track_count():
			var track_path := str(a.track_get_path(t))
			var bone := track_path.get_slice(":", 1)
			if bone != "" and sk.find_bone(bone) < 0 and bad_tracks.size() < 5:
				bad_tracks.append("%s/%s" % [clip, track_path])
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				for k in a.track_get_key_count(t):
					var q: Quaternion = a.track_get_key_value(t, k)
					if not q.is_finite() or absf(q.length() - 1.0) > 0.01:
						bad_keys += 1
	_check(short.is_empty(), "%s: every clip lasts at least 0.3 s" % tag, str(short))
	_check(bad_tracks.is_empty(), "%s: every animation track drives an existing bone" % tag, str(bad_tracks))
	_check(bad_keys == 0, "%s: all rotation keys finite and normalised" % tag, str(bad_keys))
	var found := {}
	var body: MeshInstance3D = null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).ends_with("Body"):
			body = m
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat != null:
				found[mat.resource_name.trim_prefix(prefix)] = true
	var need: Array = MATERIALS + (["Glove"] if keeper else [])
	_check(need.all(func(k: String) -> bool: return found.has(k)), "%s: kit materials by suffix" % tag, str(found.keys()))
	for style in ["Short", "Buzz", "Afro", "Long"]:
		_check(n.find_child("*_Hair_" + style, true, false) != null, "%s: hair mesh %s" % [tag, style])
	_check(n.find_child("*_Beard", true, false) != null, "%s: beard mesh" % tag)
	if body == null:
		_check(false, "%s: body mesh found" % tag)
		n.queue_free()
		return
	var tris := 0
	for s in body.mesh.get_surface_count():
		tris += (body.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check(tris > 3000 and tris < 9000, "%s: body is %d triangles (real-time budget 3k-9k)" % [tag, tris])
	var aabb := body.get_aabb()
	_check(absf(aabb.size.y - 1.8) < 0.08 and absf(aabb.position.y) < 0.02, "%s: about 1.8 m tall, feet on y = 0" % tag, str(aabb))
	# number patch: UVs span exactly 0..1 so the atlas offset picks one cell
	var num_ok := false
	for s in body.mesh.get_surface_count():
		var mat := body.mesh.surface_get_material(s)
		if mat != null and mat.resource_name.ends_with("Number"):
			var uv: PackedVector2Array = body.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
			var lo := Vector2(9, 9)
			var hi := Vector2(-9, -9)
			for u in uv:
				lo = lo.min(u)
				hi = hi.max(u)
			num_ok = lo.distance_to(Vector2.ZERO) < 0.01 and hi.distance_to(Vector2.ONE) < 0.01
	_check(num_ok, "%s: shirt-number patch UVs span 0..1" % tag)
	n.queue_free()


func _test_v1_joints_kept() -> void:
	var v1 := _inst(V1_OUTFIELD)
	var v2 := _inst(OUTFIELD)
	var s1 := _skeleton(v1)
	var s2 := _skeleton(v2)
	if s1 == null or s2 == null:
		_check(false, "v1 and v2 skeletons found for the joint comparison")
		v1.queue_free()
		v2.queue_free()
		return
	var worst := 0.0
	var worst_bone := ""
	for b in V1_BONES:
		var d := s1.get_bone_global_rest(s1.find_bone(b)).origin.distance_to(s2.get_bone_global_rest(s2.find_bone(b)).origin)
		if d > worst:
			worst = d
			worst_bone = b
	_check(worst < 0.01, "v1 joint positions kept (worst %s %.4f m): face/hair offsets stay valid" % [worst_bone, worst])
	v1.queue_free()
	v2.queue_free()


## In a locomotion clip the planted foot must move backwards at the clip's authored ground speed: then a player
## moving at that speed (playback rate = speed / clip speed) has a foot that stays put on the grass.
func _test_foot_sliding() -> void:
	var n := _inst(OUTFIELD)
	var sk := _skeleton(n)
	var ap := _anim(n)
	if sk == null or ap == null:
		_check(false, "rig found for the foot-sliding measurement")
		n.queue_free()
		return
	var speeds := {"Walk": 1.45, "Jog": 3.2, "Run": 5.0, "Sprint": 7.4, "Dribble": 4.0}
	for clip in speeds:
		var a := ap.get_animation(clip)
		var foot := sk.find_bone("Foot_L")
		var dt := 1.0 / 30.0
		var pts: Array[Vector3] = []
		ap.play(clip)
		var t := 0.0
		while t <= a.length + 1e-4:
			ap.seek(t, true)
			pts.append((sk.global_transform * sk.get_bone_global_pose(foot)).origin)
			t += dt
		ap.stop()
		var min_y := INF
		for p in pts:
			min_y = minf(min_y, p.y)
		var vel := []
		var lateral := 0.0
		for i in range(1, pts.size()):
			if pts[i].y < min_y + 0.012 and pts[i - 1].y < min_y + 0.012:
				vel.append((pts[i].z - pts[i - 1].z) / dt)          # model faces -Z: the planted foot moves to +Z
				lateral = maxf(lateral, absf(pts[i].x - pts[i - 1].x) / dt)
		var mean := 0.0
		for v in vel:
			mean += v
		mean /= maxf(1.0, vel.size())
		var authored: float = speeds[clip]
		var err := absf(mean - authored) / authored
		_check(vel.size() >= 2 and err < 0.12 and lateral < 0.35,
				"%s: planted foot moves back at %.2f m/s (authored %.2f, error %d %%, %d stance frames) - no sliding" % [
					clip, mean, authored, roundi(err * 100), vel.size()], "lateral %.2f m/s" % lateral)
	n.queue_free()
	await get_tree().process_frame


func _test_match_scenes() -> void:
	PlayerCharacterVisual.model_override = "v2"
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var vis := p.get_node("VisualRoot") as PlayerCharacterVisual
	var kit := TeamKit.new()
	kit.jersey = Color(0.8, 0.1, 0.1)
	vis.kit = kit
	vis.number = 23
	add_child(p)
	await get_tree().process_frame
	_check(vis.uses_v2 and _skeleton(vis).get_bone_count() == 50, "match player scene runs the v2 model when selected")
	_check(vis.walk_clip_speed == 1.45 and vis.run_clip_speed == 5.0, "v2 clip speeds adopted (no sliding at playback rate)")
	var ap := _anim(vis)
	_check(ap.has_animation("Celebrate") and ap.has_animation("ThrowIn") and ap.has_animation("PortraitIdle"),
			"generated reaction clips are built on the v2 rig too")
	_check(ap.get_animation("Run").loop_mode == Animation.LOOP_LINEAR and ap.get_animation("Tackle").loop_mode == Animation.LOOP_NONE
			and ap.get_animation("Shoot").loop_mode == Animation.LOOP_NONE, "loops: locomotion loops, one-shots don't")
	var red := false
	var number_atlas := false
	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			if mat.resource_name.ends_with("Jersey") and mat.albedo_color.is_equal_approx(Color(0.8, 0.1, 0.1)):
				red = true
			if mat.resource_name.ends_with("Number") and mat.albedo_texture != null and mat.uv1_offset.is_equal_approx(Vector3(0.3, 0.2, 0)):
				number_atlas = true
	_check(red, "team kit colours the v2 jersey")
	_check(number_atlas, "shirt number 23 maps to its atlas cell on the v2 shirt")
	vis.set_speed(1.2)
	_check(ap.current_animation == "Walk", "1.2 m/s -> Walk", ap.current_animation)
	vis.set_speed(2.8)
	_check(ap.current_animation == "Jog", "2.8 m/s -> Jog (v2)", ap.current_animation)
	vis.set_speed(5.2)
	_check(ap.current_animation == "Run" and absf(ap.speed_scale - 5.2 / 5.0) < 0.01, "5.2 m/s -> Run at x1.04",
			"%s %.2f" % [ap.current_animation, ap.speed_scale])
	vis.set_speed(7.6)
	_check(ap.current_animation == "Sprint", "7.6 m/s -> Sprint", ap.current_animation)
	vis.play_kick(&"shot")                  # gameplay kinds: pass / shot / lob
	_check(ap.current_animation == "Shoot" and vis.is_busy(), "shot plays the authored Shoot clip")
	await get_tree().create_timer(ap.get_animation("Shoot").length / maxf(ap.speed_scale, 0.1) + 0.5).timeout
	_check(not vis.is_busy() and ap.current_animation in ["Sprint", "Run", "Idle"], "after the shot the player returns to locomotion",
			ap.current_animation)
	p.queue_free()
	# goalkeeper in the real keeper scene
	var gk := (load("res://scenes/teams/team_goalkeeper.tscn") as PackedScene).instantiate()
	add_child(gk)
	await get_tree().process_frame
	var gv := gk.find_child("PlayerModel", true, false) as GoalkeeperVisual
	_check(gv != null and gv.uses_v2, "keeper scene runs the v2 keeper model")
	if gv != null:
		var gap := _anim(gv)
		_check(gap.current_animation == "Ready", "keeper idles in the Ready stance", gap.current_animation)
		gv.dive(-1)
		_check(gap.current_animation == "DiveLeft", "dive(-1) plays DiveLeft", gap.current_animation)
		var done := [false]
		gv.action_finished.connect(func() -> void: done[0] = true)
		await get_tree().create_timer(gap.get_animation("DiveLeft").length + 0.4).timeout
		_check(done[0], "the dive finishes and signals the keeper AI")
	gk.queue_free()
	await get_tree().process_frame


func _test_classic_unchanged() -> void:
	PlayerCharacterVisual.model_override = "classic"
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(p)
	await get_tree().process_frame
	var vis := p.get_node("VisualRoot") as PlayerCharacterVisual
	_check(not vis.uses_v2 and _skeleton(vis).get_bone_count() == 18 and vis.run_clip_speed == 6.5, "classic setting keeps the v1 model unchanged")
	p.queue_free()
	PlayerCharacterVisual.model_override = ""
	_check(GameSettings.default_of("graphics", "player_model") == "classic" and
			GameSettings._sanitize("graphics", "player_model", "nope") == "classic" and
			GameSettings._sanitize("graphics", "player_model", "v2") == "v2", "setting: default classic, v2 selectable, junk rejected")
	await get_tree().process_frame


## CPU cost of 22 animated players, v2 against classic. Wall time per frame is not usable (the game caps the frame
## rate, so a frame always lasts ~16.7 ms); the engine's own process-time monitor measures the work done per frame.
## Skinning runs on the GPU and is not measured headless.
func _test_performance() -> void:
	var classic := await _process_ms("classic")
	var v2 := await _process_ms("v2")
	_check(v2 < 8.0 and v2 <= classic * 2.5 + 1.0,
			"22 animated players: v2 %.2f ms vs classic %.2f ms of processing per frame (CPU)" % [v2, classic])


func _process_ms(model: String) -> float:
	PlayerCharacterVisual.model_override = model
	var nodes := []
	for i in 22:
		var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
		p.position = Vector3(i * 2.0, 0, 0)
		add_child(p)
		nodes.append(p)
	await get_tree().process_frame
	for i in 22:
		((nodes[i] as Node).get_node("VisualRoot") as PlayerCharacterVisual).set_speed([1.2, 2.8, 5.0, 7.5][i % 4])
	for f in 10:                                   # warm-up
		await get_tree().process_frame
	var total := 0.0
	var frames := 60
	for f in frames:
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS)       # already in ms in Godot 4.7
	for n in nodes:
		(n as Node).queue_free()
	PlayerCharacterVisual.model_override = ""
	await get_tree().process_frame
	return total / frames
