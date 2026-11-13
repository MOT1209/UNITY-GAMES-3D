class_name SaveManager
extends RefCounted

## Versioned, validated, atomic save/load (Phase T6).
## v2 adds players[].appearance (see PlayerAppearance); v1 saves are migrated.
## Format: {"save_version": int, "teams": [...], "players": [...],
##          "academies": {team_id: {...}}, "scouting": {team_id: {...}},
##          "training": {team_id: {...}}, "squads": {team_id: {...}},
##          "extras": {...}}   (extras = room for career/competitions later)
## `restore()` is all-or-nothing: the database is only touched after the whole
## file has been validated.

const SAVE_VERSION := 2
const SAVE_DIR := "user://saves"


## Snapshot of the live game state. Dictionaries map team_id -> system object.
static func capture(db: Node, academies: Dictionary = {}, scouting: Dictionary = {},
		training: Dictionary = {}, squads: Dictionary = {}, extras: Dictionary = {}) -> Dictionary:
	var teams: Array = []
	for t: TeamData in db.teams.values():
		teams.append(t.to_dict())
	var players: Array = []
	for p: PlayerData in db.players.values():
		players.append(p.to_dict())
	var crests: Array = db.crests.alternatives_to_dict() if db.get("crests") != null else []
	return {"save_version": SAVE_VERSION, "teams": teams, "players": players, "crests": crests,
			"academies": _dump(academies), "scouting": _dump(scouting),
			"training": _dump(training), "squads": _dump(squads), "extras": extras.duplicate(true)}


static func _dump(systems: Dictionary) -> Dictionary:
	var out := {}
	for k in systems:
		out[k] = systems[k].to_dict()
	return out


# --- file IO ----------------------------------------------------------------------

## Writes to "<path>.tmp" then renames, so a crash never leaves a half file.
static func write_file(path: String, data: Dictionary) -> String:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "cannot open '%s' for writing" % tmp
	# full_precision: the default truncates floats to 14 digits and loses growth progress
	f.store_string(JSON.stringify(data, "\t", true, true))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	return "" if err == OK else "cannot finalise save (error %d)" % err


## Returns {"ok": bool, "data": Dictionary, "error": String}.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "error": "save file not found"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "save file is corrupt"}
	var migrated := migrate(parsed)
	if migrated.has("error"):
		return {"ok": false, "data": {}, "error": migrated["error"]}
	return {"ok": true, "data": migrated, "error": ""}


# --- migration ---------------------------------------------------------------------

## Upgrades old saves step by step. Unknown/newer versions are refused.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version > SAVE_VERSION:
		return {"error": "save version %d is newer than this game (%d)" % [version, SAVE_VERSION]}
	var d := data.duplicate(true)
	while version < SAVE_VERSION:
		match version:
			0:   # v0 (pre-release) had no extras/squads/training blocks
				for k in ["academies", "scouting", "training", "squads", "extras"]:
					if not d.has(k):
						d[k] = {}
				version = 1
			1:   # v1 players had no stored appearance: derive it from the player id
				for pd in d.get("players", []):
					if typeof(pd) == TYPE_DICTIONARY and not (pd as Dictionary).has("appearance"):
						var is_gk := str((pd as Dictionary).get("position", "")) == "GK"
						pd["appearance"] = PlayerAppearance.generate(PlayerAppearance.seed_for(str(pd.get("id", ""))), is_gk)
				version = 2
			_:
				return {"error": "no migration from save version %d" % version}
		d["save_version"] = version
	return d


# --- validation + restore -------------------------------------------------------------

## Returns a list of integrity problems (empty = loadable).
static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		errors.append("unsupported save version")
		return errors
	var player_ids := {}
	for pd in data.get("players", []):
		var p := PlayerData.from_dict(pd)
		errors.append_array(p.validate())
		if player_ids.has(p.id):
			errors.append("duplicate player id '%s'" % p.id)
		player_ids[p.id] = true
	var team_ids := {}
	var in_squad := {}
	for td in data.get("teams", []):
		var t := TeamData.from_dict(td)
		errors.append_array(t.validate())
		if team_ids.has(t.id):
			errors.append("duplicate team id '%s'" % t.id)
		team_ids[t.id] = true
		for pid in t.squad_ids:
			if not player_ids.has(pid):
				errors.append("team '%s' squad references missing player '%s'" % [t.id, pid])
			if in_squad.has(pid):
				errors.append("player '%s' is in two squads" % pid)
			in_squad[pid] = t.id
	var in_academy := {}
	for team_id in data.get("academies", {}):
		var a := Academy.from_dict(data["academies"][team_id])
		if not team_ids.has(a.team_id):
			errors.append("academy for unknown team '%s'" % a.team_id)
		for pid in a.roster_ids:
			if not player_ids.has(pid):
				errors.append("academy references missing player '%s'" % pid)
			if in_squad.has(pid):
				errors.append("player '%s' is both in the academy and the first team" % pid)
			if in_academy.has(pid):
				errors.append("player '%s' is in two academies" % pid)
			in_academy[pid] = true
	return errors


## Validates then rebuilds the database. Returns {"ok", "errors", "academies",
## "scouting", "training", "squads", "extras"}; the database is untouched on failure.
static func restore(db: Node, data: Dictionary) -> Dictionary:
	var migrated := migrate(data)
	if migrated.has("error"):
		return {"ok": false, "errors": [migrated["error"]]}
	var errors := validate(migrated)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	db.teams.clear()
	db.players.clear()
	if db.get("crests") != null:
		db.crests.load_alternatives(migrated.get("crests", []))      # alternative crest designs added in play
	for pd in migrated.get("players", []):
		var p := PlayerData.from_dict(pd)
		if db.has_method("link_player"):
			db.link_player(p)               # nationality id of saves written before database v3
		PlayerAppearance.ensure(p)          # repairs missing/invalid appearance, never regenerates a valid one
		db.players[p.id] = p
	for td in migrated.get("teams", []):
		var t := TeamData.from_dict(td)
		db.teams[t.id] = t
		if db.has_method("link_team"):
			db.link_team(t)        # fills country/crest ids of saves written before database v3
	var out := {"ok": true, "errors": [], "extras": migrated.get("extras", {})}
	out["academies"] = _load(migrated.get("academies", {}), func(d: Dictionary) -> Object: return Academy.from_dict(d))
	out["scouting"] = _load(migrated.get("scouting", {}), func(d: Dictionary) -> Object: return ScoutingSystem.from_dict(d))
	out["training"] = _load(migrated.get("training", {}), func(d: Dictionary) -> Object: return TrainingSystem.from_dict(d))
	out["squads"] = _load(migrated.get("squads", {}), func(d: Dictionary) -> Object: return Squad.from_dict(d))
	return out


static func _load(block: Dictionary, factory: Callable) -> Dictionary:
	var out := {}
	for k in block:
		out[k] = factory.call(block[k])
	return out
