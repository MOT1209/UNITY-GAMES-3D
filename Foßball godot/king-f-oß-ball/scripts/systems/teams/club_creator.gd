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


## params: name, short_name, country, primary (Color), secondary (Color),
## strength (25-90), stadium_id, logo (template ref), seed.
## Returns {"ok", "error", "team_id"}. Nothing is registered on failure.
static func create_club(db: Node, params: Dictionary, persist: bool = true) -> Dictionary:
	var club_name := str(params.get("name", "")).strip_edges()
	var slug := slugify(club_name)
	if slug == "":
		return {"ok": false, "error": "club name is required", "team_id": ""}
	var team := TeamData.new()
	team.id = "club_" + slug
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
	f.store_string(JSON.stringify({"team": team.to_dict(), "players": players}, "\t"))
	f.close()
	return ""


## Imports a team file. Duplicates and invalid data are rejected with a reason.
static func import_team(db: Node, path: String) -> Dictionary:
	var before := db.errors.size()
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
