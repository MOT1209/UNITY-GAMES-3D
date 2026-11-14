class_name KingControllerServer
extends Node

## PC-side KING CONTROLLER server.
## - HTTP on `port` serves the phone controller page.
## - WebSocket on `port + 1` (WebSocketMultiplayerPeer) carries the protocol.
## - Issues a one-time pairing token embedded in the QR URL.

signal input_received(slot: int, move: Vector2, press: Array, release: Array)
signal client_connected(slot: int)
signal client_disconnected(slot: int)
signal pairing_changed()

@export var port: int = 7250
@export var tick_rate: int = 30
@export var max_slots: int = 2

var token: String = ""
var lan_ip: String = "127.0.0.1"
var running: bool = false

var _http: TCPServer
var _ws: WebSocketMultiplayerPeer
var _page_html: String = ""
var _http_conns: Array[Dictionary] = []
var _slots: Array[int] = []          # slot -> peer_id or -1
var _ws_clients: Dictionary = {}     # peer_id -> {slot, client_state, last_seen}
var _used_tokens: Dictionary = {}
var _rng := RandomNumberGenerator.new()


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
	token = _gen_token()
	_http = TCPServer.new()
	var err := _http.listen(port, "0.0.0.0")
	if err != OK:
		push_error("KingControllerServer: http listen failed %d" % err)
		return
	_ws = WebSocketMultiplayerPeer.new()
	err = _ws.create_server(port + 1, "0.0.0.0")
	if err != OK:
		push_error("KingControllerServer: ws listen failed %d" % err)
		_http.stop()
		return
	_ws.peer_connected.connect(_on_peer_connected)
	_ws.peer_disconnected.connect(_on_peer_disconnected)
	running = true
	set_process(true)
	pairing_changed.emit()


func stop() -> void:
	running = false
	if _http != null:
		_http.stop()
		_http = null
	if _ws != null:
		_ws.close()
		_ws = null
	_http_conns.clear()
	_ws_clients.clear()
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
	# Prefer real LAN addresses (192.168.x.x, then 10.x.x.x, then 172.16-31.x.x)
	# over virtual/WSL/Docker adapters that report private IPs but are not reachable
	# by a phone on the Wi-Fi.
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.find(":") >= 0:
			continue
		if addr == "127.0.0.1" or addr == "0.0.0.0":
			continue
		candidates.append(addr)
	# rank
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
	# WS
	if _ws != null:
		_ws.poll()
		# incoming packets
		while _ws.get_available_packet_count() > 0:
			var peer_id := _ws.get_packet_peer()
			var pkt := _ws.get_packet()
			var txt := pkt.get_string_from_utf8()
			_handle_ws_packet(peer_id, txt)


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
		return
	var header_block := text.substr(0, hdr_end)
	var lines := header_block.split("\r\n")
	var request_line := String(lines[0])
	var parts := request_line.split(" ")
	var path := "/"
	if parts.size() >= 2:
		path = parts[1]
	if path == "/" or path == "/index.html":
		var page := _page_html.replace("__WS_PORT__", str(port + 1))
		_http_respond(stream, 200, "text/html; charset=utf-8", page)
	else:
		_http_respond(stream, 404, "text/plain", "Not Found")
	c["closed"] = true
	stream.disconnect_from_host()


func _http_respond(stream: StreamPeerTCP, code: int, ctype: String, body: String) -> void:
	var status_text := "OK"
	if code == 404: status_text = "Not Found"
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, status_text, ctype, b.size()]
	stream.put_data(head.to_utf8_buffer())
	stream.put_data(b)


func _on_peer_connected(peer_id: int) -> void:
	_ws_clients[peer_id] = {"slot": -1, "client_state": {"seq": -1, "window_start": Time.get_ticks_msec(), "count": 0}, "last_seen": Time.get_ticks_msec()}


func _on_peer_disconnected(peer_id: int) -> void:
	if not _ws_clients.has(peer_id):
		return
	var info: Dictionary = _ws_clients[peer_id]
	var slot := int(info.get("slot", -1))
	if slot >= 0:
		# free live slot but keep token binding for reconnect
		for i in range(max_slots):
			if _slots[i] == peer_id:
				_slots[i] = -1
		client_disconnected.emit(slot)
		pairing_changed.emit()
	_ws_clients.erase(peer_id)


func _handle_ws_packet(peer_id: int, txt: String) -> void:
	if not _ws_clients.has(peer_id):
		_on_peer_connected(peer_id)
	var info: Dictionary = _ws_clients[peer_id]
	info["last_seen"] = Time.get_ticks_msec()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		_ws_send(peer_id, KingControllerProtocol.make_pair_fail("bad_json"))
		return
	var msg: Dictionary = parsed
	var now := Time.get_ticks_msec()
	var mtype := String(msg.get("type", ""))
	if mtype == "pair":
		var free := 0
		for s in _slots:
			if s == -1:
				free += 1
		var res := KingControllerProtocol.validate_pairing(msg, token, _used_tokens, free)
		if not bool(res["ok"]):
			_ws_send(peer_id, KingControllerProtocol.make_pair_fail(String(res["reason"])))
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
			_ws_send(peer_id, KingControllerProtocol.make_pair_fail("no_slot"))
			return
		_slots[slot] = peer_id
		info["slot"] = slot
		_used_tokens[token] = slot
		client_connected.emit(slot)
		_ws_send(peer_id, KingControllerProtocol.make_pair_ok(slot, tick_rate))
		pairing_changed.emit()
		return
	if mtype == "ping":
		_ws_send(peer_id, KingControllerProtocol.make_pong(int(msg.get("seq", 0))))
		return
	if mtype == "input":
		var slot := int(info.get("slot", -1))
		if slot < 0:
			_ws_send(peer_id, KingControllerProtocol.make_pair_fail("not_paired"))
			return
		var result := KingControllerProtocol.validate_input(msg, info["client_state"], now)
		if not result.ok:
			return
		input_received.emit(slot, result.move, result.press, result.release)
		return


func _ws_send(peer_id: int, msg: Dictionary) -> void:
	if _ws == null:
		return
	_ws.set_target_peer(peer_id)
	_ws.put_packet(JSON.stringify(msg).to_utf8_buffer())


func free_slots() -> int:
	var n := 0
	for s in _slots:
		if s == -1:
			n += 1
	return n