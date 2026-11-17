class_name MatchSnapshot
extends RefCounted

## Capture / restore of a running match (extracted from MatchManager). The format and what is deliberately
## not stored are documented in `MatchSave`. MatchManager keeps thin `capture()` / `restore()` wrappers.


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _from_v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Snapshot of the running match (see `MatchSave` for the format and what is deliberately not stored).
static func capture(m: MatchManager) -> Dictionary:
	var players: Array = []
	for side in ["home", "away"]:
		for e in m.entries[side]:
			var node := e["node"] as CharacterBody3D
			players.append({"side": side, "slot": e["slot"], "player_id": e["player_id"], "pos": _v3(node.global_position),
					"rot_y": node.global_rotation.y, "vel": _v3(node.velocity)})
	var fixture: Dictionary = {}
	var hub := m.get_node_or_null("/root/AppHub")
	if hub != null:
		fixture = (hub.get("pending_fixture") as Dictionary).duplicate()
	return {"version": MatchSave.VERSION, "kind": MatchSave.KIND, "saved_at": int(Time.get_unix_time_from_system()),
			"initial_setup": m.initial_setup_dict.duplicate(true), "setup": m.setup.to_dict(), "state": m.state.to_dict(),
			"players": players, "ball": {"pos": _v3(m.ball.global_position), "vel": _v3(m.ball.linear_velocity),
			"ang": _v3(m.ball.angular_velocity)}, "fixture": fixture,
			"flow": {"pause_left": m._pause_left, "needs_reset": m._needs_reset, "half_handled": m._half_handled,
			"manager_timer": m._manager_timer, "clock": m._clock, "possession_side": m._possession_side,
			"last_toucher": m.last_toucher_id}}


## Rebuilds the match from a validated save (`MatchSave.read`). Returns "" or an error.
## The match is created from the saved squads (same player ids, same lineups), then every saved value
## is written back. Call right after construction, in place of `begin()`.
static func restore(m: MatchManager, data: Dictionary, p_db: Node) -> String:
	var problems := MatchSave.validate(data, p_db)
	if not problems.is_empty():
		return problems[0]
	var err := m.begin(MatchSetup.from_dict(data["setup"]), p_db)
	if err != "":
		return err
	m.initial_setup_dict = (data["initial_setup"] as Dictionary).duplicate(true)
	m.state.apply_dict(data["state"])
	for p in data["players"]:
		var side := str(p["side"])
		var e: Dictionary = {}
		for x in m.entries[side]:
			if x["slot"] == int(p["slot"]):
				e = x
		if e.is_empty() or e["player_id"] != str(p["player_id"]):
			return "saved player '%s' does not match the rebuilt lineup" % str(p["player_id"])
		var node := e["node"] as CharacterBody3D
		node.global_position = _from_v3(p["pos"])
		node.global_rotation = Vector3(0.0, float(p["rot_y"]), 0.0)
		node.velocity = _from_v3(p["vel"])
	m.ball.global_position = _from_v3(data["ball"]["pos"])
	m.ball.linear_velocity = _from_v3(data["ball"]["vel"])
	m.ball.angular_velocity = _from_v3(data["ball"]["ang"])
	m.ball.sleeping = false
	var f: Dictionary = data["flow"]
	m._pause_left = float(f.get("pause_left", 0.5))
	m._needs_reset = bool(f.get("needs_reset", false))
	m._half_handled = bool(f.get("half_handled", false))
	m._manager_timer = float(f.get("manager_timer", 0.0))
	m._clock = float(f.get("clock", 0.0))
	m._possession_side = str(f.get("possession_side", ""))
	m.last_toucher_id = str(f.get("last_toucher", ""))
	# (tactics need no separate step: the live squad dictionary already holds the current presets)
	var hub := m.get_node_or_null("/root/AppHub")
	if hub != null and not (data.get("fixture", {}) as Dictionary).is_empty():
		hub.set("pending_fixture", (data["fixture"] as Dictionary).duplicate())
	m.rules.reapply_sent_off()
	m._update_hud()
	return ""
