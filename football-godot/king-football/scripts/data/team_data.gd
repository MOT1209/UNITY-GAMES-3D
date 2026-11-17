class_name TeamData
extends Resource

## Unified team record (Phase T1) for real/fictional clubs and national teams.
## `id` is the stable identifier; names are display-only.

enum Category { CLUB, NATIONAL }
## REAL = real-world club, FICTIONAL = generated/shipped fictional club, CUSTOM = user-created.
enum ClubType { REAL, FICTIONAL, CUSTOM }
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

@export_group("Identity (database v3)")
## All optional: empty / 0 = unknown. Real values are only stored when a source exists.
@export var full_name: String = ""
@export var nickname: String = ""
@export var city: String = ""
@export var region: String = ""
@export var founding_year: int = 0
@export var club_type: ClubType = ClubType.FICTIONAL
@export var country_id: String = ""      # derived from `country` by TeamDatabase when empty
@export var description: String = ""

@export_group("Football (database v3)")
@export var league_id: String = ""       # division id, e.g. "eng_d1" (derived from the pack's leagues)
@export var division: int = 0            # tier, 1 = top, 0 = unknown / no league
@export var manager_id: String = ""
@export var rival_club_ids: PackedStringArray = PackedStringArray()

@export_group("Finance (database v3)")
@export var transfer_budget: int = 0
@export var wage_budget: int = 0
@export var current_balance: int = 0
@export var weekly_expenses: int = 0
@export var sponsorship_income: int = 0

@export_group("Stadium + visuals (database v3)")
@export var stadium_name: String = ""
@export var stadium_capacity: int = 0
@export var stadium_level: int = 1
@export var crest_id: String = ""
@export var accent_color: Color = Color.WHITE

@export_group("History (database v3)")
## {historical_leagues: [], trophies: [], promotions: [], relegations: [], records: {}}.
## Only verified entries; never fabricated.
@export var history: Dictionary = {}


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
	if founding_year != 0 and (founding_year < 1800 or founding_year > 2100):
		errors.append("team '%s' founding year %d out of range" % [id, founding_year])
	if full_name.length() > 80 or nickname.length() > 40 or city.length() > 60:
		errors.append("team '%s' has an over-long name/city field" % id)
	for money in ["transfer_budget", "wage_budget", "weekly_expenses", "sponsorship_income"]:
		if int(get(money)) < 0:
			errors.append("team '%s' has negative %s" % [id, money])
	if stadium_capacity < 0 or stadium_level < 1 or stadium_level > 5:
		errors.append("team '%s' has invalid stadium capacity/level" % id)
	if division < 0:
		errors.append("team '%s' has negative division" % id)
	if rival_club_ids.has(id):
		errors.append("team '%s' lists itself as a rival" % id)
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
		"full_name": full_name, "nickname": nickname, "city": city, "region": region,
		"founding_year": founding_year, "club_type": ClubType.keys()[club_type],
		"country_id": country_id, "description": description,
		"league_id": league_id, "division": division, "manager_id": manager_id,
		"rival_club_ids": Array(rival_club_ids),
		"transfer_budget": transfer_budget, "wage_budget": wage_budget,
		"current_balance": current_balance, "weekly_expenses": weekly_expenses,
		"sponsorship_income": sponsorship_income,
		"stadium_name": stadium_name, "stadium_capacity": stadium_capacity,
		"stadium_level": stadium_level, "crest_id": crest_id,
		"accent_color": accent_color.to_html(false), "history": history.duplicate(true),
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
	t.full_name = str(d.get("full_name", ""))
	t.nickname = str(d.get("nickname", ""))
	t.city = str(d.get("city", ""))
	t.region = str(d.get("region", ""))
	t.founding_year = int(d.get("founding_year", 0))
	# Missing club_type (old data/saves): real flag decides.
	var ct := str(d.get("club_type", "REAL" if t.is_real else "FICTIONAL"))
	t.club_type = ClubType[ct] if ClubType.has(ct) else (ClubType.REAL if t.is_real else ClubType.FICTIONAL)
	t.country_id = str(d.get("country_id", ""))
	t.description = str(d.get("description", ""))
	t.league_id = str(d.get("league_id", ""))
	t.division = int(d.get("division", 0))
	t.manager_id = str(d.get("manager_id", ""))
	t.rival_club_ids = PackedStringArray(d.get("rival_club_ids", []))
	t.transfer_budget = int(d.get("transfer_budget", 0))
	t.wage_budget = int(d.get("wage_budget", 0))
	t.current_balance = int(d.get("current_balance", 0))
	t.weekly_expenses = int(d.get("weekly_expenses", 0))
	t.sponsorship_income = int(d.get("sponsorship_income", 0))
	t.stadium_name = str(d.get("stadium_name", ""))
	t.stadium_capacity = int(d.get("stadium_capacity", 0))
	t.stadium_level = int(d.get("stadium_level", 1))
	t.crest_id = str(d.get("crest_id", ""))
	t.accent_color = Color.from_string(str(d.get("accent_color", "ffffff")), Color.WHITE)
	var h: Variant = d.get("history", {})
	t.history = PlayerData._restore_ints((h as Dictionary).duplicate(true)) if h is Dictionary else {}
	return t


## Coarse financial health derived from the stored balance and weekly expenses.
func financial_status() -> String:
	if weekly_expenses <= 0 and current_balance == 0:
		return "UNKNOWN"
	if current_balance < 0:
		return "CRISIS"
	if weekly_expenses > 0 and current_balance < weekly_expenses * 10:
		return "TIGHT"
	return "HEALTHY"
