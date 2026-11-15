class_name KingControllerServer
extends Node

## PC-side KING CONTROLLER transport (P9): an HTTP server for the phone page and a WebSocket server for the
## protocol (plain, unencrypted, LAN only — see docs/KING_CONTROLLER_ARCHITECTURE.md). The rules (tokens,
## sessions, slots, heartbeat, held-input release) live in `KingControllerRegistry`; this class only moves
## bytes: it checks the size of every packet BEFORE parsing it, stamps packets with its own arrival time
## (one reading of the monotonic clock per frame), binds sockets to sessions and closes them cleanly.
##
## It keeps running while the match is paused (PROCESS_MODE_ALWAYS), otherwise the heartbeat would expire
## and the phone could not resume the match it just paused.

signal input_received(slot: int, move: Vector2, press: Array, release: Array)
signal client_connected(slot: int)
signal client_disconnected(slot: int)
signal pause_requested(slot: int)
signal pairing_changed()

const MAX_HTTP_CONNECTIONS := 16
const MAX_WS_CONNECTIONS := 8
const HTTP_MAX_REQUEST_BYTES := 8192
const HTTP_TIMEOUT_MS := 5000
const MAX_PACKETS_PER_CONNECTION_PER_FRAME := 128
const CLOSE_FLUSH_MS := 400
const MAX_PAIR_ATTEMPTS_PER_CONNECTION := 3
const PORT_ATTEMPTS := 5
const LOG_LINES := 30

@export var port: int = 7250
@export var tick_rate: int = 30
## Advertised slots. Clamped to what the match can really drive (`KingControllerProtocol.SUPPORTED_SLOTS`).
@export var max_slots: int = KingControllerProtocol.SUPPORTED_SLOTS
## Tests build a server without opening sockets.
@export var auto_start: bool = true

var registry: KingControllerRegistry
var running: bool = false
## "" | "port_in_use" — why `start()` failed.
var startup_error: String = ""
var ports_tried: Array[int] = []
var lan_ip: String = ""
var lan_candidates: Array = []
var network_error: String = ""
var recent_events: Array[String] = []

var _http: TCPServer
var _ws_tcp: TCPServer
var _page_html: String = ""
var _http_conns: Array[Dictionary] = []
var _ws_conns: Array[Dictionary] = []
var _next_conn_id := 1
var _now := 0
var _last_tick_wall_ms := -1                        # wall time of the previous tick (freeze detection)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_registry()
	_load_page()
	refresh_network()
	if auto_start:
		start()


func _exit_tree() -> void:
	stop()


func _make_registry() -> void:
	if registry != null:
		return
	registry = KingControllerRegistry.new(max_slots)
	registry.log_event.connect(_log)
	registry.changed.connect(func() -> void: pairing_changed.emit())
	registry.slot_connected.connect(func(slot: int) -> void: client_connected.emit(slot))
	registry.slot_lost.connect(func(slot: int, _reason: String) -> void: client_disconnected.emit(slot))
	registry.input.connect(func(slot: int, move: Vector2, press: Array, release: Array) -> void:
		input_received.emit(slot, move, press, release))
	registry.pause_requested.connect(func(slot: int) -> void: pause_requested.emit(slot))
	registry.rotate_token(Time.get_ticks_msec())


## The registry exists from construction on (tests and the pairing screen read it before `_ready`).
func ensure_registry() -> KingControllerRegistry:
	_make_registry()
	return registry


func _log(text: String) -> void:
	# Never receives tokens or credentials: only short session ids, slot numbers and reason codes.
	var t := Time.get_ticks_msec() / 1000
	recent_events.append("%02d:%02d %s" % [t / 60 % 60, t % 60, text])
	while recent_events.size() > LOG_LINES:
		recent_events.pop_front()


# --- start / stop ------------------------------------------------------------------------------------

## Opens the HTTP port and the WebSocket port (port + 1). On a conflict the next free pair (port + 2, ...)
## is tried; `port` then holds the pair actually used. Returns OK or ERR_ALREADY_IN_USE.
func start() -> Error:
	_make_registry()
	stop_sockets()
	startup_error = ""
	ports_tried.clear()
	var candidate := port
	for attempt in PORT_ATTEMPTS:
		ports_tried.append(candidate)
		var http := TCPServer.new()
		if http.listen(candidate, "*") != OK:
			candidate += 2
			continue
		var ws := TCPServer.new()
		if ws.listen(candidate + 1, "*") != OK:
			http.stop()
			candidate += 2
			continue
		_http = http
		_ws_tcp = ws
		port = candidate
		running = true
		set_process(true)
		_log("listening on ports %d (page) and %d (controller)" % [port, port + 1])
		pairing_changed.emit()
		return OK
	startup_error = "port_in_use"
	running = false
	_log("could not open a port pair (tried %s)" % str(ports_tried))
	pairing_changed.emit()
	return ERR_ALREADY_IN_USE


## Closes the sockets only (sessions are kept).
func stop_sockets() -> void:
	running = false
	for c in _ws_conns:
		var peer: WebSocketPeer = c["peer"]
		peer.close(1001, "server stopping")
	_ws_conns.clear()
	for c in _http_conns:
		(c["stream"] as StreamPeerTCP).disconnect_from_host()
	_http_conns.clear()
	if _http != null:
		_http.stop()
		_http = null
	if _ws_tcp != null:
		_ws_tcp.stop()
		_ws_tcp = null


## Full shutdown: sockets closed, every session ended (inputs released).
func stop() -> void:
	var was_running := running
	stop_sockets()
	if registry != null:
		registry.clear_all(Time.get_ticks_msec())
	if was_running:
		_log("server stopped")
		pairing_changed.emit()


func _load_page() -> void:
	var f := FileAccess.open("res://assets/controller/controller_page.html", FileAccess.READ)
	if f != null:
		_page_html = f.get_as_text()
		f.close()
	else:
		_page_html = "<html><body>KING CONTROLLER page missing</body></html>"


# --- LAN ----------------------------------------------------------------------------------------------

## Re-reads the machine's network adapters and picks the address for the pairing URL.
func refresh_network(interfaces: Array = []) -> void:
	var data := KingControllerNetwork.choose(interfaces if not interfaces.is_empty() else KingControllerNetwork.local_interfaces())
	lan_candidates = data["candidates"]
	network_error = str(data["error"])
	lan_ip = str(data["best"])
	pairing_changed.emit()


## The user picked another address (several adapters). Any address is accepted, loopback included
## (explicit choice, used by tests and by same-PC browser checks).
func select_address(address: String) -> void:
	lan_ip = address
	network_error = ""
	pairing_changed.emit()


func pairing_url() -> String:
	if lan_ip == "" or registry == null:
		return ""
	return "http://%s:%d/?t=%s" % [lan_ip, port, registry.token]


func qr_matrix() -> Dictionary:
	var url := pairing_url()
	return KingQrEncoder.encode(url) if url != "" else {}


## Compatibility accessor of the previous API.
var token: String:
	get:
		return registry.token if registry != null else ""


func free_slots() -> int:
	return registry.free_slots() if registry != null else 0


func rotate_token() -> void:
	registry.rotate_token(Time.get_ticks_msec())


# --- main loop ---------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not running:
		return
	_now = Time.get_ticks_msec()                        # the arrival time of every packet of this frame
	_accept_http()
	_drive_http()
	_accept_ws()
	_drive_ws()
	# Freeze-aware clock: a wall gap between two ticks bigger than MAX_SERVED_GAP_MS means this
	# _process was frozen (synchronous match build, load spike) — only the clamp counts, the frozen
	# remainder is skipped so the phone is not punished for time nobody could serve it in.
	var served_ms := -1
	if _last_tick_wall_ms >= 0:
		served_ms = mini(_now - _last_tick_wall_ms, KingControllerProtocol.MAX_SERVED_GAP_MS)
	_last_tick_wall_ms = _now
	for item in registry.tick(_now, served_ms):
		_close_by_id(int(item["connection_id"]), str(item["reason"]))


# --- HTTP (the phone page) -------------------------------------------------------------------------------

func _accept_http() -> void:
	while _http.is_connection_available():
		var stream := _http.take_connection()
		if stream == null:
			break
		if _http_conns.size() >= MAX_HTTP_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		_http_conns.append({"stream": stream, "buf": PackedByteArray(), "started": _now, "out": PackedByteArray(), "out_pos": 0, "responded": false})


func _drive_http() -> void:
	var i := 0
	while i < _http_conns.size():
		var c: Dictionary = _http_conns[i]
		var stream: StreamPeerTCP = c["stream"]
		stream.poll()
		var done := false
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			done = true
		elif not c["responded"]:
			var avail := stream.get_available_bytes()
			if avail > 0:
				var held_buf: PackedByteArray = c["buf"]
				var room := HTTP_MAX_REQUEST_BYTES - held_buf.size()
				var got := stream.get_data(mini(avail, room))
				if got[0] == OK:
					held_buf.append_array(got[1])
					c["buf"] = held_buf                    # PackedByteArray is a value type: store it back
			var buf: PackedByteArray = c["buf"]
			if buf.size() >= HTTP_MAX_REQUEST_BYTES:
				_http_prepare(c, 431, "text/plain", "Request too large")
			elif _contains_header_end(buf):
				_http_serve(c, buf)
		if c["responded"]:
			var out: PackedByteArray = c["out"]
			var pos := int(c["out_pos"])
			if pos < out.size():
				var res := stream.put_partial_data(out.slice(pos))
				if res[0] == OK:
					c["out_pos"] = pos + int(res[1])
				else:
					done = true
			if int(c["out_pos"]) >= out.size():
				done = true
		if _now - int(c["started"]) > HTTP_TIMEOUT_MS:
			done = true
		if done:
			stream.disconnect_from_host()
			_http_conns.remove_at(i)
		else:
			i += 1


static func _contains_header_end(buf: PackedByteArray) -> bool:
	for k in range(maxi(0, buf.size() - 3)):
		if buf[k] == 13 and buf[k + 1] == 10 and buf[k + 2] == 13 and buf[k + 3] == 10:
			return true
	return false


func _http_serve(c: Dictionary, buf: PackedByteArray) -> void:
	var first_line := buf.get_string_from_utf8().split("\r\n")[0]
	var parts := first_line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		_http_prepare(c, 405, "text/plain", "Method Not Allowed")
		return
	var path := parts[1]
	var qi := path.find("?")
	if qi >= 0:
		path = path.substr(0, qi)
	if path == "/" or path == "/index.html":
		_http_prepare(c, 200, "text/html; charset=utf-8", _page_html.replace("__WS_PORT__", str(port + 1)))
	elif path == "/favicon.ico":
		_http_prepare(c, 204, "text/plain", "")
	else:
		_http_prepare(c, 404, "text/plain", "Not Found")


func _http_prepare(c: Dictionary, code: int, ctype: String, body: String) -> void:
	var status: String = {200: "OK", 204: "No Content", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"}.get(code, "Error")
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src ws:; img-src data:\r\n\r\n" % [code, status, ctype, b.size()]
	var out := head.to_utf8_buffer()
	out.append_array(b)
	c["out"] = out
	c["out_pos"] = 0
	c["responded"] = true


# --- WebSocket (the protocol) ---------------------------------------------------------------------------

func _accept_ws() -> void:
	while _ws_tcp.is_connection_available():
		var stream := _ws_tcp.take_connection()
		if stream == null:
			break
		if _ws_conns.size() >= MAX_WS_CONNECTIONS:
			stream.disconnect_from_host()
			_log("connection refused (limit %d)" % MAX_WS_CONNECTIONS)
			continue
		var peer := WebSocketPeer.new()
		# Bounded buffers: a hostile peer cannot make the game allocate more than a few KB per connection.
		peer.inbound_buffer_size = 8192
		peer.outbound_buffer_size = 4096
		peer.max_queued_packets = 64
		if peer.accept_stream(stream) != OK:
			continue
		_ws_conns.append({"id": _next_conn_id, "peer": peer, "state": KingControllerSession.State.CONNECTING,
				"session": null, "connected": _now, "invalid": 0, "pair_failures": 0, "closing_at": 0,
				"ping_state": {}})
		_next_conn_id += 1


func _drive_ws() -> void:
	var i := 0
	while i < _ws_conns.size():
		var c: Dictionary = _ws_conns[i]
		var peer: WebSocketPeer = c["peer"]
		peer.poll()
		var st := peer.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_connection_gone(c, "socket_closed")
			_ws_conns.remove_at(i)
			continue
		if int(c["closing_at"]) > 0:
			if _now >= int(c["closing_at"]):
				_ws_conns.remove_at(i)
				continue
			i += 1
			continue
		if st == WebSocketPeer.STATE_OPEN:
			var n := 0
			while peer.get_available_packet_count() > 0 and n < MAX_PACKETS_PER_CONNECTION_PER_FRAME and int(c["closing_at"]) == 0:
				_handle_packet(c, peer.get_packet())
				n += 1
			if c["session"] == null and int(c["closing_at"]) == 0 and _now - int(c["connected"]) > KingControllerProtocol.AUTH_TIMEOUT_MS:
				_close_conn(c, 1008, "authentication timeout")
		elif _now - int(c["connected"]) > KingControllerProtocol.AUTH_TIMEOUT_MS * 2:
			_close_conn(c, 1008, "handshake timeout")
		i += 1


func _send(c: Dictionary, msg: Dictionary) -> void:
	var peer: WebSocketPeer = c["peer"]
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(msg))


func _reject(c: Dictionary, reason: String, answer: bool = true) -> void:
	c["invalid"] = int(c["invalid"]) + 1
	registry.counters["rejected"] += 1
	_log("connection %d: message rejected (%s)" % [int(c["id"]), reason])
	if answer and int(c["invalid"]) <= 3:
		_send(c, KingControllerProtocol.make_error(reason))
	if int(c["invalid"]) >= KingControllerProtocol.MAX_INVALID_PER_CONNECTION:
		_close_conn(c, 1008, "too many invalid messages")


func _handle_packet(c: Dictionary, raw: PackedByteArray) -> void:
	# 1. size check before any decoding (inside parse), 2. structure, 3. state.
	var parsed := KingControllerProtocol.parse(raw)
	if not bool(parsed["ok"]):
		_reject(c, str(parsed["reason"]))
		return
	var msg: Dictionary = parsed["msg"]
	var checked := KingControllerProtocol.validate_message(msg)
	if not bool(checked["ok"]):
		_reject(c, str(checked["reason"]))
		return
	var s: KingControllerSession = c["session"]
	match str(checked["type"]):
		"pair":
			_on_pair(c, msg)
		"resume":
			_on_resume(c, msg)
		"ping":
			if s == null:
				_reject(c, "not_authenticated")
			elif KingControllerProtocol.ping_allowed(c["ping_state"], _now):
				registry.touch(s, _now)
				_send(c, KingControllerProtocol.make_pong(int(msg["seq"])))
		"bye":
			if s != null:
				c["session"] = null
				registry.end_session(s, "bye", _now)
			_close_conn(c, 1000, "bye")
		"input":
			if s == null:
				_reject(c, "not_authenticated")
				return
			var r := KingControllerProtocol.process_input(msg, s.input_state, _now)
			if r.ok:
				registry.apply_input(s, r, _now)
			elif r.reason == "rate_limited":
				registry.counters["dropped"] += 1
				if int(s.input_state.get("dropped", 0)) > 600:
					_close_conn(c, 1008, "rate limit abuse")
			else:
				registry.counters["dropped"] += 1       # duplicate / out-of-order / jump: ignored silently


func _on_pair(c: Dictionary, msg: Dictionary) -> void:
	if c["session"] != null:
		_reject(c, "already_paired")
		return
	c["state"] = KingControllerSession.State.PAIRING
	var res := registry.try_pair(str(msg["token"]), str(msg.get("name", "")), _now)
	c["state"] = KingControllerSession.State.CONNECTING
	if not bool(res["ok"]):
		_send(c, KingControllerProtocol.make_pair_fail(str(res["reason"])))
		c["pair_failures"] = int(c["pair_failures"]) + 1
		if int(c["pair_failures"]) >= MAX_PAIR_ATTEMPTS_PER_CONNECTION:
			_close_conn(c, 1008, "pairing refused")
		return
	var s: KingControllerSession = res["session"]
	_bind(c, s)
	_send(c, KingControllerProtocol.make_pair_ok(s.slot, str(res["credential"]), tick_rate))


func _on_resume(c: Dictionary, msg: Dictionary) -> void:
	if c["session"] != null:
		_reject(c, "already_paired")
		return
	c["state"] = KingControllerSession.State.PAIRING
	var res := registry.try_resume(str(msg["session"]), _now)
	c["state"] = KingControllerSession.State.CONNECTING
	if not bool(res["ok"]):
		_send(c, KingControllerProtocol.make_pair_fail(str(res["reason"])))
		c["pair_failures"] = int(c["pair_failures"]) + 1
		if int(c["pair_failures"]) >= MAX_PAIR_ATTEMPTS_PER_CONNECTION:
			_close_conn(c, 1008, "resume refused")
		return
	var s: KingControllerSession = res["session"]
	if bool(res["superseded"]):
		_detach_old_connection(s, int(c["id"]))
	_bind(c, s)
	_send(c, KingControllerProtocol.make_pair_ok(s.slot, str(msg["session"]), tick_rate))


func _bind(c: Dictionary, s: KingControllerSession) -> void:
	c["session"] = s
	c["state"] = KingControllerSession.State.CONNECTED
	s.connection_id = int(c["id"])
	s.input_state = KingControllerProtocol.new_input_state(_now)


## A resume replaced a still-open socket of the same session: close the old one without ending the session.
func _detach_old_connection(s: KingControllerSession, new_id: int) -> void:
	for old in _ws_conns:
		if old["session"] == s and int(old["id"]) != new_id:
			old["session"] = null
			_close_conn(old, 1000, "replaced by a newer connection")


func _find_conn(conn_id: int) -> Dictionary:
	for c in _ws_conns:
		if int(c["id"]) == conn_id:
			return c
	return {}


func _close_by_id(conn_id: int, reason: String) -> void:
	var c := _find_conn(conn_id)
	if not c.is_empty():
		c["session"] = null                              # the registry already handled the session
		_close_conn(c, 1001, reason)


## Closes the socket (the close frame is flushed for CLOSE_FLUSH_MS) and tells the registry.
func _close_conn(c: Dictionary, code: int, reason: String) -> void:
	if int(c["closing_at"]) > 0:
		return
	_connection_gone(c, reason)
	(c["peer"] as WebSocketPeer).close(code, reason)
	c["closing_at"] = _now + CLOSE_FLUSH_MS


func _connection_gone(c: Dictionary, reason: String) -> void:
	var s: KingControllerSession = c["session"]
	c["session"] = null
	if s != null:
		registry.connection_closed(s, int(c["id"]), reason, _now)


## The PC user revokes the controller in `slot`: it is told, then disconnected, and its session credential
## is dead for good. Returns false when the slot has no controller.
func revoke(slot: int) -> bool:
	var s: KingControllerSession = registry.sessions[slot] if slot >= 0 and slot < registry.sessions.size() else null
	if s == null:
		return false
	var c := _find_conn(s.connection_id)
	if not c.is_empty():
		_send(c, KingControllerProtocol.make_revoked())
	registry.revoke_slot(slot, Time.get_ticks_msec())
	if not c.is_empty():
		c["session"] = null
		_close_conn(c, 1000, "revoked")
	return true


func connection_count() -> int:
	return _ws_conns.size()
