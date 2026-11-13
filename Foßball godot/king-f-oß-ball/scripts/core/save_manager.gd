class_name SaveManager
extends RefCounted

## Versioned, validated, atomic save/load (Phase T6).
## v2 adds players[].appearance (see PlayerAppearance); v3 (unified database) adds the club / player
## identity fields, "crests" (alternative crest designs) and season-aware statistics. Older saves are
## migrated step by step; `backup_if_outdated` keeps a copy of an old file before it is overwritten.
## Format: {"save_version": int, "teams": [...], "players": [...],
##          "academies": {team_id: {...}}, "scouting": {team_id: {...}},
##          "training": {team_id: {...}}, "squads": {team_id: {...}},
##          "extras": {...}}   (extras = room for career/competitions later)
## `restore()` is all-or-nothing: the database is only touched after the whole
## file has been validated.

const SAVE_VERSION := 3
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
			2:   # v3: unified database. Only DERIVABLE data is filled in; nothing the player did is touched.
				_migrate_2_to_3(d)
				version = 3
			_:
				return {"error": "no migration from save version %d" % version}
		d["save_version"] = version
	return d


static var _country_ids: Dictionary = {}       # country name -> id (data/countries.json), loaded once


static func _country_id_for(country_name: String) -> String:
	if _country_ids.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CountryData.PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			for c in (parsed as Dictionary).get("countries", []):
				_country_ids[str(c.get("country_name", ""))] = str(c.get("country_id", ""))
	return str(_country_ids.get(country_name, ""))


## v2 -> v3. Clubs: club type (from the real flag), country id, crest id. Players: first / last name,
## nationality id, player type. Career statistics: the all-time counters of a v2 career have no season,
## so they are kept as one "0:legacy" bucket per player (season 0, competition "legacy"); empty
## "crests" block. Existing values are never overwritten.
static func _migrate_2_to_3(d: Dictionary) -> void:
	for td in d.get("teams", []):
		if typeof(td) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = td
		if not t.has("club_type"):
			t["club_type"] = "REAL" if bool(t.get("real", false)) else "FICTIONAL"
		if not t.has("country_id"):
			t["country_id"] = _country_id_for(str(t.get("country", "")))
		if not t.has("crest_id") and str(t.get("category", "CLUB")) == "CLUB":
			t["crest_id"] = "crest_" + str(t.get("id", ""))
	for pd in d.get("players", []):
		if typeof(pd) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = pd
		var parts := PlayerData.split_name(str(p.get("name", "")))
		if not p.has("first_name") and not p.has("last_name"):
			p["first_name"] = parts[0]
			p["last_name"] = parts[1]
		if not p.has("nationality_id"):
			p["nationality_id"] = _country_id_for(str(p.get("nationality", "")))
		if not p.has("player_type"):
			p["player_type"] = PlayerData.PlayerType.keys()[PlayerData.type_for_id(str(p.get("id", "")))]
	if not d.has("crests"):
		d["crests"] = []
	var extras: Variant = d.get("extras", {})
	if typeof(extras) == TYPE_DICTIONARY and (extras as Dictionary).has("career"):
		var career: Dictionary = extras["career"]
		var stats: Dictionary = career.get("player_stats", {})
		var seasons: Dictionary = career.get("season_stats", {})
		for pid in stats:
			if not seasons.has(pid):
				seasons[pid] = {"0:legacy": (stats[pid] as Dictionary).duplicate(true)}
		career["season_stats"] = seasons


## Keeps a copy of a save file written by an OLDER game version next to it ("<file>.v<N>.bak") before
## anything overwrites it. An existing backup is never replaced. Returns "" when there is nothing to
## do or the backup exists, else an error message (callers must then not overwrite the file).
static func backup_if_outdated(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""                                   # corrupt files are never overwritten by loading; saving is the caller's call
	var version := int((parsed as Dictionary).get("save_version", 0))
	if version >= SAVE_VERSION:
		return ""
	var backup := "%s.v%d.bak" % [path, version]
	if FileAccess.file_exists(backup):
		return ""
	var err := DirAccess.copy_absolute(path, backup)
	return "" if err == OK else "cannot back up the old save (error %d): '%s' was not changed" % [err, path]


# --- validation + restore -------------------------------------------------------------

## Returns a list of integrity problems (empty = loadable).
## `parsed` (optional) receives the records built while checking ({"players": Array[PlayerData],
## "teams": Array[TeamData]}), so `restore` does not parse every record a second time.
static func validate(data: Dictionary, parsed: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		errors.append("unsupported save version")
		return errors
	# A damaged file can hold the wrong kind of value: report it instead of crashing in the checks below.
	for key in ["teams", "players"]:
		if typeof(data.get(key, [])) != TYPE_ARRAY:
			errors.append("save block '%s' is not a list" % key)
		else:
			for item in data[key]:
				if typeof(item) != TYPE_DICTIONARY:
					errors.append("save block '%s' holds a record that is not an object" % key)
					break
	for key in ["academies", "scouting", "training", "squads"]:
		if typeof(data.get(key, {})) != TYPE_DICTIONARY:
			errors.append("save block '%s' is not an object" % key)
	if not errors.is_empty():
		return errors
	var player_ids := {}
	var players_out: Array[PlayerData] = []
	var teams_out: Array[TeamData] = []
	for pd in data.get("players", []):
		var p := PlayerData.from_dict(pd)
		players_out.append(p)
		errors.append_array(p.validate())
		if player_ids.has(p.id):
			errors.append("duplicate player id '%s'" % p.id)
		player_ids[p.id] = true
	var team_ids := {}
	var in_squad := {}
	for td in data.get("teams", []):
		var t := TeamData.from_dict(td)
		teams_out.append(t)
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
	parsed["players"] = players_out
	parsed["teams"] = teams_out
	return errors


## Validates then rebuilds the database. Returns {"ok", "errors", "academies",
## "scouting", "training", "squads", "extras"}; the database is untouched on failure.
static func restore(db: Node, data: Dictionary) -> Dictionary:
	var migrated := migrate(data)
	if migrated.has("error"):
		return {"ok": false, "errors": [migrated["error"]]}
	var parsed := {}
	var errors := validate(migrated, parsed)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	db.teams.clear()
	db.players.clear()
	if db.get("crests") != null:
		db.crests.load_alternatives(migrated.get("crests", []))      # alternative crest designs added in play
	for p: PlayerData in parsed["players"]:
		if db.has_method("link_player"):
			db.link_player(p)               # nationality id of saves written before database v3
		PlayerAppearance.ensure(p)          # repairs missing/invalid appearance, never regenerates a valid one
		db.players[p.id] = p
	for t: TeamData in parsed["teams"]:
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
