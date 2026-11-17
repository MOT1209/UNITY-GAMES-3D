## Phase 3 validation suite — runs headless:
##   godot --headless --path . res://tests/phase3_validation.tscn
## Asserts: ball scripts/scenes load, scene structure, collision layers,
## gravity/bounce/rolling/friction/settle behaviour, kick/impulse/force APIs,
## speed ceiling, reset/stop, player-ball collisions (no pass-through, no
## overlap, no teleport), CCD/no-tunnelling, proximity detector + signals,
## debug tools, and that Phase 1/2 still function on top.

extends Node

const TICKS_PER_SECOND := 60.0
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"
const BALL_SCRIPTS: Array[String] = [
	"res://scripts/ball/ball_controller.gd",
	"res://scripts/ball/ball_config.gd",
	"res://scripts/ball/ball_visual.gd",
	"res://scripts/ball/ball_debug.gd",
	"res://scripts/ball/ball_proximity_detector.gd",
	"res://scripts/development/ball_physics_test.gd",
]

var _passed := 0
var _failed := 0
var _env: Node3D
var _ball: BallController
var _player: PlayerController
var _kicked_speeds: Array[float] = []
var _reset_positions: Array[Vector3] = []
var _detector_ball: Node3D = null
var _detector_lost: int = 0
var _detector_available: Array[bool] = []


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase 3 validation ===")
	_test_assets()
	await _test_ball_scene_structure()
	await _test_gravity_and_rest()
	await _test_bounce_decay()
	await _test_rolling_and_friction()
	await _test_kick_api()
	await _test_impulse_and_force_api()
	await _test_reset_and_stop()
	await _test_player_interaction()
	await _test_no_tunnelling()
	await _test_proximity_detector()
	await _test_debug_tools()
	await _test_integration()

	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _await_ticks(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


# --- Ground/env helpers ------------------------------------------------------

## Fresh ground plate (StaticBody3D layer 1, top face at y = 0) in a new env.
func _spawn_env() -> void:
	_release_all()
	if _env != null:
		_env.free()
	_env = Node3D.new()
	add_child(_env)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	_env.add_child(ground)


func _spawn_ball(at: Vector3) -> BallController:
	var ball: BallController = (load(BALL_SCENE) as PackedScene).instantiate()
	ball.position = at
	_env.add_child(ball)
	ball.kicked.connect(func(speed: float) -> void: _kicked_speeds.append(speed))
	ball.ball_reset.connect(func(pos: Vector3) -> void: _reset_positions.append(pos))
	return ball


func _spawn_player(at: Vector3) -> PlayerController:
	var player: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	player.position = at
	_env.add_child(player)
	await get_tree().physics_frame
	return player


func _release_all() -> void:
	for action: String in ["move_forward", "move_backward", "move_left",
			"move_right", "sprint"]:
		Input.action_release(action)


func _planar_speed_of(node: Node3D) -> float:
	var v: Vector3 = node.linear_velocity if node is RigidBody3D \
			else (node as PlayerController).velocity
	return Vector3(v.x, 0.0, v.z).length()


func _min_planar_distance_tracked(a: Node3D, b: Node3D, max_ticks: int) -> float:
	var minimum := INF
	for i in max_ticks:
		await get_tree().physics_frame
		var offset := b.global_position - a.global_position
		minimum = minf(minimum, Vector3(offset.x, 0.0, offset.z).length())
	return minimum


# --- 1. Static assets ---------------------------------------------------------

func _test_assets() -> void:
	for path: String in BALL_SCRIPTS:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "Script parses: %s" % path)
	_check(load(BALL_SCENE) != null, "Scene loads: %s" % BALL_SCENE)
	_check(load("res://scenes/development/ball_physics_test.tscn") != null,
			"Scene loads: ball physics test scene")
	_check(load("res://resources/configurations/ball_config.tres") is BallConfig,
			"BallConfig resource loads")
	_check(load("res://scenes/environment/goal.tscn") != null,
			"Phase 1 goal scene still loads")
	# InputMap untouched for Phase 4.
	for action: String in ["pass", "shoot", "lob_pass", "dribble", "tackle"]:
		_check(InputMap.has_action(action), "InputMap: %s untouched for Phase 4" % action)


# --- 2. Ball scene structure ---------------------------------------------------

func _test_ball_scene_structure() -> void:
	var packed: PackedScene = load(BALL_SCENE)
	var ball: BallController = packed.instantiate()
	_check(ball is BallController and ball is RigidBody3D,
			"Ball scene: root is BallController (RigidBody3D)")
	ball.free()

	# Full in-tree instance for runtime checks.
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.5, 20.0))
	await _await_ticks(3)
	_check(_ball.is_in_group("football_ball"), "Ball: registered in group 'football_ball'")

	var shape_node: CollisionShape3D = _ball.get_node("CollisionShape3D")
	_check(shape_node != null and shape_node.shape is SphereShape3D,
			"Ball scene: spherical collision shape")
	if shape_node != null:
		_check(absf((shape_node.shape as SphereShape3D).radius - 0.11) < 0.005,
				"Ball: radius matches config (≈0.11 m)",
				"radius=%.4f" % (shape_node.shape as SphereShape3D).radius)

	_check(_ball.collision_layer == 4, "Ball: collision layer 3 (value 4)")
	_check(_ball.collision_mask == 5, "Ball: mask = World(1)+Ball(4) = 5")
	_check(_ball.continuous_cd, "Ball: continuous collision detection enabled")
	_check(_ball.physics_material_override != null
			and _ball.physics_material_override.friction > 0.0
			and _ball.physics_material_override.bounce > 0.0,
			"Ball: physics material (friction + bounce) applied")
	_check(_ball.mass > 0.0 and absf(_ball.mass - 0.43) < 0.01,
			"Ball: mass matches config (≈0.43 kg)", "mass=%.3f" % _ball.mass)
	_check(_ball.linear_damp > 0.0 and _ball.angular_damp > 0.0,
			"Ball: damping values applied from config")

	var visual: BallVisual = _ball.get_node_or_null("BallVisual")
	_check(visual != null, "Ball scene: BallVisual present")
	if visual != null:
		var mesh_node: MeshInstance3D = visual.get_node_or_null("BallMesh")
		_check(mesh_node != null and mesh_node.mesh is SphereMesh,
				"Ball visual: sphere mesh child")
		if mesh_node != null and mesh_node.mesh is SphereMesh:
			var mesh := mesh_node.mesh as SphereMesh
			_check(absf(mesh.radius - 0.11) < 0.005,
					"Ball visual: mesh radius matches physics radius")
			var material_active: Material = _effective_material(mesh)
			_check(material_active != null and material_active is StandardMaterial3D
					and (material_active as StandardMaterial3D).albedo_texture != null,
					"Ball visual: procedural pattern texture applied")
	_check(_ball.get_node_or_null("BallDebug") is BallDebug,
			"Ball scene: optional BallDebug node present")
	_check(_ball.config is BallConfig, "Ball: config resource assigned")


func _effective_material(mesh: SphereMesh) -> Material:
	if mesh.material != null:
		return mesh.material
	return null


# --- 3. Gravity / resting --------------------------------------------------------

func _test_gravity_and_rest() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 5.0, 20.0))
	var min_y := INF
	var max_y := -INF
	for i in 240:
		await get_tree().physics_frame
		min_y = minf(min_y, _ball.global_position.y)
		max_y = maxf(max_y, _ball.global_position.y)
	_check(max_y <= 5.01, "Gravity: falls from height (no floating)", "max_y=%.2f" % max_y)
	_check(min_y > -0.5, "Gravity: never penetrates ground", "min_y=%.3f" % min_y)
	_check(absf(_ball.global_position.y - 0.11) < 0.03,
			"Gravity: rests at correct height (centre = radius above plate)",
			"y=%.3f" % _ball.global_position.y)
	_check(_planar_speed_of(_ball) < 0.05, "Gravity: settled into a stable rest")


# --- 4. Bounce -------------------------------------------------------------------

func _record_bounce_apexes(max_ticks: int) -> Array[float]:
	var samples: Array[float] = []
	apexes = []
	for i in max_ticks:
		await get_tree().physics_frame
		samples.append(_ball.global_position.y)
	# Local maxima above ball radius (connected plateau merged). The region that
	# starts at sample 0 is the initial drop itself, not a bounce — skip it.
	var region_start := -1
	var in_max := false
	var current_max := 0.0
	for i in samples.size():
		var value := samples[i]
		if value > 0.135:
			if not in_max:
				in_max = true
				region_start = i
				current_max = value
			else:
				current_max = maxf(current_max, value)
		else:
			if in_max:
				if region_start > 0:  # ignore the initial fall region
					apexes.append(current_max)
				in_max = false
	if in_max and region_start > 0:
		apexes.append(current_max)
	return apexes


var apexes: Array[float] = []


func _test_bounce_decay() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 5.0, 20.0))
	await _record_bounce_apexes(480)
	_check(apexes.size() >= 2, "Bounce: ball bounces more than once",
			"apexes=%s" % str(apexes))
	if apexes.size() >= 2:
		_check(apexes[0] > 0.6 and apexes[0] < 2.6,
				"Bounce: first bounce apex ≈ h₀·bounce² (0.55²·5 ≈ 1.5 m)",
				"apex1=%.2f" % apexes[0])
		_check(apexes[1] < apexes[0] * 0.9,
				"Bounce: energy lost between bounces",
				"apex1=%.2f apex2=%.2f" % [apexes[0], apexes[1]])
		if apexes.size() >= 3:
			_check(apexes[2] < apexes[1] * 0.9,
					"Bounce: decay continues (settles, no endless bouncing)",
					"apex3=%.2f" % apexes[2])
	_check(_planar_speed_of(_ball) < 0.05,
			"Bounce: ball comes to a stable rest after bouncing")


# --- 5. Rolling / friction ---------------------------------------------------------

func _test_rolling_and_friction() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.15, 20.0))
	_ball.apply_kick(Vector3(1.0, 0.0, 0.0), 10.0, 0.0)
	await _await_ticks(2)
	var v30 := _planar_speed_of(_ball)
	_check(v30 > 7.0 and v30 <= 10.2,
			"Rolling: momentum carried (no sudden stop after kick)",
			"early=%.2f" % v30)

	var begin_x := _ball.global_position.x
	await _await_ticks(90)  # 1.5 s
	var v90 := _planar_speed_of(_ball)
	var distance := _ball.global_position.x - begin_x
	_check(v90 < v30 and v90 > 3.0,
			"Rolling: speed decays smoothly via friction/damping",
			"t1.5=%.2f" % v90)
	_check(distance > 6.0,
			"Rolling: ball keeps rolling far (not over-damped)",
			"dist=%.2f" % distance)
	_check(absf(_ball.global_position.y - 0.11) < 0.03,
			"Rolling: stable ground contact while rolling",
			"y=%.3f" % _ball.global_position.y)

	# Angular motion: a rolling ball really spins, and the visual (mesh child
	# of the RigidBody3D) visibly rotates with the physics body per tick.
	var spin := _ball.angular_velocity.length()
	_check(spin > 5.0, "Angular: rolling ball has real angular velocity",
			"omega=%.1f rad/s" % spin)
	var basis_a := _ball.global_transform.basis
	await get_tree().physics_frame
	var basis_b := _ball.global_transform.basis
	var visual_rotation := (basis_b.x - basis_a.x).length()
	_check(visual_rotation > 0.005,
			"Angular: ball orientation rotates between ticks (visible spin)",
			"per-tick=%.4f" % visual_rotation)

	var stopped := false
	var start_x := _ball.global_position.x
	for i in 900:  # up to 15 s
		await get_tree().physics_frame
		if _planar_speed_of(_ball) < 0.05:
			stopped = true
			break
	_check(stopped, "Rolling: ball stops cleanly (≤15 s after a 10 m/s kick)")
	var total := _ball.global_position.x - start_x
	_check(total > 3.0, "Rolling: still rolls several metres while decelerating",
			"extra=%.2f" % total)

	# Tiny kick + settle ramp: must stop quickly, then stay stopped (no creeping
	# back into motion — the ramp must fully bleed the residual speed).
	_ball.apply_kick(Vector3(0.0, 0.0, -1.0), 0.6, 0.0)
	await _await_ticks(5)
	var settled_tick := -1
	var crept_after := false
	for i in 150:  # 2.5 s
		await get_tree().physics_frame
		var planar := _planar_speed_of(_ball)
		if settled_tick < 0:
			if planar < 0.05:
				settled_tick = i + 1
		elif planar >= 0.05:
			crept_after = true
	_check(settled_tick > 0 and settled_tick < 150,
			"Rolling: slow ball settles quickly (settle ramp)",
			"settled_tick=%d" % settled_tick)
	_check(not crept_after, "Rolling: settled ball does not creep again")


# --- 6. Kick API ----------------------------------------------------------------------

func _test_kick_api() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.15, 20.0))
	_kicked_speeds.clear()

	_ball.apply_kick(Vector3(1.0, 0.0, 0.0), 8.0, 0.0)
	# Measured after 3 ticks: friction/damping has already bled a little speed
	# by then, so the bound accounts for that (decay ≈ 5% at 0.05 s).
	await _await_ticks(3)
	var v := _ball.linear_velocity
	_check(Vector3(v.x, 0, v.z).normalized().dot(Vector3(1, 0, 0)) > 0.98,
			"Kick: planar direction honoured", "v=%s" % str(v))
	_check(absf(_ball.get_ball_speed() - 8.0) < 0.6,
			"Kick: power honoured as Δv", "speed=%.2f" % _ball.get_ball_speed())
	_check(_kicked_speeds.size() == 1, "Kick: 'kicked' signal emitted")

	# Lift adds upward velocity.
	await _await_ticks(60)
	_ball.apply_kick(Vector3(1.0, 0.0, 0.0), 2.0, 6.0)
	await _await_ticks(4)
	_check(_ball.linear_velocity.y > 3.0,
			"Kick: vertical lift applied", "vy=%.2f" % _ball.linear_velocity.y)
	await _await_ticks(40)
	_check(_ball.get_ball_speed() <= _ball.config.max_ball_speed + 0.5,
			"Kick: nothing exceeds the configured speed ceiling")

	# Ceiling under stacking.
	for i in 30:
		_ball.apply_kick(Vector3(0.7, 0.0, 0.7), 20.0, 0.0)
	await _await_ticks(4)
	_check(_ball.get_ball_speed() <= _ball.config.max_ball_speed + 0.5,
			"Kick: stacked kicks clamp at max_ball_speed (no explosion)",
			"speed=%.2f" % _ball.get_ball_speed())


func _test_impulse_and_force_api() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.15, 20.0))
	_ball.stop_ball()
	await _await_ticks(3)

	# apply_impulse (inherited RigidBody3D interface): Δv = impulse / mass.
	# Documented caveat: it does not wake a sleeping ball — wake first.
	_ball.sleeping = false
	_ball.apply_impulse(Vector3(_ball.mass * 5.0, 0.0, 0.0))
	await _await_ticks(3)
	var vx := _ball.linear_velocity.x
	_check(vx > 4.0 and vx < 6.2, "Impulse: Δv = impulse/mass honoured",
			"vx=%.2f" % vx)
	_ball.stop_ball()
	await _await_ticks(3)

	# apply_force (inherited interface): short sustained push. RigidBody3D
	# forces are consumed after a single physics step, so gameplay code
	# re-applies them every tick — the same steady-push pattern Phase 4's
	# dribbling logic will use. Wake first and disable auto-sleep for the
	# window; the push must also overpower sliding friction on the ground
	# (≈ friction·g), hence the generous 18 m/s².
	_ball.can_sleep = false
	_ball.sleeping = false
	for i in 12:  # 0.2 s of sustained push
		_ball.apply_force(Vector3(_ball.mass * 18.0, 0.0, 0.0))
		await get_tree().physics_frame
	_check(_ball.linear_velocity.x > 1.0 and _ball.linear_velocity.x < 3.5,
			"Force: sustained force accelerates ball (a = F/m)",
			"vx=%.2f" % _ball.linear_velocity.x)
	_ball.can_sleep = true


# --- 7. Reset / stop --------------------------------------------------------------------

func _test_reset_and_stop() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.15, 20.0))
	_reset_positions.clear()

	_ball.apply_kick(Vector3(1.0, 0.0, 0.0), 12.0, 0.0)
	await _await_ticks(5)
	_ball.stop_ball()
	await _await_ticks(3)
	_check(_ball.get_ball_speed() < 0.01,
			"Stop: moving ball stops immediately", "speed=%.3f" % _ball.get_ball_speed())
	var speed_after := _planar_speed_of(_ball)
	await _await_ticks(30)
	_check(_planar_speed_of(_ball) < 0.02 and _ball.global_position.y > -0.05,
			"Stop: stays stopped and still supported")


	# Reset to explicit position, then default (centre). From y = 3 the fall
	# takes ≈0.8 s plus a couple of bounces — 2 s (120 ticks) covers settling.
	_ball.reset_ball(Vector3(4.0, 3.0, 4.0))
	await _await_ticks(120)
	var p := _ball.global_position
	_check(absf(p.x - 4.0) < 0.1 and absf(p.z - 4.0) < 0.1,
			"Reset: explicit reset lands at the requested spot", "pos=%s" % str(p))
	_check(absf(p.y - 0.11) < 0.05,
			"Reset: comes to rest on the ground", "y=%.3f" % p.y)
	_ball.reset_ball()  # default → centre spot
	await _await_ticks(40)
	p = _ball.global_position
	_check(absf(p.x) < 0.05 and absf(p.z) < 0.05,
			"Reset: default reset returns to the centre spot", "pos=%s" % str(p))
	_check(_planar_speed_of(_ball) < 0.05, "Reset: motion cleared on reset")
	_check(_reset_positions.size() == 2, "Reset: 'ball_reset' signal emitted twice",
			"n=%d" % _reset_positions.size())


# --- 8. Player–ball interaction -------------------------------------------------------------

func _test_player_interaction() -> void:
	_spawn_env()
	_player = await _spawn_player(Vector3(0.0, 0.05, 0.0))
	_ball = _spawn_ball(Vector3(3.0, 0.15, 0.0))
	await _await_ticks(3)
	# Stationary player: fast ball driven at them must not tunnel through.
	_ball.apply_kick(Vector3(-1.0, 0.0, 0.0), 8.0, 0.0)
	var min_distance := await _min_planar_distance_tracked(_player, _ball, 150)
	_check(min_distance > 0.28,
			"Interaction: ball never overlaps the player capsule",
			"min=%.2f (capsule r=0.3 + ball r=0.11)" % min_distance)
	_check(_ball.global_position.x > -1.0,
			"Interaction: ball is blocked/deflected, no pass-through",
			"final_x=%.2f" % _ball.global_position.x)

	# Player runs into a stationary ball → ball gains momentum physically.
	_release_all()
	_ball.reset_ball(Vector3(0.0, 0.15, 0.0))
	_player.global_position = Vector3(-1.5, 0.05, 0.0)
	_player.velocity = Vector3.ZERO
	await _await_ticks(3)
	Input.action_press("move_right")
	Input.action_press("sprint")
	var ball_peak := 0.0
	for i in 140:
		await get_tree().physics_frame
		ball_peak = maxf(ball_peak, _planar_speed_of(_ball))
	Input.action_release("move_right")
	Input.action_release("sprint")
	_check(ball_peak > 0.5,
			"Interaction: player pushing the ball moves it physically", "peak=%.2f" % ball_peak)
	_check(_player.movement_state == PlayerController.MovementState.MOVING
			or _player.movement_state == PlayerController.MovementState.SPRINTING,
			"Interaction: Player Controller still reports states while pushing ball")
	await _await_ticks(60)


# --- 9. CCD / tunnelling -------------------------------------------------------------------

func _test_no_tunnelling() -> void:
	_spawn_env()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 1.0)
	shape.shape = box
	shape.position.y = 1.5
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, -4.0)
	_env.add_child(wall)

	_ball = _spawn_ball(Vector3(0.0, 0.15, 6.0))
	await _await_ticks(3)
	_ball.apply_kick(Vector3(0.0, 0.0, -1.0), 22.0, 0.0)
	var min_z := INF
	for i in 250:
		await get_tree().physics_frame
		min_z = minf(min_z, _ball.global_position.z)
	# Wall box spans z ∈ (−4.5, −3.5); anything past −5.5 means it tunneled
	# through 1 m of static geometry.
	_check(min_z > -5.5,
			"CCD: no tunnelling through the wall at 22 m/s", "min_z=%.2f" % min_z)

	# High vertical drop — no floor tunnel.
	_ball.reset_ball(Vector3(0.0, 10.0, -8.0))
	var min_y := INF
	for i in 180:
		await get_tree().physics_frame
		min_y = minf(min_y, _ball.global_position.y)
	_check(min_y > -0.5,
			"CCD: no tunnelling on a 10 m vertical drop", "min_y=%.3f" % min_y)


# --- 10. Proximity detector ------------------------------------------------------------------

func _test_proximity_detector() -> void:
	_spawn_env()
	_player = await _spawn_player(Vector3(0.0, 0.05, 0.0))
	var detector := BallProximityDetector.new()
	_player.add_child(detector)
	detector.ball_detected.connect(func(b: Node3D) -> void: _detector_ball = b)
	detector.ball_lost.connect(func() -> void: _detector_lost += 1)
	detector.ball_interaction_available.connect(
			func(available: bool) -> void: _detector_available.append(available))

	_ball = _spawn_ball(Vector3(5.0, 0.15, 0.0))
	await _await_ticks(5)
	_check(not detector.is_ball_nearby(), "Detector: far ball is not detected")
	_check(_detector_ball == null, "Detector: no 'ball_detected' while far")
	_check(not detector.is_interaction_available(), "Detector: no interaction while far")

	# Ball moves into detection radius.
	_ball.reset_ball(Vector3(1.4, 0.15, 0.0))
	await _await_ticks(5)
	_check(detector.is_ball_nearby(), "Detector: ball detected within radius")
	_check(_detector_ball == _ball, "Detector: 'ball_detected' with correct ball")
	_check(absf(detector.get_distance_to_ball() - 1.4) < 0.2,
			"Detector: distance to ball correct",
			"%.2f" % detector.get_distance_to_ball())
	var dir := detector.get_direction_to_ball()
	_check(dir.dot(Vector3(1, 0, 0)) > 0.98, "Detector: direction to ball correct",
			"dir=%s" % str(dir))

	# Entering the interaction window.
	_ball.reset_ball(Vector3(0.6, 0.15, 0.0))
	await _await_ticks(5)
	_check(detector.is_interaction_available(), "Detector: interaction available near ball")
	_check(_detector_available.size() > 0 and _detector_available[-1],
			"Detector: 'ball_interaction_available'(true) emitted")

	# Too high → no interaction.
	_ball.reset_ball(Vector3(0.6, 3.0, 0.0))  # airborne above interaction height... wait, 3.0 exceeds height 1.0
	await _await_ticks(5)
	_check(not detector.is_interaction_available(),
			"Detector: airborne ball above limit → no interaction")
	# Back near feet once settled.
	_ball.reset_ball(Vector3(0.5, 0.15, 0.0))
	await _await_ticks(5)
	_check(detector.is_interaction_available(),
			"Detector: interaction returns when ball is back at feet level")

	# Leaving the radius completely.
	_ball.reset_ball(Vector3(6.0, 0.15, 0.0))
	await _await_ticks(5)
	_check(not detector.is_ball_nearby(), "Detector: ball lost beyond radius")
	_check(_detector_lost == 1, "Detector: 'ball_lost' emitted once", "lost=%d" % _detector_lost)
	_check(detector.get_current_ball() == null, "Detector: current ball cleared")
	_check(detector.get_distance_to_ball() == 0.0, "Detector: distance 0 without ball")


# --- 11. Debug tools ------------------------------------------------------------------------

func _test_debug_tools() -> void:
	_spawn_env()
	_ball = _spawn_ball(Vector3(0.0, 0.15, 20.0))
	var debug: BallDebug = _ball.get_node("BallDebug")
	_check(not debug.debug_enabled and not _ball.debug_enabled,
			"Debug: disabled by default (no normal-gameplay overhead)")
	_ball.debug_enabled = true
	await _await_ticks(3)
	_check(debug.debug_enabled, "Debug: enabling via ball propagates to overlay")
	var lines: MeshInstance3D = debug.get_node_or_null("DebugLines")
	_check(lines != null and lines.visible, "Debug: velocity overlay visible when enabled")
	_ball.apply_kick(Vector3(1.0, 0.0, 0.0), 6.0, 0.0)
	await _await_ticks(2)
	_check(lines.mesh.get_surface_count() > 0,
			"Debug: velocity vector drawn while ball moves")
	_ball.debug_enabled = false
	_check(not lines.visible, "Debug: overlay hidden again when disabled")

	# Detector rings drawable.
	var rings_detector := BallProximityDetector.new()
	rings_detector.show_rings = true
	_env.add_child(rings_detector)
	await _await_ticks(2)
	_check(rings_detector.get_node_or_null("DebugRings") != null,
			"Debug: detector interaction rings drawable available")


# --- 12. Integration (Phase 1 + 2 preserved) ---------------------------------------------------

func _test_integration() -> void:
	_spawn_env()
	var pitch: FootballPitch = load("res://scenes/environment/football_pitch.tscn").instantiate()
	pitch.position = Vector3(0.0, 0.0, -30.0)  # keep pitch far from other tests
	_env.add_child(pitch)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(pitch.get_node_or_null("GroundCollision") != null,
			"Integration: pitch still builds its ground collision")

	# Player + ball on the real pitch, plus the follow camera.
	_player = await _spawn_player(Vector3(0.0, 0.1, -30.0))
	_ball = _spawn_ball(Vector3(0.0, 0.3, -31.0))  # directly in the player's path
	var camera: GameCamera = load("res://scenes/camera/game_camera.tscn").instantiate()
	camera.position = Vector3(0.0, 4.0, -25.0)
	camera.follow_target = _player
	camera.mode = GameCamera.Mode.FOLLOW
	_env.add_child(camera)
	await get_tree().physics_frame
	_check(camera.global_position.distance_to(_player.global_position) < 25.0,
			"Integration: follow camera tracks the player")
	camera.free()

	# Player still moves normally with the ball present.
	Input.action_press("move_forward")
	var begin := _player.global_position
	await _await_ticks(30)
	Input.action_release("move_forward")
	await _settle_player_idle()
	var moved := begin.distance_to(_player.global_position)
	_check(moved > 1.5,
			"Integration: Phase 2 player movement still works beside the ball",
			"moved=%.2f" % moved)
	# Ball physically pushed by the player walking into it.
	var ball_start := _ball.global_position
	_check(_ball.get_ball_speed() > 0.1
			or _ball.global_position.distance_to(ball_start) > 0.2,
			"Integration: ball reacts to the player on the real pitch",
			"speed=%.2f moved=%.2f" % [_ball.get_ball_speed(),
			_ball.global_position.distance_to(ball_start)])

	# Dedicated test scene structure (mirrors phase2's own suite pattern).
	var test_scene: Node = load("res://scenes/development/ball_physics_test.tscn").instantiate()
	test_scene.position = Vector3(0.0, 0.0, -60.0)
	add_child(test_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(test_scene.get_node_or_null("Pitch") != null, "Test scene: Phase 1 pitch reused")
	var scene_ball: BallController = test_scene.get_node_or_null("Ball")
	_check(scene_ball != null and scene_ball.is_in_group("football_ball"),
			"Test scene: ball instance present and grouped")
	_check(test_scene.get_node_or_null("Player") is PlayerController,
			"Test scene: Phase 2 player reused")
	var scene_detector: BallProximityDetector = test_scene.get_node_or_null("Player/BallDetector")
	_check(scene_detector != null, "Test scene: proximity detector mounted on player")
	var scene_camera: GameCamera = test_scene.get_node_or_null("%GameCamera")
	_check(scene_camera != null and scene_camera.follow_target == test_scene.get_node("Player"),
			"Test scene: camera wired to the player")
	_check(test_scene.get_node_or_null("HUD") != null
			and test_scene.get_node("%BallStatusLabel") != null,
			"Test scene: HUD labels present")
	_check(test_scene.get_node_or_null("Obstacles") != null,
			"Test scene: obstacle crates generated")
	test_scene.free()
	await get_tree().process_frame


# --- small helpers ----------------------------------------------------------------------------

func _settle_player_idle(max_ticks := 60) -> void:
	for i in max_ticks:
		await get_tree().physics_frame
		if _player.get_current_speed() < 0.05:
			break
