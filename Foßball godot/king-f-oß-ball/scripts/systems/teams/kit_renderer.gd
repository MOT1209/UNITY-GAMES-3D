class_name KitRenderer
extends RefCounted

## Draws a kit (shirt with sleeves, shorts, socks) as an `Image` from the saved kit data
## (`KitEditor.preview`): colours, pattern (solid, stripes, hoops, halves, sash, checks), accent
## collar/cuffs and the club crest on the left chest. Used by the kit previews so a kit looks
## like a kit instead of colour blocks. Base canvas 88 x 112; `scale` multiplies it.

const W := 88.0
const H := 112.0


## `crest` may be null (no crest drawn). Result is RGBA, transparent outside the garments.
static func render(kit: Dictionary, crest: Image = null, scale: int = 2) -> Image:
	var sc := float(maxi(scale, 1))
	var img := Image.create(int(W * sc), int(H * sc), false, Image.FORMAT_RGBA8)
	var main: Color = kit.get("main", Color.WHITE)
	var sec: Color = kit.get("secondary", Color.BLACK)
	var accent: Color = kit.get("accent", Color.WHITE)
	var shorts: Color = kit.get("shorts", sec)
	var socks: Color = kit.get("socks", main)
	var pattern := str(kit.get("pattern", "solid"))
	var outline := Color(0, 0, 0, 0.55)
	for py in img.get_height():
		var y := (float(py) + 0.5) / sc
		for px in img.get_width():
			var x := (float(px) + 0.5) / sc
			var col := Color(0, 0, 0, 0)
			# socks
			var sd_socks := minf(_box(x, y, 30.0, 97.0, 7.0, 8.0), _box(x, y, 58.0, 97.0, 7.0, 8.0))
			col = _over(col, _shade(socks, y, 88.0, 105.0), sd_socks, sc, outline)
			if sd_socks < 0.0 and y < 91.5:
				col = _over(col, accent, sd_socks, sc, Color(0, 0, 0, 0))
			# shorts: two legs + waistband, a small gap between the legs
			var sd_sh := minf(_box(x, y, 30.0, 72.0, 11.5, 13.0), _box(x, y, 58.0, 72.0, 11.5, 13.0))
			sd_sh = minf(sd_sh, _box(x, y, 44.0, 63.0, 20.0, 5.0))
			sd_sh = maxf(sd_sh, -_box(x, y, 44.0, 78.0, 1.6, 12.0))
			col = _over(col, _shade(shorts, y, 58.0, 86.0), sd_sh, sc, outline)
			if sd_sh < 0.0 and y < 61.0:
				col = _over(col, accent.lerp(shorts, 0.35), sd_sh, sc, Color(0, 0, 0, 0))
			# shirt: body + short sleeves
			var sd_body := _rbox(x, y, 44.0, 35.0, 19.5, 23.0, 4.5)
			var sd_l := _quad(x, y, 25.0, 13.0, 8.5, 22.0, 14.0, 36.0, 25.0, 30.0)
			var sd_r := _quad(x, y, 63.0, 13.0, 80.0, 22.0, 74.0, 36.0, 63.0, 30.0)
			var sd_shirt := minf(sd_body, minf(sd_l, sd_r))
			var neck := _tri(x, y, 35.5, 10.0, 52.5, 10.0, 44.0, 24.0)
			var sd_cut := maxf(sd_shirt, -neck)
			if sd_cut < 1.0 / sc:
				var shirt := _shade(_pattern(pattern, x, y, main, sec), y, 12.0, 58.0)
				var collar := clampf(0.5 - (absf(neck - 1.8) - 1.8) * sc, 0.0, 1.0)         # V-neck trim
				var cuff := maxf(clampf(0.5 - _cap(x, y, 8.8, 22.5, 14.2, 35.5, 2.0) * sc, 0.0, 1.0),
						clampf(0.5 - _cap(x, y, 79.2, 22.5, 73.8, 35.5, 2.0) * sc, 0.0, 1.0))  # sleeve cuffs
				shirt = shirt.lerp(accent, maxf(collar, cuff))
				col = _over(col, shirt, sd_cut, sc, outline)
			img.set_pixel(px, py, col)
	if crest != null:
		var size := int(21.0 * sc)
		var c := crest.duplicate() as Image
		c.convert(Image.FORMAT_RGBA8)
		c.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(int(25.0 * sc), int(19.0 * sc)))
	return img


# --- painting helpers ----------------------------------------------------------------------------

## Composites `src` over `dst` with anti-aliased coverage from `sd`, plus a thin outline.
static func _over(dst: Color, src: Color, sd: float, sc: float, outline: Color) -> Color:
	var cover := clampf(0.5 - sd * sc, 0.0, 1.0)
	if cover <= 0.0:
		return dst
	var col := src
	col.a = 1.0
	if outline.a > 0.0:
		var edge := clampf(0.5 + (sd + 1.1) * sc, 0.0, 1.0)         # outline hugging the border, 1.1 px wide
		col = col.lerp(Color(outline.r, outline.g, outline.b, 1.0), edge * outline.a)
	var a := cover
	var out_a := a + dst.a * (1.0 - a)
	if out_a <= 0.0:
		return dst
	var rgb := (Vector3(col.r, col.g, col.b) * a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - a)) / out_a
	return Color(rgb.x, rgb.y, rgb.z, out_a)


## Gentle vertical shading so a garment does not look flat.
static func _shade(c: Color, y: float, top: float, bottom: float) -> Color:
	var t := clampf((y - top) / maxf(bottom - top, 1.0), 0.0, 1.0)
	return c.lerp(Color.WHITE, 0.10 * (1.0 - t)).lerp(Color.BLACK, 0.16 * t)


static func _pattern(pattern: String, x: float, y: float, main: Color, sec: Color) -> Color:
	var alt := false
	match pattern:
		"stripes":
			alt = int(floorf((x - 24.0) / 7.2)) % 2 != 0
		"hoops":
			alt = int(floorf((y - 12.0) / 7.0)) % 2 != 0
		"halves":
			alt = x >= 44.0
		"sash":
			alt = absf((x - 44.0) + (y - 34.0) * 0.85) < 6.5
		"checks":
			alt = (int(floorf(x / 7.0)) + int(floorf(y / 7.0))) % 2 != 0
	return sec if alt else main


# --- geometry (signed distance, pixels; negative inside) -----------------------------------------

static func _box(x: float, y: float, cx: float, cy: float, hw: float, hh: float) -> float:
	var dx := absf(x - cx) - hw
	var dy := absf(y - cy) - hh
	return sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dy, 0.0) * maxf(dy, 0.0)) + minf(maxf(dx, dy), 0.0)


static func _rbox(x: float, y: float, cx: float, cy: float, hw: float, hh: float, r: float) -> float:
	return _box(x, y, cx, cy, hw - r, hh - r) - r


static func _cap(x: float, y: float, ax: float, ay: float, bx: float, by: float, w: float) -> float:
	var pax := x - ax
	var pay := y - ay
	var bax := bx - ax
	var bay := by - ay
	var h := clampf((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
	var dx := pax - bax * h
	var dy := pay - bay * h
	return sqrt(dx * dx + dy * dy) - w


static func _edge(x: float, y: float, px: float, py: float, qx: float, qy: float, s: float) -> float:
	var ex := qx - px
	var ey := qy - py
	return s * ((x - px) * ey - (y - py) * ex) / sqrt(ex * ex + ey * ey)


static func _tri(x: float, y: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var s := signf((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
	return maxf(maxf(_edge(x, y, ax, ay, bx, by, s), _edge(x, y, bx, by, cx, cy, s)), _edge(x, y, cx, cy, ax, ay, s))


## Convex quad a-b-c-d.
static func _quad(x: float, y: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float, dx: float, dy: float) -> float:
	var s := signf((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
	return maxf(maxf(_edge(x, y, ax, ay, bx, by, s), _edge(x, y, bx, by, cx, cy, s)),
			maxf(_edge(x, y, cx, cy, dx, dy, s), _edge(x, y, dx, dy, ax, ay, s)))
