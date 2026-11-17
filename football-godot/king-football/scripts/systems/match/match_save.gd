class_name MatchSave
extends RefCounted

## In-progress match save (Phase 7.4): versioned, validated, written atomically with a `.bak`
## fallback, so a damaged file can never crash the game or hand back half a match.
##
## What is saved (see `MatchManager.save_match`): kick-off setup (for restart), the live setup (current
## lineups after substitutions and current tactics), the whole `MatchState` (clock, half, phase, score,
## events, stamina, substitutions and all statistics), every player's position / rotation / velocity,
## the ball, the engine's flow timers, and the pending career fixture. Player ids are never
## regenerated: the match is rebuilt from the saved squads and then overwritten with the saved state.
## Rendering objects (meshes, materials, cameras) are not serialised; they are rebuilt.

const VERSION := 1
const KIND := "king_match"
const DEFAULT_PATH := "user://saves/match.json"
const MAX_COORD := 500.0


static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## Writes `data` atomically; the previous good file becomes `<path>.bak`. Returns "" or an error.
static func write(data: Dictionary, path: String = DEFAULT_PATH) -> String:
	var problems := validate_structure(data)
	if not problems.is_empty():
		return "refusing to save an invalid match: %s" % problems[0]
	if FileAccess.file_exists(path):
		var prev := FileAccess.get_file_as_string(path)
		if JSON.parse_string(prev) is Dictionary:           # only keep a backup that is itself readable
			var bak := FileAccess.open(path + ".bak", FileAccess.WRITE)
			if bak != null:
				bak.store_string(prev)
				bak.close()
	return SaveManager.write_file(path, data)


## Reads and validates a match save. Falls back to `<path>.bak` when the main file is damaged.
## Returns {"ok": bool, "data": Dictionary, "errors": Array[String], "recovered": bool}.
static func read(db: Node, path: String = DEFAULT_PATH) -> Dictionary:
	var errors: Array[String] = []
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s is corrupt" % candidate.get_file())
			continue
		var migrated := migrate(parsed)
		if migrated.has("error"):
			errors.append(str(migrated["error"]))
			continue
		var problems := validate(migrated, db)
		if problems.is_empty():
			return {"ok": true, "data": migrated, "errors": errors, "recovered": candidate != path}
		errors.append_array(problems)
	if errors.is_empty():
		errors.append("no saved match found")
	return {"ok": false, "data": {}, "errors": errors, "recovered": false}


## Upgrades older formats step by step; newer-than-known versions are refused.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > VERSION:
		return {"error": "match save version %d is newer than this game (%d)" % [version, VERSION]}
	var d := data.duplicate(true)
	while version < VERSION:
		match version:
			0:      # pre-release files without the kind/initial setup: treat the live setup as the kick-off setup
				if not d.has("initial_setup"):
					d["initial_setup"] = (d.get("setup", {}) as Dictionary).duplicate(true)
				if not d.has("flow"):
					d["flow"] = {}
				version = 1
			_:
				return {"error": "no migration from match save version %d" % version}
		d["version"] = version
	d["kind"] = KIND
	return d


## Structural checks that need no database (also run before writing).
static func validate_structure(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if str(d.get("kind", "")) != KIND:
		e.append("not a match save")
		return e
	for k in ["setup", "initial_setup", "state", "players", "ball", "flow"]:
		if not d.has(k):
			e.append("missing '%s'" % k)
	if not e.is_empty():
		return e
	var st: Dictionary = d["state"]
	var phase := int(st.get("phase", -1))
	if phase < 0 or phase > 3:
		e.append("invalid match phase %d" % phase)
	if phase == 3:
		e.append("the match is already finished")
	if bool(st.get("result_processed", false)):
		e.append("the result of this match was already processed")
	var half := int(st.get("half", 0))
	if half < 1 or half > 2:
		e.append("invalid half %d" % half)
	var dur := float(st.get("duration", 0.0))
	var el := float(st.get("elapsed", -1.0))
	if not is_finite(dur) or not is_finite(el) or dur <= 0.0 or el < 0.0 or el > dur:
		e.append("invalid match clock")
	var score: Dictionary = st.get("score", {})
	var goals := {"home": 0, "away": 0}
	for ev in st.get("events", []):
		if (ev as Dictionary).get("type", "") == "goal" and goals.has(str(ev.get("side", ""))):
			goals[str(ev["side"])] += 1
	for side in ["home", "away"]:
		var s := int(score.get(side, -1))
		if s < 0 or s != goals[side]:
			e.append("score of %s does not match the recorded goals" % side)
	for p in d["players"]:
		var pos: Array = (p as Dictionary).get("pos", [])
		if pos.size() != 3 or pos.any(func(v: Variant) -> bool: return not (v is float or v is int) or not is_finite(float(v)) or absf(float(v)) > MAX_COORD):
			e.append("invalid player position")
			break
	var bp: Array = (d["ball"] as Dictionary).get("pos", [])
	if bp.size() != 3 or bp.any(func(v: Variant) -> bool: return not (v is float or v is int) or not is_finite(float(v)) or absf(float(v)) > MAX_COORD):
		e.append("invalid ball position")
	if (d["players"] as Array).size() != 22:
		e.append("a saved match needs 22 players, found %d" % (d["players"] as Array).size())
	return e


## Full validation incl. references into the database.
static func validate(d: Dictionary, db: Node) -> Array[String]:
	var e := validate_structure(d)
	if not e.is_empty():
		return e
	var setup := MatchSetup.from_dict(d["setup"])
	for id in [setup.home_id, setup.away_id]:
		if db.get_team(id) == null:
			e.append("saved match references an unknown team '%s'" % id)
	if not e.is_empty():
		return e
	var seen := {}
	for p in d["players"]:
		var pid := str(p.get("player_id", ""))
		if db.get_player(pid) == null:
			e.append("saved match references an unknown player '%s'" % pid)
		if seen.has(pid):
			e.append("player '%s' appears twice" % pid)
		seen[pid] = true
	for side in ["home", "away"]:
		var squad: Squad = setup.home_squad if side == "home" else setup.away_squad
		if squad == null:
			e.append("no saved squad for %s" % side)
			continue
		for id in squad.starting:
			if not seen.has(id):
				e.append("lineup player '%s' is missing from the saved players" % id)
	return e
