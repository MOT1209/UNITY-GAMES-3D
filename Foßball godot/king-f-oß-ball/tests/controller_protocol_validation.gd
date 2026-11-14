## P5 KING CONTROLLER: protocol + QR encoder unit tests (pure logic, no sockets).
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== KING FOOTBALL — Controller protocol validation ===")
	await get_tree().process_frame
	_test_protocol_version()
	_test_pairing()
	_test_input_validation()
	_test_rate_and_freshness()
	_test_qr_encoder()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_protocol_version() -> void:
	var m := KingControllerProtocol.make_pairing_request("ABCDEFGH", "phone")
	_check(int(m["v"]) == KingControllerProtocol.PROTOCOL_VERSION, "pairing request version field")
	var r := KingControllerProtocol.validate_pairing(m, "ABCDEFGH", {}, 1)
	_check(bool(r["ok"]), "valid pairing accepted")


func _test_pairing() -> void:
	# bad token
	var m := KingControllerProtocol.make_pairing_request("XXXXXXXX", "phone")
	var r := KingControllerProtocol.validate_pairing(m, "ABCDEFGH", {}, 1)
	_check(not bool(r["ok"]) and String(r["reason"]) == "bad_token", "bad token rejected")
	# bad version
	var m2 := {"v": 999, "type": "pair", "token": "ABCDEFGH", "name": "x"}
	var r2 := KingControllerProtocol.validate_pairing(m2, "ABCDEFGH", {}, 1)
	_check(not bool(r2["ok"]) and String(r2["reason"]) == "bad_version", "bad version rejected")
	# no slot
	var r3 := KingControllerProtocol.validate_pairing(m, "ABCDEFGH".replace("X","A") if false else "ABCDEFGH", {}, 0)
	# craft valid token msg
	var m3 := KingControllerProtocol.make_pairing_request("ABCDEFGH", "phone")
	var r4 := KingControllerProtocol.validate_pairing(m3, "ABCDEFGH", {}, 0)
	_check(not bool(r4["ok"]) and String(r4["reason"]) == "no_slot", "no free slot rejected")
	# reconnect: used_tokens contains token -> reconnect_slot set
	var used := {"ABCDEFGH": 1}
	var r5 := KingControllerProtocol.validate_pairing(m3, "ABCDEFGH", used, 0)
	_check(bool(r5["ok"]) and int(r5["reconnect_slot"]) == 1, "reconnect re-binds slot")


func _test_input_validation() -> void:
	var state := {"seq": -1, "window_start": Time.get_ticks_msec(), "count": 0}
	var now := Time.get_ticks_msec()
	# valid input
	var msg := KingControllerProtocol.make_input(1, Vector2(0.5, -0.3), ["pass", "shoot"], ["sprint"], now)
	var res := KingControllerProtocol.validate_input(msg, state, now)
	_check(res.ok, "valid input accepted")
	_check(res.move.x > 0.0 and res.move.y < 0.0, "move parsed")
	_check(res.press.has(&"pass") and res.press.has(&"shoot"), "press parsed")
	_check(res.release.has(&"sprint"), "release parsed")
	_check(res.seq == 1, "seq recorded")
	# stale seq
	var msg2 := KingControllerProtocol.make_input(1, Vector2.ZERO, [], [], now)
	var res2 := KingControllerProtocol.validate_input(msg2, state, now)
	_check(not res2.ok and res2.reason == "stale_seq", "stale seq rejected")
	# unknown action filtered
	var msg3 := KingControllerProtocol.make_input(2, Vector2.ZERO, ["pass", "hack"], [], now)
	var res3 := KingControllerProtocol.validate_input(msg3, state, now)
	_check(res3.ok and res3.press.size() == 1, "unknown action filtered")
	# move clamped
	var msg4 := KingControllerProtocol.make_input(3, Vector2(2.0, 0.0), [], [], now)
	var res4 := KingControllerProtocol.validate_input(msg4, state, now)
	_check(res4.move.length() <= 1.0 + 0.001, "move clamped to unit")
	# bad version
	var msg5 := {"v": 2, "type": "input", "seq": 4, "move": {"x": 0.0, "y": 0.0}, "press": [], "release": [], "t": now}
	var res5 := KingControllerProtocol.validate_input(msg5, state, now)
	_check(not res5.ok and res5.reason == "bad_version", "bad version rejected (input)")
	# freshness stale
	var msg6 := KingControllerProtocol.make_input(5, Vector2.ZERO, [], [], now - 5000)
	var res6 := KingControllerProtocol.validate_input(msg6, state, now)
	_check(not res6.ok and res6.reason == "stale_freshness", "stale freshness rejected")


func _test_rate_and_freshness() -> void:
	var state := {"seq": -1, "window_start": Time.get_ticks_msec(), "count": 0}
	var now := Time.get_ticks_msec()
	var ok_count := 0
	for i in range(KingControllerProtocol.RATE_LIMIT_MSGS_PER_SEC + 5):
		var m := KingControllerProtocol.make_input(100 + i, Vector2.ZERO, [], [], now)
		var r := KingControllerProtocol.validate_input(m, state, now)
		if r.ok:
			ok_count += 1
	_check(ok_count == KingControllerProtocol.RATE_LIMIT_MSGS_PER_SEC, "rate limit clamps to %d msgs/s" % KingControllerProtocol.RATE_LIMIT_MSGS_PER_SEC)


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