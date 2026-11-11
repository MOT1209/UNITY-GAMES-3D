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


## Picks the kit an away team should wear against `home_kit`: away, then third.
static func pick_away_kit(team: TeamData, home_kit: Dictionary) -> String:
	for slot in ["away", "third"]:
		if team.kits.has(slot) and not kits_clash(team.kits[slot], home_kit):
			return slot
	return "away"
