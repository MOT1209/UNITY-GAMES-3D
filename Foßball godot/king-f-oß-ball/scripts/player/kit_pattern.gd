class_name KitPattern
extends RefCounted

## Procedural shirt patterns (Phase 7.7). A tiny texture (64×64, cached per pattern and colour pair)
## is applied to the jersey material with TRIPLANAR mapping, so no UV layout is needed and the pattern
## follows the body on the front, back and sleeves. `solid` uses no texture at all.
## Patterns: stripes (vertical), hoops (horizontal), halves, sash (diagonal band), checks.

const SIZE := 64
## Tile edge in metres on the model per pattern (triplanar scale = 1 / tile).
const TILE := {"stripes": 0.16, "hoops": 0.20, "halves": 1.0, "sash": 0.9, "checks": 0.12}

static var _cache: Dictionary = {}


static func is_patterned(pattern: String) -> bool:
	return TILE.has(pattern)


## Texture for `pattern` in colours `a` (the shirt's main colour) and `b` (secondary).
static func texture(pattern: String, a: Color, b: Color) -> Texture2D:
	if not is_patterned(pattern):
		return null
	var key := "%s|%s|%s" % [pattern, a.to_html(false), b.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var second := false
			match pattern:
				"stripes":
					second = u >= 0.5
				"hoops":
					second = v >= 0.5
				"halves":
					second = u >= 0.5
				"sash":
					second = absf(fposmod(u + v, 1.0) - 0.5) < 0.2
				"checks":
					second = (int(u * 2.0) + int(v * 2.0)) % 2 == 1
			img.set_pixel(x, y, b if second else a)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Configures `mat` (an own copy of the jersey material) for `pattern`; `solid` leaves a flat colour.
static func apply(mat: StandardMaterial3D, pattern: String, a: Color, b: Color) -> void:
	if not is_patterned(pattern):
		mat.albedo_color = a
		mat.albedo_texture = null
		mat.uv1_triplanar = false
		return
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = texture(pattern, a, b)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	var s := 1.0 / float(TILE[pattern])
	mat.uv1_scale = Vector3(s, s, s)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5) if pattern == "halves" else Vector3.ZERO
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
