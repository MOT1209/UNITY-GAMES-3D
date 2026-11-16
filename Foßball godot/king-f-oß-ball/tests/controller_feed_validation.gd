## PC -> phone match feed: frame content (from real match data), per-viewer orientation, size, and delivery over a
## real WebSocket to a paired phone. Nothing is sent to a slot without a live phone.
extends Node

const P = preload("res://scripts/systems/controller/controller_protocol.gd")
var _passed := 0
var _failed := 0
var _server: KingControllerServer


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
	await get_tree().process_frame
	print("=== KING FOOTBALL - Controller feed validation ===")
	_test_frames()
	await _test_delivery()
	await _test_in_match()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _state() -> MatchState:
	var s := MatchState.create("h", "a", 10, "m")
	s.register_players("home", ["h1", "h2"])
	s.register_players("away", ["a1", "agk"])
	s.kick_off()
	s.tick(30.0)
	s.record_possession("home", 3.0)
	s.record_possession("away", 1.0)
	s.record_shot("home", "h1")
	s.record_keeper_hold("away", "agk")
	s.goal("home", "h1")
	return s


func _test_frames() -> void:
	var s := _state()
	var home: Array = []
	var away: Array = []
	for i in 11:
		home.append(Vector2(float(i) * 3.0 - 15.0, 20.0))
		away.append(Vector2(-float(i) * 3.0 + 15.0, -20.0))
	var ball := Vector2(10.0, 30.0)
	var f := KingControllerFeed.state_frame(s, {"home": home, "away": away}, ball, "home")
	_check(f["type"] == "state" and f["v"] == 2 and f["you"] == "home", "state frame: type, protocol version, viewer")
	_check(f["score"] == [1, 0] and f["shots"] == [2, 0] and f["sot"] == [2, 0], "score / shots come from the match", str(f))
	_check(is_equal_approx(f["poss"][0], 75.0) and is_equal_approx(f["poss"][1], 25.0), "possession is the measured value", str(f["poss"]))
	_check(f["clock"] == s.clock_text(), "clock is the match clock")
	_check((f["me"] as Array).size() == 22 and (f["opp"] as Array).size() == 22, "11 + 11 positions (x, y pairs)")
	_check(JSON.stringify(f).length() < KingControllerFeed.MAX_FEED_BYTES, "frame stays small", str(JSON.stringify(f).length()))
	# orientation: the viewer's own goal is at the bottom (y = -1)
	var own_home := KingControllerFeed.norm(Vector2(0, PitchSpace.own_goal("home").z), "home")
	var own_away := KingControllerFeed.norm(Vector2(0, PitchSpace.own_goal("away").z), "away")
	_check(is_equal_approx(own_home[1], -1.0) and is_equal_approx(own_away[1], -1.0), "own goal is at y = -1 for either viewer", "%s %s" % [own_home, own_away])
	var fa := KingControllerFeed.state_frame(s, {"home": home, "away": away}, ball, "away")
	_check(fa["score"] == [0, 1] and fa["you"] == "away", "the other viewer sees the score from his side")
	_check(is_equal_approx(fa["ball"][1], -f["ball"][1]) and is_equal_approx(fa["ball"][0], -f["ball"][0]), "the ball is rotated 180 degrees for the other viewer")
	_check(fa["me"][0] == KingControllerFeed.norm(away[0], "away")[0], "'me' positions are the viewer's own team")
	# events
	var names := {"h1": "Ali"}
	var goal: Dictionary = s.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal")[0]
	var ef := KingControllerFeed.event_frame(goal, names, "home")
	_check(ef["kind"] == "goal" and ef["mine"] and ef["player"] == "Ali" and not ef["own_goal"], "goal event for the scoring side", str(ef))
	_check(not KingControllerFeed.event_frame(goal, names, "away")["mine"], "the same goal is 'not mine' for the opponent's phone")
	_check(KingControllerFeed.event_frame({"id": 9, "type": "throw_in", "side": "home"}, names, "home").is_empty(), "uncommented event types are not sent")
	_check(KingControllerFeed.event_frame({"id": 9, "type": "red_card", "side": "home", "player_id": "zz"}, names, "home")["player"] == "", "an unknown player is blank, not invented")


func _test_delivery() -> void:
	_server = KingControllerServer.new()
	_server.port = 7390
	_server.max_slots = 2
	add_child(_server)
	_server.select_address("127.0.0.1")
	await _frames(3)
	_check(not _server.send_to_slot(0, {"v": 2, "type": "state"}) and not _server.is_slot_live(0), "nothing is sent to a slot without a phone")
	var peer := WebSocketPeer.new()
	peer.connect_to_url("ws://127.0.0.1:%d/" % (_server.port + 1))
	for i in 200:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await get_tree().physics_frame
	peer.send_text(JSON.stringify(P.make_pairing_request(_server.token, "feed phone")))
	var got: Array = []
	for i in 15:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			got.append(JSON.parse_string(peer.get_packet().get_string_from_utf8()))
		await get_tree().physics_frame
	_check(got.any(func(m: Dictionary) -> bool: return m.get("type") == "paired"), "phone pairs")
	_check(_server.is_slot_live(0), "slot 0 is live after pairing")
	var f := KingControllerFeed.state_frame(_state(), {"home": [Vector2.ZERO], "away": [Vector2.ZERO]}, Vector2.ZERO, "home")
	_check(_server.send_to_slot(0, f), "a state frame is sent to the live slot")
	_check(not _server.send_to_slot(1, f), "slot 1 (no phone) receives nothing")
	got.clear()
	for i in 10:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			got.append(JSON.parse_string(peer.get_packet().get_string_from_utf8()))
		await get_tree().physics_frame
	_check(got.size() == 1 and got[0]["type"] == "state" and int(got[0]["score"][0]) == 1 and int(got[0]["score"][1]) == 0 and int(got[0]["shots"][0]) == 2, "the phone receives exactly that frame over the real socket", str(got))
	# the feed does not open a new door: a phone message with a feed type is still rejected
	peer.send_text(JSON.stringify({"v": 2, "type": "state", "score": [9, 9]}))
	got.clear()
	for i in 10:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			got.append(JSON.parse_string(peer.get_packet().get_string_from_utf8()))
		await get_tree().physics_frame
	_check(got.any(func(m: Dictionary) -> bool: return m.get("type") == "error"), "a phone cannot send 'state' / 'event' to the PC (rejected)", str(got))
	peer.close()
	await _frames(5)
	_check(not _server.send_to_slot(0, f), "after the phone closes, nothing is sent")
	_server.stop()


func _test_in_match() -> void:
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var gm: Node = get_node("/root/GameManager")
	var srv := KingControllerServer.new()
	srv.port = 7410
	gm.add_child(srv)
	gm.king_controller_server = srv
	srv.select_address("127.0.0.1")
	await _frames(3)
	var peer := WebSocketPeer.new()
	peer.connect_to_url("ws://127.0.0.1:%d/" % (srv.port + 1))
	for i in 200:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await get_tree().physics_frame
	peer.send_text(JSON.stringify(P.make_pairing_request(srv.token, "match phone")))
	await _frames(12)
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.human_side = "home"
	setup.rng_seed = 5
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "match builds with a phone paired")
	m.state.phase = MatchState.Phase.PLAYING
	var states := 0
	var events: Array = []
	var last_state: Dictionary = {}
	for i in 150:
		await get_tree().physics_frame
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				if msg.get("type") == "state":
					states += 1
					last_state = msg
				elif msg.get("type") == "event":
					events.append(msg)
		if i == 60:
			m.state.goal("home", m.entries["home"][5]["player_id"])
	_check(states >= 5, "a real match streams state frames to the phone (%d)" % states)
	_check(not last_state.is_empty() and (last_state["me"] as Array).size() == 22 and last_state["you"] == "home", "frames hold 11 + 11 real positions for the human side")
	var goals := events.filter(func(e: Dictionary) -> bool: return e["kind"] == "goal")
	_check(goals.size() == 1 and goals[0]["mine"] and goals[0]["player"] != "", "the goal reaches the phone once, as 'mine', with the scorer's name", str(goals))
	_check(int(last_state["score"][0]) == 1, "the streamed score follows the real match")
	m.queue_free()
	await get_tree().process_frame
	peer.close()
	gm.king_controller_server = null
	srv.stop()
	srv.queue_free()
