class_name KingControllerProtocol
extends RefCounted

## Versioned wire protocol of KING CONTROLLER (phone browser <-> game). Pure logic, no I/O: byte-level
## parsing, strict message validation, input state validation. Used by `KingControllerRegistry` /
## `KingControllerServer` and by the tests. Documented in docs/KING_CONTROLLER_ARCHITECTURE.md.
##
## Version 3 (Complete Edition). Version 2 is still understood (MIN_PROTOCOL_VERSION): an old phone page
## keeps working, it just never receives the companion streams. Messages are JSON text frames, at most
## MAX_MSG_BYTES bytes:
##   phone -> PC   pair    {v, type, token, name?}        first connection, token from the QR code
##                 resume  {v, type, session}             reconnection with the session credential
##                 input   {v, type, seq, move{x,y}, held[], t?}   full controller state (level, not edges)
##                 ping    {v, type, seq}                 heartbeat
##                 bye     {v, type}                      the user disconnects
##                 view    {v, type, view, on}            which companion screen the phone shows (v3)
##                 tactic  {v, type, op, key?, value?, slot?, player_id?}  tactical request (v3)
##                 telemetry {v, type, rtt_ms, packets}    phone-measured round trip + packet count (v3)
##   PC -> phone   paired {slot, session, tick_rate, heartbeat_ms, timeout_ms, features[]} | pair_fail
##                 pong {seq} | revoked {} | error {reason}
##                 match {…}        live dashboard payload (v3)
##                 positions {…}    live mini-map payload (v3)
##                 event {…}        one match event (v3)
##                 tactic_result {ok, reason, state}  answer to a tactical request (v3)
##                 analytics {…}    connection analytics (v3)
##                 training {…}     lesson catalogue + connection facts (v3)
##
## Input freshness (the old protocol compared the browser's Date.now() with the server's monotonic clock,
## which are unrelated clock domains, so every real browser packet was rejected): NO client timestamp is
## used for any decision. The server stamps each packet with its own arrival time (milliseconds of the
## monotonic clock, taken once per frame, so packets of one frame share it). `t` is optional, must be a
## number if present, and is ignored. Freshness is enforced by (1) strictly increasing sequence numbers per
## connection, (2) a rate limit measured in arrival time, (3) a heartbeat timeout and (4) an input-gap rule
## in the registry: no input packet for INPUT_STALE_MS while something is held releases everything.
##
## Movement convention: `move` is in SCREEN convention like TouchJoystick / Input.get_vector: up = -1.

const PROTOCOL_VERSION := 3
## The oldest protocol version the server still understands. A v2 phone page keeps working (it only
## loses the companion streams), so a protocol bump never locks an old device out.
const MIN_PROTOCOL_VERSION := 2

## Actions that drive the player through the IntentProvider.
const PLAYER_ACTIONS: Array[StringName] = [&"sprint", &"tackle", &"switch_player",
		&"pass", &"shoot", &"lob_pass", &"through_pass", &"cross"]
## Match-control actions (never routed to a player): `pause` toggles the match's pause menu.
const SYSTEM_ACTIONS: Array[StringName] = [&"pause"]
const ALLOWED_ACTIONS: Array[StringName] = [&"sprint", &"tackle", &"switch_player",
		&"pass", &"shoot", &"lob_pass", &"through_pass", &"cross", &"pause"]

## The companion features this server offers. The phone enables/disables its screens by this list, so an
## older page never asks for something the PC cannot deliver.
const FEATURES: Array[String] = ["dashboard", "tactics", "map", "training", "analytics", "layouts", "haptics"]

## Message types that exist since v2 (every protocol version understands them).
const MESSAGE_TYPES: Array[String] = ["pair", "resume", "input", "ping", "bye"]
## Message types introduced by v3 (a v2 client never sends them).
const V3_MESSAGE_TYPES: Array[String] = ["view", "tactic", "telemetry"]
## Every type the server accepts from a phone.
const INCOMING_TYPES: Array[String] = ["pair", "resume", "input", "ping", "bye", "view", "tactic", "telemetry"]

## The companion screens a phone can ask for.
const VIEWS: Array[String] = ["controller", "dashboard", "tactics", "map", "training", "analytics"]
## What a phone may ask the PC to change (the PC decides WHICH team is allowed to do it).
const TACTIC_KEYS: Array[String] = ["formation", "mentality", "build_up", "passing_style",
		"pressing", "defensive_line", "width"]
const TACTIC_OPS: Array[String] = ["set", "sub", "query"]
## Tactic keys whose value is a 0..100 integer.
const TACTIC_INT_KEYS: Array[String] = ["pressing", "defensive_line", "width"]

## How many phones the match can really drive: slot 1 = the human player (`human_intent`), slot 2 = a friend
## on the opposing side (`human_intent2`, P10). Raise this only together with a verified match seat.
const SUPPORTED_SLOTS := 2

## Hard limits.
## MAX_MSG_BYTES was 1024 in v2 (input frames only). v3 adds live-data frames (the mini-map stream), so
## the cap is 4096; the input frame itself stays small and the position stream is quantised so a full
## 22-player frame is well under 1 KB.
const MAX_MSG_BYTES := 4096
## Cap for a single "input" frame (the hot path). A phone that sends a bigger control frame is rejected.
const MAX_INPUT_BYTES := 1024
const MAX_HELD := 9
const MAX_NAME_LEN := 40
const TOKEN_LEN := 8
const TOKEN_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SESSION_HEX_LEN := 32
const MAX_SEQ := 2147483647
const MAX_SEQ_JUMP := 100000
const MOVE_TOLERANCE := 1.05
## Limits of the v3 companion messages.
const MAX_VIEW_NAME_LEN := 20
const MAX_TACTIC_VALUE_LEN := 24
const MAX_TELEMETRY_RTT_MS := 5000
const MAX_SLOT_INDEX := 10

## Timing (milliseconds).
const RATE_LIMIT_MSGS_PER_SEC := 60

## Longest wall gap between two transport ticks that still counts as fully served time (ms). A bigger
## gap means the server's _process was frozen (synchronous match build, load spike): only this much
## counts and the frozen remainder is skipped, because the phone could not be served in that window
## no matter how fast it streamed.
const MAX_SERVED_GAP_MS := 100
const PING_LIMIT_PER_SEC := 10
const HEARTBEAT_INTERVAL_MS := 1000
const HEARTBEAT_TIMEOUT_MS := 3000
const INPUT_STALE_MS := 500
const TOKEN_TTL_MS := 120000
const MAX_FAILED_PAIRINGS := 5
const AUTH_TIMEOUT_MS := 5000
const RESUME_WINDOW_MS := 120000
const SESSION_MAX_AGE_MS := 4 * 60 * 60 * 1000
const REVOKED_MEMORY_MS := 10 * 60 * 1000
const PAUSE_DEBOUNCE_MS := 500
const MAX_INVALID_PER_CONNECTION := 20

## Result of validating an incoming input message.
class InputResult:
	var ok: bool = false
	var reason: String = ""
	var move: Vector2 = Vector2.ZERO
	var held: Array[StringName] = []
	var seq: int = -1


# --- parsing ------------------------------------------------------------------------------------

## Decodes one raw packet. The size is checked BEFORE any decoding or JSON parsing, so an oversized
## packet costs nothing. Returns {ok, reason, msg}; reasons: empty, too_large, bad_encoding, bad_json,
## bad_structure. Structure of the message itself: `validate_message`.
static func parse(raw: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "reason": "", "msg": {}}
	if raw.size() == 0:
		out["reason"] = "empty"
		return out
	if raw.size() > MAX_MSG_BYTES:
		out["reason"] = "too_large"
		return out
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer().size() != raw.size():
		out["reason"] = "bad_encoding"
		return out
	var json := JSON.new()
	if json.parse(text) != OK:
		out["reason"] = "bad_json"
		return out
	if not (json.data is Dictionary):
		out["reason"] = "bad_structure"
		return out
	out["ok"] = true
	out["msg"] = json.data
	return out


# --- message validation -------------------------------------------------------------------------

static func _is_number(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT) or (typeof(v) == TYPE_FLOAT and is_finite(float(v)))


static func _is_int_in(v: Variant, lo: int, hi: int) -> bool:
	if typeof(v) == TYPE_INT:
		return int(v) >= lo and int(v) <= hi
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)) and floorf(float(v)) == float(v):
		return float(v) >= float(lo) and float(v) <= float(hi)
	return false


static func is_token_text(s: Variant) -> bool:
	if typeof(s) != TYPE_STRING or (s as String).length() != TOKEN_LEN:
		return false
	for ch in (s as String):
		if not TOKEN_ALPHABET.contains(ch):
			return false
	return true


static func is_session_text(s: Variant) -> bool:
	if typeof(s) != TYPE_STRING or (s as String).length() != SESSION_HEX_LEN:
		return false
	return (s as String).is_valid_hex_number(false) and (s as String) == (s as String).to_lower()


static func _keys_ok(msg: Dictionary, allowed: Array) -> bool:
	for k in msg.keys():
		if not (k in allowed):
			return false
	return true


## Structural validation of a decoded message. Returns {ok, reason, type}. Reasons: bad_version,
## bad_type, missing_field, bad_field, bad_action, unexpected_field.
static func validate_message(msg: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "type": ""}
	if not msg.has("v") or not _is_int_in(msg["v"], MIN_PROTOCOL_VERSION, PROTOCOL_VERSION):
		out["reason"] = "bad_version"
		return out
	if not msg.has("type") or typeof(msg["type"]) != TYPE_STRING or not (String(msg["type"]) in INCOMING_TYPES):
		out["reason"] = "bad_type"
		return out
	var t := String(msg["type"])
	out["type"] = t
	# A v3-only message must arrive with v3: a v2 client must not use the new surface.
	if t in V3_MESSAGE_TYPES and int(msg["v"]) < PROTOCOL_VERSION:
		out["reason"] = "bad_version"
		return out
	match t:
		"pair":
			if not _keys_ok(msg, ["v", "type", "token", "name"]):
				out["reason"] = "unexpected_field"
			elif not msg.has("token"):
				out["reason"] = "missing_field"
			elif not is_token_text(msg["token"]):
				out["reason"] = "bad_field"
			elif msg.has("name") and (typeof(msg["name"]) != TYPE_STRING or String(msg["name"]).length() > MAX_NAME_LEN):
				out["reason"] = "bad_field"
			else:
				out["ok"] = true
		"resume":
			if not _keys_ok(msg, ["v", "type", "session"]):
				out["reason"] = "unexpected_field"
			elif not msg.has("session"):
				out["reason"] = "missing_field"
			elif not is_session_text(msg["session"]):
				out["reason"] = "bad_field"
			else:
				out["ok"] = true
		"ping":
			if not _keys_ok(msg, ["v", "type", "seq"]):
				out["reason"] = "unexpected_field"
			elif not msg.has("seq"):
				out["reason"] = "missing_field"
			elif not _is_int_in(msg["seq"], 0, MAX_SEQ):
				out["reason"] = "bad_field"
			else:
				out["ok"] = true
		"bye":
			out["ok"] = _keys_ok(msg, ["v", "type"])
			if not out["ok"]:
				out["reason"] = "unexpected_field"
		"input":
			out["reason"] = _input_problem(msg)
			out["ok"] = out["reason"] == ""
		"view":
			out["reason"] = _view_problem(msg)
			out["ok"] = out["reason"] == ""
		"tactic":
			out["reason"] = _tactic_problem(msg)
			out["ok"] = out["reason"] == ""
		"telemetry":
			out["reason"] = _telemetry_problem(msg)
			out["ok"] = out["reason"] == ""
	return out


## The phone tells the PC which companion screen it shows. The PC then pushes only the streams that
## screen needs (no full-page refresh, no traffic for a screen that is not open).
static func _view_problem(msg: Dictionary) -> String:
	if not _keys_ok(msg, ["v", "type", "view", "on"]):
		return "unexpected_field"
	if not msg.has("view") or not msg.has("on"):
		return "missing_field"
	if typeof(msg["view"]) != TYPE_STRING or not (String(msg["view"]) in VIEWS):
		return "bad_field"
	if typeof(msg["on"]) != TYPE_BOOL:
		return "bad_field"
	return ""


## A tactical request. The phone NEVER names a team: the PC derives the side from the controller slot,
## so one phone can never change the other phone's team.
static func _tactic_problem(msg: Dictionary) -> String:
	if not _keys_ok(msg, ["v", "type", "op", "key", "value", "slot", "player_id"]):
		return "unexpected_field"
	if not msg.has("op") or typeof(msg["op"]) != TYPE_STRING or not (String(msg["op"]) in TACTIC_OPS):
		return "bad_field"
	var op := String(msg["op"])
	if op == "set":
		if not msg.has("key") or typeof(msg["key"]) != TYPE_STRING or not (String(msg["key"]) in TACTIC_KEYS):
			return "bad_field"
		if not msg.has("value"):
			return "missing_field"
		var key := String(msg["key"])
		if key in TACTIC_INT_KEYS:
			if not _is_int_in(msg["value"], 0, 100):
				return "bad_field"
		else:
			if typeof(msg["value"]) != TYPE_STRING or String(msg["value"]).length() > MAX_TACTIC_VALUE_LEN:
				return "bad_field"
		return ""
	if op == "sub":
		if not msg.has("slot") or not _is_int_in(msg["slot"], 0, MAX_SLOT_INDEX):
			return "bad_field"
		if not msg.has("player_id") or typeof(msg["player_id"]) != TYPE_STRING \
				or String(msg["player_id"]).length() > MAX_NAME_LEN:
			return "bad_field"
		return ""
	# "query" needs no payload
	return ""


## The phone reports what it measured (round-trip time of its own ping, packets it sent). The PC can
## not measure a round trip alone, so the value is measured on the phone and only aggregated here.
static func _telemetry_problem(msg: Dictionary) -> String:
	if not _keys_ok(msg, ["v", "type", "rtt_ms", "packets"]):
		return "unexpected_field"
	if not msg.has("rtt_ms") or not _is_int_in(msg["rtt_ms"], 0, MAX_TELEMETRY_RTT_MS):
		return "bad_field"
	if not msg.has("packets") or not _is_int_in(msg["packets"], 0, 1000000):
		return "bad_field"
	return ""


static func _input_problem(msg: Dictionary) -> String:
	if not _keys_ok(msg, ["v", "type", "seq", "move", "held", "t"]):
		return "unexpected_field"
	if not msg.has("seq") or not msg.has("move") or not msg.has("held"):
		return "missing_field"
	if not _is_int_in(msg["seq"], 0, MAX_SEQ):
		return "bad_field"
	if msg.has("t") and not _is_number(msg["t"]):
		return "bad_field"                   # present but not a number: malformed (the value is never used)
	if typeof(msg["move"]) != TYPE_DICTIONARY:
		return "bad_field"
	var m: Dictionary = msg["move"]
	if not _keys_ok(m, ["x", "y"]) or not m.has("x") or not m.has("y"):
		return "bad_field"
	for axis in ["x", "y"]:
		if not _is_number(m[axis]) or absf(float(m[axis])) > MOVE_TOLERANCE:
			return "bad_field"
	if typeof(msg["held"]) != TYPE_ARRAY or (msg["held"] as Array).size() > MAX_HELD:
		return "bad_field"
	for a in (msg["held"] as Array):
		if typeof(a) != TYPE_STRING:
			return "bad_field"
		if not (StringName(a) in ALLOWED_ACTIONS):
			return "bad_action"
	return ""


# --- input state (sequence, rate) ------------------------------------------------------------------

## Fresh per-connection input state. `arrival_ms` = the server's clock when the connection was authenticated.
static func new_input_state(arrival_ms: int) -> Dictionary:
	return {"seq": -1, "window_start": arrival_ms, "count": 0, "dropped": 0}


## Validates an input message against the connection's state, using the SERVER arrival time only.
## `msg` must already have passed `validate_message`. Reasons: duplicate_seq, out_of_order_seq, seq_jump,
## rate_limited. The sequence only advances for accepted packets.
static func process_input(msg: Dictionary, state: Dictionary, arrival_ms: int) -> InputResult:
	var r := InputResult.new()
	var seq := int(msg["seq"])
	var last := int(state.get("seq", -1))
	if seq == last:
		r.reason = "duplicate_seq"
		return r
	if seq < last:
		r.reason = "out_of_order_seq"
		return r
	if last >= 0 and seq - last > MAX_SEQ_JUMP:
		r.reason = "seq_jump"
		return r
	# Rate limit: fixed one-second window in arrival time.
	var window_start := int(state.get("window_start", arrival_ms))
	if arrival_ms - window_start >= 1000:
		window_start = arrival_ms
		state["count"] = 0
	state["window_start"] = window_start
	var count := int(state.get("count", 0)) + 1
	if count > RATE_LIMIT_MSGS_PER_SEC:
		state["dropped"] = int(state.get("dropped", 0)) + 1
		r.reason = "rate_limited"
		return r
	state["count"] = count
	var m: Dictionary = msg["move"]
	r.move = Vector2(clampf(float(m["x"]), -1.0, 1.0), clampf(float(m["y"]), -1.0, 1.0))
	if r.move.length() > 1.0:
		r.move = r.move.normalized()
	for a in (msg["held"] as Array):
		var an := StringName(String(a))
		if not r.held.has(an):
			r.held.append(an)
	r.ok = true
	r.seq = seq
	state["seq"] = seq
	return r


## Structural validation + state validation in one call (convenience for tests and simple callers).
static func validate_input(msg: Dictionary, state: Dictionary, arrival_ms: int) -> InputResult:
	var v := validate_message(msg)
	if not bool(v["ok"]) or String(v["type"]) != "input":
		var r := InputResult.new()
		r.reason = String(v["reason"]) if String(v["reason"]) != "" else "bad_type"
		return r
	return process_input(msg, state, arrival_ms)


## True when a ping may be answered now (own one-second window, separate from input).
static func ping_allowed(state: Dictionary, arrival_ms: int) -> bool:
	var ws := int(state.get("ping_window", arrival_ms))
	if arrival_ms - ws >= 1000:
		ws = arrival_ms
		state["ping_count"] = 0
	state["ping_window"] = ws
	state["ping_count"] = int(state.get("ping_count", 0)) + 1
	return int(state["ping_count"]) <= PING_LIMIT_PER_SEC


# --- builders ------------------------------------------------------------------------------------

static func make_pairing_request(token: String, name: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pair", "token": token, "name": name}


static func make_resume_request(session: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "resume", "session": session}


static func make_input(seq: int, move: Vector2, held: Array, t_ms: int = -1) -> Dictionary:
	var d := {"v": PROTOCOL_VERSION, "type": "input", "seq": seq, "move": {"x": move.x, "y": move.y}, "held": held}
	if t_ms >= 0:
		d["t"] = t_ms
	return d


static func make_ping(seq: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "ping", "seq": seq}


static func make_bye() -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "bye"}


static func make_pair_ok(slot: int, session: String, tick_rate: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "paired", "slot": slot, "session": session, "tick_rate": tick_rate,
			"heartbeat_ms": HEARTBEAT_INTERVAL_MS, "timeout_ms": HEARTBEAT_TIMEOUT_MS,
			"min_v": MIN_PROTOCOL_VERSION, "features": FEATURES.duplicate()}


static func make_pair_fail(reason: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pair_fail", "reason": reason}


static func make_pong(seq: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pong", "seq": seq}


static func make_revoked() -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "revoked"}


static func make_error(reason: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "error", "reason": reason}


# --- v3 builders --------------------------------------------------------------------------------------

## The phone tells the PC which companion screen it shows.
static func make_view(view: String, on: bool) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "view", "view": view, "on": on}


## A tactical request. `key`/`value` for "set", `slot`/`player_id` for "sub".
static func make_tactic(op: String, key: String = "", value: Variant = null, slot: int = -1,
		player_id: String = "") -> Dictionary:
	var d := {"v": PROTOCOL_VERSION, "type": "tactic", "op": op}
	if op == "set":
		d["key"] = key
		d["value"] = value
	elif op == "sub":
		d["slot"] = slot
		d["player_id"] = player_id
	return d


## The phone reports its own measurement (round trip of a ping) and how many packets it sent.
static func make_telemetry(rtt_ms: int, packets: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "telemetry", "rtt_ms": rtt_ms, "packets": packets}


## The live dashboard frame.
static func make_match(payload: Dictionary) -> Dictionary:
	var d := payload.duplicate()
	d["v"] = PROTOCOL_VERSION
	d["type"] = "match"
	return d


## The live mini-map frame.
static func make_positions(payload: Dictionary) -> Dictionary:
	var d := payload.duplicate()
	d["v"] = PROTOCOL_VERSION
	d["type"] = "positions"
	return d


## One match event (goal, card, substitution, ...).
static func make_event(payload: Dictionary) -> Dictionary:
	var d := payload.duplicate()
	d["v"] = PROTOCOL_VERSION
	d["type"] = "event"
	return d


## The answer to a tactical request: ok, a reason code and the resulting state.
static func make_tactic_result(ok: bool, reason: String, state: Dictionary = {}) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "tactic_result", "ok": ok, "reason": reason, "state": state}


## The connection analytics of the PC.
static func make_analytics(payload: Dictionary) -> Dictionary:
	var d := payload.duplicate()
	d["v"] = PROTOCOL_VERSION
	d["type"] = "analytics"
	return d


## The training catalogue and the connection facts the lessons need.
static func make_training(payload: Dictionary) -> Dictionary:
	var d := payload.duplicate()
	d["v"] = PROTOCOL_VERSION
	d["type"] = "training"
	return d
