class_name KitEditor
extends RefCounted

## Kit configuration (Phase T7): home / away / third / goalkeeper, with
## main, secondary, accent, shorts, socks and number colors plus a pattern.
## Kits are stored as plain dictionaries inside `TeamData.kits`, so saving a
## team and previewing it always read the same data.

const SLOTS: Array[String] = ["home", "away", "third", "goalkeeper"]
const COLOR_FIELDS: Array[String] = ["main", "secondary", "accent", "shorts", "socks", "number"]
const PATTERNS: Array[String] = ["solid", "stripes", "hoops", "halves", "sash", "checks"]


static func is_valid_color(hex: String) -> bool:
	var h := hex.trim_prefix("#")
	if h.length() != 6 and h.length() != 8:
		return false
	return h.is_valid_hex_number()


static func default_kit(main: String, secondary: String, accent: String) -> Dictionary:
	return {"main": main, "secondary": secondary, "accent": accent, "shorts": secondary,
			"socks": main, "number": accent, "pattern": "solid"}


## Complete default kit set derived from the club colors.
static func default_kits(primary: Color, secondary: Color) -> Dictionary:
	var p := primary.to_html(false)
	var s := secondary.to_html(false)
	return {
		"home": default_kit(p, s, "ffffff"),
		"away": default_kit("ffffff", p, s),
		"third": default_kit(s, p, "ffffff"),
		"goalkeeper": default_kit("2ecc71", "1b1b1b", "ffffff"),
	}


## Returns "" on success, otherwise an error. Pattern is set with field "pattern".
static func set_field(team: TeamData, slot: String, field: String, value: String) -> String:
	if not (slot in SLOTS):
		return "unknown kit slot '%s'" % slot
	if field == "pattern":
		if not (value in PATTERNS):
			return "unknown pattern '%s'" % value
	elif field in COLOR_FIELDS:
		if not is_valid_color(value):
			return "invalid color '%s'" % value
		value = value.trim_prefix("#").to_lower()
	else:
		return "unknown kit field '%s'" % field
	if not team.kits.has(slot):
		team.kits[slot] = default_kit(team.primary_color.to_html(false), team.secondary_color.to_html(false), "ffffff")
	team.kits[slot][field] = value
	return ""


static func validate_kit(kit: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for f in COLOR_FIELDS:
		if not kit.has(f) or not is_valid_color(str(kit[f])):
			errors.append("kit field '%s' missing or invalid" % f)
	if not (str(kit.get("pattern", "solid")) in PATTERNS):
		errors.append("kit has unknown pattern")
	return errors


## Resolved preview data (real Color objects) for the UI.
static func preview(team: TeamData, slot: String) -> Dictionary:
	var kit: Dictionary = team.kits.get(slot, {})
	if kit.is_empty():
		return {}
	var out := {"slot": slot, "pattern": str(kit.get("pattern", "solid"))}
	for f in COLOR_FIELDS:
		out[f] = Color.from_string(str(kit.get(f, "ffffff")), Color.WHITE)
	return out


## True when the two kits are visually too close to play against each other.
static func kits_clash(a: Dictionary, b: Dictionary, threshold: float = 0.18) -> bool:
	var ca := Color.from_string(str(a.get("main", "ffffff")), Color.WHITE)
	var cb := Color.from_string(str(b.get("main", "ffffff")), Color.WHITE)
	var d := Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length() / sqrt(3.0)
	return d < threshold


# --- validation + repair of club kit combinations (database phase 5) ------------------------------

const NUMBER_MIN_CONTRAST := 3.0
const GOALKEEPER_CHOICES: Array[String] = ["2ecc71", "f1c40f", "e67e22", "1b1b1b", "e91e63", "ffffff"]


static func _col(kit: Dictionary, field: String) -> Color:
	return Color.from_string(str(kit.get(field, "ffffff")), Color.WHITE)


## White or near-black, whichever is easier to read on `bg`.
static func readable_on(bg: Color) -> Color:
	var white := CrestRenderer.contrast(Color.WHITE, bg)
	var dark := CrestRenderer.contrast(Color(0.07, 0.07, 0.09), bg)
	return Color.WHITE if white >= dark else Color(0.07, 0.07, 0.09)


## Problems of a club's kit set (empty = fine): unreadable shirt numbers and kits that are too
## close to each other to be told apart on the pitch (home/away, home/goalkeeper, away/goalkeeper, home/third).
static func problems(team: TeamData) -> Array[String]:
	var out: Array[String] = []
	for slot in team.kits:
		var kit: Dictionary = team.kits[slot]
		if CrestRenderer.contrast(_col(kit, "number"), _col(kit, "main")) < NUMBER_MIN_CONTRAST:
			out.append("kit '%s': the shirt number is hard to read on the shirt" % slot)
	for pair in [["home", "away"], ["home", "goalkeeper"], ["away", "goalkeeper"], ["home", "third"]]:
		if team.kits.has(pair[0]) and team.kits.has(pair[1]) and kits_clash(team.kits[pair[0]], team.kits[pair[1]]):
			out.append("kits '%s' and '%s' look too similar" % [pair[0], pair[1]])
	return out


## Fixes the problems above in place and returns what was changed. Only the data of a LOADED club
## is repaired (source files are untouched); a player's later choices in the kit editor are never
## overridden. Away kit: the home secondary colour, else white/black; goalkeeper: the first
## colour that differs from both; numbers: white or black, whichever reads better.
static func repair(team: TeamData) -> Array[String]:
	var fixes: Array[String] = []
	if team.kits.has("home") and team.kits.has("away") and kits_clash(team.kits["home"], team.kits["away"]):
		var home: Dictionary = team.kits["home"]
		for cand in [_col(home, "secondary"), Color.WHITE, Color(0.07, 0.07, 0.09), _col(home, "accent")]:
			if not kits_clash(home, {"main": cand.to_html(false)}):
				set_field(team, "away", "main", cand.to_html(false))
				set_field(team, "away", "secondary", str(home.get("main", "ffffff")))
				fixes.append("away kit changed to avoid looking like the home kit")
				break
	if team.kits.has("third") and team.kits.has("home") and kits_clash(team.kits["home"], team.kits["third"]):
		var home3: Dictionary = team.kits["home"]
		for cand in [_col(home3, "secondary"), Color.WHITE, Color(0.07, 0.07, 0.09)]:
			if not kits_clash(home3, {"main": cand.to_html(false)}):
				set_field(team, "third", "main", cand.to_html(false))
				fixes.append("third kit changed to avoid looking like the home kit")
				break
	if team.kits.has("goalkeeper"):
		var gk: Dictionary = team.kits["goalkeeper"]
		var others: Array = []
		for s in ["home", "away"]:
			if team.kits.has(s):
				others.append(team.kits[s])
		var clash := false
		for o in others:
			clash = clash or kits_clash(gk, o)
		if clash:
			for cand in GOALKEEPER_CHOICES:
				var ok := true
				for o in others:
					ok = ok and not kits_clash({"main": cand}, o)
				if ok:
					set_field(team, "goalkeeper", "main", cand)
					set_field(team, "goalkeeper", "socks", cand)
					fixes.append("goalkeeper kit changed to avoid looking like an outfield kit")
					break
	for slot in team.kits:
		var kit: Dictionary = team.kits[slot]
		if CrestRenderer.contrast(_col(kit, "number"), _col(kit, "main")) < NUMBER_MIN_CONTRAST:
			set_field(team, slot, "number", readable_on(_col(kit, "main")).to_html(false))
			fixes.append("kit '%s': shirt number colour changed to be readable" % slot)
	return fixes


## Picks the kit an away team should wear against `home_kit`: away, then third.
static func pick_away_kit(team: TeamData, home_kit: Dictionary) -> String:
	for slot in ["away", "third"]:
		if team.kits.has(slot) and not kits_clash(team.kits[slot], home_kit):
			return slot
	return "away"
