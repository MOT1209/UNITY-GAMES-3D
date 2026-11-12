class_name ClubCreator
extends RefCounted

## Fictional club creation, import/export and deletion (Phase T7).
## User clubs are stored as JSON in `user://teams/<id>.json`, which `TeamDB`
## loads on start-up — adding a club never requires a code change.

const USER_DIR := "user://teams"
const MIN_STRENGTH := 25
const MAX_STRENGTH := 90


## "Royal Harbor FC" -> "club_royal_harbor_fc" (ASCII, unique-friendly).
static func slugify(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


## Common Latin letters mapped to ASCII for the readable part of generated ids.
const _TRANSLIT := {"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "é": "e", "è": "e", "ê": "e",
		"á": "a", "à": "a", "â": "a", "í": "i", "ó": "o", "ô": "o", "ú": "u", "ñ": "n", "ç": "c",
		"ø": "o", "å": "a", "æ": "ae"}
const MAX_NAME_LENGTH := 40


## Readable ASCII hint for an id ("Köln United" -> "koeln_united"). May be "".
static func id_hint(text: String) -> String:
	var t := text.to_lower()
	for k in _TRANSLIT:
		t = t.replace(k, _TRANSLIT[k])
	return slugify(t)


## Stable 8-hex digest of the name (case-insensitive). Same name -> same value
## on every run/platform, so ids never depend on the display text's script.
static func stable_hash(text: String) -> String:
	return text.strip_edges().to_lower().sha256_text().substr(0, 8)


static func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 127:
			return false
	return true


## Generates the internal club id, independent of how the name is displayed.
##  - plain ASCII names keep the readable legacy id ("club_royal_harbor_fc");
##  - names with any non-ASCII character (Arabic, German umlauts, ...) get
##    "club_<ascii hint>_<hash>" so two different names can never collide;
##  - when a *different* club already owns the candidate id, the next candidate
##    (hash suffix, then a counter) is used.
## Returns "" for an unusable name. If a club with the same name already exists
## its id is returned unchanged so the caller can reject the duplicate.
static func make_id(db: Node, club_name: String) -> String:
	var name := club_name.strip_edges()
	if name == "" or name.length() > MAX_NAME_LENGTH:
		return ""
	var hint := id_hint(name)
	var h := stable_hash(name)
	var ascii_only := _is_ascii(name)
	if ascii_only and hint == "":
		return ""                                   # punctuation only
	var base := "club_" + hint if ascii_only else "club_" + (hint + "_" if hint != "" else "") + h
	var candidates: Array[String] = [base]
	if ascii_only:
		candidates.append(base + "_" + h)
	for id in candidates:
		if not db.teams.has(id):
			return id
		if (db.teams[id] as TeamData).display_name.strip_edges().to_lower() == name.to_lower():
			return id                                # true duplicate
	var n := 2
	while db.teams.has("%s_%d" % [candidates[-1], n]):
		n += 1
	return "%s_%d" % [candidates[-1], n]


## params: name, short_name, country, primary (Color), secondary (Color),
## strength (25-90), stadium_id, logo (template ref), seed.
## Returns {"ok", "error", "team_id"}. Nothing is registered on failure.
static func create_club(db: Node, params: Dictionary, persist: bool = true) -> Dictionary:
	var club_name := str(params.get("name", "")).strip_edges()
	if club_name.length() > MAX_NAME_LENGTH:
		return {"ok": false, "error": "club name is too long (max %d characters)" % MAX_NAME_LENGTH, "team_id": ""}
	var team_id := make_id(db, club_name)
	if team_id == "":
		return {"ok": false, "error": "club name is required", "team_id": ""}
	var team := TeamData.new()
	team.id = team_id                   # internal id; display_name below keeps the exact text
	team.display_name = club_name
	team.short_name = str(params.get("short_name", "")).strip_edges().to_upper()
	team.category = TeamData.Category.CLUB
	team.is_real = false
	team.country = str(params.get("country", "")).strip_edges()
	team.primary_color = params.get("primary", Color.WHITE)
	team.secondary_color = params.get("secondary", Color.BLACK)
	var strength := clampi(int(params.get("strength", 50)), MIN_STRENGTH, MAX_STRENGTH)
	team.reputation = strength
	team.budget = strength * 1_000_000
	team.stadium_id = str(params.get("stadium_id", "std_default"))
	team.logo_path = str(params.get("logo", LogoService.template_ref("shield")))
	if not LogoService.is_template(team.logo_path) and not FileAccess.file_exists(team.logo_path):
		team.logo_path = LogoService.template_ref("shield")   # missing asset -> graceful fallback
	team.kits = KitEditor.default_kits(team.primary_color, team.secondary_color)
	if db.teams.has(team.id):
		return {"ok": false, "error": "a club with id '%s' already exists" % team.id, "team_id": ""}
	var roster := SquadGenerator.generate(team.id, team.country, strength, int(params.get("seed", 1)))
	team.squad_ids = PackedStringArray(roster.map(func(p: PlayerData) -> String: return p.id))
	if not db.register_team(team, roster, "club_creator"):
		return {"ok": false, "error": str(db.errors[-1]), "team_id": ""}
	if persist:
		var err := export_team(db, team.id, "%s/%s.json" % [USER_DIR, team.id])
		if err != "":
			db.remove_team(team.id)
			return {"ok": false, "error": err, "team_id": ""}
	return {"ok": true, "error": "", "team_id": team.id}


## Writes {"team", "players"} JSON for a team (same format TeamDB loads).
static func export_team(db: Node, team_id: String, path: String) -> String:
	var team: TeamData = db.get_team(team_id)
	if team == null:
		return "unknown team '%s'" % team_id
	var players: Array = []
	for p in db.get_squad(team_id):
		players.append(p.to_dict())
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write '%s'" % path
	f.store_string(JSON.stringify({"team": team.to_dict(), "players": players}, "\t", true, true))
	f.close()
	return ""


## Imports a team file. Duplicates and invalid data are rejected with a reason.
static func import_team(db: Node, path: String) -> Dictionary:
	var before: int = db.errors.size()
	if not db.load_file(path):
		var msg := "import failed"
		if db.errors.size() > before:
			msg = str(db.errors[-1])
		return {"ok": false, "error": msg}
	return {"ok": true, "error": ""}


## Deletes a USER-created club (file in user://teams). Seed data is protected.
static func delete_user_club(db: Node, team_id: String) -> String:
	var path := "%s/%s.json" % [USER_DIR, team_id]
	if not FileAccess.file_exists(path):
		return "only user-created clubs can be deleted"
	if db.get_team(team_id) == null:
		return "unknown team '%s'" % team_id
	db.remove_team(team_id)
	DirAccess.remove_absolute(path)
	return ""
