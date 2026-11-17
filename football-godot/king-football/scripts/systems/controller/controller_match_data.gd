class_name KingControllerMatchData
extends RefCounted

## The PC side of the KING CONTROLLER companion data. It is the ONLY place that turns match values into
## the payloads the phone receives (dashboard, mini map, tactics). It never invents a number: every field
## comes from the live match (`MatchState`, `MatchStats`, the real player / ball positions).
##
## Independence from the match engine: this class knows the match only through a small, explicit adapter
## surface (see `CONTRACT` below). The controller package therefore never references `MatchManager`, and
## the dependency runs one way only: match -> controller. That keeps the protocol testable without a
## scene and keeps the match engine free of controller concerns.
##
## Two layers:
##  * pure static formatters (`match_payload`, `positions_payload`, `team_stats`, `quantize`) — unit
##    testable without a match at all;
##  * the instance layer (`attach`, `collect_match`, `collect_positions`, ...) that reads the live match
##    through the adapter surface and feeds the formatters.
##
## CONTRACT — the attached match node must provide:
##   state      : the live MatchState (score, clock, phase, events, stats)
##   sides      : {side: {formation, tactics, squad, team_id}}
##   entries    : {side: [ {node, player_id, slot, side, pdata} ]}
##   ball       : the ball node (global_position)
##   db         : the database (team / player lookups)
##   selected   : the entry the human drives (or {})
##   selected2  : the entry the second phone drives (or {})
##   controller_side_for_slot(slot) -> String       ("home" / "away" / "")
##   controller_side_info() -> Dictionary           {side: {id, name}}
##   controller_tactical_state(side) -> Dictionary
##   controller_apply_tactic(side, key, value) -> String   ("" = ok, else a reason code)
##   controller_substitute(side, slot, player_id) -> String
##   controller_player_name(player_id) -> String

## Statistics the match engine does NOT measure. They are reported as unavailable, never faked.
const UNAVAILABLE_STATS: Array[String] = ["tackles"]

## The map frame: the pitch is drawn with goal N at the top (map y = 0) and goal S at the bottom.
const MAP_HALF_WIDTH := 34.0 * 0.9      # PitchSpace.HALF_WIDTH * 0.9 (the width the positions use)
const MAP_HALF_LENGTH := 52.0            # PitchSpace.HALF_LENGTH
## Positions are quantised to 1/1000 of the pitch so a 22-player frame stays below one kilobyte.
const MAP_SCALE := 1000.0

var source: Node = null


func attach(match_node: Node) -> void:
	source = match_node


func detach() -> void:
	source = null


func is_active() -> bool:
	return source != null and is_instance_valid(source) and source.has_method("controller_side_for_slot")


# --- pure formatters ----------------------------------------------------------------------------------

## World position -> map coordinates (0..1, x = left/right, y = top/bottom with goal N at the top).
static func to_map(world: Vector3) -> Vector2:
	var x := clampf(world.x / (MAP_HALF_WIDTH * 2.0) + 0.5, 0.0, 1.0)
	var y := clampf((world.z + MAP_HALF_LENGTH) / (MAP_HALF_LENGTH * 2.0), 0.0, 1.0)
	return Vector2(x, y)


## The same, quantised for the wire (integers 0..1000).
static func quantize(world: Vector3) -> Vector2i:
	var m := to_map(world)
	return Vector2i(int(round(m.x * MAP_SCALE)), int(round(m.y * MAP_SCALE)))


## The measured statistics of one side. Only the values `MatchStats` really measures are exported;
## everything else stays out of the payload (the phone shows "-" for the unavailable list).
static func team_stats(stats: MatchStats, side: String) -> Dictionary:
	if stats == null:
		return {}
	var t: Dictionary = stats.teams.get(side, {})
	return {
		"possession": snappedf(stats.possession_pct(side), 0.1),
		"shots": int(t.get("shots", 0)),
		"shots_on_target": int(t.get("on_target", 0)),
		"passes": int(t.get("passes", 0)),
		"successful_passes": int(t.get("passes_ok", 0)),
		"pass_accuracy": snappedf(stats.pass_accuracy(side), 0.1),
		"saves": int(t.get("saves", 0)),
		"fouls": int(t.get("fouls", 0)),
		"yellow_cards": int(t.get("yellows", 0)),
		"red_cards": int(t.get("reds", 0)),
		"cards": int(t.get("yellows", 0)) + int(t.get("reds", 0)),
		"corners": int(t.get("corners", 0)),
		"throw_ins": int(t.get("throw_ins", 0)),
		"goal_kicks": int(t.get("goal_kicks", 0)),
		"offsides": int(t.get("offsides", 0)),
		"substitutions": int(t.get("subs", 0)),
	}


## One match event, reduced to what the phone shows. Returns {} for an unknown event shape.
static func event_payload(ev: Dictionary) -> Dictionary:
	var type := str(ev.get("type", ""))
	if type == "":
		return {}
	return {"minute": snappedf(float(ev.get("minute", 0.0)), 0.1), "type": type,
			"side": str(ev.get("side", "")), "player_id": str(ev.get("player_id", "")),
			"assist_id": str(ev.get("assist_id", "")), "out_id": str(ev.get("out_id", "")),
			"victim_id": str(ev.get("victim_id", "")), "own_goal": bool(ev.get("own_goal", false))}


## The dashboard frame. `values` is filled by `collect_match`; the formatter itself is pure so it can be
## tested without a match.
static func match_payload(values: Dictionary) -> Dictionary:
	var out := {
		"has_match": bool(values.get("has_match", false)),
		"seq": int(values.get("seq", 0)),
		"home": values.get("home", {}),
		"away": values.get("away", {}),
		"score": values.get("score", {"home": 0, "away": 0}),
		"clock": str(values.get("clock", "00:00")),
		"minute": snappedf(float(values.get("minute", 0.0)), 0.1),
		"phase": str(values.get("phase", "none")),
		"half": int(values.get("half", 1)),
		"formations": values.get("formations", {}),
		"stats": values.get("stats", {}),
		"unavailable": UNAVAILABLE_STATS.duplicate(),
		"events": values.get("events", []),
		"event_count": int(values.get("event_count", 0)),
		"controlled": values.get("controlled", {}),
	}
	return out


## The mini-map frame. `players` is a list of [side_index, slot, x_q, y_q]; the ball is [x_q, y_q].
## `attack` maps a side to -1 (attacking towards the top of the map) or +1.
static func positions_payload(values: Dictionary) -> Dictionary:
	return {
		"has_match": bool(values.get("has_match", false)),
		"seq": int(values.get("seq", 0)),
		"half": int(values.get("half", 1)),
		"players": values.get("players", []),
		"ball": values.get("ball", [500, 500]),
		"attack": values.get("attack", {"home": -1, "away": 1}),
		"ctrl": values.get("ctrl", {}),
	}


# --- the adapter layer --------------------------------------------------------------------------------

## Reads the live match and returns the dashboard values.
func collect_match() -> Dictionary:
	var v := {"has_match": false, "seq": 0, "events": [], "event_count": 0}
	if not is_active():
		return v
	var state: MatchState = source.get("state")
	if state == null:
		return v
	v["has_match"] = true
	var info: Dictionary = source.call("controller_side_info")
	v["home"] = info.get("home", {})
	v["away"] = info.get("away", {})
	v["score"] = state.score.duplicate()
	v["clock"] = state.clock_text()
	v["minute"] = snappedf(state.display_minute(), 0.1)
	v["phase"] = _phase_name(state.phase)
	v["half"] = state.half
	var sides: Dictionary = source.get("sides")
	var forms := {}
	for side in ["home", "away"]:
		forms[side] = str((sides.get(side, {}) as Dictionary).get("formation", ""))
	v["formations"] = forms
	v["stats"] = {"home": team_stats(state.stats, "home"), "away": team_stats(state.stats, "away")}
	var events: Array = []
	for e in state.events:
		var p := event_payload(e as Dictionary)
		if not p.is_empty():
			events.append(p)
	v["event_count"] = events.size()
	# The phone only ever needs the tail of the timeline, but the count stays exact.
	v["events"] = events.slice(maxi(0, events.size() - 40))
	v["controlled"] = _controlled_slots()
	return v


## Reads the live match and returns the mini-map values.
func collect_positions() -> Dictionary:
	var v := {"has_match": false, "seq": 0, "players": [], "ball": [500, 500],
			"attack": {"home": -1, "away": 1}, "ctrl": {}, "half": 1}
	if not is_active():
		return v
	var ball: Node3D = source.get("ball")
	var entries: Dictionary = source.get("entries")
	if ball == null or entries.is_empty():
		return v
	v["has_match"] = true
	var state: MatchState = source.get("state")
	v["half"] = state.half if state != null else 1
	# In the second half the teams change ends: home then attacks towards the bottom of the map.
	var home_dir := -1 if v["half"] == 1 else 1
	v["attack"] = {"home": home_dir, "away": -home_dir}
	var players: Array = []
	for side_index in ["home", "away"]:
		var si := 0 if side_index == "home" else 1
		for e in (entries.get(side_index, []) as Array):
			var entry: Dictionary = e
			var node: Node3D = entry.get("node")
			if node == null:
				continue
			var q := quantize(node.global_position)
			players.append([si, int(entry.get("slot", 0)), q.x, q.y])
	v["players"] = players
	var bq := quantize(ball.global_position)
	v["ball"] = [bq.x, bq.y]
	v["ctrl"] = _controlled_slots()
	return v


## The slot the human drives and the slot the second phone drives, per side (-1 = none).
func _controlled_slots() -> Dictionary:
	var out := {"home": -1, "away": -1}
	if not is_active():
		return out
	for pair in [["selected", "home"], ["selected2", "away"]]:
		var sel: Dictionary = source.get(pair[0])
		if sel.is_empty():
			continue
		var side := str(sel.get("side", ""))
		if out.has(side):
			out[side] = int(sel.get("slot", -1))
	return out


static func _phase_name(phase: int) -> String:
	match phase:
		MatchState.Phase.KICKOFF:
			return "kickoff"
		MatchState.Phase.PLAYING:
			return "playing"
		MatchState.Phase.HALF_TIME:
			return "half_time"
		MatchState.Phase.FINISHED:
			return "finished"
	return "none"
