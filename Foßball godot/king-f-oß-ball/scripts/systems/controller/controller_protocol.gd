class_name KingControllerProtocol
extends RefCounted

## Versioned input protocol for KING CONTROLLER.
## Pure logic (no I/O): encode/decode + validation. Used by both the server
## (KingControllerServer) and the headless test client.

const PROTOCOL_VERSION := 1

## Actions a phone is allowed to send. Must match the game's action names.
const ALLOWED_ACTIONS: Array[StringName] = [&"sprint", &"tackle", &"switch_player",
		&"pass", &"shoot", &"lob_pass", &"through_pass", &"cross"]

## Hard limits.
const MAX_MOVE_LEN := 1.0
const MAX_PRESSES_PER_MSG := 8
const MAX_MSG_BYTES := 1024
const TOKEN_LEN := 8
const RATE_LIMIT_MSGS_PER_SEC := 60
const FRESHNESS_MS := 1500

## Result of validating an incoming input message.
class InputResult:
	var ok: bool = false
	var reason: String = ""
	var move: Vector2 = Vector2.ZERO
	var press: Array[StringName] = []
	var release: Array[StringName] = []
	var seq: int = -1


## Build a pairing request (phone -> server).
static func make_pairing_request(token: String, name: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pair", "token": token, "name": name}


## Build an input message (phone -> server).
static func make_input(seq: int, move: Vector2, press: Array, release: Array, t_ms: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "input", "seq": seq,
			"move": {"x": move.x, "y": move.y},
			"press": press, "release": release, "t": t_ms}


## Build a ping.
static func make_ping(seq: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "ping", "seq": seq}


## Validate a pairing request. Returns {ok, reason, slot_hint}.
static func validate_pairing(msg: Dictionary, expected_token: String,
		used_tokens: Dictionary, slots_free: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "reconnect_slot": -1}
	if not msg.has("v") or int(msg["v"]) != PROTOCOL_VERSION:
		res["reason"] = "bad_version"
		return res
	if not msg.has("type") or String(msg["type"]) != "pair":
		res["reason"] = "bad_type"
		return res
	if not msg.has("token") or String(msg["token"]) != expected_token:
		res["reason"] = "bad_token"
		return res
	# Reconnect: if this token already owns a slot, allow re-bind.
	if used_tokens.has(expected_token):
		res["ok"] = true
		res["reconnect_slot"] = int(used_tokens[expected_token])
		return res
	if slots_free <= 0:
		res["reason"] = "no_slot"
		return res
	res["ok"] = true
	return res


## Validate an input message against per-client state.
## `state` is a Dictionary the caller keeps per client:
##   {seq, last_ms, msg_count_window_start, msg_count}
static func validate_input(msg: Dictionary, state: Dictionary, now_ms: int) -> InputResult:
	var r := InputResult.new()
	if not msg.has("v") or int(msg["v"]) != PROTOCOL_VERSION:
		r.reason = "bad_version"
		return r
	if not msg.has("type") or String(msg["type"]) != "input":
		r.reason = "bad_type"
		return r
	if not msg.has("seq"):
		r.reason = "missing_seq"
		return r
	var seq := int(msg["seq"])
	if seq <= int(state.get("seq", -1)):
		r.reason = "stale_seq"
		return r
	# freshness
	if msg.has("t"):
		var age := now_ms - int(msg["t"])
		if age > FRESHNESS_MS or age < -FRESHNESS_MS:
			r.reason = "stale_freshness"
			return r
	# rate limit (sliding 1s window)
	var window_start := int(state.get("window_start", now_ms))
	if now_ms - window_start >= 1000:
		window_start = now_ms
		state["count"] = 0
	state["window_start"] = window_start
	var count := int(state.get("count", 0)) + 1
	if count > RATE_LIMIT_MSGS_PER_SEC:
		r.reason = "rate_limited"
		return r
	state["count"] = count

	# move
	var move := Vector2.ZERO
	if msg.has("move") and msg["move"] is Dictionary:
		var m: Dictionary = msg["move"]
		var mx := clampf(float(m.get("x", 0.0)), -1.0, 1.0)
		var my := clampf(float(m.get("y", 0.0)), -1.0, 1.0)
		move = Vector2(mx, my)
		if move.length() > MAX_MOVE_LEN:
			move = move.normalized()

	# press/release
	var press: Array[StringName] = []
	var release: Array[StringName] = []
	if msg.has("press") and msg["press"] is Array:
		for a in msg["press"]:
			var an := StringName(String(a))
			if ALLOWED_ACTIONS.has(an) and not press.has(an):
				press.append(an)
				if press.size() >= MAX_PRESSES_PER_MSG:
					break
	if msg.has("release") and msg["release"] is Array:
		for a in msg["release"]:
			var an := StringName(String(a))
			if ALLOWED_ACTIONS.has(an) and not release.has(an):
				release.append(an)

	r.ok = true
	r.move = move
	r.press = press
	r.release = release
	r.seq = seq
	state["seq"] = seq
	return r


## Server -> client messages.
static func make_pair_ok(slot: int, tick_rate: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "paired", "slot": slot, "tick_rate": tick_rate}


static func make_pair_fail(reason: String) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pair_fail", "reason": reason}


static func make_pong(seq: int) -> Dictionary:
	return {"v": PROTOCOL_VERSION, "type": "pong", "seq": seq}
