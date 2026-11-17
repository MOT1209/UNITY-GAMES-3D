## Stadiums & match balls validation suite — runs headless:
##   godot --headless --path . res://tests/stadiums_validation.tscn
## Asserts for every StadiumCatalog stadium: the shell loads, replaces the base stands / roof / facade, keeps
## every gameplay helper (ground, goals + triggers, spawn points), the stands are grounded on collision the
## crowd can fill, and nothing solid stands between the broadcast camera and the pitch. Plus the catalogue
## rules (home stadium, fallbacks) and every BallCatalog ball style.

extends Node

const SCENE := "res://scenes/stadium/stadium_arena.tscn"
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"

var _passed := 0
var _failed := 0


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Stadiums & balls validation ===")
	for id in StadiumCatalog.ids():
		await _test_stadium(id)
	_test_catalog()
	await _test_balls()
	_test_setup_round_trip()
	await _test_match("old_fortress", "night")
	await _test_match("home", "gold")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_stadium(id: String) -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var arena := root.get_node("Arena") as StadiumArena
	var default_player := root.get_node_or_null("Player")
	if default_player != null:
		default_player.free()           # the match spawns its own players (MatchManager does the same)
	var applied := StadiumCatalog.apply_to(arena, id)
	_check(applied == id, "%s: catalogue applies the stadium" % id)
	add_child(root)
	for i in 3:
		await get_tree().physics_frame
	var shell := str(StadiumCatalog.entry(id)["shell"])
	var names: Array[String] = []
	for b in arena.collision_bodies:
		names.append(String(b.name))
	for expected: String in ["COL_Ground", "COL_AdBoards", "COL_Goal_N", "COL_Goal_S"]:
		_check(expected in names, "%s: keeps %s" % [id, expected])
	_check(arena.goal_areas.has(&"N") and arena.goal_areas.has(&"S"), "%s: both goal triggers" % id)
	_check(arena.spawn_points.has(&"Kickoff") and arena.spawn_points.has(&"Tunnel"), "%s: spawn points" % id)
	if shell != "":
		_check(arena.model_root.find_child("Shell", false, false) != null, "%s: shell instanced" % id)
		_check(arena.model_root.find_child("Stand_Upper", true, false) == null and arena.model_root.find_child("Facade_Roof", true, false) == null,
				"%s: base stands / roof removed" % id)
		_check("COL_Shell_Stands" in names and not ("COL_Stands" in names), "%s: shell stand collision replaces the base one" % id, str(names))
	var space := arena.get_world_3d().direct_space_state
	var crowd := StandCrowd.new()
	add_child(crowd)
	var n := crowd.build(space, 1.0, [Color.RED, Color.BLUE], 7)
	_check(n >= (150 if id == "riverside_park" else 800), "%s: the crowd finds the stands" % id, "%d spectators" % n)
	var outside := 0
	for p in crowd.positions:
		if absf(p.x) < 37.0 and absf(p.z) < 55.5:
			outside += 1
	_check(outside == 0, "%s: no spectator on the pitch" % id)
	crowd.queue_free()
	# Solid geometry between the broadcast camera (offset 30, 22 from the ball) and the play.
	var blocked := 0
	for bx in [-30.0, 0.0, 30.0]:
		for bz in [-50.0, 0.0, 50.0]:
			var cam := Vector3(30.0 + bx, 22.0, bz)
			var q := PhysicsRayQueryParameters3D.create(cam, Vector3(bx, 0.3, bz))
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				blocked += 1
				print("    %s: ray from %s blocked by %s at %s" % [id, cam, (hit["collider"] as Node).name, hit["position"]])
	_check(blocked == 0, "%s: nothing solid between the broadcast camera and the pitch" % id, "%d of 9 rays blocked" % blocked)
	_check(_visual_clear(arena, id), "%s: no stand / roof mesh above the camera's sightline on the camera side" % id)
	root.queue_free()
	await get_tree().process_frame


## Visual meshes have no collision: check vertex heights of the shell meshes on the camera side (+x) instead.
## For x in [37, 64] the sightline from (64, 22) down to the touchline is above y = 22 * (x - 34) / 30.
func _visual_clear(arena: StadiumArena, id: String) -> bool:
	var shell := arena.model_root.find_child("Shell", false, false)
	if shell == null:
		return true
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				if v.x > 37.0 and v.x < 64.0 and absf(v.z) < 52.5 and v.y > 22.0 * (v.x - 34.0) / 30.0 + 0.5 and v.y < 22.5:
					print("    %s: vertex %s in the sightline" % [id, v])
					return false
	return true


func _test_catalog() -> void:
	_check(StadiumCatalog.resolve("nowhere", null) == "arena", "unknown stadium falls back to the arena")
	_check(StadiumCatalog.resolve("desert_dome", null) == "desert_dome", "a catalogue id is used as is")
	var t := TeamData.new()
	t.id = "club_test_city"
	t.stadium_id = "std_club_test_city"
	var a := StadiumCatalog.for_team(t)
	_check(StadiumCatalog.has(a) and a == StadiumCatalog.for_team(t), "a club without a catalogue stadium always gets the same one", a)
	_check(StadiumCatalog.resolve("home", t) == a, "'home' resolves to the home club's stadium")
	t.stadium_id = "old_fortress"
	_check(StadiumCatalog.for_team(t) == "old_fortress", "a club's own catalogue stadium wins")
	var seen := {}
	for i in 40:
		var c := TeamData.new()
		c.id = "club_%d" % i
		seen[StadiumCatalog.for_team(c)] = true
	_check(seen.size() >= 3, "clubs are spread over the stadiums", str(seen.keys()))
	for id in StadiumCatalog.ids():
		_check(StadiumCatalog.display_name(id) != str(StadiumCatalog.entry(id)["name_key"]), "%s has a translated name" % id)


func _test_balls() -> void:
	for id in BallCatalog.ids():
		var ball := (load(BALL_SCENE) as PackedScene).instantiate()
		add_child(ball)
		await get_tree().process_frame
		_check(BallCatalog.apply_to(ball, id) == id, "ball %s applies" % id)
		var v := ball.get_node("BallVisual") as BallVisual
		var e := BallCatalog.entry(id)
		_check(v.base_color == e["base"] and is_equal_approx(v.pentagon_size_degrees, float(e["size"])), "ball %s: colours and panel size" % id)
		var mat := ((ball.get_node("BallVisual/BallMesh") as MeshInstance3D).mesh as PrimitiveMesh).material as StandardMaterial3D
		_check(mat != null and mat.albedo_texture != null and mat.emission_enabled == (float(e["glow"]) > 0.0), "ball %s: material rebuilt (glow only on the night ball)" % id)
		_check(BallCatalog.display_name(id) != str(e["name_key"]), "ball %s has a translated name" % id)
		ball.queue_free()
	_check(BallCatalog.apply_to(null, "nonsense") == "classic", "unknown ball falls back to the classic ball")


func _test_setup_round_trip() -> void:
	var s := MatchSetup.new()
	s.stadium_id = "home"
	s.ball_id = "night"
	var r := MatchSetup.from_dict(s.to_dict())
	_check(r.stadium_id == "home" and r.ball_id == "night", "stadium and ball survive the match save round trip")
	_check(MatchSetup.from_dict({}).ball_id == "classic", "old saves without a ball get the classic ball")


## A real match in a shell stadium with a non-default ball, and the "home" rule through MatchManager.
func _test_match(stadium: String, ball: String) -> void:
	var db := get_node("/root/TeamDB")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 5
	setup.stadium_id = stadium
	setup.ball_id = ball
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "a match in '%s' with the %s ball starts" % [stadium, ball])
	var want := StadiumCatalog.resolve(stadium, db.get_team(setup.home_id))
	_check(m.stadium_id == want, "the match plays in %s" % want, m.stadium_id)
	var arena := m.arena_root.get_node("Arena") as StadiumArena
	var has_shell := arena.model_root.find_child("Shell", false, false) != null
	_check(has_shell == (str(StadiumCatalog.entry(want)["shell"]) != ""), "the arena carries the stadium's shell")
	_check(m.ball_id == ball and (m.ball.get_node("BallVisual") as BallVisual).base_color == BallCatalog.entry(ball)["base"], "the match ball wears the %s style" % ball)
	for i in 20:
		await get_tree().physics_frame
	_check(m.stand_crowd != null and m.stand_crowd.built and m.stand_crowd.spectators > 0, "the crowd fills the stands of %s" % want,
			str(m.stand_crowd.spectators if m.stand_crowd != null else -1))
	m.queue_free()
	await get_tree().process_frame
