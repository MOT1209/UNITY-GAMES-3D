class_name CrestRegistry
extends RefCounted

## Index of all crest records (database phase 4): lookup by crest id and by club, validation,
## alternative-crest assignment and custom-crest import.
##
## Shipped records live in `res://data/crests/crests.json` (generated once, deterministic, see
## tools/generate_crests.gd). A club WITHOUT a shipped record (generated or user-made clubs) gets
## a deterministic design derived from its id on first use, so a crest never changes between
## sessions and no screen has to wait for generation.

const CRESTS_PATH := "res://data/crests/crests.json"
const BLOCKLIST_PATH := "res://data/crests/blocklist.json"

var crests: Dictionary = {}            # crest_id -> CrestData
var errors: Array[String] = []
var _blocked: Dictionary = {}          # club id -> Array of blocked symbols
var _derived: Dictionary = {}          # club id -> CrestData derived on demand (not shipped)
var _used: Dictionary = {}             # signature -> club id (designs taken by shipped crests)
var _alternatives: Array[String] = []  # ids of crests added in play (not shipped): saved with the game


func clear() -> void:
	crests.clear()
	errors.clear()
	_blocked.clear()
	_derived.clear()
	_used.clear()
	_alternatives.clear()


func load_defaults() -> void:
	load_blocklist()
	load_file()


func load_blocklist(path: String = BLOCKLIST_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		_blocked = (parsed as Dictionary).get("blocked_symbols", {})


## Loads a crests file; invalid records are reported in `errors` and skipped.
func load_file(path: String = CRESTS_PATH) -> int:
	if not FileAccess.file_exists(path):
		errors.append("%s: crests file missing" % path)
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: crests file missing or invalid" % path)
		return 0
	var loaded := 0
	for d in (parsed as Dictionary).get("crests", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var c := CrestData.from_dict(d)
		var problems := c.validate()
		if crests.has(c.crest_id):
			problems.append("duplicate crest id '%s'" % c.crest_id)
		if not problems.is_empty():
			for e in problems:
				errors.append("%s: %s" % [path, e])
			continue
		register(c)
		loaded += 1
	return loaded


func register(c: CrestData) -> void:
	crests[c.crest_id] = c
	if c.is_procedural():
		_used[c.signature()] = c.club_id


func get_crest(crest_id: String) -> CrestData:
	return crests.get(crest_id)


## All crests that belong to a club (the shipped one plus alternatives).
func crests_of(club_id: String) -> Array[CrestData]:
	var out: Array[CrestData] = []
	for c: CrestData in crests.values():
		if c.club_id == club_id:
			out.append(c)
	return out


func blocked_symbols(club_id: String) -> Array:
	return _blocked.get(club_id, [])


## The crest a team shows right now. Order: its own image/template (user crest), the crest id
## it points to, a shipped crest of the club, else a deterministic derived design.
func for_team(team: TeamData) -> CrestData:
	if team.logo_path != "":
		if LogoService.is_template(team.logo_path) or LogoService.file_ok(team.logo_path):
			return _custom(team)
	var c: CrestData = crests.get(team.crest_id)
	if c != null and c.club_id == team.id and (c.is_procedural() or LogoService.file_ok(c.asset_path)):
		return c
	var own := crests_of(team.id)
	for o in own:
		if o.is_procedural():
			return o
	return derived(team)


## Deterministic design for a club without a shipped crest. Stable: the same id and colours
## always give the same crest (shipped designs are avoided, other derived ones are not tracked).
func derived(team: TeamData) -> CrestData:
	var d: CrestData = _derived.get(team.id)
	if d != null and d.primary_color == team.primary_color and d.secondary_color == team.secondary_color:
		return d
	d = CrestGenerator.generate(team.id, team.primary_color, team.secondary_color, team.accent_color,
			team.is_real, _used.duplicate(), blocked_symbols(team.id))
	if team.club_type == TeamData.ClubType.CUSTOM:
		d.asset_type = CrestData.AssetType.USER_CUSTOM
		d.license_status = "USER_SUPPLIED"
		d.source = "generated for a custom club"
	_derived[team.id] = d
	return d


func _custom(team: TeamData) -> CrestData:
	var c := CrestData.new()
	c.crest_id = "crest_%s_custom" % team.id
	c.club_id = team.id
	c.asset_path = team.logo_path
	if team.logo_path.begins_with("res://"):           # artwork shipped with the game (e.g. the fictional clubs of the default world)
		c.asset_type = CrestData.AssetType.FICTIONAL if not team.is_real else CrestData.AssetType.USER_CUSTOM
		c.license_status = "FICTIONAL" if not team.is_real else "USER_SUPPLIED"
		c.source = "shipped artwork"
	else:
		c.asset_type = CrestData.AssetType.USER_CUSTOM
		c.license_status = "USER_SUPPLIED"
		c.source = "user" if not LogoService.is_template(team.logo_path) else "template"
	c.created_at = "user"
	c.primary_color = team.primary_color
	c.secondary_color = team.secondary_color
	c.accent_color = team.accent_color
	if LogoService.is_template(team.logo_path):
		c.version = 1
	elif LogoService.file_ok(team.logo_path):
		c.version = maxi(1, int(FileAccess.get_modified_time(team.logo_path) % 100000))   # changes with the file
	return c


## Points a team at one of its own crests (an alternative design). Returns "" or an error.
func assign(team: TeamData, crest_id: String) -> String:
	var c := get_crest(crest_id)
	if c == null:
		return "unknown crest '%s'" % crest_id
	if c.club_id != team.id:
		return "crest '%s' belongs to club '%s'" % [crest_id, c.club_id]
	if c.is_file() and not LogoService.file_ok(c.asset_path):
		return "crest asset is missing: %s" % c.asset_path
	team.crest_id = crest_id
	team.logo_path = ""                      # a chosen crest replaces a custom image/template
	return ""


## Adds an alternative design record for a club (not shipped; lives for this session unless the
## caller persists it). Returns "" or an error; the design must be valid and not copy another club's.
func add_alternative(c: CrestData) -> String:
	var problems := c.validate()
	if not problems.is_empty():
		return problems[0]
	if crests.has(c.crest_id):
		return "crest '%s' already exists" % c.crest_id
	var sig := c.signature()
	if c.is_procedural() and _used.has(sig) and _used[sig] != c.club_id:
		return "the same design is already used by '%s'" % _used[sig]
	register(c)
	_alternatives.append(c.crest_id)
	return ""


## The crests added in play (alternative designs), as dictionaries for the save file.
func alternatives_to_dict() -> Array:
	var out: Array = []
	for id in _alternatives:
		if crests.has(id):
			out.append((crests[id] as CrestData).to_dict())
	return out


## Replaces the in-play crests with those of a save: older ones are dropped, saved ones are validated
## and registered (invalid records are reported in `errors` and skipped).
func load_alternatives(records: Array) -> void:
	for id in _alternatives:
		crests.erase(id)
	_alternatives.clear()
	for d in records:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var c := CrestData.from_dict(d)
		var problems := c.validate()
		if crests.has(c.crest_id):
			problems.append("crest '%s' already exists" % c.crest_id)
		if not problems.is_empty():
			errors.append_array(problems.map(func(e: String) -> String: return "save: %s" % e))
			continue
		register(c)
		_alternatives.append(c.crest_id)


## Imports a user image as the crest of `team` (validated, resized, stored by LogoService).
## Returns {"ok", "error", "path"}.
func import_custom(team: TeamData, source_path: String) -> Dictionary:
	return LogoService.import_logo(team, source_path)


# --- validation ---------------------------------------------------------------------------------

## Cross-record problems (empty = consistent): every record valid, every club resolves to a crest, shipped designs are unique, asset files exist and are not duplicated.
func validate(db: Node) -> Array[String]:
	var out: Array[String] = []
	var seen_sig := {}
	var seen_hash := {}
	for c: CrestData in crests.values():
		out.append_array(c.validate())
		if c.is_procedural():
			var sig := c.signature()
			if seen_sig.has(sig):
				out.append("crests '%s' and '%s' have the same design" % [seen_sig[sig], c.crest_id])
			seen_sig[sig] = c.crest_id
		elif c.is_file() and LogoService.file_ok(c.asset_path):
			var h := FileAccess.get_sha256(c.asset_path)
			if seen_hash.has(h):
				out.append("crests '%s' and '%s' use identical image files" % [seen_hash[h], c.crest_id])
			seen_hash[h] = c.crest_id
	for t: TeamData in db.teams.values():
		if t.category != TeamData.Category.CLUB:
			continue
		var ref: CrestData = crests.get(t.crest_id)
		if ref != null and ref.club_id != t.id:
			out.append("club '%s' points at crest '%s' of club '%s'" % [t.id, ref.crest_id, ref.club_id])
	return out


## Shipped crests of clubs that are not in the loaded world (normal: the file covers every shipped world).
func orphan_crests(db: Node) -> Array[String]:
	var out: Array[String] = []
	for c: CrestData in crests.values():
		if db.get_team(c.club_id) == null:
			out.append(c.crest_id)
	return out


## crest ids whose asset file (not a procedural/template crest) is missing.
func missing_assets() -> Array[String]:
	var out: Array[String] = []
	for c: CrestData in crests.values():
		if c.is_file() and not LogoService.file_ok(c.asset_path):
			out.append(c.crest_id)
	return out


func stats() -> Dictionary:
	var by_type := {}
	for c: CrestData in crests.values():
		var k: String = CrestData.AssetType.keys()[c.asset_type]
		by_type[k] = int(by_type.get(k, 0)) + 1
	return {"crests": crests.size(), "by_type": by_type, "missing_assets": missing_assets().size()}
