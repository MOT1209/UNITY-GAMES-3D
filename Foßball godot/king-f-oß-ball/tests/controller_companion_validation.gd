## KING CONTROLLER (P1): companion data validation. Covers the pure formatters of
## `KingControllerMatchData` (map projection, quantising, measured-only team stats, event / dashboard /
## mini-map payloads) and the match adapter contract: the four read-only `controller_*` methods the
## CONTRACT requires exist on the real `MatchManager` and answer safely before a match is built, and
## the collectors read a contract-shaped match correctly (real `MatchState` / `MatchStats` objects,
## nothing invented). Real-phone status is documented separately.
extends Node

const D = preload("res://scripts/systems/controller/controller_match_data.gd")

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== KING FOOTBALL - Controller companion data validation ===")
	await get_tree().process_frame
	_test_map_projection()
	_test_quantize()
	_test_team_stats_measured_only()
	_test_event_payload()
	_test_payload_shapes()
	await _test_contract_on_real_manager()
	await _test_collectors_on_contract_match()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- A. map projection --------------------------------------------------------------------------------

func _test_map_projection() -> void:
	_check(D.to_map(Vector3.ZERO).is_equal_approx(Vector2(0.5, 0.5)), "map: pitch centre is (0.5, 0.5)")
	var south := D.to_map(Vector3(0.0, 0.0, D.MAP_HALF_LENGTH))
	_check(absf(south.y - 1.0) < 0.001, "map: south goal line is the bottom edge")
	var north := D.to_map(Vector3(0.0, 0.0, -D.MAP_HALF_LENGTH))
	_check(absf(north.y) < 0.001, "map: north goal line is the top edge")
	var east := D.to_map(Vector3(D.MAP_HALF_WIDTH, 0.0, 0.0))
	_check(absf(east.x - 1.0) < 0.001, "map: east touchline is the right edge")
	_check(D.to_map(Vector3(-999.0, 0.0, -999.0)).is_equal_approx(Vector2.ZERO),
			"map: far-outside positions clamp to the map corner")


# --- B. quantising -----------------------------------------------------------------------------------

func _test_quantize() -> void:
	_check(D.quantize(Vector3.ZERO) == Vector2i(500, 500), "quantize: centre is (500, 500)")
	_check(D.quantize(Vector3(0.0, 0.0, D.MAP_HALF_LENGTH)).y == 1000, "quantize: south line is 1000")
	var out := D.quantize(Vector3(-9999.0, 0.0, -9999.0))
	_check(out.x == 0 and out.y == 0, "quantize: far outside clamps to 0..1000")
	_check(D.quantize(Vector3(9999.0, 0.0, 9999.0)) == Vector2i(1000, 1000),
			"quantize: far positive clamps to 1000")


# --- C. team stats: only what MatchStats really measures ----------------------------------------------

func _test_team_stats_measured_only() -> void:
	# Every value below comes out of the real MatchStats API (the same engine pipeline a match feeds).
	var stats := MatchStats.new()
	stats.add_possession("home", 60.0)
	stats.add_possession("away", 40.0)
	stats.register_player("p1", "home")
	stats.register_player("p2", "home")
	stats.register_player("a1", "away")
	stats.pass_started("home", "p1", 0.0)
	stats.owner_changed("home", "p2", 1.0)          # completed pass
	stats.pass_started("away", "a1", 1.5)
	stats.owner_changed("home", "p2", 2.0)          # intercepted: failed pass
	stats.shot_started("away", "a1", 2.5)
	stats.keeper_hold("home", "k1")                 # away shot on target, home save
	stats.goal("home", "p2", "home", 4.0)           # home goal counts shot + on target
	stats.foul("away", "a1", "p2")
	stats.card("away", "a1")                        # yellow
	stats.red_card("away", "a2")                    # straight red
	stats.restart("home", "corners")
	stats.restart("home", "throw_ins")
	stats.restart("away", "goal_kicks")
	stats.offside("home", "p2")
	stats.substitution("home", "p1", "p9")
	var home := D.team_stats(stats, "home")
	var away := D.team_stats(stats, "away")
	_check(home.get("possession", -1.0) == 60.0, "stats: home possession 60.0")
	_check(away.get("possession", -1.0) == 40.0, "stats: away possession 40.0")
	_check(home.get("shots", -1) == 1 and away.get("shots", -1) == 1, "stats: one shot each side")
	_check(home.get("shots_on_target", -1) == 1 and away.get("shots_on_target", -1) == 1,
			"stats: one shot on target each side")
	_check(home.get("saves", -1) == 1, "stats: home keeper saved once")
	_check(home.get("passes", -1) == 1 and home.get("successful_passes", -1) == 1,
			"stats: home pass completed")
	_check(away.get("passes", -1) == 1 and away.get("successful_passes", -1) == 0,
			"stats: away pass failed")
	_check(home.get("pass_accuracy", -1.0) == 100.0, "stats: home pass accuracy 100.0")
	_check(away.get("pass_accuracy", -1.0) == 0.0, "stats: away pass accuracy 0.0")
	_check(away.get("fouls", -1) == 1, "stats: away foul counted")
	_check(away.get("yellow_cards", -1) == 1 and away.get("red_cards", -1) == 1, "stats: cards counted")
	_check(away.get("cards", -1) == 2, "stats: combined card count 2")
	_check(home.get("corners", -1) == 1 and home.get("throw_ins", -1) == 1, "stats: home restarts counted")
	_check(away.get("goal_kicks", -1) == 1, "stats: away goal kick counted")
	_check(home.get("offsides", -1) == 1, "stats: home offside counted")
	_check(home.get("substitutions", -1) == 1, "stats: home substitution counted")
	_check(not home.has("tackles") and not away.has("tackles"),
			"stats: unmeasured tackles never appear in the payload")
	_check(D.team_stats(null, "home").is_empty(), "stats: null MatchStats yields an empty payload")


# --- D. event payload --------------------------------------------------------------------------------

func _test_event_payload() -> void:
	var ev := D.event_payload({"minute": 7.3, "type": "goal", "side": "home", "player_id": "p2",
			"assist_id": "p1", "out_id": "", "victim_id": "", "own_goal": false})
	_check(absf(float(ev.get("minute", -1.0)) - 7.3) < 0.05 and ev.get("type", "") == "goal"
			and ev.get("side", "") == "home" and ev.get("player_id", "") == "p2"
			and ev.get("assist_id", "") == "p1" and ev.get("own_goal", true) == false,
			"event: full goal event maps every field")
	_check(D.event_payload({"minute": 1.0}).is_empty(), "event: an event without a type is dropped")
	_check(D.event_payload({"type": "foul"}).get("own_goal", true) == false,
			"event: missing booleans default to false")


# --- E. payload shapes -------------------------------------------------------------------------------

func _test_payload_shapes() -> void:
	var m := D.match_payload({})
	_check(m.get("has_match", true) == false and m.get("seq", -1) == 0 and m.get("phase", "") == "none",
			"dashboard: safe defaults for an empty frame")
	_check(m.get("unavailable", []) == D.UNAVAILABLE_STATS and D.UNAVAILABLE_STATS.has("tackles"),
			"dashboard: the unavailable list carries the unmeasured stats")
	_check(m.get("score", {}).get("home", 1) == 0, "dashboard: score defaults to 0:0")
	var p := D.positions_payload({})
	_check(p.get("ball", []) == [500, 500], "mini map: ball defaults to the pitch centre")
	_check(p.get("attack", {}).get("home", 0) == -1 and p.get("attack", {}).get("away", 0) == 1,
			"mini map: default attack directions are home up / away down")
	var filled := D.match_payload({"seq": 4, "phase": "playing", "clock": "07:12",
			"formations": {"home": "4-3-3"}, "events": [{"minute": 7.3, "type": "goal"}],
			"event_count": 1, "controlled": {"home": 3}})
	_check(filled.get("seq", 0) == 4 and filled.get("clock", "") == "07:12"
			and filled.get("phase", "") == "playing"
			and filled.get("formations", {}).get("home", "") == "4-3-3"
			and (filled.get("events", []) as Array).size() == 1
			and filled.get("event_count", 0) == 1
			and filled.get("controlled", {}).get("home", -1) == 3,
			"dashboard: real values flow through the formatter")


# --- F. the contract on the real MatchManager ---------------------------------------------------------

func _test_contract_on_real_manager() -> void:
	var script: GDScript = load("res://scripts/systems/match/match_manager.gd")
	var manager := Node3D.new()          # MatchManager extends Node3D
	manager.set_script(script)
	add_child(manager)
	await get_tree().process_frame
	for method in ["controller_side_for_slot", "controller_side_info", "controller_tactical_state",
			"controller_player_name"]:
		_check(manager.has_method(method), "contract: MatchManager provides %s()" % method)
	_check(manager.call("controller_side_for_slot", 0) == ""
			and manager.call("controller_side_for_slot", 1) == ""
			and manager.call("controller_side_for_slot", 2) == "",
			"contract: no match built yet -> no side for any slot")
	_check(manager.call("controller_side_info").is_empty(),
			"contract: side info is empty before the match is built")
	_check(manager.call("controller_tactical_state", "home").is_empty(),
			"contract: tactical state is empty before the match is built")
	_check(manager.call("controller_player_name", "") == "",
			"contract: an empty player id yields no name")
	var data: KingControllerMatchData = D.new()
	data.attach(manager)
	_check(data.is_active(), "contract: the collector attaches to the real MatchManager")
	_check(data.collect_match().get("has_match", true) == false,
			"contract: dashboard frame is safe (no match) before begin()")
	_check(data.collect_positions().get("has_match", true) == false,
			"contract: mini-map frame is safe (no match) before begin()")
	data.detach()
	_check(not data.is_active(), "contract: detach clears the source")
	manager.queue_free()
	await get_tree().process_frame


# --- G. collectors on a contract-shaped match ----------------------------------------------------------

## A node that implements the CONTRACT exactly (real MatchState / MatchStats, real Node3D
## positions) so the collectors can be integration-tested without spawning a full match scene.
class ContractMatch extends Node:
	var state: MatchState
	var sides: Dictionary = {}
	var entries: Dictionary = {}
	var ball: Node3D
	var db: Node = null
	var selected: Dictionary = {}
	var selected2: Dictionary = {}

	func controller_side_for_slot(slot: int) -> String:
		return "home" if slot == 0 else ("away" if slot == 1 else "")

	func controller_side_info() -> Dictionary:
		return {"home": {"side": "home", "id": "team_a", "name": "Team A"},
				"away": {"side": "away", "id": "team_b", "name": "Team B"}}

	func controller_tactical_state(side: String) -> Dictionary:
		if not sides.has(side):
			return {}
		var preset: TacticsPreset = sides[side].get("tactics")
		return {"formation": str(sides[side].get("formation", "")), "mentality": preset.mentality,
				"pressing": preset.pressing, "defensive_line": preset.defensive_line,
				"build_up": preset.build_up, "passing_style": preset.passing_style,
				"width": preset.width}

	func controller_apply_tactic(_side: String, _key: String, _value: int) -> String:
		return "unsupported"

	func controller_substitute(_side: String, _slot: int, _player_id: String) -> String:
		return "unsupported"

	func controller_player_name(_player_id: String) -> String:
		return ""


func _test_collectors_on_contract_match() -> void:
	var sim := ContractMatch.new()
	add_child(sim)
	sim.state = MatchState.create("team_a", "team_b", 10, "m1")
	sim.state.register_players("home", ["p1", "p2", "k1"])
	sim.state.register_players("away", ["a1"])
	sim.sides = {
		"home": {"formation": "4-3-3", "tactics": TacticsPreset.new(), "team_id": "team_a"},
		"away": {"formation": "5-4-1", "tactics": TacticsPreset.new(), "team_id": "team_b"},
	}
	var n_home := Node3D.new()
	var n_away := Node3D.new()
	n_home.position = Vector3(5.0, 0.0, 10.0)
	n_away.position = Vector3(-5.0, 0.0, -10.0)
	sim.add_child(n_home)
	sim.add_child(n_away)
	sim.entries = {"home": [{"node": n_home, "player_id": "p2", "slot": 3, "side": "home", "pdata": null}],
			"away": [{"node": n_away, "player_id": "a1", "slot": 5, "side": "away", "pdata": null}]}
	sim.ball = Node3D.new()
	sim.add_child(sim.ball)
	sim.selected = sim.entries["home"][0]

	var data: KingControllerMatchData = D.new()
	data.attach(sim)
	_check(data.is_active(), "collectors: attached to the contract match")

	# The match state itself is live: a real goal through the real pipeline.
	sim.state.kick_off()
	_check(sim.state.goal("home", "p2"), "collectors: the real MatchState registered a goal")
	var dash := data.collect_match()
	_check(dash.get("has_match", false) == true, "dashboard: live match reported")
	_check(dash.get("score", {}).get("home", 0) == 1 and dash.get("score", {}).get("away", 0) == 0,
			"dashboard: score comes from the real MatchState")
	_check(str(dash.get("clock", "")) != "", "dashboard: a real clock string is present")
	_check(dash.get("phase", "") == "kickoff", "dashboard: phase maps to kickoff after the goal")
	_check(dash.get("formations", {}).get("home", "") == "4-3-3"
			and dash.get("formations", {}).get("away", "") == "5-4-1",
			"dashboard: formations come from the real sides")
	_check(dash.get("stats", {}).get("home", {}).get("possession", -1.0) == 50.0,
			"dashboard: stats come from the real MatchStats (no possession yet -> 50.0)")
	var events: Array = dash.get("events", [])
	_check(events.size() == 1 and events[0].get("type", "") == "goal"
			and events[0].get("player_id", "") == "p2" and dash.get("event_count", 0) == 1,
			"dashboard: the real goal event flows into the timeline")
	_check(dash.get("home", {}).get("name", "") == "Team A", "dashboard: side info carries team names")
	_check(dash.get("controlled", {}).get("home", -1) == 3
			and dash.get("controlled", {}).get("away", -1) == -1,
			"dashboard: controlled slots mirror selected / selected2")

	var pos := data.collect_positions()
	_check(pos.get("has_match", false) == true, "mini map: live match reported")
	_check((pos.get("players", []) as Array).size() == 2, "mini map: both entries projected")
	_check(pos.get("ball", [0, 0]) == [500, 500], "mini map: centre ball is (500, 500)")
	_check(pos.get("attack", {}).get("home", 0) == -1 and pos.get("attack", {}).get("away", 0) == 1,
			"mini map: first-half attack directions")
	sim.state.half = 2
	pos = data.collect_positions()
	_check(pos.get("attack", {}).get("home", 0) == 1 and pos.get("attack", {}).get("away", 0) == -1,
			"mini map: second half flips the attack directions")
	var home_q: Vector2i = D.quantize(n_home.global_position)
	var found_home := false
	for p in (pos.get("players", []) as Array):
		if p[0] == 0 and p[1] == 3 and p[2] == home_q.x and p[3] == home_q.y:
			found_home = true
	_check(found_home, "mini map: the home entry is projected at its real quantised position")
	_check(pos.get("ctrl", {}).get("home", -1) == 3 and pos.get("ctrl", {}).get("away", -1) == -1,
			"mini map: controlled slots mirror selected / selected2")

	# Defensive defaults still hold for a half-built contract (no ball, no entries).
	sim.ball = null
	sim.entries = {}
	pos = data.collect_positions()
	_check(pos.get("has_match", false) == false, "mini map: no ball / no entries -> safe empty frame")
	_check(data.collect_match().get("has_match", true) == true,
			"dashboard: state-only contract still yields the dashboard")
	data.detach()
	sim.queue_free()
	await get_tree().process_frame
