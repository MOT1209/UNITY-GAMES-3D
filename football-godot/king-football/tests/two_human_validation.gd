## P10: two humans in one match. A second KING CONTROLLER phone (slot 2) takes over the opposing side: its own
## intent, selected player, indicator, auto-switch and aim assist, while the first phone / keyboard keeps the
## home side. Real sockets, real match, real MatchManager seats.
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


func _until(cond: Callable) -> bool:
	for i in 40:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL - Two-human match validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	_gm = get_node("/root/GameManager")
	_server = KingControllerServer.new()
	_server.port = 17320
	_gm.add_child(_server)
	_gm.king_controller_server = _server
	_server.select_address("127.0.0.1")
	await _frames(3)
	await _test_no_second_phone()
	await _test_two_phones_before_match()
	await _test_join_and_leave_mid_match()
	await _test_no_human_match()
	await _test_teardown()
	_gm.king_controller_server = null
	_server.stop()
	_server.queue_free()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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


func _pair(name_: String) -> Dictionary:
	var peer := await _open()
	_send(peer, P.make_pairing_request(_server.token, name_))
	var slot := -1
	for i in 12:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if m is Dictionary and String(m.get("type", "")) == "paired":
				slot = int(m.get("slot", -1))
		await get_tree().physics_frame
	return {"peer": peer, "slot": slot}


func _reset_server() -> void:
	for i in 2:
		_server.revoke(i)


func _match(human_side := "home") -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.human_side = human_side
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


## Everybody except the two humans parked far away, ball in a corner, humans on their halves.
func _stage(m: MatchManager) -> void:
	var keep := [m.selected["player_id"]]
	if not m.selected2.is_empty():
		keep.append(m.selected2["player_id"])
	var park := 0
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if keep.has(e["player_id"]):
				continue
			(e["node"] as Node3D).global_position = Vector3(-40.0 + park * 2.0, 0.05, 80.0 if side == "home" else -80.0)
			(e["node"] as CharacterBody3D).velocity = Vector3.ZERO
			park += 1
	(m.selected["node"] as Node3D).global_position = Vector3(-8.0, 0.05, 10.0)
	if not m.selected2.is_empty():
		(m.selected2["node"] as Node3D).global_position = Vector3(8.0, 0.05, -10.0)
	m.ball.reset_ball(Vector3(30.0, 0.2, 0.0))


func _test_no_second_phone() -> void:
	_reset_server()
	var m := _match()
	_check(m.seat2_side() == "away", "the second human plays the side opposite to the first")
	_check(not m.seat2_active() and m.selected2.is_empty(), "no second phone -> the opposing side is plain AI")
	var ai_count := 0
	for e in m.entries["away"]:
		if e["ai"] != null:
			ai_count += 1
	_check(ai_count == (m.entries["away"] as Array).size() - 1, "every outfield away player is AI-driven (the keeper has his own logic)")
	_check(not m.human_intent2.driven, "seat 2 intent stays raw / idle")
	await _discard(m)


func _test_two_phones_before_match() -> void:
	_reset_server()
	var a := await _pair("phone 1")
	var b := await _pair("phone 2")
	_check(a["slot"] == 0 and b["slot"] == 1, "two phones pair into slots 1 and 2 (slots %d, %d)" % [a["slot"], b["slot"]])
	var c := await _pair("phone 3")
	_check(c["slot"] == -1, "a third phone is refused")
	var m := _match()
	_check(m.controller_hub.is_connected_slot(0) and m.controller_hub.is_connected_slot(1), "the hub routes both slots")
	_check(m.seat2_active(), "the second phone controls a player from kick-off")
	_check(m.selected["side"] == "home" and m.selected2["side"] == "away", "each human controls a player of his own side")
	_check(m.selected["node"].intent == m.human_intent and m.selected2["node"].intent == m.human_intent2, "separate intents are attached")
	_check(m.selected2["slot"] != 0, "the second human never takes the goalkeeper")
	_check(m.selected2["ai"] == null and m.selected["ai"] == null, "both humans' players have no AI intent")
	_check(m.selection_indicator2 != null and m.selection_indicator2.controller_slot == 1, "player 2 has his own indicator (slot colour 2)")
	_check(m.camera.mode == GameCamera.Mode.BROADCAST, "the camera frames the whole play (follow mode cannot track two players)")
	_stage(m)
	await _frames(5)
	var s1: Vector3 = (m.selected["node"] as Node3D).global_position
	var s2: Vector3 = (m.selected2["node"] as Node3D).global_position
	var seq1 := 0
	var seq2 := 0
	for i in 40:
		_send(a["peer"], P.make_input(seq1, Vector2(1, 0), ["sprint"]))
		seq1 += 1
		_send(b["peer"], P.make_input(seq2, Vector2(-1, 0), ["shoot"]))
		seq2 += 1
		await get_tree().physics_frame
	var d1: Vector3 = (m.selected["node"] as Node3D).global_position - s1
	var d2: Vector3 = (m.selected2["node"] as Node3D).global_position - s2
	_check(d1.length() > 1.0 and d2.length() > 1.0, "both humans move their own player (%.1f m / %.1f m)" % [d1.length(), d2.length()])
	_check(d1.dot(d2) < 0.0, "stick right and stick left move the two players in opposite directions")
	_check(m.human_intent.is_pressed(&"sprint") and not m.human_intent.is_pressed(&"shoot"), "player 1's buttons stay with player 1")
	_check(m.human_intent2.is_pressed(&"shoot") and not m.human_intent2.is_pressed(&"sprint"), "player 2's buttons stay with player 2")
	# independent releases
	_send(b["peer"], P.make_input(seq2, Vector2.ZERO, []))
	seq2 += 1
	await _until(func() -> bool: return not m.human_intent2.is_pressed(&"shoot"))
	_check(not m.human_intent2.is_pressed(&"shoot") and m.human_intent.is_pressed(&"sprint"), "releasing player 2's button does not touch player 1")
	# switch player 2 only
	var before1: String = m.selected["player_id"]
	var before2: String = m.selected2["player_id"]
	var mate: Dictionary = {}
	for e in m.entries["away"]:
		if e["slot"] != 0 and e["player_id"] != before2:
			mate = e
			break
	(mate["node"] as Node3D).global_position = m.ball.global_position + Vector3(1.0, 0.0, 0.0)
	_send(b["peer"], P.make_input(seq2, Vector2.ZERO, ["switch_player"]))
	seq2 += 1
	await _until(func() -> bool: return m.selected2["player_id"] != before2)
	_check(m.selected2["player_id"] != before2, "player 2's switch hands him another away player")
	_check(m.selected["player_id"] == before1, "player 1's selection is unchanged")
	_check(mate["ai"] == null and (m.entries["away"] as Array).any(func(e: Dictionary) -> bool: return e["player_id"] == before2 and e["ai"] != null), "the released away player is AI again")
	# pause by phone 2
	_send(b["peer"], P.make_input(seq2, Vector2.ZERO, ["pause"]))
	seq2 += 1
	await _until(func() -> bool: return get_tree().paused)
	_check(get_tree().paused and m.pause_menu != null, "the second phone can pause the match")
	_send(b["peer"], P.make_input(seq2, Vector2.ZERO, []))
	seq2 += 1
	await get_tree().create_timer(0.7, true, false, true).timeout
	_send(b["peer"], P.make_input(seq2, Vector2.ZERO, ["pause"]))
	for i in 12:
		await get_tree().process_frame
	_check(not get_tree().paused, "and resume it")
	a["peer"].close()
	b["peer"].close()
	c["peer"].close()
	await _frames(12)
	await _discard(m)


func _test_join_and_leave_mid_match() -> void:
	_reset_server()
	var a := await _pair("phone 1")
	var m := _match()
	_check(not m.seat2_active(), "match with one phone: the opponent is AI")
	_stage(m)
	var b := await _pair("friend")
	_check(b["slot"] == 1, "a friend's phone joins slot 2 mid-match")
	await _until(func() -> bool: return m.seat2_active())
	_check(m.seat2_active() and m.selected2["side"] == "away", "the friend takes over the opponent at once")
	_check(m.human_intent.driven and m.human_intent2.driven, "both intents are driven")
	var taken: Dictionary = m.selected2
	# friend leaves while holding sprint + stick
	var seq := 0
	for i in 10:
		_send(b["peer"], P.make_input(seq, Vector2(1, 0), ["sprint"]))
		seq += 1
		await get_tree().physics_frame
	_check(m.human_intent2.is_pressed(&"sprint"), "the friend's input reaches seat 2")
	b["peer"].close()
	await _until(func() -> bool: return not m.seat2_active())
	_check(not m.seat2_active() and m.selected2.is_empty(), "when the friend's phone drops, seat 2 is released")
	_check(taken["ai"] != null and taken["node"].intent == taken["ai"], "his player is controlled by the AI again")
	_check(not m.human_intent2.is_pressed(&"sprint") and m.human_intent2.move == Vector2.ZERO and not m.human_intent2.driven, "seat 2's buttons are released and its stick reset")
	_check(m.selection_indicator2 == null, "player 2's indicator is gone")
	_check(m.human_intent.driven and m.controller_hub.is_connected_slot(0), "player 1 is not affected")
	var p0: Vector3 = (taken["node"] as Node3D).global_position
	await _frames(40)
	_check(is_finite((taken["node"] as Node3D).global_position.x), "the released player keeps running under AI control")
	# a different friend can join again
	_server.revoke(1)
	var b2 := await _pair("friend 2")
	await _until(func() -> bool: return m.seat2_active())
	_check(m.seat2_active(), "a new friend can join again")
	# the match is not corrupted when seat 2 is released twice
	m._release_seat2()
	m._release_seat2()
	_check(not m.seat2_active(), "releasing seat 2 twice is harmless")
	a["peer"].close()
	b2["peer"].close()
	await _frames(12)
	await _discard(m)


func _test_no_human_match() -> void:
	_reset_server()
	var b := await _pair("p1")
	var c := await _pair("p2")
	var m := _match("none")
	_check(m.seat2_side() == "" and not m.seat2_active(), "a match without a human has no second seat")
	await _frames(10)
	_check(m.selected.is_empty() and m.selected2.is_empty(), "no seat is filled when nobody is human-controlled")
	b["peer"].close()
	c["peer"].close()
	await _frames(8)
	await _discard(m)


func _test_teardown() -> void:
	_reset_server()
	var a := await _pair("p1")
	var b := await _pair("p2")
	var m := _match()
	var i1 := m.human_intent
	var i2 := m.human_intent2
	_check(i1.driven and i2.driven, "both driven before teardown")
	await _discard(m)
	_check(not i1.driven and not i2.driven, "tearing the match down releases both intents")
	a["peer"].close()
	b["peer"].close()
	await _frames(8)
