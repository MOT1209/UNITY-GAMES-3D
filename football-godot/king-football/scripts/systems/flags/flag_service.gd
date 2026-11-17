class_name FlagService
extends RefCounted

## National flags (round 3, task B). `texture(country_id)` returns the flag of a country from
## assets/flags/<country_id>.png (128 x 84) or <country_id>_64.png (64 x 42), cached; a missing or
## unknown country gets a neutral grey flag with its 3-letter code, never an empty hole.
## Real flags come from flag-icons (MIT), fictional ones from FlagGenerator — see
## docs/DATA_SOURCE_AND_LICENSES.md and tools/build_flags.gd.

const DIR := "res://assets/flags/"

static var _cache: Dictionary = {}       # "<id>|<small>" -> Texture2D
static var fallbacks_served := 0          # tests / diagnostics: how often the neutral flag was used


static func path_of(country_id: String, small := false) -> String:
	return DIR + country_id + ("_64.png" if small else ".png")


static func has_flag(country_id: String) -> bool:
	return country_id != "" and ResourceLoader.exists(path_of(country_id))


## Flag texture of `country_id` (cached). `small` = the 64 x 42 file (lists, small cards).
static func texture(country_id: String, small := false) -> Texture2D:
	var key := "%s|%s" % [country_id, small]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var path := path_of(country_id, small)
	if country_id != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		fallbacks_served += 1
		var w := 64 if small else FlagGenerator.WIDTH
		var h := 42 if small else FlagGenerator.HEIGHT
		tex = ImageTexture.create_from_image(FlagGenerator.fallback(_code(country_id), w, h))
	_cache[key] = tex
	return tex


## Country id for a stored nationality NAME ("England" -> "eng"); "" when unknown.
static func id_for_name(db: Node, country_name: String) -> String:
	if db == null or country_name == "":
		return ""
	for c: CountryData in db.countries.values():
		if c.country_name == country_name:
			return c.country_id
	return ""


static func clear_cache() -> void:
	_cache.clear()


static func _code(country_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var db: Node = tree.root.get_node_or_null("TeamDB") if tree != null else null
	if db != null and db.countries.has(country_id):
		return (db.countries[country_id] as CountryData).country_code
	return country_id if country_id != "" else "?"
