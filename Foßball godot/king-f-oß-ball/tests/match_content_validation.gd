## Match content validation (UX phase 6): defensive wall at free kicks, the referee on the pitch,
## animated spectators that react to goals.
##   godot --headless --path . res://tests/match_content_validation.tscn
extends Node

var _passed := 0
var _failed := 0
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
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Match content validation ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	var m := _match()
	await _frames(3)
	await _test_wall(m)
	await _test_referee(m)
	await _test_crowd(m)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _match() -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 10
	setup.human_side = "none"
	setup.rng_seed = 4
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	return m


func _test_wall(m: MatchManager) -> void:
	var goal := PitchSpace.opponent_goal(m.frame_side("home"))
	var spot := Vector3(4.0, 0.3, goal.z - signf(goal.z) * 22.0)
	m.rules.restart_from(spot, "home", "free_kick")
	var wall: Array = m.rules.last_wall
	_check(wall.size() == 4, "a free kick 22 m out gets a 4-man wall", str(wall.size()))
	var ok := true
	var to_goal := Vector3(goal.x - spot.x, 0.0, goal.z - spot.z).normalized()
	for e in m.entries["away"]:
		if e["player_id"] in wall:
			var p := (e["node"] as Node3D).global_position
			var d := Vector2(p.x - spot.x, p.z - spot.z).length()
			var ahead := Vector3(p.x - spot.x, 0.0, p.z - spot.z).normalized().dot(to_goal)
			ok = ok and d >= MatchRules.WALL_DISTANCE - 0.05 and d <= MatchRules.WALL_DISTANCE + 1.5 and ahead > 0.9
	_check(ok, "the wall stands 9.15 m from the ball, between ball and goal")
	m.rules.restart_from(Vector3(0.0, 0.3, 0.0), "home", "free_kick")
	_check(m.rules.last_wall.is_empty(), "no wall for a free kick in midfield")
	m.rules.restart_from(spot, "home", "corner")
	_check(m.rules.last_wall.is_empty(), "no wall at corners")
	m.state.phase = MatchState.Phase.PLAYING


func _test_referee(m: MatchManager) -> void:
	var ref := m.referee
	_check(ref != null and ref.model != null, "the referee model is on the pitch")
	_check(ref.find_children("*", "CollisionObject3D", true, false).is_empty(), "the referee has no collision (can never block ball or players)")
	var w := MatchReferee.wanted_position(Vector3(30.0, 0.0, 50.0))
	_check(absf(w.x) <= PitchSpace.HALF_WIDTH and absf(w.z) <= PitchSpace.HALF_LENGTH, "the wanted spot stays inside the pitch", str(w))
	m.ball.reset_ball(Vector3(-20.0, 0.3, 30.0))
	var target := MatchReferee.wanted_position(m.ball.global_position)
	var before := ref.global_position.distance_to(target)
	await _frames(40)
	var after := ref.global_position.distance_to(MatchReferee.wanted_position(m.ball.global_position))
	_check(after < before - 3.0, "the referee follows play", "%.1f -> %.1f m" % [before, after])
	_check(ref.current_animation() in ["Run", "Walk"], "and runs / walks while doing so", ref.current_animation())
	ref.gesture("card")
	_check(ref.current_animation() == "ShowCard", "bookings: card gesture")


func _test_crowd(m: MatchManager) -> void:
	var c := m.stand_crowd
	_check(c != null and c.built and c.spectators > 500, "spectators fill the stands", str(c.spectators if c != null else -1))
	var bad: Array = []
	for i in mini(c.spectators, 200):
		var p := c.positions[i]
		if not ((absf(p.x) > StandCrowd.PITCH_KEEP_OUT.x - 0.3 or absf(p.z) > StandCrowd.PITCH_KEEP_OUT.y - 0.3) and p.y > 0.5):
			bad.append(p)
	_check(bad.is_empty(), "nobody stands on the pitch: every spectator is on the stand steps", str(bad.slice(0, 3)))
	m.crowd.mood = "calm"
	m.crowd.excitement = 0.0
	await _frames(2)
	var calm := c.excitement()
	m.state.goal("home", "")
	await _frames(3)
	_check(c.excitement() > calm + 0.3, "the crowd jumps after a home goal", "%.2f -> %.2f" % [calm, c.excitement()])
