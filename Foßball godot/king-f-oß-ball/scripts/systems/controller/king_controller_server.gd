class_name KingControllerServer
extends Node

## PC-side KING CONTROLLER server.
## - HTTP on `port` serves the phone controller page.
## - WebSocket on `port + 1` (raw WebSocketPeer via accept_stream) carries the
##   protocol as plain text frames, readable by any browser.
## - Issues a one-time pairing token embedded in the QR URL.

signal input_received(slot: int, move: Vector2, press: Array, release: Array)
signal client_connected(slot: int)
signal client_disconnected(slot: int)
signal pairing_changed()

@export var port: int = 7250
@export var tick_rate: int = 30
## How many controller slots (physical controllers / phones) may pair at once.
## Raised from 2 to 4 in the P5/P8 real-device pass so four controllers can be
## connected (slots 0..3).
@export var max_slots: int = 4

var token: String = ""
var lan_ip: String = "127.0.0.1"
var running: bool = false

var _http: TCPServer
var _ws_tcp: TCPServer
var _page_html: String = ""
var _http_conns: Array[Dictionary] = []
var _ws_conns: Array[Dictionary] = []
var _slots: Array[int] = []          # slot -> index into _ws_conns or -1
var _used_tokens: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## When the current token was issued (Time.get_ticks_msec) and how many wrong pairings it has seen.
var token_issued_ms: int = 0
var failed_pairings: int = 0


func _ready() -> void:
	_rng.randomize()
	_slots.resize(max_slots)
	for i in range(max_slots):
		_slots[i] = -1
	_load_page()
	_detect_lan_ip()
	_start()


func _exit_tree() -> void:
	stop()


func _start() -> void:
	rotate_token()
	_http = TCPServer.new()
	var err := _http.listen(port, "0.0.0.0")
	if err != OK:
		push_error("KingControllerServer: http listen failed %d" % err)
		return
	_ws_tcp = TCPServer.new()
	err = _ws_tcp.listen(port + 1, "0.0.0.0")
	if err != OK:
		push_error("KingControllerServer: ws listen failed %d" % err)
		_http.stop()
		return
	running = true
	set_process(true)
	pairing_changed.emit()


func stop() -> void:
	running = false
	if _http != null:
		_http.stop()
		_http = null
	if _ws_tcp != null:
		_ws_tcp.stop()
		_ws_tcp = null
	for c in _ws_conns:
		if c.has("peer") and c["peer"] != null:
			c["peer"].close()
	_ws_conns.clear()
	_http_conns.clear()
	for i in range(max_slots):
		_slots[i] = -1
	_used_tokens.clear()


func _gen_token() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var out := ""
	for _i in range(KingControllerProtocol.TOKEN_LEN):
		out += chars[_rng.randi() % chars.length()]
	return out


func _load_page() -> void:
	var f := FileAccess.open("res://assets/controller/controller_page.html", FileAccess.READ)
	if f != null:
		_page_html = f.get_as_text()
		f.close()
	else:
		_page_html = "<html><body>KING CONTROLLER page missing</body></html>"


func _detect_lan_ip() -> void:
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.find(":") >= 0:
			continue
		if addr == "127.0.0.1" or addr == "0.0.0.0":
			continue
		candidates.append(addr)
	var best := ""
	for a in candidates:
		if a.begins_with("192.168."):
			best = a
			break
	if best == "":
		for a in candidates:
			if a.begins_with("10."):
				best = a
				break
	if best == "":
		for a in candidates:
			if a.begins_with("172."):
				var parts := a.split(".")
				if parts.size() >= 2:
					var second := int(parts[1])
					if second >= 16 and second <= 31:
						best = a
						break
	if best == "":
		if candidates.size() > 0:
			best = candidates[0]
	lan_ip = best if best != "" else "127.0.0.1"


func pairing_url() -> String:
	return "http://%s:%d/?t=%s" % [lan_ip, port, token]


func qr_matrix() -> Dictionary:
	return KingQrEncoder.encode(pairing_url())


func _process(_delta: float) -> void:
	if not running:
		return
	# HTTP
	while _http.is_connection_available():
		var stream := _http.take_connection()
		if stream == null:
			break
		_http_conns.append({"stream": stream, "buf": PackedByteArray(), "closed": false, "last_seen": Time.get_ticks_msec()})
	var i := 0
	while i < _http_conns.size():
		var c: Dictionary = _http_conns[i]
		_drive_http(c)
		if c.get("closed", false):
			_http_conns.remove_at(i)
		else:
			i += 1
	# WS accept
	while _ws_tcp.is_connection_available():
		var stream := _ws_tcp.take_connection()
		if stream == null:
			break
		var peer := WebSocketPeer.new()
		var err := peer.accept_stream(stream)
		if err != OK:
			continue
		_ws_conns.append({"peer": peer, "stream": stream, "slot": -1,
				"client_state": {"seq": -1, "window_start": Time.get_ticks_msec(), "count": 0},
				"last_seen": Time.get_ticks_msec(), "opened": false})
	# WS drive
	i = 0
	while i < _ws_conns.size():
		var c: Dictionary = _ws_conns[i]
		var peer: WebSocketPeer = c["peer"]
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_handle_ws_close(i)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			i += 1
			continue
		if not c["opened"]:
			c["opened"] = true
		c["last_seen"] = Time.get_ticks_msec()
		while peer.get_available_packet_count() > 0:
			var pkt := peer.get_packet()
			var txt := ""
			if peer.was_string_packet():
				txt = pkt.get_string_from_utf8()
			else:
				txt = pkt.get_string_from_utf8()
			_handle_ws_message(c, txt, peer)
		if Time.get_ticks_msec() - int(c["last_seen"]) > 30000:
			peer.close()
		i += 1


func _drive_http(c: Dictionary) -> void:
	var stream: StreamPeerTCP = c["stream"]
	var avail := stream.get_available_bytes()
	if avail > 0:
		var res := stream.get_data(avail)
		if res[0] == OK:
			c["buf"].append_array(res[1])
	c["last_seen"] = Time.get_ticks_msec()
	var text := String(c["buf"].get_string_from_utf8())
	var hdr_end := text.find("\r\n\r\n")
	if hdr_end < 0:
		if Time.get_ticks_msec() - int(c["last_seen"]) > 5000:
			c["closed"] = true
			stream.disconnect_from_host()
		return
	var header_block := text.substr(0, hdr_end)
	var lines := header_block.split("\r\n")
	var request_line := String(lines[0])
	var parts := request_line.split(" ")
	var path := "/"
	if parts.size() >= 2:
		path = parts[1]
	var qi := path.find("?")
	if qi >= 0:
		path = path.substr(0, qi)
	if path == "/" or path == "/index.html":
		var page := _page_html.replace("__WS_PORT__", str(port + 1))
		_http_respond(stream, 200, "text/html; charset=utf-8", page)
	else:
		_http_respond(stream, 404, "text/plain", "Not Found")
	c["closed"] = true
	stream.disconnect_from_host()


func _http_respond(stream: StreamPeerTCP, code: int, ctype: String, body: String) -> void:
	var status_text := "OK"
	if code == 404:
		status_text = "Not Found"
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, status_text, ctype, b.size()]
	stream.put_data(head.to_utf8_buffer())
	stream.put_data(b)


func _handle_ws_message(c: Dictionary, txt: String, peer: WebSocketPeer) -> void:
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		_ws_send(peer, KingControllerProtocol.make_pair_fail("bad_json"))
		return
	var msg: Dictionary = parsed
	var now := Time.get_ticks_msec()
	var mtype := String(msg.get("type", ""))
	if mtype == "pair":
		var free := 0
		for s in _slots:
			if s == -1:
				free += 1
		var res := check_pairing(msg, free, now)
		if not bool(res["ok"]):
			_ws_send(peer, KingControllerProtocol.make_pair_fail(String(res["reason"])))
			return
		var slot := -1
		if int(res["reconnect_slot"]) >= 0:
			slot = int(res["reconnect_slot"])
		else:
			for i in range(max_slots):
				if _slots[i] == -1:
					slot = i
					break
		if slot < 0:
			_ws_send(peer, KingControllerProtocol.make_pair_fail("no_slot"))
			return
		_slots[slot] = _conn_index(c)
		c["slot"] = slot
		_used_tokens[token] = slot
		client_connected.emit(slot)
		_ws_send(peer, KingControllerProtocol.make_pair_ok(slot, tick_rate))
		pairing_changed.emit()
		return
	if mtype == "ping":
		_ws_send(peer, KingControllerProtocol.make_pong(int(msg.get("seq", 0))))
		return
	if mtype == "input":
		var slot := int(c.get("slot", -1))
		if slot < 0:
			_ws_send(peer, KingControllerProtocol.make_pair_fail("not_paired"))
			return
		var result := KingControllerProtocol.validate_input(msg, c["client_state"], now)
		if not result.ok:
			return
		input_received.emit(slot, result.move, result.press, result.release)
		return


## New one-time token (new QR code): on start, after it expired, after too many wrong attempts.
## Controllers already paired keep their slot (their token is remembered in `_used_tokens`).
func rotate_token() -> void:
	token = _gen_token()
	token_issued_ms = Time.get_ticks_msec()
	failed_pairings = 0
	pairing_changed.emit()


## Pairing check with token expiry and the wrong-token limit (see KingControllerProtocol).
func check_pairing(msg: Dictionary, free: int, now: int) -> Dictionary:
	var sent := String(msg.get("token", ""))
	if _used_tokens.has(sent) and int(msg.get("v", -1)) == KingControllerProtocol.PROTOCOL_VERSION \
			and String(msg.get("type", "")) == "pair":    # re-bind of a paired controller (any earlier token)
		return {"ok": true, "reason": "", "reconnect_slot": int(_used_tokens[sent])}
	var window := KingControllerProtocol.pairing_window(now, token_issued_ms, failed_pairings)
	if window != "":
		rotate_token()
		return {"ok": false, "reason": window, "reconnect_slot": -1}
	var res := KingControllerProtocol.validate_pairing(msg, token, _used_tokens, free)
	if not bool(res["ok"]) and String(res["reason"]) == "bad_token":
		failed_pairings += 1
		if failed_pairings >= KingControllerProtocol.MAX_FAILED_PAIRINGS:
			rotate_token()
			res["reason"] = "too_many_attempts"
	return res


func _ws_send(peer: WebSocketPeer, msg: Dictionary) -> void:
	peer.send_text(JSON.stringify(msg))


func _handle_ws_close(idx: int) -> void:
	if idx < 0 or idx >= _ws_conns.size():
		return
	var c: Dictionary = _ws_conns[idx]
	var slot := int(c.get("slot", -1))
	if slot >= 0:
		for i in range(max_slots):
			if _slots[i] == idx:
				_slots[i] = -1
		client_disconnected.emit(slot)
		pairing_changed.emit()
	_ws_conns.remove_at(idx)
	for i in range(max_slots):
		if _slots[i] > idx:
			_slots[i] -= 1


func _conn_index(c: Dictionary) -> int:
	for i in range(_ws_conns.size()):
		if _ws_conns[i] == c:
			return i
	return -1


func free_slots() -> int:
	var n := 0
	for s in _slots:
		if s == -1:
			n += 1
	return n