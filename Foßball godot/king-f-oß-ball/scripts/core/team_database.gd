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
## Kit repairs applied while loading (team id -> list), see KitEditor.repair.
var kit_repairs: Dictionary = {}
## When true, a pack's `fictional/clubs/` layer (generated clubs, database phase 6) is not loaded.
## Only the world generator sets it, to read the real data it builds on.
var skip_fictional_layer := false
## Countries (data/countries.json): country_id -> CountryData.
var countries: Dictionary = {}
## Crest records (data/crests/crests.json) and crest lookup for every club.
var crests := CrestRegistry.new()
var _country_by_name: Dictionary = {}   # country_name -> country_id
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
	load_countries()
	crests.load_defaults()
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
	countries.clear()
	_country_by_name.clear()
	crests.clear()
	kit_repairs.clear()
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
	if not skip_fictional_layer:
		load_directory(base + "/fictional/clubs")      # generated fictional clubs, kept apart from the real data
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
	link_leagues()
	return true


# --- countries + club links (database v3) ------------------------------------------

## Loads `data/countries.json`. A bad file or record is reported in `errors`, never fatal.
func load_countries(path: String = CountryData.PATH) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: countries file missing or invalid" % path)
		return 0
	for cd in (parsed as Dictionary).get("countries", []):
		if typeof(cd) != TYPE_DICTIONARY:
			continue
		var c := CountryData.from_dict(cd)
		var problems := c.validate()
		if countries.has(c.country_id):
			problems.append("duplicate country id '%s'" % c.country_id)
		if not problems.is_empty():
			for e in problems:
				errors.append("%s: %s" % [path, e])
			continue
		countries[c.country_id] = c
		_country_by_name[c.country_name] = c.country_id
	return countries.size()


func get_country(country_id: String) -> CountryData:
	return countries.get(country_id)


## Country id for a stored country name ("" when unknown).
func country_id_for(country_name: String) -> String:
	return str(_country_by_name.get(country_name, ""))


## Fills the derived, optional club fields (country id, crest id) without touching
## anything that is already set. Safe to call repeatedly (also for restored saves).
func link_team(t: TeamData) -> void:
	if t.country_id == "":
		t.country_id = country_id_for(t.country)
	if t.crest_id == "" and t.category == TeamData.Category.CLUB:
		t.crest_id = "crest_" + t.id


## Fills the optional derived player fields without overwriting stored values.
func link_player(p: PlayerData) -> void:
	if p.nationality_id == "":
		p.nationality_id = country_id_for(p.nationality)
	if p.first_name == "" and p.last_name == "":
		var parts := PlayerData.split_name(p.display_name)
		p.first_name = parts[0]
		p.last_name = parts[1]
	if p.id.begins_with("tm_") or p.id.begins_with("yth_"):
		p.player_type = PlayerData.type_for_id(p.id)     # origin follows the id; GENERATED is the default


## Sets league_id (division id) and division (tier) on every club of the loaded leagues.
func link_leagues() -> void:
	for lg: LeagueDef in leagues.values():
		for dv in lg.divisions:
			for tid in dv["team_ids"]:
				var t: TeamData = teams.get(tid)
				if t == null:
					continue
				t.league_id = str(dv["id"])
				t.division = int(dv["tier"])


## Kit problems of every club (see KitEditor.problems); empty after loading because loading repairs them.
func validate_kits() -> Array[String]:
	var out: Array[String] = []
	for t: TeamData in teams.values():
		if t.category == TeamData.Category.CLUB:
			for p in KitEditor.problems(t):
				out.append("team '%s': %s" % [t.id, p])
	return out


## Cross-record problems (empty = consistent): clubs without a known country, league links
## that disagree with the leagues, missing rivals, squads referencing unknown players or
## players whose team_id does not match their squad.
func validate_relations() -> Array[String]:
	var out: Array[String] = []
	var division_of := {}          # club id -> division id
	for lg: LeagueDef in leagues.values():
		for dv in lg.divisions:
			for tid in dv["team_ids"]:
				division_of[tid] = str(dv["id"])
	for t: TeamData in teams.values():
		if t.category == TeamData.Category.CLUB:
			if t.country_id == "" or not countries.has(t.country_id):
				out.append("team '%s': unknown country '%s'" % [t.id, t.country])
			elif (countries[t.country_id] as CountryData).country_name != t.country:
				out.append("team '%s': country_id '%s' does not match country '%s'" % [t.id, t.country_id, t.country])
		if not leagues.is_empty() and t.category == TeamData.Category.CLUB:
			if t.league_id != str(division_of.get(t.id, "")):
				out.append("team '%s': league_id '%s' disagrees with the leagues ('%s')" % [t.id, t.league_id, division_of.get(t.id, "")])
		for r in t.rival_club_ids:
			if not teams.has(r):
				out.append("team '%s': unknown rival '%s'" % [t.id, r])
		for pid in t.squad_ids:
			var p: PlayerData = players.get(pid)
			if p == null:
				out.append("team '%s': squad lists missing player '%s'" % [t.id, pid])
			elif p.team_id != t.id and p.status != PlayerData.Status.LOANED:
				out.append("team '%s': player '%s' has team_id '%s'" % [t.id, pid, p.team_id])
	return out


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
	link_team(team)
	if team.category == TeamData.Category.CLUB:
		var fixes := KitEditor.repair(team)
		if not fixes.is_empty():
			kit_repairs[team.id] = fixes
	for p in roster:
		players[p.id] = p
		link_player(p)
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
	link_player(p)
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
