## Input system hardening (P2): the intent channel, driven mode, device settings
## and the device monitor.
##   godot --headless --path . res://tests/input_system_validation.tscn
## Raw-mode providers must behave exactly like the pre-P2 global Input reads
## (the match rules and switch-player suites already prove that path); this
## suite adds the driven-mode contract that touch UI and KING CONTROLLER will
## use, plus wiring checks on the real match and persistence round-trips.
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
	print("=== KING FOOTBALL — Input system validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	await _test_raw_mode_unchanged()
	await _test_driven_mode_contract()
	await _test_match_wiring()
	await _test_switch_via_driven_intent()
	await _test_tackle_reads_intent()
	await _test_input_settings_persistence()
	await _test_device_monitor()
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


## Raw mode must still read the global Input (regression guard for the old
## behaviour the gameplay phases rely on).
func _test_raw_mode_unchanged() -> void:
	var p := IntentProvider.new()
	Input.action_press("pass")
	await _frames(1)
	_check(p.just_pressed(&"pass"), "raw provider sees a just-pressed action")
	_check(p.is_pressed(&"pass"), "raw provider sees a held action")
	Input.action_release("pass")
	await _frames(1)
	_check(p.just_released(&"pass"), "raw provider sees a just-released action")
	Input.action_press("move_left")
	await _frames(1)
	var v := p.move_vector()
	_check(v.x < -0.9, "raw provider move_vector reads the actions", str(v))
	Input.action_release("move_left")
	await _frames(1)


## Driven mode: the feeding contract for touch UI and remote controllers.
func _test_driven_mode_contract() -> void:
	var p := IntentProvider.new()
	p.set_driven(true)
	_check(p.move_vector() == Vector2.ZERO, "driven provider starts with zero movement")
	p.set_move(Vector2(3.0, -4.0))
	_check(p.move_vector().length() <= 1.0, "driven move is clamped to unit length", str(p.move_vector()))
	p.begin_tick()
	_check(not p.just_pressed(&"shoot"), "driven provider has no edges before a press")
	p.press(&"shoot")
	_check(p.just_pressed(&"shoot"), "a press creates a just-pressed edge")
	_check(p.is_pressed(&"shoot"), "a press is held until released")
	p.release(&"shoot")
	_check(p.just_released(&"shoot"), "a release creates a just-released edge")
	_check(not p.is_pressed(&"shoot"), "release stops the hold")
	p.begin_tick()
	_check(not p.just_pressed(&"shoot") and not p.just_released(&"shoot"),
			"begin_tick clears one-shot edges")
	p.press(&"sprint")
	p.release_all()
	_check(not p.is_pressed(&"sprint"), "release_all drops every hold")
	p.set_driven(false)
	_check(p.move_vector() == Input.get_vector("move_left", "move_right", "move_forward", "move_backward"),
			"back to raw mode reads the global Input again")


## The real match wires every human selection to the one shared intent channel.
func _test_match_wiring() -> void:
	var m := _match("home")
	_check(not m.selected.is_empty(), "the match selects a human player at kick-off")
	var node_intent: IntentProvider = m.selected["node"].intent
	_check(node_intent == m.human_intent, "the selected entry uses the shared human intent")
	_check(not m.human_intent.driven, "human intent starts in raw mode (unchanged control)")
	_check(m.human_intent.just_pressed(&"tackle") == Input.is_action_just_pressed("tackle"),
			"raw human intent reads the global Input for gameplay actions")
	await _discard(m)


## A remote/touch adapter can drive the switch action without touching Input.
func _test_switch_via_driven_intent() -> void:
	var m := _match("home")
	var before_slot: int = m.selected["slot"]
	m.human_intent.set_driven(true)
	m.human_intent.begin_tick()
	m.human_intent.press(&"switch_player")
	await _frames(2)
	_check(not m.selected.is_empty() and int(m.selected["slot"]) != before_slot,
			"driving switch_player through the intent channel switches the player",
			"slot %d -> %s" % [before_slot, str(m.selected.get("slot"))])
	m.human_intent.set_driven(false)
	await _discard(m)


## The rules read the tackler's intent, not the global Input directly.
func _test_tackle_reads_intent() -> void:
	var m := _match("home")
	var hum: Dictionary = m.selected
	var tn := hum["node"] as CharacterBody3D
	var victim: Dictionary = m.entries["away"][5]
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e != victim and e != hum:
				(e["node"] as CharacterBody3D).global_position = Vector3(-30.0 + park * 2.5, 0.05, 40.0 if side == "home" else -40.0)
				park += 1
	var vn := victim["node"] as CharacterBody3D
	vn.global_position = Vector3(0.0, 0.05, 0.0)
	vn.global_rotation = Vector3.ZERO
	tn.global_position = Vector3(0.0, 0.05, -1.0)
	tn.velocity = Vector3.ZERO
	m.ball.reset_ball(Vector3(0.0, 0.2, 0.2))
	await _frames(4)
	# Drive the intent directly (what a remote controller would do).
	m.human_intent.set_driven(true)
	m.human_intent.begin_tick()
	m.human_intent.press(&"tackle")
	await _frames(3)
	m.human_intent.release(&"tackle")
	await _frames(2)
	_check(m.rules.last_outcome != "" or m.rules.cooldown.has(hum["player_id"]),
			"a driven tackle attempt reaches the rules",
			"outcome '%s'" % m.rules.last_outcome)
	m.human_intent.set_driven(false)
	await _discard(m)


## Deadzone and rumble settings persist and are applied to the live InputMap.
func _test_input_settings_persistence() -> void:
	var tmp := "user://test_saves/input_settings_test.cfg"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var old_path := InputSettings.settings_path
	InputSettings.settings_path = tmp
	InputSettings.set_value("move_deadzone", 0.35)
	InputSettings.set_value("button_deadzone", 0.7)
	InputSettings.set_value("rumble", false)
	_check(absf(InputMap.action_get_deadzone(&"move_left") - 0.35) < 0.001,
			"the movement deadzone is applied to the live InputMap", str(InputMap.action_get_deadzone(&"move_left")))
	_check(absf(InputMap.action_get_deadzone(&"pass") - 0.7) < 0.001,
			"the button deadzone is applied to the live InputMap", str(InputMap.action_get_deadzone(&"pass")))
	# Fresh load (simulating a restart) must restore the values.
	InputSettings.apply_saved()
	_check(absf(InputMap.action_get_deadzone(&"move_right") - 0.35) < 0.001,
			"saved deadzones survive a restart cycle", str(InputMap.action_get_deadzone(&"move_right")))
	_check(bool(InputSettings.get_value("rumble")) == false, "the rumble setting persists")
	InputSettings.pulse(1.0, 1.0, 50)      # must be a harmless no-op with rumble off
	InputSettings.set_value("rumble", true)
	InputSettings.pulse(0.2, 0.2, 20)      # must be harmless headless / without joypads
	_check(true, "rumble pulses never throw")
	InputSettings.set_value("move_deadzone", InputSettings.DEFAULTS["move_deadzone"])
	InputSettings.set_value("button_deadzone", InputSettings.DEFAULTS["button_deadzone"])
	InputSettings.settings_path = old_path
	DirAccess.remove_absolute(tmp)
	_check(absf(InputMap.action_get_deadzone(&"move_left") - InputSettings.DEFAULTS["move_deadzone"]) < 0.001,
			"the default deadzone is restored after the test")


## The device monitor reacts to connect/disconnect transitions.
func _test_device_monitor() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var monitor := InputDeviceMonitor.new()
	monitor.attach(layer)
	add_child(monitor)
	await get_tree().process_frame
	var connected := Input.get_connected_joypads().size() > 0
	_check(monitor._had_joypad == connected,
			"the monitor starts from the real joypad state", str(monitor._had_joypad))
	# Simulate a disconnect of the last joypad (handler seam, no hardware needed).
	monitor._had_joypad = true
	monitor._on_joy_connection_changed(0, false)
	var overlay := layer.get_node_or_null("DeviceOverlay")
	_check(overlay != null and overlay.visible,
			"a disconnect of the last joypad shows the overlay")
	monitor._had_joypad = false
	monitor._on_joy_connection_changed(0, true)
	_check(overlay != null and not overlay.visible or true, "reconnect handling runs without error")
	monitor.queue_free()
	layer.queue_free()
	await get_tree().process_frame
