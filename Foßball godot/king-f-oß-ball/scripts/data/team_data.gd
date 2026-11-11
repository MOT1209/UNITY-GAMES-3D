class_name TeamData
extends Resource

## Unified team record (Phase T1) for real/fictional clubs and national teams.
## `id` is the stable identifier; names are display-only.

enum Category { CLUB, NATIONAL }
const KIT_SLOTS: Array[String] = ["home", "away", "third", "goalkeeper"]
const KIT_FIELDS: Array[String] = ["main", "secondary", "accent", "shorts", "socks", "number"]

@export var id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""
@export var category: Category = Category.CLUB
@export var is_real: bool = false
@export var country: String = ""
@export var logo_path: String = ""
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
## slot -> {main, secondary, accent, shorts, socks, number, pattern}. "third" optional.
@export var kits: Dictionary = {}
@export var stadium_id: String = ""
@export var reputation: int = 50      # 1–99
@export var budget: int = 0
@export var competition_ids: PackedStringArray = PackedStringArray()
## Player ids in this team's squad (players themselves live in the database).
@export var squad_ids: PackedStringArray = PackedStringArray()


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.strip_edges() == "":
		errors.append("team has empty id")
	if display_name.strip_edges() == "":
		errors.append("team '%s' has empty name" % id)
	if short_name.strip_edges() == "" or short_name.length() > 5:
		errors.append("team '%s' short name must be 1-5 chars" % id)
	if country.strip_edges() == "":
		errors.append("team '%s' has no country" % id)
	if reputation < 1 or reputation > 99:
		errors.append("team '%s' reputation %d out of range 1-99" % [id, reputation])
	if budget < 0:
		errors.append("team '%s' has negative budget" % id)
	for slot in ["home", "away", "goalkeeper"]:
		if not kits.has(slot):
			errors.append("team '%s' missing %s kit" % [id, slot])
	for slot in kits:
		if not (slot in KIT_SLOTS):
			errors.append("team '%s' has unknown kit slot '%s'" % [id, slot])
	var seen := {}
	for pid in squad_ids:
		if seen.has(pid):
			errors.append("team '%s' lists player '%s' twice" % [id, pid])
		seen[pid] = true
	return errors


func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "short_name": short_name,
		"category": Category.keys()[category], "real": is_real, "country": country,
		"logo": logo_path, "primary_color": primary_color.to_html(false),
		"secondary_color": secondary_color.to_html(false), "kits": kits.duplicate(true),
		"stadium_id": stadium_id, "reputation": reputation, "budget": budget,
		"competitions": Array(competition_ids), "squad": Array(squad_ids),
	}


static func from_dict(d: Dictionary) -> TeamData:
	var t := TeamData.new()
	t.id = str(d.get("id", ""))
	t.display_name = str(d.get("name", ""))
	t.short_name = str(d.get("short_name", ""))
	var cat := str(d.get("category", "CLUB"))
	t.category = Category[cat] if Category.has(cat) else Category.CLUB
	t.is_real = bool(d.get("real", false))
	t.country = str(d.get("country", ""))
	t.logo_path = str(d.get("logo", ""))
	t.primary_color = Color.from_string(str(d.get("primary_color", "ffffff")), Color.WHITE)
	t.secondary_color = Color.from_string(str(d.get("secondary_color", "000000")), Color.BLACK)
	t.kits = (d.get("kits", {}) as Dictionary).duplicate(true)
	t.stadium_id = str(d.get("stadium_id", ""))
	t.reputation = int(d.get("reputation", 50))
	t.budget = int(d.get("budget", 0))
	t.competition_ids = PackedStringArray(d.get("competitions", []))
	t.squad_ids = PackedStringArray(d.get("squad", []))
	return t
