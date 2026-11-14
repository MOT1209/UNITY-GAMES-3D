## P3 gameplay feel: human through passes and crosses (DLS-inspired actions).
##   godot --headless --path . res://tests/gameplay_feel_validation.tscn
## The AI already had both actions (PlayerAI.lead_point / cross_target); the
## human now drives the SAME ball systems through the new InputMap actions,
## with HumanAimAssist reusing the AI's target logic. All tests are the real
## engine, the real match and the real kick systems — no simulation.
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"
const GOAL_N := Vector3(0.0, 0.0, -52.5)   # home attacks N in the first half

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
	print("=== KING FOOTBALL — Gameplay feel validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	await _test_inputmap_bindings()
	await _test_assist_through_unit()
	await _test_assist_through_blocked()
	await _test_assist_cross_unit()
	await _test_first_touch_quality()
	await _test_match_wiring()
	await _test_human_through_kick()
	await _test_human_cross_kick()
	await _test_null_assist_fallback()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _discard(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _match(human := "home") -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 2
	setup.human_side = human
	setup.rng_seed = 11
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	return m


## Park every other entry far away so AI movement cannot disturb the stage.
func _park_others(m: MatchManager, keep: Array) -> void:
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if keep.has(e):
				continue
			(e["node"] as Node3D).global_position = Vector3(-30.0 + park * 2.5, 0.05,
					40.0 if side == "home" else -40.0)
			park += 1


## The first entry of `side` that is neither the human selection nor the keeper.
func _pick_other(m: MatchManager, hum: Dictionary, side := "home") -> Dictionary:
	for e in m.entries[side]:
		if e != hum and int(e["slot"]) != 0:
			return e
	return {}


## The two new actions exist in the project InputMap with the planned bindings.
func _test_inputmap_bindings() -> void:
	_check(InputMap.has_action("through_pass"), "through_pass action exists in the InputMap")
	_check(InputMap.has_action("cross"), "cross action exists in the InputMap")
	var through_keys := 0
	var through_buttons: Array = []
	if InputMap.has_action("through_pass"):
		for ev in InputMap.action_get_events("through_pass"):
			if ev is InputEventKey and ev.physical_keycode == KEY_R:
				through_keys += 1
			elif ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_STICK:
				through_buttons.append(ev.button_index)
	_check(through_keys == 1, "through_pass is bound to the R key")
	_check(through_buttons.has(JOY_BUTTON_RIGHT_STICK), "through_pass is bound to a gamepad button (R3)")
	var cross_keys := 0
	var cross_buttons: Array = []
	if InputMap.has_action("cross"):
		for ev in InputMap.action_get_events("cross"):
			if ev is InputEventKey and ev.physical_keycode == KEY_T:
				cross_keys += 1
			elif ev is InputEventJoypadButton:
				cross_buttons.append(ev.button_index)
	_check(cross_keys == 1, "cross is bound to the T key")
	_check(cross_buttons.has(JOY_BUTTON_MISC1) or cross_buttons.has(JOY_BUTTON_DPAD_LEFT),
			"cross is bound to a gamepad button (touchpad / dpad)", str(cross_buttons))


## Unit: the assist picks the most goal-advanced team-mate inside the aim cone
## and aims into his run (the AI's lead_point logic).
func _test_assist_through_unit() -> void:
	var assist := HumanAimAssist.new()
	var mates: Array[Vector3] = [Vector3(3.0, 0.0, -42.0), Vector3(5.0, 0.0, -10.0)]
	var opps: Array[Vector3] = [Vector3(-40.0, 0.0, 30.0)]
	assist.context = func() -> Dictionary:
		return {"teammates": mates, "opponents": opps, "goal": GOAL_N}
	var pos := Vector3(0.0, 0.0, -30.0)
	var aim := (Vector3(3.0, 0.0, -12.0)).normalized()
	var target := assist.through_target(pos, aim)
	_check(target != Vector3.INF, "through assist finds the advanced team-mate in the cone")
	if target != Vector3.INF:
		_check(target.z < -42.0, "through assist aims INTO the receiver's run (lead point)",
				str(target))
	# Aiming sideways from everyone finds nobody.
	var backward := assist.through_target(pos, Vector3(1.0, 0.0, 0.0))
	_check(backward == Vector3.INF, "through assist returns INF when the cone is empty")
	_check(assist.through_target(pos, Vector3.ZERO) == Vector3.INF,
			"through assist returns INF without an aim direction")
	_check(HumanAimAssist.new().through_target(pos, aim) == Vector3.INF,
			"through assist returns INF without a wired context")


## Unit: an opponent camped on the lead spot cancels the lead (kick to feet).
func _test_assist_through_blocked() -> void:
	var assist := HumanAimAssist.new()
	var mates: Array[Vector3] = [Vector3(3.0, 0.0, -42.0)]
	# This opponent sits exactly on the computed lead spot.
	var opps: Array[Vector3] = [Vector3(2.0, 0.0, -45.4)]
	assist.context = func() -> Dictionary:
		return {"teammates": mates, "opponents": opps, "goal": GOAL_N}
	var target := assist.through_target(Vector3(0.0, 0.0, -30.0),
			(Vector3(3.0, 0.0, -12.0)).normalized())
	_check(target != Vector3.INF and target.distance_to(Vector3(3.0, 0.0, -42.0)) < 0.5,
			"a blocked lead spot falls back to the receiver's feet", str(target))


## Unit: the cross assist finds the free box team-mate; a covered one gives INF.
func _test_assist_cross_unit() -> void:
	var assist := HumanAimAssist.new()
	var mates: Array[Vector3] = [Vector3(0.0, 0.0, -40.0)]
	assist.context = func() -> Dictionary:
		return {"teammates": mates, "opponents": [] as Array[Vector3], "goal": GOAL_N}
	var target := assist.cross_target_for(Vector3(20.0, 0.0, -38.0))
	_check(target != Vector3.INF, "cross assist finds the free team-mate in the box")
	if target != Vector3.INF:
		_check(absf(target.z - (-41.5)) < 0.4,
				"cross assist aims slightly ahead of the receiver", str(target))
	var covered := HumanAimAssist.new()
	covered.context = func() -> Dictionary:
		return {"teammates": mates,
				"opponents": [Vector3(0.0, 0.0, -39.5)] as Array[Vector3], "goal": GOAL_N}
	_check(covered.cross_target_for(Vector3(20.0, 0.0, -38.0)) == Vector3.INF,
			"a covered box team-mate gives no cross target")


## P3 first touch: attributes scale the control force, pressure degrades it.
func _test_first_touch_quality() -> void:
	# Attribute-driven control multiplier (neutral without data).
	var neutral := AttributeModifiers.new()
	_check(absf(neutral.control_multiplier() - 1.0) < 0.0001,
			"the control multiplier is neutral without player data")
	var elite := PlayerData.new()
	elite.dribbling = 99
	var poor := PlayerData.new()
	poor.dribbling = 1
	_check(AttributeModifiers.new(elite).control_multiplier() > 1.09
			and AttributeModifiers.new(elite).control_multiplier() < 1.11,
			"a 99 dribbling rating boosts the first touch",
			str(AttributeModifiers.new(elite).control_multiplier()))
	_check(AttributeModifiers.new(poor).control_multiplier() < 0.91,
			"a 1 dribbling rating degrades the first touch",
			str(AttributeModifiers.new(poor).control_multiplier()))

	# Pressure term (pure function of positions).
	var assist := HumanAimAssist.new()
	assist.context = func() -> Dictionary:
		return {"teammates": [] as Array[Vector3],
				"opponents": [Vector3(1.0, 0.0, 0.0)] as Array[Vector3], "goal": GOAL_N}
	var q := assist.pressure_quality(Vector3.ZERO)
	_check(q > HumanAimAssist.PRESSURE_FLOOR - 0.01 and q < 1.0,
			"an opponent 1 m away degrades the touch quality", str(q))
	_check(absf(assist.pressure_quality(Vector3(0.0, 0.0, 20.0)) - 1.0) < 0.0001,
			"a far opponent leaves the touch quality neutral")
	_check(absf(HumanAimAssist.new().pressure_quality(Vector3.ZERO) - 1.0) < 0.0001,
			"without a wired context the touch quality is neutral")

	# Real physics: the same ball slows faster with quality 1.0 than 0.5.
	var ball_scene: PackedScene = load("res://scenes/ball/football_ball.tscn")
	var a := ball_scene.instantiate() as BallController
	var b := ball_scene.instantiate() as BallController
	add_child(a)
	add_child(b)
	a.global_position = Vector3(0.0, 0.3, 0.0)
	b.global_position = Vector3(0.0, 0.3, 0.0)
	a.linear_velocity = Vector3(0.0, 0.0, -5.0)
	b.linear_velocity = Vector3(0.0, 0.0, -5.0)
	var host := Node3D.new()
	add_child(host)
	host.global_position = a.global_position
	var system := BallControlSystem.new()
	add_child(system)
	var cfg := BallActionConfig.new()
	for i in 12:
		await get_tree().physics_frame
		system.physics_tick(a, host, cfg, 1.0)
		system.physics_tick(b, host, cfg, 0.5)
	var speed_a := Vector3(a.linear_velocity.x, 0.0, a.linear_velocity.z).length()
	var speed_b := Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z).length()
	_check(speed_b > speed_a, "a degraded first touch lets the ball run on more",
			"q1 %.2f vs q0.5 %.2f" % [speed_a, speed_b])
	a.queue_free()
	b.queue_free()
	host.queue_free()
	system.queue_free()
	await get_tree().process_frame


## The real match wires one assist to every human selection and the context
## reads live state.
func _test_match_wiring() -> void:
	var m := _match("home")
	_check(not m.selected.is_empty(), "the match selects a human player at kick-off")
	_check(m.selected["actions"].aim_assist == m._assist,
			"the human entry carries the match aim assist")
	var ctx := m._aim_context("home")
	_check(ctx["goal"] == PitchSpace.opponent_goal(m.frame_side("home")),
			"the assist context targets the opponent goal")
	_check(ctx["teammates"].size() == m.entries["home"].size() - 1,
			"the assist context excludes the human carrier himself",
			"%d vs %d" % [ctx["teammates"].size(), m.entries["home"].size() - 1])
	var acts := m.selected["actions"] as FootballActions
	var avail: Dictionary = acts.get_action_availability()
	_check(avail.has(&"through") and avail.has(&"cross"),
			"the action availability reports the two new actions")
	await _discard(m)


## A driven through press really executes a pass-family kick with cooldown.
func _test_human_through_kick() -> void:
	var m := _match("home")
	var hum: Dictionary = m.selected
	var acts := hum["actions"] as FootballActions
	var tn := hum["node"] as CharacterBody3D
	var mate: Dictionary = _pick_other(m, hum)
	_park_others(m, [hum, mate])
	tn.global_position = Vector3(0.0, 0.05, -30.0)
	tn.velocity = Vector3.ZERO
	tn.global_rotation = Vector3.ZERO
	(mate["node"] as Node3D).global_position = Vector3(3.0, 0.05, -42.0)
	m.ball.reset_ball(Vector3(0.0, 0.2, -29.8))
	await _frames(6)
	var started := [false]
	acts.through_started.connect(func(_power: float) -> void: started[0] = true)
	m.human_intent.set_driven(true)
	m.human_intent.world_space = true
	m.human_intent.set_move(Vector2(0.0, -1.0))          # towards the goal / the mate
	m.human_intent.begin_tick()
	m.human_intent.press(&"through_pass")
	await _frames(2)
	m.human_intent.release(&"through_pass")
	await _frames(3)
	_check(started[0], "a driven through press emits through_started")
	var speed: float = m.ball.linear_velocity.length()
	_check(speed > 1.5, "the through kick really moves the ball", "speed %.2f" % speed)
	_check(acts._through_cooldown > 0.0, "the through cooldown engages after the kick")
	_check(acts.get_action_availability()[&"through"] == false,
			"the through action is unavailable during its cooldown")
	m.human_intent.set_driven(false)
	await _discard(m)


## A driven cross press really executes a lob-family kick into the box.
func _test_human_cross_kick() -> void:
	var m := _match("home")
	var hum: Dictionary = m.selected
	var acts := hum["actions"] as FootballActions
	var tn := hum["node"] as CharacterBody3D
	var mate: Dictionary = _pick_other(m, hum)
	_park_others(m, [hum, mate])
	tn.global_position = Vector3(20.0, 0.05, -38.0)      # wide in the final third
	tn.velocity = Vector3.ZERO
	tn.global_rotation = Vector3.ZERO
	(mate["node"] as Node3D).global_position = Vector3(0.0, 0.05, -40.0)  # free in the box
	# Ball 0.7 m ahead towards the goal (as when dribbling): the lob system
	# blends the kick intent with the ball-relative direction, so the ball must
	# sit on the goal side of the kicker for a goal-ward cross.
	m.ball.reset_ball(Vector3(20.0, 0.2, -38.7))
	await _frames(6)
	var started := [false]
	acts.cross_started.connect(func(_power: float, _lift: float) -> void: started[0] = true)
	m.human_intent.set_driven(true)
	m.human_intent.world_space = true
	m.human_intent.set_move(Vector2(0.0, -1.0))
	m.human_intent.begin_tick()
	m.human_intent.press(&"cross")
	await _frames(2)
	m.human_intent.release(&"cross")
	await _frames(3)
	_check(started[0], "a driven cross press emits cross_started")
	var speed: float = m.ball.linear_velocity.length()
	_check(speed > 1.5, "the cross kick really moves the ball", "speed %.2f" % speed)
	_check(acts._cross_cooldown > 0.0, "the cross cooldown engages after the kick")
	# The assist aimed into the box: the ball travels towards the goal.
	_check(m.ball.linear_velocity.z < 0.0, "the assisted cross flies towards the opponent goal",
			"vz %.2f" % m.ball.linear_velocity.z)
	m.human_intent.set_driven(false)
	await _discard(m)


## Without an assist the two actions degrade to plain directional kicks.
func _test_null_assist_fallback() -> void:
	var m := _match("home")
	var hum: Dictionary = m.selected
	var acts := hum["actions"] as FootballActions
	var tn := hum["node"] as CharacterBody3D
	_park_others(m, [hum])
	acts.aim_assist = null
	tn.global_position = Vector3(0.0, 0.05, -30.0)
	tn.velocity = Vector3.ZERO
	tn.global_rotation = Vector3.ZERO
	m.ball.reset_ball(Vector3(0.0, 0.2, -29.8))
	await _frames(6)
	var started := [false]
	acts.through_started.connect(func(_power: float) -> void: started[0] = true)
	m.human_intent.set_driven(true)
	m.human_intent.world_space = true
	m.human_intent.set_move(Vector2(0.0, -1.0))
	m.human_intent.begin_tick()
	m.human_intent.press(&"through_pass")
	await _frames(2)
	m.human_intent.release(&"through_pass")
	await _frames(3)
	_check(started[0], "a null-assist through still executes as a plain kick")
	_check(m.ball.linear_velocity.length() > 1.5, "the fallback through kick moves the ball",
			"speed %.2f" % m.ball.linear_velocity.length())
	m.human_intent.set_driven(false)
	await _discard(m)
