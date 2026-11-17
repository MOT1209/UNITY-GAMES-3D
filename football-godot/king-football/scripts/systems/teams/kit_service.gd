class_name KitService
extends RefCounted

## Cached kit textures (shirt + shorts + socks with the club crest), keyed by the kit data and
## the crest design, so a changed colour, pattern or crest shows immediately.

static var cache := CrestCache.new()


static func texture(db: Node, team: TeamData, slot: String, scale: int = 2) -> Texture2D:
	var pv := KitEditor.preview(team, slot)
	if pv.is_empty():
		return null
	var crest := CrestService.crest_of(db, team) if db != null else null
	var key := "%s|%s|%d|%s" % [slot, str(pv), scale, CrestService.cache_key(crest, "kit", 0) if crest != null else "-"]
	var tex := cache.fetch(key)
	if tex != null:
		return tex
	var crest_img: Image = CrestRenderer.render(crest, "kit") if crest != null else null
	tex = ImageTexture.create_from_image(KitRenderer.render(pv, crest_img, scale))
	cache.store(key, tex)
	return tex
