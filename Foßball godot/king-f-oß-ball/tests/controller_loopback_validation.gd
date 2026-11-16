## KING CONTROLLER (P9): real loopback integration test. A real KingControllerServer listens on real TCP ports;
## the test talks to it with real WebSocketPeer / StreamPeerTCP clients exactly like the phone page does.
## (This is a LOCAL loopback test, not a phone test: real-device status is documented separately.)
extends Node

const P = preload("res://scripts/systems/controller/controller_protocol.gd")

var _passed := 0
var _failed := 0
var _server: KingControllerServer
var _port := 17250
var _inputs: Array = []
var _pauses := 0
var _connected_events: Array = []
var _lost_events: Array = []


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
	print("=== KING FOOTBALL - Controller loopback validation ===")
	await get_tree().process_frame
	_server = KingControllerServer.new()
	_server.port = _port
	_server.max_slots = 1               # these checks are about one slot; two slots are tested in controller_gameplay_validation
	add_child(_server)
	_server.select_address("127.0.0.1")
	await _frames(3)
	_server.input_received.connect(func(slot: int, move: Vector2, press: Array, release: Array) -> void:
		_inputs.append({"slot": slot, "move": move, "press": press, "release": release}))
	_server.pause_requested.connect(func(_slot: int) -> void: _pauses += 1)
	_server.client_connected.connect(func(slot: int) -> void: _connected_events.append(slot))
	_server.client_disconnected.connect(func(slot: int) -> void: _lost_events.append(slot))

	await _test_http_page()
	await _test_pair_and_browser_input()
	await _test_pause()
	await _test_view()
	await _test_rejections()
	await _test_second_device_and_resume()
	await _test_revoke()
	await _test_bye_and_disconnect_cleanup()
	await _test_heartbeat_timeout()
	await _test_stop_start()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	_server.stop()
	get_tree().quit(1 if _failed > 0 else 0)


# --- helpers ---------------------------------------------------------------------------------------

func _open() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	peer.connect_to_url("ws://127.0.0.1:%d/" % (_server.port + 1))
	for i in 200:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await get_tree().physics_frame
	return peer


func _send(peer: WebSocketPeer, msg: Variant) -> void:
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(msg if msg is String else JSON.stringify(msg))


## Collects the JSON messages the server sent within `frames` frames.
func _read(peer: WebSocketPeer, frames: int = 20) -> Array:
	var msgs: Array = []
	for i in frames:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var p: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if p is Dictionary:
				msgs.append(p)
		await get_tree().physics_frame
	return msgs


func _has(msgs: Array, type: String) -> Dictionary:
	for m in msgs:
		if String(m.get("type", "")) == type:
			return m
	return {}


func _pair(device: String = "test phone") -> Dictionary:
	var peer := await _open()
	_send(peer, P.make_pairing_request(_server.token, device))
	var msgs := await _read(peer, 12)
	var paired := _has(msgs, "paired")
	return {"peer": peer, "paired": paired, "msgs": msgs}


func _closed(peer: WebSocketPeer, frames: int = 120) -> bool:
	for i in frames:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return true
		await get_tree().physics_frame
	return peer.get_ready_state() == WebSocketPeer.STATE_CLOSED


func _http_get(path: String) -> String:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _server.port)
	var out := PackedByteArray()
	var sent := false
	for i in 200:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			tcp.put_data(("GET %s HTTP/1.1\r\nHost: x\r\n\r\n" % path).to_utf8_buffer())
			sent = true
		if sent:
			var n := tcp.get_available_bytes()
			if n > 0:
				out.append_array(tcp.get_data(n)[1])
			if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
		await get_tree().physics_frame
	tcp.disconnect_from_host()
	return out.get_string_from_utf8()


# --- tests -----------------------------------------------------------------------------------------

func _test_http_page() -> void:
	var r := await _http_get("/?t=" + _server.token)
	_check(r.begins_with("HTTP/1.1 200"), "HTTP server answers 200 for the controller page")
	_check(r.contains("KING CONTROLLER"), "page content is the controller page")
	_check(r.contains(str(_server.port + 1)) and not r.contains("__WS_PORT__"), "WebSocket port is injected into the page")
	_check(r.contains("through_pass") and r.contains("rtl"), "page carries the i18n / RTL support")
	_check(r.contains("Cache-Control: no-store"), "page is served with no-store (token in URL)")
	var nf := await _http_get("/secret")
	_check(nf.begins_with("HTTP/1.1 404"), "unknown path is 404")
	var trav := await _http_get("/../../etc/passwd")
	_check(not trav.contains("root:"), "path traversal does not serve files")


func _test_pair_and_browser_input() -> void:
	var before_conn := _connected_events.size()
	var r := await _pair("Pixel test")
	var peer: WebSocketPeer = r["peer"]
	var paired: Dictionary = r["paired"]
	_check(not paired.is_empty(), "pairing with the one-time token succeeds")
	_check(int(paired.get("slot", -1)) == 0, "assigned slot 0")
	_check(int(paired.get("v", 0)) == P.PROTOCOL_VERSION, "reply carries the current protocol version (v3)")
	_check(P.is_session_text(str(paired.get("session", ""))), "a separate session credential is issued")
	_check(str(paired.get("session", "")) != _server.token, "session credential differs from the pairing token")
	_check(_connected_events.size() == before_conn + 1, "client_connected emitted once")
	_check(_server.registry.connected_count() == 1, "registry shows one connected controller")
	# Browser-style packet: Date.now() as t (the old protocol rejected exactly this)
	var n := _inputs.size()
	_send(peer, P.make_input(0, Vector2(0.5, -0.5), ["pass"], 1794721201371))
	await _frames(4)
	_check(_inputs.size() == n + 1, "browser-style input (with a huge Date.now() t) is accepted")
	if _inputs.size() > n:
		var last: Dictionary = _inputs[_inputs.size() - 1]
		_check(int(last["slot"]) == 0 and absf(last["move"].x - 0.5) < 0.01 and absf(last["move"].y + 0.5) < 0.01, "move arrives unchanged in screen convention")
		_check((last["press"] as Array).has(&"pass"), "pass arrives as a press edge")
	var n2 := _inputs.size()
	_send(peer, P.make_input(1, Vector2(0.5, -0.5), ["pass"]))      # same state again: no new edge
	await _frames(3)
	_check(_inputs.size() == n2, "an unchanged state produces no new edge")
	_send(peer, P.make_input(2, Vector2.ZERO, []))
	await _frames(3)
	var rel: Dictionary = _inputs[_inputs.size() - 1]
	_check((rel["release"] as Array).has(&"pass") and rel["move"] == Vector2.ZERO, "releasing yields a release edge and a centred stick")
	var n3 := _inputs.size()
	_send(peer, P.make_input(2, Vector2(1, 0), ["shoot"]))
	_send(peer, P.make_input(1, Vector2(1, 0), ["shoot"]))
	await _frames(4)
	_check(_inputs.size() == n3, "duplicate and out-of-order sequence numbers are ignored")
	_send(peer, P.make_ping(7))
	var msgs := await _read(peer, 6)
	var pong := _has(msgs, "pong")
	_check(not pong.is_empty() and int(pong.get("seq", -1)) == 7, "ping is answered with pong (same seq)")
	_send(peer, P.make_bye())
	await _closed(peer)
	await _frames(3)


func _test_pause() -> void:
	var r := await _pair("pause phone")
	var peer: WebSocketPeer = r["peer"]
	var n_inputs := _inputs.size()
	var p0 := _pauses
	_send(peer, P.make_input(0, Vector2.ZERO, ["pause"]))
	await _frames(3)
	_check(_pauses == p0 + 1, "pause arrives as a dedicated pause request")
	_check(_inputs.size() == n_inputs, "pause never produces a player input edge")
	_send(peer, P.make_input(1, Vector2.ZERO, ["pause"]))
	await _frames(3)
	_check(_pauses == p0 + 1, "holding pause does not repeat the request")
	_send(peer, P.make_input(2, Vector2.ZERO, []))
	_send(peer, P.make_input(3, Vector2.ZERO, ["pause"]))
	await _frames(3)
	_check(_pauses == p0 + 1, "a second pause press inside the debounce window is ignored")
	await get_tree().create_timer(0.7).timeout
	_send(peer, P.make_input(4, Vector2.ZERO, []))
	_send(peer, P.make_input(5, Vector2.ZERO, ["pause"]))
	await _frames(4)
	_check(_pauses == p0 + 2, "a later press is a new pause request")
	_send(peer, P.make_bye())
	await _closed(peer)
	await _frames(3)


func _test_view() -> void:
	## Phase 2: the `view` message routes into the session and the PC is told which screen is open.
	var views: Array = []
	var handler := func(slot: int, view: String, on: bool) -> void: views.append({"slot": slot, "view": view, "on": on})
	_server.view_changed.connect(handler)
	var a := await _pair("view phone")
	var peer: WebSocketPeer = a["peer"]
	_check(not (a["paired"] as Dictionary).is_empty(), "paired for the view test")
	_send(peer, P.make_view("dashboard", true))
	await _frames(4)
	var s := _server.registry.sessions[0]
	_check(s != null and s.current_view == "dashboard", "an open dashboard is stored in the session")
	_check(views.size() == 1 and int(views[0]["slot"]) == 0 and str(views[0]["view"]) == "dashboard" and bool(views[0]["on"]), "view_changed fired for the open screen")
	# A v2 client must not use the v3-only message surface.
	var before := views.size()
	_send(peer, {"v": 2, "type": "view", "view": "dashboard", "on": true})
	var m2 := await _read(peer, 8)
	var e2 := _has(m2, "error")
	_check(not e2.is_empty() and str(e2.get("reason", "")) == "bad_version", "a v2 view message is rejected as bad_version")
	_check(s.current_view == "dashboard" and views.size() == before, "the rejected view changes nothing")
	# Unknown view names are never stored.
	_send(peer, P.make_view("party", true))
	var m3 := await _read(peer, 8)
	var e3 := _has(m3, "error")
	_check(not e3.is_empty() and str(e3.get("reason", "")) == "bad_field", "an unknown view name is rejected as bad_field")
	_check(s.current_view == "dashboard" and views.size() == before, "the unknown view changes nothing")
	# Closing a companion screen returns the session to the primary controller screen.
	_send(peer, P.make_view("dashboard", false))
	await _frames(4)
	_check(s.current_view == "controller", "closing the companion screen returns to the controller view")
	_check(views.size() == before + 1 and str(views[views.size() - 1]["view"]) == "dashboard" and not bool(views[views.size() - 1]["on"]), "view_changed fired for the closed screen")
	# A socket with no session cannot switch screens.
	var ghost := await _open()
	_send(ghost, P.make_view("dashboard", true))
	var gm := await _read(ghost, 8)
	var ge := _has(gm, "error")
	_check(not ge.is_empty() and str(ge.get("reason", "")) == "not_authenticated", "an unpaired socket cannot switch screens")
	ghost.close()
	_send(peer, P.make_bye())
	await _closed(peer)
	_server.view_changed.disconnect(handler)
	await _frames(3)


func _test_rejections() -> void:
	var peer := await _open()
	var n := _inputs.size()
	_send(peer, P.make_input(0, Vector2(1, 0), ["shoot"]))
	await _frames(4)
	_check(_inputs.size() == n, "input before pairing is ignored")
	_send(peer, P.make_pairing_request("AAAAAAAA", "x"))
	var msgs := await _read(peer, 8)
	var fail := _has(msgs, "pair_fail")
	_check(String(fail.get("reason", "")) == "bad_token", "wrong token -> pair_fail bad_token")
	_check(_server.registry.connected_count() == 0, "a wrong token creates no session")
	var peer2 := await _open()
	_send(peer2, {"v": 1, "type": "pair", "token": _server.token, "name": "old"})
	await _frames(6)
	_check(_server.registry.connected_count() == 0, "old protocol version cannot pair")
	var peer3 := await _open()
	_send(peer3, "{definitely not json")
	await _frames(6)
	_check(_server.registry.connected_count() == 0 and _server.running, "malformed JSON is dropped, server keeps running")
	var huge := "{\"v\":2,\"type\":\"pair\",\"token\":\"%s\",\"name\":\"%s\"}" % [_server.token, "A".repeat(P.MAX_MSG_BYTES * 4)]
	_send(peer3, huge)
	await _frames(8)
	_check(_server.registry.connected_count() == 0, "an oversized packet cannot pair, even with the right token")
	var good := await _pair("after junk")
	_check(not (good["paired"] as Dictionary).is_empty(), "a valid pairing still works after junk traffic")
	_send(good["peer"], P.make_bye())
	await _closed(good["peer"])
	for p in [peer, peer2, peer3]:
		(p as WebSocketPeer).close()
	await _frames(4)
	var old_token := _server.token
	var a := await _pair("first")
	_send(a["peer"], P.make_bye())
	await _closed(a["peer"])
	var b := await _open()
	_send(b, P.make_pairing_request(old_token, "replay"))
	var rm := await _read(b, 8)
	_check(not _has(rm, "pair_fail").is_empty(), "a used pairing token cannot be replayed")
	b.close()
	await _frames(3)


func _test_second_device_and_resume() -> void:
	var a := await _pair("phone A")
	var pa: WebSocketPeer = a["peer"]
	var cred := str((a["paired"] as Dictionary).get("session", ""))
	var b := await _pair("phone B")
	var fail := _has(b["msgs"], "pair_fail")
	_check(String(fail.get("reason", "")) == "no_slot" and (b["paired"] as Dictionary).is_empty(), "a second phone cannot take the only slot")
	_check(_server.registry.connected_count() == 1, "slot stays with the first phone")
	var n := _inputs.size()
	_send(b["peer"], P.make_input(0, Vector2(1, 0), ["shoot"]))
	await _frames(4)
	_check(_inputs.size() == n, "an unassigned phone cannot control a player")
	var lost_before := _lost_events.size()
	pa.close()
	await _frames(15)
	_check(_lost_events.size() == lost_before + 1, "connection loss emits client_disconnected")
	var s := _server.registry.sessions[0]
	_check(s != null and s.state == KingControllerSession.State.CONNECTION_LOST, "slot is reserved in state connection_lost")
	var c := await _pair("phone C")
	_check((c["paired"] as Dictionary).is_empty(), "slot of a lost controller cannot be stolen by a new pairing")
	var r := await _open()
	_send(r, P.make_resume_request(cred))
	var rm := await _read(r, 10)
	var res := _has(rm, "paired")
	_check(not res.is_empty() and int(res.get("slot", -1)) == 0, "resume with the session credential re-binds the same slot")
	_check(_server.registry.connected_count() == 1, "session is connected again")
	var w := await _open()
	_send(w, P.make_resume_request("0".repeat(32)))
	var wm := await _read(w, 8)
	_check(not _has(wm, "pair_fail").is_empty(), "unknown credential cannot resume")
	var r2 := await _open()
	_send(r2, P.make_resume_request(cred))
	await _read(r2, 8)
	_check(await _closed(r), "a newer connection replaces the previous one of the same session")
	_send(r2, P.make_bye())
	await _closed(r2)
	for p in [b["peer"], c["peer"], w]:
		(p as WebSocketPeer).close()
	await _frames(4)


func _test_revoke() -> void:
	var a := await _pair("to revoke")
	var pa: WebSocketPeer = a["peer"]
	var cred := str((a["paired"] as Dictionary).get("session", ""))
	_send(pa, P.make_input(0, Vector2(1, 0), ["sprint", "shoot"]))
	await _frames(4)
	var n := _inputs.size()
	_check(_server.revoke(0), "revoke(slot) succeeds for a connected controller")
	await _frames(4)
	_check(_inputs.size() > n, "revocation releases the held buttons")
	var last: Dictionary = _inputs[_inputs.size() - 1]
	_check((last["release"] as Array).has(&"sprint") and (last["release"] as Array).has(&"shoot") and last["move"] == Vector2.ZERO, "released: sprint, shoot, stick centred")
	var msgs := await _read(pa, 8)
	_check(not _has(msgs, "revoked").is_empty() or pa.get_ready_state() != WebSocketPeer.STATE_OPEN, "the phone is told it was revoked / disconnected")
	_check(_server.registry.connected_count() == 0 and _server.registry.sessions[0] == null, "slot is free after revoke")
	var r := await _open()
	_send(r, P.make_resume_request(cred))
	var rm := await _read(r, 8)
	var f := _has(rm, "pair_fail")
	_check(String(f.get("reason", "")) == "revoked", "a revoked credential can never resume")
	r.close()
	_check(not _server.revoke(0), "revoking an empty slot is a no-op")
	await _frames(3)


func _test_bye_and_disconnect_cleanup() -> void:
	var a := await _pair("cleanup")
	var pa: WebSocketPeer = a["peer"]
	_send(pa, P.make_input(0, Vector2(-1, 0), ["sprint", "pass"]))
	await _frames(4)
	var n := _inputs.size()
	pa.close()
	await _frames(15)
	_check(_inputs.size() > n, "dropping the connection emits releases")
	var last: Dictionary = _inputs[_inputs.size() - 1]
	_check((last["release"] as Array).has(&"sprint") and (last["release"] as Array).has(&"pass") and last["move"] == Vector2.ZERO, "held buttons released and stick reset on disconnect")
	# the lost session still owns the slot until it expires or ends; end it like the PC "disconnect" button does
	_server.revoke(0)
	var b := await _pair("bye")
	_check(not (b["paired"] as Dictionary).is_empty(), "the slot is reusable after the old controller was removed")
	_send(b["peer"], P.make_bye())
	await _closed(b["peer"])
	await _frames(4)
	_check(_server.registry.sessions[0] == null, "bye frees the slot immediately")


func _test_heartbeat_timeout() -> void:
	var a := await _pair("silent phone")
	var pa: WebSocketPeer = a["peer"]
	_send(pa, P.make_input(0, Vector2(1, 0), ["shoot"]))
	await _frames(4)
	var n := _inputs.size()
	var t0 := Time.get_ticks_msec()
	var timed_out := false
	for i in 600:
		pa.poll()
		var s := _server.registry.sessions[0]
		if s != null and s.state == KingControllerSession.State.CONNECTION_LOST:
			timed_out = true
			break
		await get_tree().physics_frame
	var dt := Time.get_ticks_msec() - t0
	_check(timed_out, "a silent controller times out", "after %d ms" % dt)
	_check(dt <= P.HEARTBEAT_TIMEOUT_MS + 2500, "timeout happens within the documented window (%d ms)" % dt)
	_check(_inputs.size() > n and ((_inputs[_inputs.size() - 1]["release"] as Array).has(&"shoot")), "timeout releases the held button")
	_check(await _closed(pa), "the server closes the timed-out socket")
	_server.revoke(0)
	await _frames(3)


func _test_stop_start() -> void:
	var a := await _pair("restart")
	_check(not (a["paired"] as Dictionary).is_empty(), "paired before stop")
	_server.stop()
	_check(not _server.running, "stop() stops the server")
	_check(await _closed(a["peer"]), "stop() closes every open controller connection")
	var res := _server.start()
	_check(res == OK and _server.running, "the server can be started again")
	var b := await _pair("after restart")
	_check(not (b["paired"] as Dictionary).is_empty(), "a new pairing works after restart")
	_send(b["peer"], P.make_bye())
	await _closed(b["peer"])
	# port conflict: another listener on the first port pair moves the server to the next pair
	_server.stop()
	var blocker := TCPServer.new()
	var busy_port := _server.port
	blocker.listen(busy_port, "*")
	_server.start()
	_check(_server.running and _server.port != busy_port, "a busy port pair is skipped (now %d)" % _server.port)
	blocker.stop()
	_server.stop()
	var blockers: Array[TCPServer] = []
	var base := _server.port
	for i in KingControllerServer.PORT_ATTEMPTS:
		var t := TCPServer.new()
		t.listen(base + i * 2, "*")
		blockers.append(t)
	var e := _server.start()
	_check(e == ERR_ALREADY_IN_USE and not _server.running and _server.startup_error == "port_in_use", "no free port pair -> clear error, not running")
	for t in blockers:
		t.stop()
	_check(_server.start() == OK, "recovers once ports are free")
