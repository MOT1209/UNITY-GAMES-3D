## Passing network (F4): empty input, node/edge counts, determinism, top-link order, no input mutation.
##   godot --headless --path . res://tests/passing_network_validation.tscn
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
	await get_tree().process_frame
	print("=== KING FOOTBALL — Passing network validation ===")
	_test_empty()
	_test_counts()
	_test_determinism()
	_test_top_links()
	_test_no_mutation()
	_test_metadata_and_last_pass_shape()
	_test_real_pipeline()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Mirrors MatchState.log_event: {id, t, half, minute, type, side, player_id, pos} + pass receiver `to`
## (the real field name of MatchStats.last_pass). `to` is deliberately the only extra field.
func _pass(id: int, side: String, passer: String, receiver: String, x: float, z: float, t: float) -> Dictionary:
	return {"id": id, "t": t, "half": 1, "minute": t / 6.0, "type": "pass", "side": side,
			"player_id": passer, "to": receiver, "pos": [x, z]}


func _events() -> Array:
	return [
		_pass(1, "home", "h1", "h2", 1.0, 2.0, 10.0),
		_pass(2, "home", "h1", "h2", 3.0, 4.0, 12.0),
		_pass(3, "home", "h2", "h3", 5.0, 6.0, 14.0),
		_pass(4, "away", "a1", "a2", -7.0, -8.0, 16.0),
		_pass(5, "home", "h1", "h1", 9.0, 9.0, 18.0),                 # self-pass: not a link
		{"id": 6, "type": "shot", "side": "home", "player_id": "h1", "assist_id": "h2"},  # not a pass
		{"id": 7, "type": "pass", "side": "home", "player_id": ""},     # no passer
		{"id": 8, "type": "pass", "side": "home", "player_id": "h2"},   # no receiver
		null,                                                          # malformed entry
	]


func _test_empty() -> void:
	var g := PassingNetwork.build([])
	_check((g["nodes"] as Array).is_empty() and (g["edges"] as Array).is_empty() and int(g["pass_count"]) == 0,
			"no events = empty nodes, empty edges, zero passes")
	_check(not bool(g["measured"]), "an empty network is not labelled as measured")
	_check((PassingNetwork.top_links(g, 5) as Array).is_empty() and (PassingNetwork.most_involved(g, 5) as Array).is_empty(),
			"top links / involvement are empty too")
	# other event types only, still no pass events
	var other := PassingNetwork.build([{"id": 1, "type": "shot", "player_id": "h1"}, {"id": 2, "type": "goal", "player_id": "h2"}])
	_check((other["nodes"] as Array).is_empty() and int(other["pass_count"]) == 0, "non-pass events never create nodes")


func _test_counts() -> void:
	var g := PassingNetwork.build(_events())
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]
	_check(nodes.size() == 5 and edges.size() == 3 and int(g["pass_count"]) == 4,
			"4 valid passes -> 5 nodes, 3 directed edges", "nodes=%d edges=%d passes=%d" % [nodes.size(), edges.size(), int(g["pass_count"])])
	var by_id := {}
	for n in nodes:
		by_id[str(n["id"])] = n
	_check(by_id.has("h1") and by_id.has("h2") and by_id.has("h3") and by_id.has("a1") and by_id.has("a2"),
			"both teams' players appear as nodes")
	_check(int(by_id["h1"]["passes_made"]) == 2 and int(by_id["h1"]["passes_received"]) == 0,
			"h1 made two passes and received none")
	_check(int(by_id["h2"]["passes_made"]) == 1 and int(by_id["h2"]["passes_received"]) == 2,
			"h2 made one pass and received two")
	_check(float(by_id["h1"]["x"]) == 2.0 and float(by_id["h1"]["y"]) == 3.0,
			"node x/y is the mean of that player's pass-event positions", str(by_id["h1"]))
	_check(str(nodes[0]["id"]) == "a1" and str(nodes[4]["id"]) == "h3", "nodes are sorted by id", str(nodes))
	var e0: Dictionary = edges[0]
	_check(str(e0["from"]) == "h1" and str(e0["to"]) == "h2" and int(e0["count"]) == 2,
			"the h1 -> h2 edge is aggregated to count 2 and sorted first", str(e0))
	var total := 0
	for e in edges:
		total += int(e["count"])
	_check(total == int(g["pass_count"]), "edge counts sum to the number of passes")
	_check(str(nodes[0]["name"]) == "a1" and str(nodes[0]["position"]) == "",
			"without metadata a node keeps its id as name and an empty position")


func _test_determinism() -> void:
	var a := PassingNetwork.build(_events())
	var b := PassingNetwork.build(_events())
	_check(JSON.stringify(a) == JSON.stringify(b), "the same events always produce the same graph")
	var rev := _events()
	rev.reverse()
	var c := PassingNetwork.build(rev)
	_check(JSON.stringify(a) == JSON.stringify(c), "node / edge order does not depend on event order")
	var meta := {"h1": {"name": "Home One", "position": "CM"}, "h2": "Home Two"}
	var m1 := PassingNetwork.build(_events(), meta)
	var m2 := PassingNetwork.build(_events(), meta)
	_check(JSON.stringify(m1) == JSON.stringify(m2), "metadata lookups are deterministic too")


func _test_top_links() -> void:
	var g := PassingNetwork.build(_events())
	var top: Array = PassingNetwork.top_links(g, 2)
	_check(top.size() == 2 and str(top[0]["from"]) == "h1" and str(top[0]["to"]) == "h2" and int(top[0]["count"]) == 2,
			"top_links starts with the most frequent link", str(top))
	# both remaining links have count 1; ids break the tie alphabetically (a1 before h2)
	_check(str(top[1]["from"]) == "a1" and str(top[1]["to"]) == "a2", "ties are broken by passer then receiver id", str(top[1]))
	_check(str(top[0]["from"]) == "h1" and int(top[0]["count"]) >= int(top[1]["count"]), "top links are non-increasing in count")
	_check((PassingNetwork.top_links(g, 0) as Array).is_empty() and (PassingNetwork.top_links(g, 99) as Array).size() == 3,
			"top_links clamps the requested number of links")
	var involved: Array = PassingNetwork.most_involved(g, 2)
	_check(str(involved[0]["id"]) == "h2" and str(involved[1]["id"]) == "h1", "most_involved sorts by made + received")
	_check(str(PassingNetwork.most_involved(g, 3)[2]["id"]) == "a1", "involvement ties are broken by id")


func _test_no_mutation() -> void:
	var events := _events()
	var snapshot := events.duplicate(true)
	var meta := {"h1": {"name": "Home One", "position": "CM"}}
	var meta_snapshot := meta.duplicate(true)
	var g := PassingNetwork.build(events, meta)
	_check(events == snapshot, "building the graph does not mutate the input events")
	_check(meta == meta_snapshot, "building the graph does not mutate the metadata")
	# and a second build from the same untouched events still agrees
	_check(JSON.stringify(g) == JSON.stringify(PassingNetwork.build(events, meta)), "no mutation means repeated builds agree")
	# edge dictionaries are fresh: editing the result must not rewrite the source log
	(g["nodes"][0] as Dictionary)["passes_made"] = 999
	_check(events[1]["player_id"] == "h1" and events == snapshot, "editing the output cannot reach the input events")


func _test_metadata_and_last_pass_shape() -> void:
	var meta := {"h1": {"name": "Home One", "position": "CM"}, "h2": "Home Two"}
	var g := PassingNetwork.build(_events(), meta)
	var by_id := {}
	for n in g["nodes"]:
		by_id[str(n["id"])] = n
	_check(str(by_id["h1"]["name"]) == "Home One" and str(by_id["h1"]["position"]) == "CM",
			"a {name, position} metadata entry fills both fields")
	_check(str(by_id["h2"]["name"]) == "Home Two" and str(by_id["h2"]["position"]) == "",
			"a plain String metadata entry fills only the name")
	# the saved `MatchStats.last_pass` record shape {from, to, side, t} is accepted without a `type` key
	var saved := PassingNetwork.build([{"from": "h1", "to": "h2", "side": "home", "t": 3.0},
			{"from": "h2", "to": "h1", "side": "home", "t": 5.0}])
	_check(int(saved["pass_count"]) == 2 and (saved["edges"] as Array).size() == 2 and (saved["nodes"] as Array).size() == 2,
			"completed-pass records {from, to} build a two-way graph")
	_check(str((saved["edges"][0] as Dictionary)["from"]) == "h1" and str((saved["edges"][0] as Dictionary)["to"]) == "h2",
			"equal-count edges keep a stable id order")


## The real pipeline: MatchState logs completed passes into `pass_events`, MatchReport turns them into a
## measured graph. Passes must NOT enter the shared `events` pipeline, and old saves stay compatible.
func _test_real_pipeline() -> void:
	var s := MatchState.create("home_team", "away_team", 10)
	s.kick_off()
	s.record_pass("home", "h1")
	s.set_ball_position(3.0, -12.0)
	s.record_owner("home", "h2")                      # real completed pass h1 -> h2
	s.record_pass("home", "h2")
	s.set_ball_position(-4.0, 8.0)
	s.record_owner("home", "h3")                      # real completed pass h2 -> h3
	_check(s.pass_events.size() == 2, "two completed passes produce two pass events")
	_check(str(s.pass_events[0]["type"]) == "pass" and str(s.pass_events[0]["player_id"]) == "h1"
			and str(s.pass_events[0]["to"]) == "h2" and s.pass_events[0]["pos"] == [3.0, -12.0],
			"a pass event carries the real passer, receiver and ball position")
	_check(s.events.is_empty(), "passes never pollute the shared event pipeline")

	# An intercepted pass (opponent takes the ball) resolves as failed: no event must be logged.
	s.record_pass("home", "h3")
	s.record_owner("away", "a1")
	_check(s.pass_events.size() == 2, "an intercepted pass logs no network event")

	var rep := MatchReport.build(s, null, "none", null)
	var net: Dictionary = rep.get("passing_network", {})
	_check(int(net.get("pass_count", 0)) == 2 and bool(net.get("measured", false)),
			"the report carries a measured network built from real passes")
	var edges: Array = net.get("edges", [])
	_check(edges.size() == 2 and str((edges[0] as Dictionary)["from"]) == "h1"
			and str((edges[0] as Dictionary)["to"]) == "h2", "the report graph has the real h1 -> h2 link")
	_check(str((net["nodes"][0] as Dictionary)["name"]) == "h1" and str((net["nodes"][0] as Dictionary)["position"]) == "",
			"without a database, unknown players keep their id and an empty position (no invented names)")

	# Save round trip keeps the pass log; an old save without the key starts empty.
	var d := s.to_dict()
	var restored := MatchState.create("home_team", "away_team", 10)
	restored.apply_dict(d)
	_check(restored.pass_events.size() == 2 and restored.pass_events[1]["pos"] == [-4.0, 8.0],
			"the pass log survives a state save / load round trip")
	var old_save := s.to_dict()
	old_save.erase("pass_events")
	old_save.erase("next_pass_event_id")
	var legacy := MatchState.create("home_team", "away_team", 10)
	legacy.apply_dict(old_save)
	_check(legacy.pass_events.is_empty() and int(MatchReport.build(legacy, null)["passing_network"]["pass_count"]) == 0,
			"a save from before pass logging loads with an empty network (nothing invented)")
