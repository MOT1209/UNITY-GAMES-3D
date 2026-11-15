class_name KingControllerRegistry
extends RefCounted

## The rules of KING CONTROLLER without any socket (P9): pairing tokens, sessions, slots, input state,
## heartbeat / resume windows, revocation. Everything takes the clock as an argument (`now_ms`, the
## server's monotonic milliseconds) and the random source is injectable, so every rule is unit-testable
## and deterministic. `KingControllerServer` is the transport that feeds packets in and sockets out.
##
## Security model (see docs/KING_CONTROLLER_ARCHITECTURE.md, honest limits included):
##  * Pairing token: TOKEN_LEN characters from a 32-symbol alphabet (40 bits) drawn from the platform CSPRNG
##    (`Crypto.generate_random_bytes`), valid TOKEN_TTL_MS, ONE-TIME (consumed by the first successful
##    pairing), replaced after MAX_FAILED_PAIRINGS wrong guesses. It travels in the QR code / URL only.
##  * Session credential: 128 random bits issued in the `paired` reply, stored only as a hash; used for
##    `resume`. Expires RESUME_WINDOW_MS after the connection was lost and SESSION_MAX_AGE_MS after pairing.
##  * A revoked / expired / replaced session can never take a slot back; the slot belongs to the session
##    that currently owns it.

signal changed()
signal slot_connected(slot: int)
## The controller of `slot` is gone (connection lost, timeout, revoked, bye): every held input was released.
signal slot_lost(slot: int, reason: String)
## Edge events for the match: movement in screen convention, newly pressed / released PLAYER actions.
signal input(slot: int, move: Vector2, press: Array, release: Array)
signal pause_requested(slot: int)
signal log_event(text: String)

var max_slots := KingControllerProtocol.SUPPORTED_SLOTS
var token := ""
var token_issued_ms := 0
var failed_pairings := 0
var sessions: Array[KingControllerSession] = []     # index = slot (null = free)
var revoked_hashes: Dictionary = {}                  # credential hash -> forget-at ms
var counters: Dictionary = {"paired": 0, "resumed": 0, "revoked": 0, "rejected": 0, "dropped": 0, "timeouts": 0}

var _random: Callable                                # (byte_count: int) -> PackedByteArray


func _init(p_max_slots: int = KingControllerProtocol.SUPPORTED_SLOTS, p_random: Callable = Callable()) -> void:
	max_slots = clampi(p_max_slots, 1, KingControllerProtocol.SUPPORTED_SLOTS)
	_random = p_random if p_random.is_valid() else _crypto_bytes
	sessions.resize(max_slots)


static func _crypto_bytes(n: int) -> PackedByteArray:
	return Crypto.new().generate_random_bytes(n)


# --- tokens ---------------------------------------------------------------------------------------

## New pairing token (new QR code). Resets the wrong-guess counter.
func rotate_token(now_ms: int) -> void:
	var raw := _random.call(KingControllerProtocol.TOKEN_LEN * 2) as PackedByteArray
	var alphabet := KingControllerProtocol.TOKEN_ALPHABET
	var out := ""
	for i in KingControllerProtocol.TOKEN_LEN:
		out += alphabet[int(raw[i]) % alphabet.length()]       # 256 % 32 == 0: no modulo bias
	token = out
	token_issued_ms = now_ms
	failed_pairings = 0
	changed.emit()


func token_remaining_ms(now_ms: int) -> int:
	return maxi(0, KingControllerProtocol.TOKEN_TTL_MS - (now_ms - token_issued_ms))


## Constant-time comparison of two equal-purpose strings (no early exit on the first difference).
static func _same(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff := 0
	for i in a.length():
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0


func _hex(n: int) -> String:
	return (_random.call(n) as PackedByteArray).hex_encode()


# --- pairing / resume -----------------------------------------------------------------------------

func free_slot() -> int:
	for i in max_slots:
		if sessions[i] == null:
			return i
	return -1


func free_slots() -> int:
	var n := 0
	for i in max_slots:
		if sessions[i] == null:
			n += 1
	return n


## First connection with the QR token. Returns {ok, reason, session, credential}. Reasons: token_expired,
## too_many_attempts, bad_token, no_slot. The token is consumed by a success and replaced.
func try_pair(token_text: String, device_name: String, now_ms: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "session": null, "credential": ""}
	if failed_pairings >= KingControllerProtocol.MAX_FAILED_PAIRINGS:
		rotate_token(now_ms)
		counters["rejected"] += 1
		res["reason"] = "too_many_attempts"
		return res
	if now_ms - token_issued_ms > KingControllerProtocol.TOKEN_TTL_MS:
		rotate_token(now_ms)
		counters["rejected"] += 1
		res["reason"] = "token_expired"
		return res
	if not _same(token_text, token):
		failed_pairings += 1
		counters["rejected"] += 1
		res["reason"] = "bad_token"
		if failed_pairings >= KingControllerProtocol.MAX_FAILED_PAIRINGS:
			rotate_token(now_ms)
			res["reason"] = "too_many_attempts"
		log_event.emit("pairing refused (%s)" % res["reason"])
		return res
	var slot := free_slot()
	if slot < 0:
		counters["rejected"] += 1
		res["reason"] = "no_slot"
		log_event.emit("pairing refused (no free slot)")
		return res
	var credential := _hex(16)
	var s := KingControllerSession.new()
	s.id = _hex(4)
	s.slot = slot
	s.name = device_name.strip_edges().left(KingControllerProtocol.MAX_NAME_LEN)
	s.credential_hash = credential.sha256_text()
	s.created_ms = now_ms
	s.last_seen_ms = now_ms
	s.last_input_ms = now_ms
	s.state = KingControllerSession.State.CONNECTED
	s.input_state = KingControllerProtocol.new_input_state(now_ms)
	sessions[slot] = s
	counters["paired"] += 1
	rotate_token(now_ms)                          # one-time: the next device needs a new QR code
	res["ok"] = true
	res["session"] = s
	res["credential"] = credential
	log_event.emit("controller %s paired in slot %d" % [s.id, slot])
	slot_connected.emit(slot)
	changed.emit()
	return res


func session_by_hash(h: String) -> KingControllerSession:
	for s in sessions:
		if s != null and _same(s.credential_hash, h):
			return s
	return null


## Reconnection with the session credential. Returns {ok, reason, session, superseded}. Reasons:
## revoked, session_unknown, session_expired. `superseded` = the session still had a live connection:
## the caller must close that old socket (the new one replaces it).
func try_resume(credential: String, now_ms: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "session": null, "superseded": false}
	var h := credential.sha256_text()
	_forget_old_revocations(now_ms)
	if revoked_hashes.has(h):
		counters["rejected"] += 1
		res["reason"] = "revoked"
		return res
	var s := session_by_hash(h)
	if s == null:
		counters["rejected"] += 1
		res["reason"] = "session_unknown"
		return res
	if now_ms - s.created_ms > KingControllerProtocol.SESSION_MAX_AGE_MS \
			or (s.state == KingControllerSession.State.CONNECTION_LOST and now_ms - s.lost_ms > KingControllerProtocol.RESUME_WINDOW_MS):
		_drop_session(s, "expired", now_ms)
		counters["rejected"] += 1
		res["reason"] = "session_expired"
		return res
	var was_live := s.is_live()
	s.state = KingControllerSession.State.RECONNECTING if was_live else KingControllerSession.State.CONNECTED
	s.input_state = KingControllerProtocol.new_input_state(now_ms)   # a new connection starts a new sequence
	s.last_seen_ms = now_ms
	s.last_input_ms = now_ms
	s.connections += 1
	s.clear_inputs()
	if was_live:
		s.state = KingControllerSession.State.CONNECTED
	counters["resumed"] += 1
	res["ok"] = true
	res["session"] = s
	res["superseded"] = was_live
	log_event.emit("controller %s resumed in slot %d" % [s.id, s.slot])
	if not was_live:
		slot_connected.emit(s.slot)
	changed.emit()
	return res


# --- ending sessions ----------------------------------------------------------------------------

## The user (PC side) revokes the controller of `slot`: its credential can never be used again.
func revoke_slot(slot: int, now_ms: int) -> bool:
	if slot < 0 or slot >= max_slots or sessions[slot] == null:
		return false
	var s := sessions[slot]
	revoked_hashes[s.credential_hash] = now_ms + KingControllerProtocol.REVOKED_MEMORY_MS
	s.state = KingControllerSession.State.REVOKED
	counters["revoked"] += 1
	log_event.emit("controller %s revoked" % s.id)
	_release_all(s)
	sessions[slot] = null
	slot_lost.emit(slot, "revoked")
	changed.emit()
	return true


## The phone said goodbye: the session ends and the slot is free at once.
func end_session(s: KingControllerSession, reason: String, now_ms: int) -> void:
	_drop_session(s, reason, now_ms)


func _drop_session(s: KingControllerSession, reason: String, _now_ms: int) -> void:
	if s == null or sessions[s.slot] != s:
		return
	var had_live := s.is_live()
	_release_all(s)
	s.state = KingControllerSession.State.DISCONNECTED
	sessions[s.slot] = null
	log_event.emit("controller %s ended (%s)" % [s.id, reason])
	if had_live:
		slot_lost.emit(s.slot, reason)
	changed.emit()


## The socket of `s` is gone (closed, error, heartbeat timeout). Held inputs are released NOW; the slot stays
## reserved for the resume window. `connection_id` guards against a late close of an OLD connection.
func connection_closed(s: KingControllerSession, conn_id: int, reason: String, now_ms: int) -> void:
	if s == null or sessions[s.slot] != s or s.connection_id != conn_id:
		return
	if s.state != KingControllerSession.State.CONNECTED:
		return
	_release_all(s)
	s.state = KingControllerSession.State.CONNECTION_LOST
	s.lost_ms = now_ms
	s.connection_id = -1
	log_event.emit("controller %s lost (%s)" % [s.id, reason])
	slot_lost.emit(s.slot, reason)
	changed.emit()


## Releases every held button and zeroes the stick (stuck-input protection).
func _release_all(s: KingControllerSession) -> void:
	var released: Array = s.held.keys()
	var had_move := s.move != Vector2.ZERO
	s.clear_inputs()
	if not released.is_empty() or had_move:
		input.emit(s.slot, Vector2.ZERO, [], released)


func _forget_old_revocations(now_ms: int) -> void:
	for h in revoked_hashes.keys():
		if now_ms >= int(revoked_hashes[h]):
			revoked_hashes.erase(h)


# --- input / heartbeat -----------------------------------------------------------------------------

## Any valid packet of a live session counts as a sign of life.
func touch(s: KingControllerSession, now_ms: int) -> void:
	if s != null:
		s.last_seen_ms = now_ms


## Applies a validated input packet. `result` comes from `KingControllerProtocol.process_input`.
## Emits the PLAYER-action edges (held now vs. held before) and, for `pause`, a debounced single request.
func apply_input(s: KingControllerSession, result: KingControllerProtocol.InputResult, now_ms: int) -> void:
	if s == null or not s.is_live():
		return
	s.last_seen_ms = now_ms
	s.last_input_ms = now_ms
	var press: Array = []
	var release: Array = []
	var now_held := {}
	var pause_now := false
	for a in result.held:
		if a in KingControllerProtocol.SYSTEM_ACTIONS:
			pause_now = pause_now or a == &"pause"
		else:
			now_held[a] = true
			if not s.held.has(a):
				press.append(a)
	for a in s.held.keys():
		if not now_held.has(a):
			release.append(a)
	s.held = now_held
	var moved := result.move != s.move
	s.move = result.move
	if not press.is_empty() or not release.is_empty() or moved:
		input.emit(s.slot, result.move, press, release)
	# Pause: one request per press (rising edge) and at most one per PAUSE_DEBOUNCE_MS.
	if pause_now and not s.pause_down and now_ms - s.last_pause_ms >= KingControllerProtocol.PAUSE_DEBOUNCE_MS:
		s.last_pause_ms = now_ms
		pause_requested.emit(s.slot)
	s.pause_down = pause_now


## Ends every session (server stop): all inputs are released first.
func clear_all(now_ms: int) -> void:
	for s in sessions.duplicate():
		if s != null:
			_drop_session(s, "server stopped", now_ms)
	changed.emit()


## Time-driven rules. Returns [{session, connection_id, reason}] for every socket the transport must close.
##  * heartbeat: no packet for HEARTBEAT_TIMEOUT_MS -> connection lost (inputs released),
##  * input gap: something held / stick away from centre but no input for INPUT_STALE_MS -> released,
##  * resume window / session age -> the slot is freed,
##  * an unused or expired token is replaced so the QR code on the PC never goes stale.
func tick(now_ms: int) -> Array:
	var to_close: Array = []
	for s in sessions:
		if s == null:
			continue
		if s.state == KingControllerSession.State.CONNECTED:
			if now_ms - s.last_seen_ms > KingControllerProtocol.HEARTBEAT_TIMEOUT_MS:
				counters["timeouts"] += 1
				var cid := s.connection_id
				connection_closed(s, cid, "heartbeat_timeout", now_ms)
				to_close.append({"session": s, "connection_id": cid, "reason": "heartbeat_timeout"})
				continue
			if (not s.held.is_empty() or s.move != Vector2.ZERO) and now_ms - s.last_input_ms > KingControllerProtocol.INPUT_STALE_MS:
				log_event.emit("controller %s input gap: inputs released" % s.id)
				_release_all(s)
		elif s.state == KingControllerSession.State.CONNECTION_LOST:
			if now_ms - s.lost_ms > KingControllerProtocol.RESUME_WINDOW_MS:
				_drop_session(s, "resume window expired", now_ms)
				continue
		if now_ms - s.created_ms > KingControllerProtocol.SESSION_MAX_AGE_MS:
			var old_cid := s.connection_id
			_drop_session(s, "session expired", now_ms)
			to_close.append({"session": s, "connection_id": old_cid, "reason": "session_expired"})
	if now_ms - token_issued_ms > KingControllerProtocol.TOKEN_TTL_MS:
		rotate_token(now_ms)
	_forget_old_revocations(now_ms)
	return to_close


# --- snapshot for the UI ----------------------------------------------------------------------------

## One entry per advertised slot: {slot, supported, state, id, name, age_ms}. Slots beyond SUPPORTED_SLOTS
## are listed as unsupported so the UI can say so instead of pretending four-player support.
func snapshot(now_ms: int, listed_slots: int = 4) -> Array:
	var out: Array = []
	for i in listed_slots:
		if i >= max_slots:
			out.append({"slot": i, "supported": false, "state": "unsupported", "id": "", "name": "", "age_ms": 0})
			continue
		var s := sessions[i]
		if s == null:
			out.append({"slot": i, "supported": true, "state": "disconnected", "id": "", "name": "", "age_ms": 0})
		else:
			out.append({"slot": i, "supported": true, "state": s.state_name(), "id": s.id, "name": s.name,
					"age_ms": now_ms - s.created_ms})
	return out


func connected_count() -> int:
	var n := 0
	for s in sessions:
		if s != null and s.state == KingControllerSession.State.CONNECTED:
			n += 1
	return n
