class_name MatchBugReport
extends RefCounted

## In-match bug report (Phase M0, F8 on PC): the last REPLAY_SECONDS of the replay buffer (ball + 22 bodies at 20 Hz),
## the full `MatchSnapshot` (positions, velocities, score, clock, stats, setup) and, per player, what the engine was
## doing at that moment (ball owner, AI intent, kick being charged, `FootballActions` state, move / aim of the intent).
## Written as JSON to `user://bug_reports/<time>.json`; `tools/replay_bug_report.tscn` plays one back.

const VERSION := 1
const DIR := "user://bug_reports"
const REPLAY_SECONDS := 10.0


static func build(m: MatchManager) -> Dictionary:
	var owner := m._owner_entry()
	var players: Array = []
	for side in ["home", "away"]:
		for e in m.entries[side]:
			var n := e["node"] as CharacterBody3D
			var acts := e["actions"] as FootballActions
			var intent: IntentProvider = n.get("intent") as IntentProvider
			var cmd: Dictionary = e.get("cmd", {})
			players.append({"side": side, "slot": int(e["slot"]), "player_id": str(e["player_id"]),
					"human": e["ai"] == null, "owner": not owner.is_empty() and owner["player_id"] == e["player_id"],
					"intent": str(e.get("intent", "HUMAN" if e["ai"] == null else "")),
					"action_state": acts.get_action_state_name() if acts != null else "KEEPER",
					"charging": str(e.get("charging", &"")), "cmd_action": str(cmd.get("action", &"")),
					"move": _v2(intent.move_vector()) if intent != null else [0, 0], "aim": _v2(intent.aim) if intent != null else [0, 0],
					"pos": _v3(n.global_position), "vel": _v3(n.velocity)})
	var clip := m.replay_buffer.clip(REPLAY_SECONDS) if m.replay_buffer != null else {"frames": [], "duration": 0.0, "body_count": 0}
	var frames: Array = []
	for f in clip["frames"]:
		frames.append({"t": float(f["t"]), "data": Array(f["data"] as PackedFloat32Array)})
	return {"version": VERSION, "kind": "king_football_bug_report", "created": Time.get_datetime_string_from_system(),
			"engine": Engine.get_version_info()["string"], "clock": m._clock, "display_minute": m.state.display_minute(),
			"phase": int(m.state.phase), "ball_owner": str(owner.get("player_id", "")), "incoming_pass": _clean(m.incoming_pass),
			"players": players, "ball": {"pos": _v3(m.ball.global_position), "vel": _v3(m.ball.linear_velocity)},
			"snapshot": MatchSnapshot.capture(m),
			"replay": {"duration": float(clip["duration"]), "body_count": int(clip["body_count"]), "frames": frames}}


## Saves a report of the running match. Returns the file path, or "" when it could not be written.
static func save(m: MatchManager, dir: String = DIR) -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s_%d.json" % [dir, stamp, Time.get_ticks_msec() % 1000]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(build(m)))
	f.close()
	return path


## Reads a report back (empty Dictionary when the file is missing or not a report).
static func load_report(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or str((parsed as Dictionary).get("kind", "")) != "king_football_bug_report":
		return {}
	return parsed


## The replay part of a report as a `ReplayBuffer` clip (for `ReplayPlayer` / `ReplayBuffer.sample`).
static func replay_clip(report: Dictionary) -> Dictionary:
	var r: Dictionary = report.get("replay", {})
	var frames: Array = []
	for f in r.get("frames", []):
		frames.append({"t": float(f["t"]), "data": PackedFloat32Array(f["data"])})
	return {"frames": frames, "duration": float(r.get("duration", 0.0)), "body_count": int(r.get("body_count", 0))}


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func _clean(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k] if (d[k] is String or d[k] is float or d[k] is int or d[k] is bool) else str(d[k])
	return out
