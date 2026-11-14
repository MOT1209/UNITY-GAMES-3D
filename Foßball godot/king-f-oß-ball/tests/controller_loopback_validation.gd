## P5 KING CONTROLLER: real loopback integration test.
extends Node

var _passed := 0
var _failed := 0
var _server: KingControllerServer
var _port := 17250
var _inputs: Array = []
var _disconnected_seen := false


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


func _wait_until(cond: Callable, max_frames: int = 200) -> bool:
	for i in range(max_frames):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _ready() -> void:
	print("=== KING FOOTBALL — Controller loopback validation ===")
	await get_tree().process_frame
	_server = KingControllerServer.new()
	_server.port = _port
	add_child(_server)
	await _frames(3)
	_server.input_received.connect(func(slot, move, press, release):
		_inputs.append({"slot": slot, "move": move, "press": press, "release": release}))
	await _test_ws_pair_and_input()
	await _test_bad_token()
	await _test_stale_seq()
	await _test_disconnect_reconnect()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	if _server != null:
		_server.stop()
	get_tree().quit(1 if _failed > 0 else 0)


func _ws_connect() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	var err := peer.connect_to_url("ws://127.0.0.1:%d/" % (_port + 1))
	_check(err == OK, "WS client connect_to_url ok")
	var opened := false
	for i in range(200):
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			opened = true
			break
		await get_tree().physics_frame
	_check(opened, "WS connection opened")
	return peer


func _ws_read(peer: WebSocketPeer, max_frames: int = 60) -> Array:
	var msgs: Array = []
	for i in range(max_frames):
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var pkt := peer.get_packet()
			var txt := pkt.get_string_from_utf8()
			if not txt.begins_with("{"):
				continue
			var p = JSON.parse_string(txt)
			if p is Dictionary:
				msgs.append(p)
		if msgs.size() > 0:
			break
		await get_tree().physics_frame
	return msgs


func _test_ws_pair_and_input() -> void:
	var peer := await _ws_connect()
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"v": 1, "type": "pair", "token": _server.token, "name": "testphone"}))
	var msgs := await _ws_read(peer, 100)
	var paired := false
	var slot := -1
	for m in msgs:
		if String(m.get("type", "")) == "paired":
			paired = true
			slot = int(m.get("slot", -1))
	_check(paired, "pairing succeeded")
	_check(slot == 0, "assigned slot 0")
	var before := _inputs.size()
	peer.send_text(JSON.stringify({"v": 1, "type": "input", "seq": 1, "move": {"x": 0.5, "y": 0.0}, "press": ["pass"], "release": [], "t": Time.get_ticks_msec()}))
	await _frames(5)
	_check(_inputs.size() == before + 1, "input received by server (count %d->%d)" % [before, _inputs.size()])
	if _inputs.size() > before:
		var last = _inputs[_inputs.size() - 1]
		_check(int(last["slot"]) == 0, "input slot 0")
		_check(abs(float(last["move"].x) - 0.5) < 0.01, "input move x=0.5")
		_check(last["press"].has("pass"), "input press pass")
	await _frames(3)
	peer.close()
	await _frames(5)


func _test_bad_token() -> void:
	var peer := await _ws_connect()
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"v": 1, "type": "pair", "token": "WRONGTOKEN", "name": "x"}))
	var msgs := await _ws_read(peer, 100)
	var failed := false
	var reason := ""
	for m in msgs:
		if String(m.get("type", "")) == "pair_fail":
			failed = true
			reason = String(m.get("reason", ""))
	_check(failed, "bad token -> pair_fail")
	_check(reason == "bad_token", "reason bad_token (got %s)" % reason)
	peer.close()
	await _frames(3)


func _test_stale_seq() -> void:
	var peer := await _ws_connect()
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"v": 1, "type": "pair", "token": _server.token, "name": "x2"}))
	await _ws_read(peer, 100)
	peer.send_text(JSON.stringify({"v": 1, "type": "input", "seq": 10, "move": {"x": 0.0, "y": 0.0}, "press": [], "release": [], "t": Time.get_ticks_msec()}))
	await _frames(3)
	var before := _inputs.size()
	peer.send_text(JSON.stringify({"v": 1, "type": "input", "seq": 10, "move": {"x": 0.0, "y": 0.0}, "press": [], "release": [], "t": Time.get_ticks_msec()}))
	await _frames(3)
	_check(_inputs.size() == before, "stale seq not counted (ignored)")
	peer.close()
	await _frames(3)


func _test_disconnect_reconnect() -> void:
	var peer := await _ws_connect()
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify({"v": 1, "type": "pair", "token": _server.token, "name": "x3"}))
	await _ws_read(peer, 100)
	_disconnected_seen = false
	var cb := func(slot): _disconnected_seen = true
	_server.client_disconnected.connect(cb, CONNECT_ONE_SHOT)
	peer.close()
	for i in range(200):
		if _disconnected_seen:
			break
		await get_tree().physics_frame
	_check(_disconnected_seen, "disconnect emits client_disconnected")
	var peer2 := await _ws_connect()
	if peer2.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer2.send_text(JSON.stringify({"v": 1, "type": "pair", "token": _server.token, "name": "x3"}))
	var msgs := await _ws_read(peer2, 100)
	var recon_slot := -1
	for m in msgs:
		if String(m.get("type", "")) == "paired":
			recon_slot = int(m.get("slot", -1))
	_check(recon_slot == 0, "reconnect re-binds slot 0 (got %d)" % recon_slot)
	peer2.close()
	await _frames(3)