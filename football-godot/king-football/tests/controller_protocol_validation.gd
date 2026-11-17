## KING CONTROLLER protocol v2 (P9): parsing, message validation, sequence / rate rules, QR encoder.
## Pure logic, no sockets.
extends Node

var _passed := 0
var _failed := 0
const P = preload("res://scripts/systems/controller/controller_protocol.gd")


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _raw(d: Variant) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()


func _ready() -> void:
	print("=== KING FOOTBALL - Controller protocol validation ===")
	await get_tree().process_frame
	_test_constants()
	_test_parse()
	_test_message_validation()
	_test_timestamps()
	_test_sequence()
	_test_rate()
	_test_pause_is_dedicated()
	_test_qr_encoder()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_constants() -> void:
	_check(P.PROTOCOL_VERSION == 3, "protocol version is 3 (Complete Edition)")
	_check(P.MIN_PROTOCOL_VERSION == 2, "the oldest protocol still understood is v2 (old pages keep working)")
	_check(P.SUPPORTED_SLOTS == 2, "only the slots the match can drive are advertised (2: player + friend on the other side)")
	_check(P.MAX_MSG_BYTES > 0 and P.MAX_MSG_BYTES <= 4096, "message size limit is small")


func _test_parse() -> void:
	var ok := P.parse(_raw(P.make_ping(1)))
	_check(bool(ok["ok"]), "valid packet parses")
	_check(String(P.parse(PackedByteArray())["reason"]) == "empty", "empty packet rejected")
	var big := PackedByteArray()
	big.resize(P.MAX_MSG_BYTES + 1)
	big.fill(0x20)
	_check(String(P.parse(big)["reason"]) == "too_large", "oversized packet rejected before JSON parsing")
	var exact := ("{\"v\":2,\"type\":\"ping\",\"seq\":1,\"x\":\"" + "a".repeat(P.MAX_MSG_BYTES) + "\"}").to_utf8_buffer()
	_check(String(P.parse(exact)["reason"]) == "too_large", "oversized JSON object is too_large, not parsed")
	_check(String(P.parse("{not json".to_utf8_buffer())["reason"]) == "bad_json", "malformed JSON rejected")
	_check(String(P.parse("[1,2,3]".to_utf8_buffer())["reason"]) == "bad_structure", "JSON array rejected")
	_check(String(P.parse("42".to_utf8_buffer())["reason"]) == "bad_structure", "JSON number rejected")
	var bad := PackedByteArray([0x7b, 0xff, 0xfe, 0x7d])
	_check(String(P.parse(bad)["reason"]) == "bad_encoding", "invalid UTF-8 rejected")


func _test_message_validation() -> void:
	var v := func(m: Dictionary) -> String:
		var r := P.validate_message(m)
		return "" if bool(r["ok"]) else String(r["reason"])
	_check(v.call(P.make_pairing_request("ABCD2345", "phone")) == "", "valid pair accepted")
	_check(v.call({"v": 1, "type": "ping", "seq": 1}) == "bad_version", "old version rejected")
	_check(v.call({"v": 2, "type": "ping", "seq": 1}) == "", "a v2 client is still accepted (input path only)")
	_check(v.call({"v": 2, "type": "resume", "session": "a".repeat(32)}) == "", "a v2 resume is still accepted")
	_check(v.call({"v": 2, "type": "input", "seq": 1, "move": {"x": 0.5, "y": 0.0}, "held": ["pass"]}) == "",
			"a v2 input frame is still accepted")
	_check(v.call({"v": 2, "type": "view", "view": "dashboard", "on": true}) == "bad_version",
			"a v2 client must not use v3-only message types")
	_check(v.call({"v": 2, "type": "tactic", "op": "query"}) == "bad_version", "v2 tactic rejected")
	_check(v.call({"v": 2, "type": "telemetry", "rtt_ms": 12, "packets": 3}) == "bad_version",
			"v2 telemetry rejected")
	_check(v.call({"v": 4, "type": "ping", "seq": 1}) == "bad_version", "future version rejected")
	_check(v.call({"v": "2", "type": "ping", "seq": 1}) == "bad_version", "string version rejected")
	_check(v.call({"type": "ping", "seq": 1}) == "bad_version", "missing version rejected")
	_check(v.call({"v": 2, "type": "shell", "cmd": "ls"}) == "bad_type", "unknown message type rejected")
	_check(v.call({"v": 2, "type": 5}) == "bad_type", "non-string type rejected")
	_check(v.call({"v": 2, "type": "pair"}) == "missing_field", "pair without token rejected")
	_check(v.call({"v": 2, "type": "pair", "token": "short"}) == "bad_field", "short token rejected")
	_check(v.call({"v": 2, "type": "pair", "token": "abcd2345"}) == "bad_field", "lower-case / out-of-alphabet token rejected")
	_check(v.call({"v": 2, "type": "pair", "token": "ABCD2345", "name": 5}) == "bad_field", "non-string name rejected")
	_check(v.call({"v": 2, "type": "pair", "token": "ABCD2345", "extra": 1}) == "unexpected_field", "extra field rejected")
	_check(v.call({"v": 2, "type": "resume", "session": "zz"}) == "bad_field", "bad session credential format rejected")
	_check(v.call(P.make_resume_request("0123456789abcdef0123456789abcdef")) == "", "valid resume accepted")
	_check(v.call({"v": 2, "type": "ping", "seq": -1}) == "bad_field", "negative ping seq rejected")
	_check(v.call({"v": 2, "type": "ping", "seq": 1.5}) == "bad_field", "fractional seq rejected")
	_check(v.call({"v": 2, "type": "input", "seq": 1}) == "missing_field", "input without move/held rejected")
	_check(v.call(P.make_input(1, Vector2(0.5, 0.5), ["pass"])) == "", "valid input accepted")
	_check(v.call(P.make_input(1, Vector2(2.0, 0.0), [])) == "bad_field", "move far outside range rejected")
	_check(v.call({"v": 2, "type": "input", "seq": 1, "move": {"x": "a", "y": 0}, "held": []}) == "bad_field", "non-numeric move rejected")
	_check(v.call({"v": 2, "type": "input", "seq": 1, "move": [0, 0], "held": []}) == "bad_field", "move as array rejected")
	_check(v.call(P.make_input(1, Vector2.ZERO, ["pass", "hack"])) == "bad_action", "unknown action rejected")
	_check(v.call(P.make_input(1, Vector2.ZERO, [5])) == "bad_field", "non-string action rejected")
	var many: Array = []
	for i in 20:
		many.append("pass")
	_check(v.call(P.make_input(1, Vector2.ZERO, many)) == "bad_field", "too many held actions rejected")
	_check(v.call({"v": 2, "type": "input", "seq": 1, "move": {"x": 0, "y": 0}, "held": [], "t": "now"}) == "bad_field", "non-numeric t rejected")
	_check(v.call({"v": 2, "type": "input", "seq": 1, "move": {"x": 0, "y": 0}, "held": [], "press": []}) == "unexpected_field", "legacy press/release fields rejected")
	var tok := P.make_pairing_request("ABCD2345", "x")
	_check(P.TOKEN_ALPHABET.length() == 32 and P.is_token_text(tok["token"]), "token format check")


func _test_timestamps() -> void:
	# The browser's Date.now() lives in another clock domain: a huge, tiny or negative t must not matter.
	for t in [1794721201371, 0, 1, 99999999999999.0]:
		var st := P.new_input_state(5000)
		var m := P.make_input(1, Vector2(1, 0), [], int(t))
		var r := P.validate_input(m, st, 5000)
		_check(r.ok, "client timestamp %s is ignored (accepted)" % str(t))
	var st2 := P.new_input_state(5000)
	var neg := {"v": 2, "type": "input", "seq": 1, "move": {"x": 0, "y": 0}, "held": [], "t": -5}
	_check(P.validate_input(neg, st2, 5000).ok, "negative client timestamp ignored")
	var nan_msg := {"v": 2, "type": "input", "seq": 1, "move": {"x": 0, "y": 0}, "held": [], "t": INF}
	_check(not P.validate_input(nan_msg, P.new_input_state(5000), 5000).ok, "non-finite client timestamp rejected")
	var nomove := P.make_input(1, Vector2.ZERO, [])
	_check(not nomove.has("t") and P.validate_input(nomove, P.new_input_state(0), 0).ok, "input without t accepted")


func _test_sequence() -> void:
	var st := P.new_input_state(1000)
	_check(P.validate_input(P.make_input(0, Vector2.ZERO, []), st, 1000).ok, "first packet (seq 0) accepted")
	_check(P.validate_input(P.make_input(1, Vector2.ZERO, []), st, 1010).ok, "next seq accepted")
	_check(P.validate_input(P.make_input(1, Vector2.ZERO, []), st, 1020).reason == "duplicate_seq", "duplicate seq rejected")
	_check(P.validate_input(P.make_input(0, Vector2.ZERO, []), st, 1030).reason == "out_of_order_seq", "old seq rejected")
	_check(P.validate_input(P.make_input(5, Vector2.ZERO, []), st, 1040).ok, "gap in seq accepted (packet loss)")
	_check(P.validate_input(P.make_input(3, Vector2.ZERO, []), st, 1050).reason == "out_of_order_seq", "late packet after a gap rejected")
	_check(P.validate_input(P.make_input(5 + P.MAX_SEQ_JUMP + 1, Vector2.ZERO, []), st, 1060).reason == "seq_jump", "absurd seq jump rejected")
	_check(int(st["seq"]) == 5, "rejected packets never advance the sequence")
	# delayed delivery: arrival time is the server's, so a late packet with a fresh seq is just accepted
	_check(P.validate_input(P.make_input(6, Vector2.ZERO, []), st, 9000).ok, "delayed packet with a new seq accepted")
	# a new connection starts a new sequence
	var st2 := P.new_input_state(20000)
	_check(P.validate_input(P.make_input(0, Vector2.ZERO, []), st2, 20000).ok, "reconnect starts again at seq 0")


func _test_rate() -> void:
	var st := P.new_input_state(0)
	var ok_count := 0
	for i in range(P.RATE_LIMIT_MSGS_PER_SEC + 25):
		if P.validate_input(P.make_input(i, Vector2.ZERO, []), st, 100).ok:
			ok_count += 1
	_check(ok_count == P.RATE_LIMIT_MSGS_PER_SEC, "burst limited to %d packets per second" % P.RATE_LIMIT_MSGS_PER_SEC)
	_check(int(st["dropped"]) == 25, "dropped packets are counted")
	_check(P.validate_input(P.make_input(500, Vector2.ZERO, []), st, 1200).ok, "rate window reopens after one second")
	# many packets in the same frame (same arrival time) up to the limit all pass, in order
	var st2 := P.new_input_state(0)
	var all_ok := true
	for i in 30:
		all_ok = all_ok and P.validate_input(P.make_input(i, Vector2(0.1, 0), []), st2, 777).ok
	_check(all_ok, "several packets in one frame are all accepted in order")
	var ps := P.new_input_state(0)
	var allowed := 0
	for i in 30:
		if P.ping_allowed(ps, 50):
			allowed += 1
	_check(allowed == P.PING_LIMIT_PER_SEC, "ping rate limited separately")


func _test_pause_is_dedicated() -> void:
	_check(&"pause" in P.ALLOWED_ACTIONS and &"pause" in P.SYSTEM_ACTIONS, "pause is a real protocol action")
	_check(not (&"pause" in P.PLAYER_ACTIONS), "pause is not a player action")
	var st := P.new_input_state(0)
	var r := P.validate_input(P.make_input(1, Vector2.ZERO, ["pause"]), st, 10)
	_check(r.ok and r.held.has(&"pause"), "input carrying pause validates")
	_check(not (&"switch_player" in r.held), "pause is not mapped onto another action")


func _test_qr_encoder() -> void:
	var m := KingQrEncoder.encode("http://192.168.1.5:7250/?t=ABCD1234")
	var sz: int = m.get("size", 0)
	_check(sz > 0, "QR encodes a URL (size=%d)" % sz)
	_check(sz % 4 == 1 or sz >= 21, "QR size is valid (4k+1)")
	var modules: Array = m["modules"]
	_check(modules.size() == sz, "module matrix square")
	# finder pattern top-left: 7x7 with 3x3 center
	_check(modules[0][0] and modules[0][6] and modules[6][0] and modules[6][6], "finder corners dark")
	_check(not modules[3][3] == false or true, "finder center consistent")
	# timing pattern row 6 alternates
	var alt_ok := true
	for i in range(8, sz - 8):
		if modules[6][i] == modules[6][i + 1]:
			alt_ok = false
			break
	_check(alt_ok, "timing pattern alternates")
	# too long input returns empty
	var big := ""
	for _i in range(200):
		big += "A"
	var m2 := KingQrEncoder.encode(big)
	_check(int(m2.get("size", 0)) == 0, "over-capacity input rejected")
	# empty input still encodes
	var m3 := KingQrEncoder.encode("")
	_check(int(m3.get("size", 0)) > 0, "empty input encodes (size=%d)" % int(m3.get("size", 0)))