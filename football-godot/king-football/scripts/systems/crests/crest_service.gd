class_name CrestService
extends RefCounted

## Facade used by every screen: `texture(db, team, variant)` returns the crest of the team's
## CURRENT crest record (so a changed crest or a new club shows everywhere), from a shared LRU
## cache; nothing is drawn until something asks. `image()` skips the cache (tools, tests).

static var cache := CrestCache.new()


static func _team(db: Node, team: Variant) -> TeamData:
	if team is TeamData:
		return team
	return db.get_team(str(team))


## Crest record of a team (null for unknown teams and national teams, which have no club crest).
static func crest_of(db: Node, team: Variant) -> CrestData:
	var t := _team(db, team)
	if t == null or t.category != TeamData.Category.CLUB:
		return null
	return db.crests.for_team(t)


static func image(db: Node, team: Variant, variant: String = "icon", px: int = 0) -> Image:
	var c := crest_of(db, team)
	return CrestRenderer.render(c, variant, px) if c != null else null


static func cache_key(c: CrestData, variant: String, px: int) -> String:
	var s := px if px > 0 else CrestRenderer.size_of(variant)
	return "%s|%s|%d|v%d|%s" % [c.crest_id, variant, s, c.version, c.signature() + c.asset_path]


## Cached texture; null when the team has no crest.
static func texture(db: Node, team: Variant, variant: String = "icon", px: int = 0) -> Texture2D:
	var c := crest_of(db, team)
	if c == null:
		return null
	var key := cache_key(c, variant, px)
	var tex := cache.fetch(key)
	if tex != null:
		return tex
	tex = ImageTexture.create_from_image(CrestRenderer.render(c, variant, px))
	cache.store(key, tex)
	return tex


## Crest of a club outside the loaded leagues (transfers v2 "external" buyers, ids `TransferMarket.EXTERNAL_PREFIX`...):
## a procedural design from the same generator as fictional clubs, coloured from the id, so it is stable.
static var _external: Dictionary = {}           # cache key -> texture


static func external_texture(club_id: String, variant: String = "icon", px: int = 0) -> Texture2D:
	var key := "%s|%s|%d" % [club_id, variant, px]
	if _external.has(key):
		return _external[key]
	var h := hash("ext-colors:" + club_id) & 0x7fffffff
	var primary := Color.from_hsv(float(h % 360) / 360.0, 0.65, 0.75)
	var secondary := Color.from_hsv(float((h / 360) % 360) / 360.0, 0.25, 0.95)
	var accent := Color.from_hsv(float((h / 129600) % 360) / 360.0, 0.8, 0.55)
	var c := CrestGenerator.generate(club_id, primary, secondary, accent, false)
	var tex := ImageTexture.create_from_image(CrestRenderer.render(c, variant, px))
	_external[key] = tex
	return tex
