## KING CONTROLLER (P9): the phone against the REAL match. A real KingControllerServer (real sockets) is
## shared through GameManager exactly like the pairing screen does it; a real MatchManager is built; a
## WebSocketPeer client plays the part of the phone page. Checks: pair-before-match wiring, the stick really
## moves the player in the same direction as the keyboard, buttons reach the intent, pause / resume through the
## match-control path, input dropped while paused, disconnect releases everything and hands the intent back to
## keyboard / gamepad, no routing for unsupported slots, and the pairing screen mirrors the real server state.
extends Node

const P = preload("res://scripts/systems/controller/controller_protocol.gd")
const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

var _passed := 0
var _failed := 0
var _gm: Node
var _server: KingControllerServer
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL - Controller gameplay validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	_gm = get_node("/root/GameManager")
	_server = KingControllerServer.new()
	_server.port = 17300
	_gm.add_child(_server)
	_gm.king_controller_server = _server
	_server.select_address("127.0.0.1")
	await _frames(3)
	await _test_pair_before_match_and_movement()
	await _test_buttons_and_unsupported_slot()
	await _test_pause_resume()
	await _test_disconnect_returns_control()
	await _test_pairing_screen()
	_gm.king_controller_server = null
	_server.stop()
	_server.queue_free()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Waits (at most 30 physics frames) for a condition produced by the network path.
func _until(cond: Callable) -> bool:
	for i in 30:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _open() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	peer.connect_to_url("ws://127.0.0.1:%d/" % (_server.port + 1))
	for i in 200:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await get_tree().physics_frame
	return peer


func _send(peer: WebSocketPeer, msg: Dictionary) -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(msg))


func _read(peer: WebSocketPeer, frames: int) -> Array:
	var msgs: Array = []
	for i in frames:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var p: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if p is Dictionary:
				msgs.append(p)
		await get_tree().physics_frame
	return msgs


func _pair() -> WebSocketPeer:
	_server.revoke(0)           # the previous test's phone: the user pressed "disconnect" on the PC
	var peer := await _open()
	_send(peer, P.make_pairing_request(_server.token, "gameplay phone"))
	var msgs := await _read(peer, 10)
	var ok := false
	for m in msgs:
		ok = ok or String(m.get("type", "")) == "paired"
	_check(ok, "phone paired")
	return peer


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


func _discard(m: MatchManager) -> void:
	get_tree().paused = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


func _park_others(m: MatchManager) -> void:
	var hum: Dictionary = m.selected
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e == hum:
				continue
			(e["node"] as Node3D).global_position = Vector3(-30.0 + park * 2.5, 0.05, 40.0 if side == "home" else -40.0)
			park += 1


func _place(m: MatchManager) -> CharacterBody3D:
	var tn := m.selected["node"] as CharacterBody3D
	_park_others(m)
	tn.global_position = Vector3(0.0, 0.05, 0.0)
	tn.velocity = Vector3.ZERO
	m.ball.reset_ball(Vector3(15.0, 0.2, 15.0))
	return tn


## The phone paired on the menu BEFORE the match exists (the normal flow): the match must pick it up.
func _test_pair_before_match_and_movement() -> void:
	var peer := await _pair()
	var m := _match()
	_check(m.controller_hub != null and m.controller_hub.is_connected_slot(0), "a phone paired before the match is wired to it")
	_check(m.human_intent.driven, "the shared human intent is in driven mode while the phone is connected")
	_check(m._touch == null or not m._touch.active, "the on-screen touch layer stays off while the phone drives")
	var tn := _place(m)
	await _frames(5)
	var start := tn.global_position
	var seq := 0
	# stick UP (screen convention up = -1)
	for i in 40:
		_send(peer, P.make_input(seq, Vector2(0, -1), []))
		seq += 1
		await get_tree().physics_frame
	_check(m.human_intent.move_vector().y < -0.9, "stick up arrives as move.y = -1 in the intent", str(m.human_intent.move_vector()))
	var phone_move := tn.global_position - start
	_check(phone_move.length() > 1.0, "the phone really moves the player (%.2f m)" % phone_move.length())
	# release and compare with the keyboard's move_forward
	_send(peer, P.make_input(seq, Vector2.ZERO, []))
	seq += 1
	await _frames(40)
	peer.close()
	await _frames(15)
	_check(not m.human_intent.driven, "closing the phone returns the intent to keyboard / gamepad")
	tn = _place(m)
	await _frames(5)
	var start2 := tn.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	var key_move := tn.global_position - start2
	_check(key_move.length() > 1.0, "keyboard still drives the player after the phone is gone (%.2f m)" % key_move.length())
	var dir_dot := phone_move.normalized().dot(key_move.normalized())
	_check(dir_dot > 0.95, "stick up moves the player the same way as keyboard forward (dot %.3f)" % dir_dot)
	await _discard(m)


func _test_buttons_and_unsupported_slot() -> void:
	var peer := await _pair()
	var m := _match()
	var ip := m.human_intent
	var seq := 0
	var map := {"sprint": &"sprint", "tackle": &"tackle", "switch_player": &"switch_player", "pass": &"pass",
			"shoot": &"shoot", "lob_pass": &"lob_pass", "through_pass": &"through_pass", "cross": &"cross"}
	for a in map.keys():
		_send(peer, P.make_input(seq, Vector2.ZERO, [a]))
		seq += 1
		var got := await _until(func() -> bool: return ip.is_pressed(map[a]))
		_check(got, "phone button %s reaches the intent" % a)
		_send(peer, P.make_input(seq, Vector2.ZERO, []))
		seq += 1
		var gone := await _until(func() -> bool: return not ip.is_pressed(map[a]))
		_check(gone, "phone button %s releases" % a)
	_send(peer, P.make_input(seq, Vector2.ZERO, ["pause"]))
	seq += 1
	await _frames(3)
	for a in map.values():
		_check(not ip.is_pressed(a), "pause did not press the player action %s" % a)
	_send(peer, P.make_input(seq, Vector2.ZERO, []))
	if m.pause_menu != null:
		m.resume_match()
	# slot routing: a controller event for a slot without a provider is dropped, never routed
	var dropped := m.controller_hub.dropped_unrouted
	m.controller_hub._on_input(1, Vector2(1, 0), [&"shoot"], [])
	_check(m.controller_hub.dropped_unrouted == dropped + 1 and not ip.is_pressed(&"shoot"), "input for an unsupported slot is dropped, not applied to the player")
	peer.close()
	await _frames(10)
	await _discard(m)


func _test_pause_resume() -> void:
	var peer := await _pair()
	var m := _match()
	var seq := 0
	_check(not get_tree().paused and m.pause_menu == null, "match starts unpaused")
	_send(peer, P.make_input(seq, Vector2.ZERO, ["pause"]))
	seq += 1
	await _frames(5)
	_check(get_tree().paused and m.pause_menu != null, "the phone's Pause really pauses the match and opens the pause menu")
	# release, then keep talking while paused: the server must keep running (PROCESS_MODE_ALWAYS)
	_send(peer, P.make_input(seq, Vector2.ZERO, []))
	seq += 1
	_send(peer, P.make_input(seq, Vector2.ZERO, ["shoot"]))
	seq += 1
	await _frames(5)
	_check(not m.human_intent.is_pressed(&"shoot"), "a button tapped while the match is paused does not fire when it resumes")
	_send(peer, P.make_input(seq, Vector2.ZERO, []))
	seq += 1
	await get_tree().create_timer(0.7, true, false, true).timeout
	_send(peer, P.make_input(seq, Vector2.ZERO, ["pause"]))
	seq += 1
	for i in 10:
		await get_tree().process_frame
	_check(not get_tree().paused and m.pause_menu == null, "Pause again resumes the match (server polls while paused)")
	_send(peer, P.make_input(seq, Vector2.ZERO, []))
	# no pause when the match is finished
	m.state.phase = MatchState.Phase.FINISHED
	_check(not m.toggle_pause_from_controller(), "pause is refused once the match is finished")
	peer.close()
	await _frames(10)
	await _discard(m)


func _test_disconnect_returns_control() -> void:
	var peer := await _pair()
	var m := _match()
	var tn := _place(m)
	var seq := 0
	for i in 10:
		_send(peer, P.make_input(seq, Vector2(1, 0), ["sprint", "pass"]))
		seq += 1
		await get_tree().physics_frame
	_check(m.human_intent.is_pressed(&"sprint") and m.human_intent.move_vector().x > 0.9, "sprint + stick right are active")
	peer.close()                                  # the phone vanishes while holding buttons
	await _frames(15)
	_check(not m.human_intent.is_pressed(&"sprint") and not m.human_intent.is_pressed(&"pass"), "held buttons are released at once on disconnect")
	_check(m.human_intent.move == Vector2.ZERO and not m.human_intent.driven, "stick reset and intent back to raw input")
	var before := tn.global_position
	await _frames(30)
	_check(tn.global_position.distance_to(before) < 0.6, "the player does not keep running after the phone disconnects (%.2f m)" % tn.global_position.distance_to(before))
	# the same slot can be reclaimed: reconnect = a new pairing after the old session is removed
	_server.revoke(0)
	var peer2 := await _pair()
	_check(m.controller_hub.is_connected_slot(0) and m.human_intent.driven, "a later phone connection drives the running match again")
	peer2.close()
	await _frames(10)
	await _discard(m)
	# leaving the match while a phone is connected must not leave the provider driven
	var peer3: WebSocketPeer = null
	_server.revoke(0)
	peer3 = await _pair()
	var m2 := _match()
	var ip2 := m2.human_intent
	_check(ip2.driven, "second match picks the phone up as well")
	await _discard(m2)
	_check(not ip2.driven, "a match that is torn down releases driven mode")
	peer3.close()
	await _frames(10)
	_server.revoke(0)


func _test_pairing_screen() -> void:
	_server.start() if not _server.running else null
	var ps := PairingScreen.new()
	add_child(ps)
	await _frames(3)
	_check(ps.server == _server, "the pairing screen shows the shared server (no second server)")
	_check(ps._qr.texture != null, "a QR code is rendered for the real pairing URL")
	_check(ps._url.text.contains("127.0.0.1:%d" % _server.port) and ps._url.text.contains(_server.token), "the screen shows the real URL with the current token")
	var slot_rows := ps._slots_box.get_child_count()
	_check(slot_rows == 4, "four slot rows are listed")
	var unsupported := 0
	for i in range(1, 4):
		var l := (ps._slots_box.get_child(i) as Control).get_child(0) as Label
		if l.text == Loc.f("PAIR_SLOT_UNSUPPORTED", [i + 1]):
			unsupported += 1
	_check(unsupported == 3, "slots 2-4 are shown as not supported in this version")
	_check(ps._status.text.contains("0") and ps._status.text.contains(str(_server.port)), "status shows the connected count and the ports")
	# connect a phone: the screen follows the real server
	var old_token := _server.token
	var peer := await _pair()
	await _frames(5)
	_check(ps._status.text.contains("1"), "the screen shows one connected device")
	var first_row := (ps._slots_box.get_child(0) as Control)
	_check(first_row.get_child_count() == 2 and first_row.get_child(1) is Button, "the connected slot has a disconnect button")
	_check(_server.token != old_token and ps._url.text.contains(_server.token), "the code is regenerated after a pairing and the screen shows the new one")
	# regenerate
	var t1 := _server.token
	ps._on_regen()
	await _frames(2)
	_check(_server.token != t1 and ps._url.text.contains(_server.token), "the new-code button issues a new token and QR")
	# revoke from the screen
	ps._on_revoke(0)
	await _frames(6)
	_check(_server.registry.connected_count() == 0, "the screen's disconnect button revokes the controller")
	_check(ps._status.text.contains("0"), "the screen reflects the revoke")
	# closing the screen does not stop the server
	var running_before := _server.running
	ps.queue_free()
	await _frames(3)
	_check(running_before and _server.running and is_instance_valid(_server), "closing the pairing screen does not stop the server")
	var peer2 := await _pair()
	_check(_server.registry.connected_count() == 1, "pairing still works after the screen was closed")
	# reopening shows the connected device and does not create a second server
	var ps2 := PairingScreen.new()
	add_child(ps2)
	await _frames(3)
	_check(ps2.server == _server and ps2._status.text.contains("1"), "reopening the screen shows the live connection")
	# stop button
	ps2._on_toggle()
	await _frames(3)
	_check(not _server.running and ps2._problem.visible, "stopping from the screen stops the server and says so")
	ps2._on_toggle()
	await _frames(3)
	_check(_server.running and not ps2._problem.visible, "starting again from the screen works")
	ps2.queue_free()
	peer.close()
	peer2.close()
	await _frames(5)
