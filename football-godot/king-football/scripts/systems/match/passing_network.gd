class_name PassingNetwork
extends RefCounted

## Directed passing network built from the match event log (Phase 8 analytics, F4).
##
## HONESTY / LIMITATIONS
## Completed passes live in `MatchState.pass_events`, a dedicated log that mirrors `log_event`'s shape
## ({id, t, half, minute, type, side, player_id, pos}) and adds `to` = receiver, so passes never pollute
## the shared event pipeline (commentary / sound / crowd / referee / controller). This analyzer consumes
## those PASS events (and, unchanged, a pass event from any events-style array):
##   type       == "pass"
##   player_id  = the passer (the log's single actor field)
##   pos        = [x, z] ball position at the moment of the pass (output as node x / y; y is the log's pitch-plane z)
##   to         = the receiver. `to` is the real field name used by `MatchStats.last_pass` ({from, to, side, t});
##                `receiver_id`, `to_id` and `assist_id` are accepted as aliases, never invented as a new log schema.
## The older completed-pass record shape {from, to, side, t} is accepted too, for saved matches.
##
## Counts are MEASURED only when pass events exist. Node name / position are optional caller metadata: a player
## with no metadata keeps his id as the name and an empty position — nothing is guessed. A node's (x, y) is the
## mean `pos` of the pass events that involve that player, so it is a location, not a formation or a heat map.
## A match with no pass events has an empty network (no fabricated links). This is a pure, deterministic function:
## input events are never modified and the same input always yields the same sorted nodes and edges.

## Real completed-pass event type (`MatchState.log_pass`).
const PASS_TYPE := "pass"
## Receiver field names, in priority order. `to` is the field used by `MatchStats.last_pass`.
const RECEIVER_FIELDS: Array[String] = ["to", "receiver_id", "to_id", "assist_id"]
const OUTPUT_NOTE := "Links are counted only from logged pass events. Names and positions are caller metadata; node x/y is the mean pass-event location. No pass events = no network."


## Build the graph. `events` = a MatchState.events-style Array; `metadata` optionally maps player_id -> display name
## (String) or -> {name, position} (Dictionary). Returns a JSON-safe Dictionary:
## {nodes: [{id, name, position, passes_made, passes_received, x, y}], edges: [{from, to, count}],
##  pass_count: int, measured: bool, note: String}. Nodes are sorted by id; edges by (-count, from, to).
static func build(events: Array, metadata: Dictionary = {}) -> Dictionary:
	var nodes: Dictionary = {}          # player_id -> mutable node dictionary
	var sums: Dictionary = {}           # player_id -> [x_sum, y_sum, sample_count]
	var edges: Dictionary = {}          # "from|to" -> mutable edge dictionary
	var pass_count := 0

	for item in events:
		if not (item is Dictionary):
			continue
		var ev: Dictionary = item
		var from := ""
		var to := ""
		if str(ev.get("type", "")) == PASS_TYPE:
			from = str(ev.get("player_id", ""))
			to = _receiver(ev)
		elif ev.has("from") and ev.has("to"):
			# saved `MatchStats.last_pass` record: {from, to, side, t}
			from = str(ev.get("from", ""))
			to = str(ev.get("to", ""))
		if from == "" or to == "" or from == to:
			continue                    # no self-passes: the passer touching the ball again is not a completed pass

		pass_count += 1
		_touch(nodes, from, metadata)
		_touch(nodes, to, metadata)
		(nodes[from] as Dictionary)["passes_made"] = int((nodes[from] as Dictionary)["passes_made"]) + 1
		(nodes[to] as Dictionary)["passes_received"] = int((nodes[to] as Dictionary)["passes_received"]) + 1

		var p := _event_pos(ev)
		for pid in [from, to]:
			if not sums.has(pid):
				sums[pid] = [0.0, 0.0, 0]
			var s: Array = sums[pid]
			s[0] = float(s[0]) + p.x
			s[1] = float(s[1]) + p.y
			s[2] = int(s[2]) + 1

		var key := from + "|" + to
		if not edges.has(key):
			edges[key] = {"from": from, "to": to, "count": 0}
		var edge: Dictionary = edges[key]
		edge["count"] = int(edge["count"]) + 1

	for pid in nodes:
		var node: Dictionary = nodes[pid]
		var s: Array = sums.get(pid, [0.0, 0.0, 0])
		var n: int = int(s[2])
		node["x"] = snappedf(float(s[0]) / float(n), 0.1) if n > 0 else 0.0
		node["y"] = snappedf(float(s[1]) / float(n), 0.1) if n > 0 else 0.0

	var node_list: Array[Dictionary] = []
	for pid in nodes:
		node_list.append(nodes[pid])
	node_list.sort_custom(_node_less)
	var edge_list: Array[Dictionary] = []
	for key in edges:
		edge_list.append(edges[key])
	edge_list.sort_custom(_edge_less)

	return {"nodes": node_list, "edges": edge_list, "pass_count": pass_count,
			"measured": pass_count > 0, "note": OUTPUT_NOTE}


## Most frequent directed links first; ties broken by id so the order never depends on input order.
static func top_links(network: Dictionary, limit: int = 5) -> Array:
	var all: Array = network.get("edges", [])
	var n: int = clampi(limit, 0, all.size())
	return all.slice(0, n)


## Players with the most involvement (passes made + received), id as the tie-breaker.
static func most_involved(network: Dictionary, limit: int = 0) -> Array:
	var sorted: Array[Dictionary] = []
	for item in network.get("nodes", []):
		sorted.append(item)
	sorted.sort_custom(_involvement_less)
	var n: int = clampi(limit, 0, sorted.size()) if limit > 0 else sorted.size()
	return sorted.slice(0, n)


# --- internals ---------------------------------------------------------------------------------

static func _touch(nodes: Dictionary, pid: String, metadata: Dictionary) -> void:
	if nodes.has(pid):
		return
	nodes[pid] = {"id": pid, "name": _meta(metadata, pid, "name", pid),
			"position": _meta(metadata, pid, "position", ""),
			"passes_made": 0, "passes_received": 0, "x": 0.0, "y": 0.0}


static func _meta(metadata: Dictionary, pid: String, key: String, fallback: String) -> String:
	if not metadata.has(pid):
		return fallback
	var m: Variant = metadata[pid]
	if m is String:
		return m if key == "name" else fallback
	if m is Dictionary:
		return str((m as Dictionary).get(key, fallback))
	return fallback


static func _receiver(ev: Dictionary) -> String:
	for key in RECEIVER_FIELDS:
		var value := str(ev.get(key, ""))
		if value != "":
			return value
	return ""


static func _event_pos(ev: Dictionary) -> Vector2:
	var p: Variant = ev.get("pos", null)
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float((p as Array)[0]), float((p as Array)[1]))
	return Vector2.ZERO


static func _node_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a["id"]) < str(b["id"])


static func _edge_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	if str(a["from"]) != str(b["from"]):
		return str(a["from"]) < str(b["from"])
	return str(a["to"]) < str(b["to"])


static func _involvement_less(a: Dictionary, b: Dictionary) -> bool:
	var ia: int = int(a["passes_made"]) + int(a["passes_received"])
	var ib: int = int(b["passes_made"]) + int(b["passes_received"])
	if ia != ib:
		return ia > ib
	return str(a["id"]) < str(b["id"])
