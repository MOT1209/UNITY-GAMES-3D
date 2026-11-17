## Stadium arena (GLB) validation suite — runs headless:
##   godot --headless --path . res://tests/stadium_arena_validation.tscn
## Asserts: GLB + scene load, helper objects converted (collision bodies,
## goal triggers, spawn points), no helper mesh left visible, ground collision
## everywhere a player/ball can go, player stands on the arena, a ball shot
## into each goal fires `goal_entered` and is stopped by the net, the
## broadcast camera sees the centre spot, GameManager starts this scene.

extends Node

const SCENE := "res://scenes/stadium/stadium_arena.tscn"
const GLB := "res://assets/models/stadium/stadium.glb"

var _passed := 0
var _failed := 0
var _root: Node3D
var _arena: StadiumArena
var _goals: Array[StringName] = []


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Stadium arena validation ===")
	_check(load(GLB) != null, "GLB loads: %s" % GLB)
	var packed: PackedScene = load(SCENE)
	_check(packed != null, "Scene loads: %s" % SCENE)
	if packed == null:
		_finish()
		return
	_root = packed.instantiate()
	add_child(_root)
	await _physics_frames(3)
	_arena = _root.get_node("%Arena")
	_arena.goal_entered.connect(func(id: StringName, _b: Node3D) -> void: _goals.append(id))

	_test_structure()
	_test_ground_coverage()
	await _test_player_grounded()
	await _test_goal(&"N", -1.0)
	await _test_goal(&"S", 1.0)
	_test_broadcast_view()
	_check(GameManager.SCENE_STADIUM == SCENE, "GameManager.start_match opens the arena")
	_finish()


func _finish() -> void:
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _test_structure() -> void:
	_check(_arena.model_root != null, "Arena instanced the GLB model")
	var names := _arena.collision_bodies.map(func(b: StaticBody3D) -> String: return b.name)
	for expected: String in ["COL_Ground", "COL_Stands", "COL_Facade", "COL_AdBoards", "COL_Goal_N", "COL_Goal_S"]:
		_check(expected in names, "Collision body built: %s" % expected)
	_check(_arena.goal_areas.has(&"N") and _arena.goal_areas.has(&"S"), "Goal triggers N and S built")
	for id: StringName in [&"Kickoff", &"Home_Bench", &"Away_Bench", &"Tunnel"]:
		_check(_arena.spawn_points.has(id), "Spawn point: %s" % id)
	_check(_arena.get_spawn(&"Kickoff").origin.length() < 0.01, "Kickoff spawn at the centre spot")
	var leftovers := _arena.model_root.find_children("COL_*", "MeshInstance3D", true, false) \
			+ _arena.model_root.find_children("TRIGGER_*", "MeshInstance3D", true, false)
	_check(leftovers.all(func(n: Node) -> bool: return n.is_queued_for_deletion()),
			"No helper mesh left in the render")
	var visible_meshes := _arena.model_root.find_children("*", "MeshInstance3D", true, false)
	_check(visible_meshes.size() >= 15, "Visual meshes present (%d)" % visible_meshes.size())


func _ray_down(x: float, z: float) -> Dictionary:
	var space := _arena.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 5.0, z), Vector3(x, -5.0, z))
	q.exclude = [(_root.get_node("Player") as CollisionObject3D).get_rid()]
	return space.intersect_ray(q)


func _test_ground_coverage() -> void:
	# Pitch, run-off between touchline and stands (fell through in Phase 1),
	# corner of the pitch, and the outside plaza.
	for p: Vector2 in [Vector2(0, 0), Vector2(38.5, 0), Vector2(34, 52.5),
			Vector2(-36.0, 55.0), Vector2(110, 0)]:
		var hit := _ray_down(p.x, p.y)
		_check(not hit.is_empty() and absf(hit.position.y) < 0.05,
				"Ground collision at (%.1f, %.1f)" % [p.x, p.y],
				"no hit" if hit.is_empty() else "hit y=%.2f" % hit.position.y)


func _test_player_grounded() -> void:
	var player: CharacterBody3D = _root.get_node("Player")
	player.global_position = Vector3(0, 1.0, 10)
	await _physics_frames(90)
	_check(player.is_on_floor() and absf(player.global_position.y) < 0.1,
			"Player lands and stands on the arena floor",
			"y=%.3f floor=%s" % [player.global_position.y, player.is_on_floor()])


func _test_goal(id: StringName, dir: float) -> void:
	_goals.clear()
	var ball := RigidBody3D.new()
	ball.name = "TestBall_%s" % id
	ball.mass = 0.43
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.11
	cs.shape = sphere
	ball.add_child(cs)
	ball.continuous_cd = true
	_root.add_child(ball)
	ball.global_position = Vector3(1.0, 0.8, dir * 45.0)
	ball.linear_velocity = Vector3(0.0, 2.0, dir * 22.0)
	await _physics_frames(180)
	_check(id in _goals, "Shot into goal %s fires goal_entered(%s)" % [id, id], "got %s" % [_goals])
	var z := absf(ball.global_position.z)
	_check(z < 54.7 and z > 52.0, "Net stops the ball in goal %s" % id, "ball |z|=%.2f" % z)
	ball.queue_free()


func _test_broadcast_view() -> void:
	var cam: GameCamera = _root.get_node("%GameCamera")
	cam.set_mode(GameCamera.Mode.BROADCAST)
	var from := cam.config.broadcast_look_target + cam.config.broadcast_position_offset
	var space := _arena.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(0, 0.3, 0))
	var hit := space.intersect_ray(q)
	_check(hit.is_empty(), "Broadcast camera has a clear line of sight to the centre spot",
			"" if hit.is_empty() else "blocked by %s" % hit.collider.name)
