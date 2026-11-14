## P4 mobile foundations: the virtual joystick + touch buttons drive the SAME
## shared human `IntentProvider` as the keyboard/gamepad, in driven mode, with
## one clean edge per physics tick. All checks run the real engine and the real
## match — no simulated input layer.
##   godot --headless --path . res://tests/mobile_input_validation.tscn
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

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
	print("=== KING FOOTBALL — Mobile input validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	await _test_joystick_conventions()
	await _test_touch_layer_edges()
	await _test_match_wiring()
	await _test_match_kick_via_touch()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _discard(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _match() -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 2
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


## The stick's screen convention matches the keyboard move actions exactly
## (Input.get_vector: +x right, −y forward), length clamped, release resets.
func _test_joystick_conventions() -> void:
	var stick := TouchJoystick.new(90.0)
	# Drag straight up: local point one full radius above the base centre.
	stick._update_output(Vector2(90.0, 90.0 - 180.0))
	_check(stick.output.distance_to(Vector2(0.0, -1.0)) < 0.001,
			"dragging up yields (0, -1) like move_forward", str(stick.output))
	# Drag right.
	stick._update_output(Vector2(270.0, 90.0))
	_check(stick.output.distance_to(Vector2(1.0, 0.0)) < 0.001,
			"dragging right yields (1, 0) like move_right", str(stick.output))
	# An overshoot far outside the base is clamped, not rejected.
	stick._update_output(Vector2(90.0 + 400.0, 90.0))
	_check(stick.output.distance_to(Vector2(1.0, 0.0)) < 0.001,
			"an overshoot drag clamps to unit length", str(stick.output))
	stick.release()
	_check(stick.output == Vector2.ZERO, "releasing the stick zeroes the output")
	# Diagonal keeps full unit length.
	stick._update_output(Vector2(90.0 + 180.0, 90.0 - 180.0))
	_check(absf(stick.output.length() - 1.0) < 0.001,
			"a diagonal drag is clamped to unit length", str(stick.output))
	stick.free()


## Buttons queue edges; one physics tick applies them exactly once; the stick
## feeds move every tick; set_active toggles the driven flag.
func _test_touch_layer_edges() -> void:
	var tc := TouchControls.new()
	add_child(tc)
	var intent := IntentProvider.new()
	tc.attach(intent)
	_check(not tc.active and not intent.driven,
			"without a touchscreen the layer stays inert (desktop behaviour)")
	tc.set_active(true)
	_check(tc.active and intent.driven, "set_active(true) switches the intent to driven mode")
	_check(intent.is_pressed(&"pass") == false, "nothing is held before any button input")
	# Stick up → move (0, -1) after one full physics tick (physics_frame fires
	# at the START of a tick, before the layer's _physics_process applies it).
	tc._joystick._update_output(Vector2(90.0, 90.0 - 180.0))
	await _frames(2)
	_check(intent.move_vector().distance_to(Vector2(0.0, -1.0)) < 0.001,
			"the stick output reaches the intent as the move vector",
			str(intent.move_vector()))
	# A queued press becomes a held action and exactly one pressed edge.
	tc.test_press(&"pass")
	await _frames(1)
	_check(intent.is_pressed(&"pass"), "a queued press holds the action")
	# Second tick: still held, no new pressed edge.
	await _frames(1)
	_check(not intent._pressed_edge.get(&"pass", false),
			"the pressed edge is consumed exactly once")
	# Release.
	tc.test_release(&"pass")
	await _frames(1)
	_check(not intent.is_pressed(&"pass"), "a queued release drops the action")
	# Deactivate clears held state and driven mode.
	tc.set_active(false)
	_check(not intent.driven, "set_active(false) leaves driven mode")
	_check(intent.move == Vector2.ZERO, "deactivation zeroes the move vector")
	tc.queue_free()
	await get_tree().process_frame


## The real match owns one TouchControls wired to human_intent; the pause
## button is wired exactly once; forced activation drives gameplay.
func _test_match_wiring() -> void:
	var m := _match()
	_check(m._touch != null, "the match owns a touch layer")
	_check(m._touch.intent == m.human_intent, "the touch layer feeds the shared human intent")
	_check(not m._touch.active, "the touch layer is inert without touch hardware")
	_check(m._touch.pause_pressed.get_connections().size() == 1,
			"the touch pause button is wired exactly once")
	_check(m._touch.BUTTON_ACTIONS.has(&"through_pass") and m._touch.BUTTON_ACTIONS.has(&"cross"),
			"the P3 kick actions have touch buttons")
	# Forced activation drives the real gameplay intent (the entry shares it).
	m._touch.set_active(true)
	_check(m.human_intent.driven, "activating the touch layer switches the match intent")
	var hum: Dictionary = m.selected
	_check(hum["node"].intent == m.human_intent, "the selected player still reads the shared intent")
	m._touch.set_active(false)
	_check(not m.human_intent.driven, "deactivating returns the intent to raw input")
	await _discard(m)


## End to end: a touch button press/release really charges and kicks the ball.
func _test_match_kick_via_touch() -> void:
	var m := _match()
	var hum: Dictionary = m.selected
	var acts := hum["actions"] as FootballActions
	var tn := hum["node"] as CharacterBody3D
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e == hum:
				continue
			(e["node"] as Node3D).global_position = Vector3(-30.0 + park * 2.5, 0.05,
					40.0 if side == "home" else -40.0)
			park += 1
	tn.global_position = Vector3(0.0, 0.05, -30.0)
	tn.velocity = Vector3.ZERO
	tn.global_rotation = Vector3.ZERO
	m.ball.reset_ball(Vector3(0.0, 0.2, -29.8))
	await _frames(6)
	m._touch.set_active(true)
	var started := [false]
	acts.pass_started.connect(func(_power: float) -> void: started[0] = true)
	# Tap: press + release queued, edges land one tick apart at worst.
	m._touch.test_press(&"pass")
	await _frames(2)
	_check(acts._pass_charge.is_charging() or started[0],
			"a touch press charges (or quick-taps) the pass action")
	m._touch.test_release(&"pass")
	await _frames(3)
	_check(started[0], "the touch release executes the pass")
	_check(m.ball.linear_velocity.length() > 1.5, "the touch pass really moves the ball",
			"speed %.2f" % m.ball.linear_velocity.length())
	_check(acts._pass_cooldown > 0.0, "the pass cooldown engages after a touch pass")
	m._touch.set_active(false)
	await _discard(m)
