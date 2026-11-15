## KING CONTROLLER (P9): session / registry rules and LAN address selection. Pure logic with an injected clock
## and random source: no sockets, fully deterministic.
extends Node

const P = preload("res://scripts/systems/controller/controller_protocol.gd")
const S = preload("res://scripts/systems/controller/controller_session.gd")

var _passed := 0
var _failed := 0
var _events: Array = []        # [kind, slot, ...]


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== KING FOOTBALL - Controller session validation ===")
	await get_tree().process_frame
	_test_token()
	_test_pairing_rules()
	_test_slots()
	_test_resume_and_revoke()
	_test_input_edges_and_pause()
	_test_timeouts()
	_test_snapshot()
	_test_network()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


var _ctr := 0


func _fake_random(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in n:
		_ctr += 1
		b.append((_ctr * 37 + 11) % 256)
	return b


func _reg() -> KingControllerRegistry:
	var r := KingControllerRegistry.new(1, _fake_random)
	r.rotate_token(0)
	_events.clear()
	r.slot_connected.connect(func(slot: int) -> void: _events.append(["up", slot]))
	r.slot_lost.connect(func(slot: int, reason: String) -> void: _events.append(["lost", slot, reason]))
	r.input.connect(func(slot: int, move: Vector2, press: Array, release: Array) -> void: _events.append(["input", slot, move, press, release]))
	r.pause_requested.connect(func(slot: int) -> void: _events.append(["pause", slot]))
	return r


func _count(kind: String) -> int:
	var n := 0
	for e in _events:
		if e[0] == kind:
			n += 1
	return n


func _inp(seq: int, move: Vector2, held: Array) -> KingControllerProtocol.InputResult:
	return P.process_input(P.make_input(seq, move, held), P.new_input_state(0), 0)


func _test_token() -> void:
	var r := KingControllerRegistry.new()      # real CSPRNG
	r.rotate_token(0)
	_check(P.is_token_text(r.token), "pairing token has the documented format (8 chars, 32-symbol alphabet)")
	var seen := {}
	for i in 50:
		r.rotate_token(i)
		seen[r.token] = true
	_check(seen.size() >= 49, "tokens come from the CSPRNG (50 draws, %d distinct)" % seen.size())
	_check(r.token_remaining_ms(49) == P.TOKEN_TTL_MS and r.token_remaining_ms(49 + P.TOKEN_TTL_MS + 5) == 0, "token remaining time counts down to zero at the TTL")


func _test_pairing_rules() -> void:
	var r := _reg()
	var tok := r.token
	var bad := r.try_pair("AAAAAAAA" if tok != "AAAAAAAA" else "BBBBBBBB", "x", 1000)
	_check(not bad["ok"] and bad["reason"] == "bad_token", "wrong token refused")
	_check(r.connected_count() == 0, "no session after a wrong token")
	var ok := r.try_pair(tok, "My phone", 1000)
	_check(ok["ok"] and ok["session"] != null, "right token pairs")
	_check(ok["credential"] != tok and P.is_session_text(ok["credential"]), "session credential is separate from the token")
	var s: KingControllerSession = ok["session"]
	_check(s.credential_hash == (ok["credential"] as String).sha256_text() and s.credential_hash != ok["credential"], "only the hash of the credential is stored")
	_check(r.token != tok, "the token is one-time: replaced after a successful pairing")
	_check(r.try_pair(tok, "replay", 1500)["reason"] in ["bad_token", "no_slot"], "the used token cannot be replayed")
	_check(_count("up") == 1, "slot_connected emitted once")
	# expiry
	var r2 := _reg()
	var t2 := r2.token
	var late := r2.try_pair(t2, "late", P.TOKEN_TTL_MS + 1)
	_check(not late["ok"] and late["reason"] == "token_expired", "an expired token is refused")
	_check(r2.token != t2, "an expired token is replaced")
	# brute force
	var r3 := _reg()
	var old := r3.token
	var last := ""
	for i in P.MAX_FAILED_PAIRINGS:
		last = r3.try_pair("AAAAAAAA", "x", 100 + i)["reason"]
	_check(last == "too_many_attempts" and r3.token != old, "repeated wrong guesses rotate the token")
	var guess := r3.try_pair(old, "x", 200)
	_check(not guess["ok"], "the rotated-away token is dead")
	_check(r3.counters["rejected"] >= P.MAX_FAILED_PAIRINGS, "rejections are counted")


func _test_slots() -> void:
	var r := _reg()
	_check(r.max_slots == 1 and r.sessions.size() == 1, "a one-slot registry exposes one slot")
	var big := KingControllerRegistry.new(4, _fake_random)
	_check(big.max_slots == P.SUPPORTED_SLOTS and big.sessions.size() == 2, "asking for 4 slots still yields only the supported number (2)")
	var a := r.try_pair(r.token, "A", 0)
	var b := r.try_pair(r.token, "B", 10)
	_check(a["ok"] and not b["ok"] and b["reason"] == "no_slot", "two controllers can never share one player slot")
	_check(r.free_slots() == 0, "no free slot reported while occupied")
	# two-slot registry: each phone gets its own slot, a third is refused
	var t := KingControllerRegistry.new(2, _fake_random)
	t.rotate_token(0)
	var p1 := t.try_pair(t.token, "P1", 0)
	var p2 := t.try_pair(t.token, "P2", 5)
	var p3 := t.try_pair(t.token, "P3", 9)
	_check(p1["ok"] and p2["ok"] and (p1["session"] as KingControllerSession).slot == 0 and (p2["session"] as KingControllerSession).slot == 1, "two phones get slots 1 and 2")
	_check(not p3["ok"] and p3["reason"] == "no_slot", "a third phone is refused")
	t.revoke_slot(0, 20)
	var p4 := t.try_pair(t.token, "P4", 30)
	_check(p4["ok"] and (p4["session"] as KingControllerSession).slot == 0 and t.sessions[1] == p2["session"], "a freed slot 1 is reassigned without touching slot 2")


func _test_resume_and_revoke() -> void:
	var r := _reg()
	var a := r.try_pair(r.token, "A", 0)
	var s: KingControllerSession = a["session"]
	s.connection_id = 1
	var cred: String = a["credential"]
	r.apply_input(s, _inp(0, Vector2(1, 0), ["sprint", "shoot"]), 100)
	r.connection_closed(s, 1, "closed", 200)
	_check(s.state == S.State.CONNECTION_LOST and r.sessions[0] == s, "lost connection keeps the slot reserved")
	var last_input: Array = []
	for e in _events:
		if e[0] == "input":
			last_input = e
	_check(last_input[2] == Vector2.ZERO and (last_input[4] as Array).has(&"sprint") and (last_input[4] as Array).has(&"shoot"), "connection loss releases held buttons and resets the stick")
	_check(_count("lost") == 1, "slot_lost emitted on connection loss")
	# a late close of an OLD connection must not affect a new one
	var res := r.try_resume(cred, 300)
	_check(res["ok"] and not res["superseded"], "resume within the window re-binds the session")
	s.connection_id = 2
	r.connection_closed(s, 1, "late close", 310)
	_check(s.state == S.State.CONNECTED, "a late close of an old connection is ignored")
	_check(s.input_state["seq"] == -1, "resume starts a fresh sequence")
	# resume while still live -> superseded
	var res2 := r.try_resume(cred, 320)
	_check(res2["ok"] and res2["superseded"], "resuming a live session supersedes the old connection")
	# unknown credential
	_check(r.try_resume("f".repeat(32), 330)["reason"] == "session_unknown", "unknown credential refused")
	# revoke
	_check(r.revoke_slot(0, 400), "revoke succeeds")
	_check(r.sessions[0] == null and r.connected_count() == 0, "revoke frees the slot")
	_check(r.try_resume(cred, 410)["reason"] == "revoked", "a revoked credential can never resume")
	_check(not r.revoke_slot(0, 420), "revoking a free slot is a no-op")
	# revoked credential memory expires, but the session is gone anyway
	var late := r.try_resume(cred, 410 + P.REVOKED_MEMORY_MS + 1)
	_check(late["reason"] == "session_unknown", "after the tombstone expires the credential is simply unknown (never valid)")
	# a new pairing after revoke gets a fresh credential and the slot
	var again := r.try_pair(r.token, "A2", 500)
	_check(again["ok"] and again["credential"] != cred, "a new pairing after revoke works with a new credential")
	# resume window
	var r2 := _reg()
	var p2 := r2.try_pair(r2.token, "A", 0)
	var s2: KingControllerSession = p2["session"]
	s2.connection_id = 5
	r2.connection_closed(s2, 5, "x", 1000)
	var exp := r2.try_resume(p2["credential"], 1000 + P.RESUME_WINDOW_MS + 1)
	_check(not exp["ok"] and exp["reason"] == "session_expired", "no indefinite stale reconnect: the resume window ends")
	_check(r2.sessions[0] == null, "an expired session frees its slot")
	# max age
	var r3 := _reg()
	var p3 := r3.try_pair(r3.token, "A", 0)
	var old := r3.try_resume(p3["credential"], P.SESSION_MAX_AGE_MS + 1)
	_check(not old["ok"] and old["reason"] == "session_expired", "a session older than the maximum age cannot resume")


func _test_input_edges_and_pause() -> void:
	var r := _reg()
	var a := r.try_pair(r.token, "A", 0)
	var s: KingControllerSession = a["session"]
	_events.clear()
	r.apply_input(s, _inp(0, Vector2(0, -1), ["pass"]), 10)
	var e0: Array = _events[0]
	_check(e0[0] == "input" and (e0[3] as Array).has(&"pass") and e0[2] == Vector2(0, -1), "first state yields a press edge + move")
	_events.clear()
	r.apply_input(s, _inp(1, Vector2(0, -1), ["pass"]), 20)
	_check(_events.is_empty(), "identical state yields no event")
	r.apply_input(s, _inp(2, Vector2(0, -1), ["pass", "shoot"]), 30)
	_check((_events[0][3] as Array) == [&"shoot"], "only the NEW button is a press edge")
	r.apply_input(s, _inp(3, Vector2.ZERO, []), 40)
	var rel: Array = _events[_events.size() - 1]
	_check((rel[4] as Array).has(&"pass") and (rel[4] as Array).has(&"shoot"), "buttons removed from held[] become releases")
	# pause
	_events.clear()
	r.apply_input(s, _inp(4, Vector2.ZERO, ["pause"]), 1000)
	_check(_count("pause") == 1 and _count("input") == 0, "pause = one request, never a player input")
	r.apply_input(s, _inp(5, Vector2.ZERO, ["pause"]), 1010)
	_check(_count("pause") == 1, "holding pause does not repeat")
	r.apply_input(s, _inp(6, Vector2.ZERO, []), 1020)
	r.apply_input(s, _inp(7, Vector2.ZERO, ["pause"]), 1030)
	_check(_count("pause") == 1, "pause inside the debounce window is ignored")
	r.apply_input(s, _inp(8, Vector2.ZERO, []), 1040)
	r.apply_input(s, _inp(9, Vector2.ZERO, ["pause"]), 1000 + P.PAUSE_DEBOUNCE_MS + 1)
	_check(_count("pause") == 2, "a later pause press is a new request")
	_check(not s.held.has(&"pause"), "pause is never stored as a held player action")
	# inputs for a dead session are ignored
	r.revoke_slot(0, 2000)
	_events.clear()
	r.apply_input(s, _inp(10, Vector2(1, 0), ["shoot"]), 2010)
	_check(_events.is_empty(), "input for an ended session is ignored")


func _test_timeouts() -> void:
	var r := _reg()
	var a := r.try_pair(r.token, "A", 0)
	var s: KingControllerSession = a["session"]
	s.connection_id = 9
	r.apply_input(s, _inp(0, Vector2(1, 0), ["sprint"]), 100)
	# input gap: connected (pings arriving) but the input stream stopped while something is held
	r.touch(s, 400)
	_events.clear()
	var closes := r.tick(100 + P.INPUT_STALE_MS + 50)
	_check(closes.is_empty() and s.held.is_empty() and s.move == Vector2.ZERO, "input gap releases held buttons and the stick")
	_check(_count("input") == 1 and (_events[0][4] as Array).has(&"sprint"), "the gap release is reported as an input release")
	_check(s.state == S.State.CONNECTED, "an input gap alone does not disconnect")
	# heartbeat timeout
	_events.clear()
	var closes2 := r.tick(s.last_seen_ms + P.HEARTBEAT_TIMEOUT_MS + 1)
	_check(closes2.size() == 1 and closes2[0]["connection_id"] == 9 and closes2[0]["reason"] == "heartbeat_timeout", "heartbeat timeout asks the transport to close the socket")
	_check(s.state == S.State.CONNECTION_LOST and _count("lost") == 1, "timeout -> connection_lost + slot_lost")
	_check(r.counters["timeouts"] == 1, "timeouts are counted")
	# resume window then free
	r.tick(s.lost_ms + P.RESUME_WINDOW_MS + 1)
	_check(r.sessions[0] == null, "slot is freed when the resume window ends")
	# token refresh when stale
	var old := r.token
	r.tick(P.TOKEN_TTL_MS * 3)
	_check(r.token != old, "a stale token is replaced so the QR never goes stale")
	# clear_all
	var r2 := _reg()
	var a2 := r2.try_pair(r2.token, "A", 0)
	r2.apply_input(a2["session"], _inp(0, Vector2(1, 0), ["shoot"]), 5)
	_events.clear()
	r2.clear_all(10)
	_check(r2.connected_count() == 0 and _count("input") == 1 and _count("lost") == 1, "clear_all releases inputs and ends every session")


func _test_snapshot() -> void:
	var r := _reg()
	var snap := r.snapshot(0, 4)
	_check(snap.size() == 4, "snapshot lists four rows for the UI")
	_check(snap[0]["supported"] and snap[0]["state"] == "disconnected", "slot 1 is supported and free")
	var two := KingControllerRegistry.new(2, _fake_random).snapshot(0, 4)
	_check(two[0]["supported"] and two[1]["supported"] and not two[2]["supported"] and two[3]["state"] == "unsupported", "with two slots, rows 3-4 are marked unsupported")
	_check(not snap[1]["supported"] and snap[1]["state"] == "unsupported" and not snap[3]["supported"], "in a one-slot registry rows 2-4 are unsupported")
	var a := r.try_pair(r.token, "Pixel 8", 0)
	var snap2 := r.snapshot(5000, 4)
	_check(snap2[0]["state"] == "connected" and snap2[0]["name"] == "Pixel 8" and snap2[0]["age_ms"] == 5000, "snapshot reflects the real session")
	_check(a["ok"] and S.STATE_NAMES.size() == 7, "the seven lifecycle states exist")
	for st in ["disconnected", "connecting", "pairing", "connected", "reconnecting", "connection_lost", "revoked"]:
		_check(st in S.STATE_NAMES, "lifecycle state %s defined" % st)


func _test_network() -> void:
	var N := KingControllerNetwork
	var itf := func(n: String, addrs: Array) -> Dictionary:
		return {"name": n, "friendly": n, "addresses": addrs}
	# a typical Windows PC with Hyper-V + VPN + real Wi-Fi: the Wi-Fi address must win
	var win := [
		itf.call("vEthernet (Default Switch)", ["172.28.16.1"]),
		itf.call("Wi-Fi", ["192.168.1.23", "fe80::1"]),
		itf.call("Loopback Pseudo-Interface 1", ["127.0.0.1"]),
		itf.call("Tailscale", ["100.101.102.103"]),
		itf.call("VirtualBox Host-Only Network", ["192.168.56.1"]),
	]
	var c := N.choose(win)
	_check(c["best"] == "192.168.1.23", "Wi-Fi address chosen over Hyper-V / VPN / VirtualBox (got %s)" % c["best"])
	_check((c["candidates"] as Array).size() == 4, "loopback and IPv6 are never candidates")
	var addrs: Array = []
	for x in c["candidates"]:
		addrs.append(x["address"])
	_check(not addrs.has("127.0.0.1") and not addrs.has("fe80::1"), "no loopback / IPv6 in the list")
	_check(N.choose([itf.call("eth0", ["10.0.0.5"]), itf.call("docker0", ["172.17.0.1"])])["best"] == "10.0.0.5", "real Ethernet beats docker")
	_check(N.choose([itf.call("en0", ["192.168.0.10"]), itf.call("utun3", ["10.8.0.2"])])["best"] == "192.168.0.10", "Wi-Fi beats a VPN tunnel")
	# only virtual adapters: still offered (user may pick) but flagged
	var v := N.choose([itf.call("vEthernet (WSL)", ["172.20.0.1"])])
	_check(v["best"] == "172.20.0.1" and v["candidates"][0]["note"] == "virtual_or_vpn", "a lone virtual adapter is offered but flagged")
	# errors
	_check(N.choose([])["error"] == "no_interface" and N.choose([])["best"] == "", "no adapters -> no_interface, never a fake address")
	_check(N.choose([itf.call("Ethernet", ["169.254.10.2"])])["error"] == "only_link_local", "link-local only -> only_link_local")
	_check(N.choose([itf.call("lo", ["127.0.0.1"])])["best"] == "", "loopback only -> no address")
	_check(N.classify("999.1.1.1") == "" and N.classify("1.2.3") == "" and N.classify("abc") == "" and N.classify("0.0.0.0") == "", "malformed addresses classify as unusable")
	_check(N.classify("192.168.1.1") == "private" and N.classify("172.16.0.1") == "private" and N.classify("172.32.0.1") == "other", "private range boundaries")
	_check(N.classify("100.64.0.1") == "cgnat" and N.classify("224.0.0.1") == "", "CGNAT detected, multicast rejected")
	# the live machine: whatever it is, the result must never be loopback
	var live := N.choose(N.local_interfaces())
	_check(live["best"] != "127.0.0.1", "live adapters never yield loopback (best='%s' error='%s')" % [live["best"], live["error"]])
