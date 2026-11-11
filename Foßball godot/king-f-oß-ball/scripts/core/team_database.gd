extends Node

## Central team + player database (autoload `TeamDB`, Phases T1/T2).
## Loads JSON from `res://data/clubs` and `res://data/national_teams` (plus
## optional user files in `user://teams`). Bad files/records are skipped and
## reported in `errors`; a duplicate id never overwrites an existing record.
## Adding a team needs only a new JSON file — no code changes.

const DATA_DIRS: Array[String] = ["res://data/clubs", "res://data/national_teams", "user://teams"]

var teams: Dictionary = {}     # team_id -> TeamData
var players: Dictionary = {}   # player_id -> PlayerData
var errors: Array[String] = []


func _ready() -> void:
	reload()


func reload() -> void:
	clear()
	for dir in DATA_DIRS:
		load_directory(dir)


func clear() -> void:
	teams.clear()
	players.clear()
	errors.clear()


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
