extends Node
class_name TeamDatabase

## Central team + player database (autoload `TeamDB`, Phases T1/T2).
## Loads JSON from `res://data/clubs` and `res://data/national_teams` (plus
## optional user files in `user://teams`). Bad files/records are skipped and
## reported in `errors`; a duplicate id never overwrites an existing record.
## Adding a team needs only a new JSON file — no code changes.

const DATA_DIRS: Array[String] = ["res://data/clubs", "res://data/national_teams", "user://teams"]
## Optional data packs: `res://data/packs/<id>/{pack.json, clubs/, leagues/}`. A pack REPLACES
## the default world (never mixed with it). The choice is stored in the settings file.
const PACKS_DIR := "res://data/packs"
const SETTINGS_PATH := "user://settings.cfg"

var teams: Dictionary = {}     # team_id -> TeamData
var players: Dictionary = {}   # player_id -> PlayerData
var errors: Array[String] = []
## Leagues of the active pack: key -> LeagueDef (empty for the default world).
var leagues: Dictionary = {}
## Id of the loaded pack ("" = default fictional world) and its pack.json.
var pack_id := ""
var pack_info: Dictionary = {}


func _ready() -> void:
	reload()


## Loads the configured world: the saved pack choice, or the default world.
## Headless runs (tests) ignore the saved choice unless KING_DATA_PACK is set.
func reload() -> void:
	load_world(configured_pack())


func load_world(p_pack_id: String) -> void:
	clear()
	if p_pack_id != "" and FileAccess.file_exists("%s/%s/pack.json" % [PACKS_DIR, p_pack_id]):
		load_pack(p_pack_id)
	else:
		for dir in DATA_DIRS:
			load_directory(dir)


func clear() -> void:
	teams.clear()
	players.clear()
	errors.clear()
	leagues.clear()
	pack_id = ""
	pack_info = {}


# --- data packs ---------------------------------------------------------------------

## Loads clubs and leagues of a pack. Invalid leagues are reported in `errors` and skipped.
func load_pack(p_pack_id: String) -> bool:
	var base := "%s/%s" % [PACKS_DIR, p_pack_id]
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "/pack.json"))
	if typeof(info) != TYPE_DICTIONARY:
		errors.append("%s: pack.json missing or invalid" % base)
		return false
	pack_id = p_pack_id
	pack_info = info
	load_directory(base + "/clubs")
	var dir := DirAccess.open(base + "/leagues")
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for f in files:
			if f.get_extension() != "json":
				continue
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/leagues/%s" % [base, f]))
			if typeof(d) != TYPE_DICTIONARY:
				errors.append("%s/leagues/%s: invalid JSON" % [base, f])
				continue
			var lg := LeagueDef.from_dict(f.get_basename(), d)
			var problems := lg.validate(self)
			if not problems.is_empty():
				for e in problems:
					errors.append("%s: %s" % [f, e])
				continue
			leagues[lg.key] = lg
	return true


## Packs shipped with the game: [{id, name, season, ...pack.json}].
static func available_packs() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PACKS_DIR)
	if dir == null:
		return out
	for sub in dir.get_directories():
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/pack.json" % [PACKS_DIR, sub]))
		if typeof(info) == TYPE_DICTIONARY:
			var entry: Dictionary = info
			entry["id"] = sub
			out.append(entry)
	return out


static func configured_pack() -> String:
	var forced := OS.get_environment("KING_DATA_PACK")
	if forced != "":
		return "" if forced == "default" else forced
	if DisplayServer.get_name() == "headless":
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value("data", "pack", ""))


## Stores the pack choice (takes effect on the next `reload()` / start). "" = default world.
static func save_pack_choice(p_pack_id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)          # keep the other settings (language)
	cfg.set_value("data", "pack", p_pack_id)
	cfg.save(SETTINGS_PATH)


func load_directory(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var loaded := 0
	var files := dir.get_files()
	files.sort()
	for f in files:
		if f.get_extension().to_lower() == "json":
			if load_file("%s/%s" % [path, f]):
				loaded += 1
	return loaded


## Loads one JSON file: {"team": {...}, "players": [{...}, ...]}.
func load_file(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		errors.append("%s: unreadable or empty" % path)
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("team"):
		errors.append("%s: invalid JSON structure" % path)
		return false
	return register_from_dict(parsed, path)


func register_from_dict(data: Dictionary, source := "dict") -> bool:
	var team := TeamData.from_dict(data["team"])
	var roster: Array[PlayerData] = []
	for pd in data.get("players", []):
		if typeof(pd) == TYPE_DICTIONARY:
			var p := PlayerData.from_dict(pd)
			p.team_id = team.id
			roster.append(p)
	team.squad_ids = PackedStringArray(roster.map(func(p: PlayerData) -> String: return p.id))
	return register_team(team, roster, source)


## Validates and atomically registers a team with its players. Returns false
## (and records errors) on invalid data or duplicate ids; nothing is added then.
func register_team(team: TeamData, roster: Array[PlayerData], source := "code") -> bool:
	var problems: Array[String] = team.validate()
	if teams.has(team.id):
		problems.append("duplicate team id '%s'" % team.id)
	var batch_ids := {}
	for p in roster:
		problems.append_array(p.validate())
		if players.has(p.id) or batch_ids.has(p.id):
			problems.append("duplicate player id '%s'" % p.id)
		batch_ids[p.id] = true
	if not problems.is_empty():
		for e in problems:
			errors.append("%s: %s" % [source, e])
		return false
	teams[team.id] = team
	for p in roster:
		players[p.id] = p
		PlayerAppearance.ensure(p)
		p.team_id = team.id
		if not team.squad_ids.has(p.id):
			team.squad_ids.append(p.id)   # keep squad_ids authoritative so remove_team finds everyone
	return true


## Registers a single player that is not part of a team squad (academy youth).
func register_player(p: PlayerData) -> bool:
	var problems := p.validate()
	if players.has(p.id):
		problems.append("duplicate player id '%s'" % p.id)
	if not problems.is_empty():
		for e in problems:
			errors.append("register_player: %s" % e)
		return false
	players[p.id] = p
	PlayerAppearance.ensure(p)
	return true


func remove_team(team_id: String) -> bool:
	if not teams.has(team_id):
		return false
	for pid in (teams[team_id] as TeamData).squad_ids:
		players.erase(pid)
	teams.erase(team_id)
	return true


func get_team(team_id: String) -> TeamData:
	return teams.get(team_id)


func get_player(player_id: String) -> PlayerData:
	return players.get(player_id)


func list_teams(category: int = -1, real_filter: int = -1) -> Array[TeamData]:
	var out: Array[TeamData] = []
	for t: TeamData in teams.values():
		if category >= 0 and int(t.category) != category:
			continue
		if real_filter >= 0 and int(t.is_real) != real_filter:
			continue
		out.append(t)
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.id < b.id)
	return out


func get_squad(team_id: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var t := get_team(team_id)
	if t == null:
		return out
	for pid in t.squad_ids:
		if players.has(pid):
			out.append(players[pid])
	return out


## Team rating = mean overall of the best 11 players (0 when squad < 11).
func get_team_rating(team_id: String) -> int:
	var overalls: Array[int] = []
	for p in get_squad(team_id):
		overalls.append(p.get_overall())
	if overalls.size() < 11:
		return 0
	overalls.sort()
	overalls.reverse()
	var total := 0
	for i in 11:
		total += overalls[i]
	return roundi(total / 11.0)
