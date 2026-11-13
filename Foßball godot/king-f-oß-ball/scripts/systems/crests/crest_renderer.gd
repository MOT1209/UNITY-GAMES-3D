class_name CrestRenderer
extends RefCounted

## Draws a crest as an `Image` (RGBA, transparent outside the shape, anti-aliased) from a
## CrestData. Every variant comes from the SAME record:
##   full   128 px, all details        icon  40 px, thick border
##   mono   64 px, one colour (white)  kit   64 px, no pattern split, bold symbol
##   card   72 px, all details
## Procedural crests are drawn per pixel from signed distance functions (shape + division +
## symbol); template and file assets (user crests) are loaded through LogoService / Image.

const VARIANTS := {
	"full": {"size": 128, "border": 0.11, "mono": false, "pattern": true},
	"icon": {"size": 40, "border": 0.17, "mono": false, "pattern": true},
	"mono": {"size": 64, "border": 0.12, "mono": true, "pattern": false},
	"kit": {"size": 64, "border": 0.13, "mono": false, "pattern": false},
	"card": {"size": 72, "border": 0.12, "mono": false, "pattern": true},
}
const HALO := 0.035
const OUTLINE := 0.05
const DARK := Color(0.07, 0.07, 0.09)
const LIGHT := Color(1, 1, 1)
## Per shape: symbol centre offset (x, y) and scale inside the shape.
const SYMBOL_FIT := {
	"shield": Vector3(0.0, -0.1, 0.95), "round": Vector3(0.0, 0.0, 1.0), "hex": Vector3(0.0, 0.0, 1.0),
	"banner": Vector3(0.0, -0.06, 0.95), "oval": Vector3(0.0, 0.0, 0.9), "kite": Vector3(0.0, -0.1, 0.85),
}


static func size_of(variant: String) -> int:
	return int(VARIANTS.get(variant, VARIANTS["icon"])["size"])


## `px` 0 = the variant's own size.
static func render(c: CrestData, variant: String = "full", px: int = 0) -> Image:
	var v: Dictionary = VARIANTS.get(variant, VARIANTS["full"])
	var s := px if px > 0 else int(v["size"])
	if c.is_template():
		return _template(c, s, bool(v["mono"]))
	if c.is_file():
		return _file(c, s, bool(v["mono"]))
	return _procedural(c, s, v)


static func _template(c: CrestData, s: int, mono: bool) -> Image:
	var img := LogoService.render_template(c.asset_path.trim_prefix(LogoService.TEMPLATE_PREFIX), c.primary_color, c.secondary_color, s)
	return _to_mono(img) if mono else img


static func _file(c: CrestData, s: int, mono: bool) -> Image:
	var img: Image = null
	if c.asset_path.begins_with("res://"):             # imported project resource: also works in an exported game
		var tex := load(c.asset_path) as Texture2D
		img = tex.get_image() if tex != null else null
	else:
		img = Image.load_from_file(c.asset_path)
	if img == null or img.is_empty():
		return _procedural(c, s, VARIANTS["full"])          # a broken file never breaks the UI
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != s or img.get_height() != s:
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
	return _to_mono(img) if mono else img


static func _to_mono(img: Image) -> Image:
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(1, 1, 1, img.get_pixel(x, y).a))
	return img


static func _procedural(c: CrestData, s: int, v: Dictionary) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var mono: bool = v["mono"]
	var border_w: float = v["border"]
	var pattern: bool = v["pattern"]
	var fit: Vector3 = SYMBOL_FIT.get(c.shape_style, Vector3(0, 0, 1))
	var division := c.division if pattern else "plain"
	var fills: Array[Color] = [c.primary_color]
	if division != "plain":
		fills.append(c.secondary_color)
	var border_col := _border_color(c)
	var symbol_col := _symbol_color(c, fills)
	var halo_col := DARK if _luma(symbol_col) > 0.3 else LIGHT
	var outline_col := border_col.darkened(0.6)
	var rich := s >= 56                  # shading, gloss and shadow only where they can be seen
	var half := float(s) * 0.5
	for py in s:
		var y := (float(py) + 0.5) / half - 1.0
		for px in s:
			var x := (float(px) + 0.5) / half - 1.0
			var sd := _shape_sd(c.shape_style, x, y)
			var cover := clampf(0.5 - sd * half, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var sym := 0.0
			var halo := 0.0
			var shadow := 0.0
			if absf(x) < 0.7 and absf(y) < 0.7:
				var ssd := CrestSymbols.sd(c.symbol, (x - fit.x) / fit.z, (y - fit.y) / fit.z) * fit.z
				sym = clampf(0.5 - ssd * half, 0.0, 1.0)
				halo = clampf(0.5 - (ssd - HALO) * half, 0.0, 1.0)
				if rich:
					var dsd := CrestSymbols.sd(c.symbol, (x - fit.x - 0.03) / fit.z, (y - fit.y - 0.05) / fit.z) * fit.z
					shadow = clampf(0.5 - (dsd - 0.02) * half, 0.0, 1.0)
			if mono:
				var ring := clampf(0.5 - (absf(sd + border_w * 0.5) - border_w * 0.5) * half, 0.0, 1.0)
				img.set_pixel(px, py, Color(1, 1, 1, maxf(ring, sym)))
				continue
			var col := _fill(division, x, y, c, half)
			if rich:                                         # soft top light, darker bottom: a little depth
				var ty := (y + 1.0) * 0.5
				col = col.lerp(Color.WHITE, 0.13 * (1.0 - ty)).lerp(Color.BLACK, 0.2 * ty * ty)
			col = col.lerp(border_col, clampf(0.5 + (sd + border_w) * half, 0.0, 1.0))
			if rich:                                         # fine inner line inside the border
				var il := clampf(0.5 - (absf(sd + border_w + 0.04) - 0.011) * half, 0.0, 1.0)
				col = col.lerp(border_col.lightened(0.35) if _luma(border_col) < 0.4 else border_col.darkened(0.3), il * 0.6)
				col = col.lerp(Color.WHITE, clampf(1.0 - (x * x * 1.3 + (y + 0.62) * (y + 0.62) * 6.0), 0.0, 1.0) * 0.14)   # gloss
			col = col.lerp(outline_col, clampf(0.5 + (sd + OUTLINE) * half, 0.0, 1.0))     # dark outer outline
			if rich:
				col = col.lerp(Color.BLACK, shadow * 0.38)
			col = col.lerp(halo_col, halo * 0.9)         # thin outline keeps the symbol legible on any fill
			col = col.lerp(symbol_col, sym)
			img.set_pixel(px, py, Color(col.r, col.g, col.b, cover))
	return img


static func _fill(division: String, x: float, y: float, c: CrestData, half: float) -> Color:
	var t := 0.0                                  # 0 = primary, 1 = secondary (soft 1 px edge)
	match division:
		"vertical":
			t = clampf(0.5 + x * half, 0.0, 1.0)
		"diagonal":
			t = clampf(0.5 + (x - y) * half * 0.7, 0.0, 1.0)
		"band":
			t = 1.0 - clampf(0.5 + (absf(y) - 0.2) * half, 0.0, 1.0)
		"quarters":
			t = 1.0 if (x < 0.0) != (y < 0.0) else 0.0
	return c.primary_color.lerp(c.secondary_color, t)


# --- colour choices (legible on every fill) ---------------------------------------------------

static func _luma(col: Color) -> float:
	return 0.2126 * pow(col.r, 2.2) + 0.7152 * pow(col.g, 2.2) + 0.0722 * pow(col.b, 2.2)


static func contrast(a: Color, b: Color) -> float:
	var la := _luma(a)
	var lb := _luma(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _symbol_color(c: CrestData, fills: Array[Color]) -> Color:
	var best := LIGHT
	var best_score := -1.0
	for cand in [c.accent_color, LIGHT, DARK]:
		var score := 99.0
		for f in fills:
			score = minf(score, contrast(cand, f))
		if cand == c.accent_color:
			score *= 1.25                          # prefer the club's own accent when it is legible
		if score > best_score:
			best_score = score
			best = cand
	return best


static func _border_color(c: CrestData) -> Color:
	if contrast(c.secondary_color, c.primary_color) >= 1.6:
		return c.secondary_color
	return LIGHT if contrast(LIGHT, c.primary_color) >= contrast(DARK, c.primary_color) else DARK


# --- shapes (signed distance, negative inside) ------------------------------------------------

static func _shape_sd(shape: String, x: float, y: float) -> float:
	match shape:
		"round":
			return sqrt(x * x + y * y) - 0.92
		"oval":
			return (sqrt((x / 0.78) * (x / 0.78) + (y / 0.95) * (y / 0.95)) - 1.0) * 0.78
		"hex":
			return _hex(x, y, 0.9)
		"banner":
			var yb := 0.95 - 0.5 * (1.0 - minf(absf(x) / 0.78, 1.0))
			return maxf(maxf(absf(x) - 0.78, -0.92 - y), (y - yb) * 0.9)
		"kite":
			var h := 0.82 if y < -0.1 else 1.05
			return (absf(x) / 0.82 + absf(y + 0.1) / h - 1.0) * 0.6
	# shield (default): flat top, straight sides, pointed bottom
	var w := 0.84
	if y > 0.05:
		w = 0.84 * (1.0 - pow(minf((y - 0.05) / 0.9, 1.5), 1.35))
	return maxf((absf(x) - w) * 0.85, -0.92 - y)


static func _hex(x: float, y: float, r: float) -> float:
	var kx := -0.866025404
	var ky := 0.5
	var kz := 0.577350269
	var px := absf(x)
	var py := absf(y)
	var d := minf(kx * px + ky * py, 0.0)
	px -= 2.0 * d * kx
	py -= 2.0 * d * ky
	px -= clampf(px, -kz * r, kz * r)
	py -= r
	return sqrt(px * px + py * py) * signf(py)
