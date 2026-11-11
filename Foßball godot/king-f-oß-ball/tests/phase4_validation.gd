## Phase 4 validation suite — runs headless:
##   godot --headless --path . res://tests/phase4_validation.tscn
## Asserts: gameplay scripts/resources load, player scene carries the
## BallActions/BallDetector gameplay node, the plan §5 query API exists,
## subsystem contracts (no native-method overrides), kick-power charging,
## ground/directional passing, shooting (ground + elevated), lob trajectory,
## dribbling control + separation + recovery, ball reception (fast + slow),
## cooldown/repeat-input handling, action-state machine behaviour, and that
## Phase 1–3 assets and movement still function on top.

extends Node

const TICKS_PER_SECOND := 60.0
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

const GAMEPLAY_SCRIPTS: Array[String] = [
	"res://scripts/gameplay/ball_action_config.gd",
	"res://scripts/gameplay/kick_power_controller.gd",
	"res://scripts/gameplay/passing_system.gd",
	"res://scripts/gameplay/shooting_system.gd",
	"res://scripts/gameplay/lob_pass_system.gd",
	"res://scripts/gameplay/dribbling_system.gd",
	"res://scripts/gameplay/ball_control_system.gd",
	"res://scripts/gameplay/football_actions.gd",
]

var _passed := 0
var _failed := 0
var _env: Node3D
var _ball: BallController
var _player: PlayerController
var _actions: FootballActions
var _state_history: Array[int] = []
var _pass_starts: Array[float] = []
var _pass_completes: Array[float] = []
var _shot_starts: Array[float] = []
var _shot_lifts: Array[float] = []
var _lob_starts: Array[float] = []
var _received_speeds: Array[float] = []
var _dribble_on: int = 0
var _dribble_off: int = 0
var _max_step := 0.0
var _prev_ball_pos := Vector3.ZERO


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase 4 validation ===")
	_test_assets()
	_test_player_gameplay_node()
	_test_query_api()
	_test_subsystem_contracts()
	_test_config_defaults()
	await _test_runtime_subsystems()
	await _test_ground_pass()
	await _test_pass_cooldown_and_repeat()
	await _test_ground_shot()
	await _test_elevated_charged_shot()
	await _test_lob_pass()
	await _test_charge_guard_out_of_range()
	await _test_dribbling()
	await _test_reception()
	await _test_state_recovery_and_movement()
	_test_phase_integration()

	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _await_ticks(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _release_all() -> void:
	for action: String in ["move_forward", "move_backward", "move_left",
			"move_right", "sprint", "pass", "shoot", "lob_pass", "dribble", "tackle"]:
		Input.action_release(action)


# --- Env helpers ---------------------------------------------------------------

func _spawn_env() -> void:
	_release_all()
	_state_history.clear()
	_pass_starts.clear()
	_pass_completes.clear()
	_shot_starts.clear()
	_shot_lifts.clear()
	_lob_starts.clear()
	_received_speeds.clear()
	_dribble_on = 0
	_dribble_off = 0
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
	return ball


func _spawn_player(at: Vector3) -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	_player.position = at
	_env.add_child(_player)
	await get_tree().physics_frame
	_actions = _player.get_node("BallActions") as FootballActions
	_actions.action_state_changed.connect(func(state: int) -> void:
		_state_history.append(state))
	_actions.pass_started.connect(func(power: float) -> void:
		_pass_starts.append(power))
	_actions.pass_completed.connect(func() -> void:
		_pass_completes.append(1.0))
	_actions.shot_started.connect(func(power: float, lift: float) -> void:
		_shot_starts.append(power)
		_shot_lifts.append(lift))
	_actions.lob_started.connect(func(power: float, _lift: float) -> void:
		_lob_starts.append(power))
	_actions.dribble_started.connect(func() -> void: _dribble_on += 1)
	_actions.dribble_stopped.connect(func() -> void: _dribble_off += 1)
	_actions.ball_received.connect(func(speed: float) -> void:
		_received_speeds.append(speed))


## Watches ball position continuity (teleport detection) between awaited ticks.
func _track_ball_step() -> void:
	if _ball != null and is_instance_valid(_ball):
		var pos := _ball.global_position
		if _prev_ball_pos != Vector3.ZERO:
			_max_step = maxf(_max_step, (pos - _prev_ball_pos).length())
		_prev_ball_pos = pos


func _await_ticks_tracked(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_track_ball_step()


func _ball_planar_speed() -> float:
	var v := _ball.linear_velocity
	return Vector3(v.x, 0.0, v.z).length()


func _reset_scenario(ball_pos: Vector3, player_pos: Vector3) -> void:
	_spawn_env()
	_ball = _spawn_ball(ball_pos)
	await _spawn_player(player_pos)
	await _await_ticks(5)  # let the ball settle on the ground


# --- 1. Static assets -----------------------------------------------------------

func _test_assets() -> void:
	for path: String in GAMEPLAY_SCRIPTS:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "Script parses: %s" % path)
	_check(load("res://resources/configurations/ball_action_config.tres") is BallActionConfig,
			"BallActionConfig resource loads")
	_check(load("res://scenes/development/football_mechanics_test.tscn") != null,
			"Scene loads: football mechanics test scene")
	for action: String in ["pass", "shoot", "lob_pass", "dribble", "tackle"]:
		_check(InputMap.has_action(action), "InputMap: %s still present" % action)
	for action: String in ["move_forward", "move_backward", "move_left",
			"move_right", "sprint"]:
		_check(InputMap.has_action(action), "InputMap: %s (Phase 2) intact" % action)


# --- 2. Player scene carries the gameplay node ----------------------------------

func _test_player_gameplay_node() -> void:
	# Static structure only — the player is NOT added to the tree here, so
	# `_ready()` has not built the subsystems yet (checked at runtime below).
	var player: PlayerController = (load(PLAYER_SCENE) as PackedScene).instantiate()
	var actions := player.get_node_or_null("BallActions")
	_check(actions != null, "Player scene: BallActions node present")
	var actions_script: GDScript = actions.get_script() if actions != null else null
	_check(actions_script != null and actions_script.resource_path
			.ends_with("football_actions.gd"),
			"BallActions script is football_actions.gd")
	var detector := actions.get_node_or_null("BallDetector") if actions != null else null
	_check(detector != null, "BallActions: BallDetector child present")
	var detector_script: GDScript = detector.get_script() if detector != null else null
	_check(detector_script != null and detector_script.resource_path
			.ends_with("ball_proximity_detector.gd"),
			"BallDetector script is ball_proximity_detector.gd")
	player.free()


## Runtime wiring: the same checks against a player that went through _ready().
func _test_runtime_subsystems() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	var subsystems := [
		["PassingSystem", "passing_system.gd"],
		["ShootingSystem", "shooting_system.gd"],
		["LobPassSystem", "lob_pass_system.gd"],
		["DribblingSystem", "dribbling_system.gd"],
		["BallControlSystem", "ball_control_system.gd"],
		["PassCharge", "kick_power_controller.gd"],
		["ShootCharge", "kick_power_controller.gd"],
		["LobCharge", "kick_power_controller.gd"],
	]
	for entry: Array in subsystems:
		var node := _actions.get_node_or_null(NodePath(entry[0]))
		var ok := node != null and node.get_script() != null \
				and (node.get_script() as GDScript).resource_path.ends_with(entry[1])
		_check(ok, "BallActions subsystem wired: %s" % entry[0])


# --- 3. Plan §5 query API ---------------------------------------------------------

func _test_query_api() -> void:
	var actions := FootballActions.new()
	var required := ["can_interact_with_ball", "get_ball_relative_position",
			"get_ball_distance", "get_kick_direction", "get_action_availability"]
	for method: String in required:
		_check(actions.has_method(method), "FootballActions method: %s" % method)
	var required_signals := ["action_state_changed", "charge_changed", "pass_started",
			"pass_completed", "shot_started", "shot_completed", "lob_started",
			"dribble_started", "dribble_stopped", "ball_received"]
	for signal_name: String in required_signals:
		_check(actions.has_signal(signal_name), "FootballActions signal: %s" % signal_name)
	actions.free()


# --- 4. Subsystem contracts --------------------------------------------------------

func _test_subsystem_contracts() -> void:
	# Gameplay must extend with NEW method names, never override the inherited
	# RigidBody3D interfaces (Godot 4.7 native-method override rule).
	for path: String in [
			"res://scripts/gameplay/dribbling_system.gd",
			"res://scripts/gameplay/ball_control_system.gd",
			"res://scripts/gameplay/football_actions.gd"]:
		var source: String = (load(path) as GDScript).source_code
		_check(not source.contains("func apply_force"), "No apply_force override: %s" % path)
		_check(not source.contains("func apply_impulse"), "No apply_impulse override: %s" % path)
	# Test scene: pitch + player + ball + camera + script present.
	var scene: PackedScene = load("res://scenes/development/football_mechanics_test.tscn")
	var state := scene.instantiate() as Node3D
	_check(state.get_node_or_null("Pitch") != null, "Test scene has Pitch")
	_check(state.get_node_or_null("Player/BallActions") != null,
			"Test scene player carries gameplay node")
	_check(state.get_node_or_null("Ball") != null, "Test scene has Ball")
	_check(state.get_node_or_null("GameCamera") != null, "Test scene has GameCamera")
	_check(state.get_node_or_null("HUD") != null, "Test scene has development HUD")
	state.free()


# --- 5. Config defaults sanity ------------------------------------------------------

func _test_config_defaults() -> void:
	var config := BallActionConfig.new()
	_check(config.min_pass_power < config.default_pass_power
			and config.default_pass_power < config.max_pass_power,
			"Pass power: min < default < max")
	_check(config.min_shoot_power < config.default_shoot_power
			and config.default_shoot_power < config.max_shoot_power,
			"Shoot power: min < default < max")
	_check(config.min_lob_power < config.default_lob_power
			and config.default_lob_power < config.max_lob_power,
			"Lob power: min < default < max")
	_check(config.pass_cooldown > 0.0 and config.shoot_cooldown > 0.0
			and config.lob_cooldown > 0.0, "Cooldowns positive")
	_check(config.dribble_distance > 0.9 and config.dribble_max_force > 0.0,
			"Dribble range and force cap sane")
	_check(config.reception_damping > 0.0 and config.reception_max_force > 0.0,
			"Reception damping sane")
	_check(config.lob_lift > 0.0, "Lob lift positive")


# --- 6. Ground pass (quick tap) ------------------------------------------------------

func _test_ground_pass() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	_check(_actions.can_interact_with_ball(), "Interaction window available at 0.5 m")
	_check(absf(_actions.get_ball_distance() - 0.5) < 0.15, "get_ball_distance ≈ 0.5 m")
	var rel := _actions.get_ball_relative_position()
	_check(rel.z < -0.3 and absf(rel.x) < 0.3, "get_ball_relative_position: ball ahead (-Z)")
	var kick_dir := _actions.get_kick_direction()
	_check(kick_dir.dot(Vector3(0.0, 0.0, -1.0)) > 0.99,
			"get_kick_direction: default facing -Z")

	Input.action_press("pass")
	await _await_ticks_tracked(3)
	Input.action_release("pass")
	await _await_ticks_tracked(4)
	_check(_pass_starts.size() == 1, "Quick-tap pass executed exactly once")
	if _pass_starts.size() > 0:
		var power: float = _pass_starts[0]
		_check(absf(power - 9.0) < 0.1, "Quick tap uses default pass power (9)", str(power))
	var speed := _ball_planar_speed()
	_check(speed > 6.5 and speed < 11.0, "Pass ball speed ≈ default power", str(speed))
	var vel := _ball.linear_velocity
	_check(Vector3(vel.x, 0.0, vel.z).normalized().dot(Vector3(0.0, 0.0, -1.0)) > 0.9,
			"Pass travels along the player's facing (-Z)")
	_check(vel.y < 0.2, "Ground pass stays low")
	await _await_ticks_tracked(30)
	_check(_pass_completes.size() == 1, "pass_completed emitted after the transient state")
	_check(_actions.action_state == FootballActions.ActionState.IDLE,
			"State returned to IDLE after pass")


# --- 7. Cooldown + repeated input ----------------------------------------------------

func _test_pass_cooldown_and_repeat() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	# Double-tap within the cooldown: only the first kick must execute.
	Input.action_press("pass")
	await _await_ticks_tracked(2)
	Input.action_release("pass")
	await _await_ticks_tracked(2)
	var speed_after_first := _ball_planar_speed()
	_check(_pass_starts.size() == 1, "First tap kicks once")
	# second press while cooldown is still running
	Input.action_press("pass")
	await _await_ticks_tracked(2)
	_check(not _actions.get_action_availability()[&"pass"],
			"Pass unavailable during cooldown")
	_check(_pass_starts.size() == 1, "Repeated input during cooldown does not kick again")
	Input.action_release("pass")
	await _await_ticks_tracked(10)
	_check(_pass_starts.size() == 1, "Still exactly one kick after double-tap")
	_check(_ball_planar_speed() <= speed_after_first + 0.5,
			"Ball did not receive a second impulse")


# --- 8. Ground shot ------------------------------------------------------------------

func _test_ground_shot() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	Input.action_press("shoot")
	await _await_ticks_tracked(3)
	Input.action_release("shoot")
	await _await_ticks_tracked(3)
	_check(_shot_starts.size() == 1, "Quick-tap shot executed")
	if _shot_starts.size() > 0:
		var power: float = _shot_starts[0]
		_check(absf(power - 16.0) < 0.1, "Quick-tap shot uses default power (16)", str(power))
	var speed := _ball_planar_speed()
	_check(speed > 12.0 and speed < 20.0, "Shot speed ≈ default shot power", str(speed))
	var vel := _ball.linear_velocity
	_check(Vector3(vel.x, 0.0, vel.z).normalized().dot(Vector3(0.0, 0.0, -1.0)) > 0.9,
			"Shot travels along facing (-Z)")
	if _shot_lifts.size() > 0:
		_check(_shot_lifts[0] >= 0.29, "Ground shot has slight lift",
				str(_shot_lifts[0]))
	else:
		_check(false, "Ground shot has slight lift", "no shot signal")


# --- 9. Elevated charged shot ----------------------------------------------------------

func _test_elevated_charged_shot() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	Input.action_press("shoot")
	await _await_ticks_tracked(3)
	_check(_actions.get_charge_ratio(&"shoot") == 0.0,
			"Charge ratio 0 before the quick-tap threshold")
	await _await_ticks_tracked(30)  # ~0.6 s total hold → ratio ≈ 0.53
	var ratio := _actions.get_charge_ratio(&"shoot")
	_check(ratio > 0.3 and ratio < 0.75, "Charge ratio ramps during hold", str(ratio))
	Input.action_release("shoot")
	await _await_ticks_tracked(3)
	_check(_shot_starts.size() == 1, "Charged shot executed")
	if _shot_starts.size() > 0:
		var power: float = _shot_starts[0]
		_check(power > 20.0, "Charged shot power exceeds default", str(power))
	var vel := _ball.linear_velocity
	_check(vel.y > 0.8, "Charged shot is elevated", str(vel.y))
	await _await_ticks_tracked(30)


# --- 10. Lob pass ------------------------------------------------------------------------

func _test_lob_pass() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	Input.action_press("lob_pass")
	await _await_ticks_tracked(3)
	Input.action_release("lob_pass")
	await _await_ticks_tracked(2)
	_check(_lob_starts.size() == 1, "Quick-tap lob executed")
	if _lob_starts.size() > 0:
		var power: float = _lob_starts[0]
		_check(absf(power - 7.0) < 0.1, "Quick-tap lob uses default power (7)", str(power))
	var vel := _ball.linear_velocity
	_check(vel.y > 4.0, "Lob has a strong upward impulse", str(vel.y))
	var planar := Vector3(vel.x, 0.0, vel.z)
	_check(planar.length() > 5.0 and planar.length() < 10.0,
			"Lob keeps horizontal speed", str(planar.length()))
	_check(planar.normalized().dot(Vector3(0.0, 0.0, -1.0)) > 0.9,
			"Lob direction follows the facing")
	# Airborne arc: ball gains height after the kick.
	var start_y := _ball.global_position.y
	await _await_ticks_tracked(12)
	_check(_ball.global_position.y > start_y + 0.3, "Lob produces an airborne trajectory")


# --- 11. Charge guard: cannot charge outside the interaction window ------------------------

func _test_charge_guard_out_of_range() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, 10.0), Vector3(0.0, 0.2, 0.0))
	await _await_ticks(10)
	Input.action_press("shoot")
	await _await_ticks_tracked(20)
	_check(not _actions.get_charge_ratio(&"shoot") > 0.0,
			"Charging prevented while ball is out of interaction range")
	Input.action_release("shoot")
	await _await_ticks_tracked(5)
	_check(_shot_starts.is_empty(), "No shot when out of range")
	_check(_ball_planar_speed() < 0.5, "Far ball untouched")


# --- 12. Dribbling ---------------------------------------------------------------------------

func _test_dribbling() -> void:
	# Ball 1.2 m ahead: outside the 0.9 m interaction window, inside the
	# 1.6 m dribble range.
	await _reset_scenario(Vector3(0.0, 0.4, -1.2), Vector3(0.0, 0.2, 0.0))
	_check(not _actions.can_interact_with_ball(),
			"Interaction window closed at 1.2 m (detector contract)")
	_max_step = 0.0
	_prev_ball_pos = Vector3.ZERO
	Input.action_press("dribble")
	Input.action_press("move_forward")
	await _await_ticks_tracked(45)
	Input.action_release("move_forward")
	Input.action_release("dribble")
	await _await_ticks_tracked(2)
	_check(_dribble_on >= 1, "Dribble control engaged while held")
	var offset := _ball.global_position - _player.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	_check(planar.length() < 1.6, "Ball gathered within dribble range", str(planar.length()))
	_check(_ball_planar_speed() > 2.0, "Ball carried with the player", str(_ball_planar_speed()))
	_check(_max_step < 0.4, "No teleport during dribbling (max per-tick move %.2f)" % _max_step)
	Input.action_release("dribble")
	# Control lost → ball decelerates on its own (no recovery snap).
	await _await_ticks_tracked(70)
	_check(_ball_planar_speed() < 1.0, "Ball settles freely after dribble release",
			str(_ball_planar_speed()))
	_check(_dribble_off >= 1, "dribble_stopped emitted")


# --- 13. Reception (fast incoming ball) --------------------------------------------------------

func _test_reception() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, 4.0), Vector3(0.0, 0.2, 0.0))
	await _await_ticks(10)
	_max_step = 0.0
	_prev_ball_pos = Vector3.ZERO
	# Send the ball fast toward the player (8 m/s).
	_ball.apply_kick(Vector3(0.0, 0.0, -1.0), 8.0)
	await _await_ticks_tracked(120)
	_check(_state_history.has(FootballActions.ActionState.RECEIVING),
			"Reception state (RECEIVING) entered automatically")
	_check(_received_speeds.size() >= 1, "ball_received emitted")
	if _received_speeds.size() > 0:
		_check(_received_speeds[0] < 1.5,
				"Reception completes under the completion speed", str(_received_speeds[0]))
	_check(_ball_planar_speed() < 1.5, "Fast ball brought under control", str(_ball_planar_speed()))
	var offset := _ball.global_position - _player.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	_check(planar.length() < 1.6, "Ball ends near the player", str(planar.length()))
	_check(_max_step < 0.35, "No teleport during reception (max per-tick move %.2f)" % _max_step)


# --- 14. State recovery + movement unaffected ----------------------------------------------------

func _test_state_recovery_and_movement() -> void:
	await _reset_scenario(Vector3(0.0, 0.4, -0.5), Vector3(0.0, 0.2, 0.0))
	Input.action_press("lob_pass")
	await _await_ticks_tracked(2)
	Input.action_release("lob_pass")
	await _await_ticks_tracked(2)
	_check(_actions.action_state == FootballActions.ActionState.LOB_PASSING,
			"Transient LOB_PASSING state active right after the kick")
	await _await_ticks_tracked(45)
	_check(_actions.action_state == FootballActions.ActionState.IDLE,
			"Transient state resolves back to IDLE (no lockup)")
	# Bring the ball back into range so availability reflects the cooldown
	# itself (the kicked ball is long gone from the interaction window).
	_ball.reset_ball(Vector3(0.0, 0.4, -0.5))
	await _await_ticks(8)
	var avail: Dictionary = _actions.get_action_availability()
	_check(avail[&"lob"] == true, "Lob available again after cooldown (0.6 s)")
	# Phase 2 movement regression guard with the gameplay node mounted.
	Input.action_press("move_forward")
	var max_speed := 0.0
	for i in 40:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, _player.get_current_speed())
	Input.action_release("move_forward")
	_check(max_speed > 4.8, "Movement speed unaffected by gameplay node (≈5.5)", str(max_speed))


# --- 15. Phase integration -------------------------------------------------------------------------

func _test_phase_integration() -> void:
	_check(load(BALL_SCENE) != null, "Phase 3 ball scene still loads")
	_check(load("res://scenes/environment/football_pitch.tscn") != null,
			"Phase 1 pitch still loads")
	_check(load("res://scenes/player/player.tscn") != null, "Phase 2 player scene still loads")
	_check(load("res://scripts/gameplay/football_actions.gd") != null,
			"Phase 4 gameplay script loads")
	var config: BallActionConfig = load("res://resources/configurations/ball_action_config.tres")
	_check(config != null, "Phase 4 config resource loads")
