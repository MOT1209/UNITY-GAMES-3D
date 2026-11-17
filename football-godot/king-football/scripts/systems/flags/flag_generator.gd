class_name FlagGenerator
extends RefCounted

## Procedural flags (round 3, task B) for the FICTIONAL countries (Aldoria, Zamoria, ...) and the neutral
## fallback flag. Pure code, no external art: the design is a pure function of the country id (String.hash
## is stable between runs and platforms), so a fictional flag never changes. `tools/build_flags.tscn` saves
## the results as PNG files in assets/flags/; the game loads those files through FlagService.
##
## Flags are 3:2 (WIDTH x HEIGHT). Shapes are drawn at SUPERSAMPLE x the size and scaled down (smooth edges).

const WIDTH := 128
const HEIGHT := 84
const SUPERSAMPLE := 4

## Flag colours (saturated, distinct; two of them never equal in one flag).
const PALETTE := [Color("#c8102e"), Color("#ffffff"), Color("#00247d"), Color("#007a3d"), Color("#fcd116"),
		Color("#000000"), Color("#0072ce"), Color("#ef7d00"), Color("#5b2c83"), Color("#7b1e1e"), Color("#00a3a1")]
const PATTERNS := ["tri_h", "tri_v", "cross", "diagonal", "disc", "star", "chevron", "bicolor_star"]


## Design for `country_id`: {pattern, colors: [c0, c1, c2]} — deterministic.
static func design(country_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = country_id.hash()
	var pattern: String = PATTERNS[rng.randi() % PATTERNS.size()]
	var picks: Array = []
	while picks.size() < 3:
		var c: Color = PALETTE[rng.randi() % PALETTE.size()]
		if not picks.has(c):
			picks.append(c)
	# keep good contrast between the two field colours: never two dark colours side by side
	if picks[0].get_luminance() < 0.25 and picks[1].get_luminance() < 0.25:
		picks[1] = Color.WHITE if not picks.has(Color.WHITE) else Color("#fcd116")
	return {"pattern": pattern, "colors": picks}


static func generate(country_id: String, w: int = WIDTH, h: int = HEIGHT) -> Image:
	var d := design(country_id)
	var sw := w * SUPERSAMPLE
	var sh := h * SUPERSAMPLE
	var img := Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	var c: Array = d["colors"]
	match str(d["pattern"]):
		"tri_h":
			for i in 3:
				img.fill_rect(Rect2i(0, sh * i / 3, sw, sh / 3 + 1), c[i])
		"tri_v":
			for i in 3:
				img.fill_rect(Rect2i(sw * i / 3, 0, sw / 3 + 1, sh), c[i])
		"cross":
			img.fill(c[0])
			var t := sh / 5
			var cx := sw * 3 / 8
			img.fill_rect(Rect2i(cx - t / 2 - t / 4, 0, t + t / 2, sh), c[1])
			img.fill_rect(Rect2i(0, sh / 2 - t / 2 - t / 4, sw, t + t / 2), c[1])
			img.fill_rect(Rect2i(cx - t / 2, 0, t, sh), c[2])
			img.fill_rect(Rect2i(0, sh / 2 - t / 2, sw, t), c[2])
		"diagonal":
			img.fill(c[0])
			_poly(img, PackedVector2Array([Vector2(sw, 0), Vector2(sw, sh), Vector2(0, sh)]), c[1])
			var band := sh * 0.16
			_poly(img, PackedVector2Array([Vector2(sw - band, 0), Vector2(sw, 0), Vector2(sw, band * 0.66),
					Vector2(band, sh), Vector2(0, sh), Vector2(0, sh - band * 0.66)]), c[2])
		"disc":
			img.fill(c[0])
			_circle(img, Vector2(sw * 0.5, sh * 0.5), sh * 0.3, c[1])
			_circle(img, Vector2(sw * 0.5, sh * 0.5), sh * 0.17, c[2])
		"star":
			img.fill_rect(Rect2i(0, 0, sw, sh / 2), c[0])
			img.fill_rect(Rect2i(0, sh / 2, sw, sh - sh / 2), c[1])
			_poly(img, _star(Vector2(sw * 0.5, sh * 0.5), sh * 0.3), c[2])
		"chevron":
			img.fill_rect(Rect2i(0, 0, sw, sh / 2), c[0])
			img.fill_rect(Rect2i(0, sh / 2, sw, sh - sh / 2), c[1])
			_poly(img, PackedVector2Array([Vector2(0, 0), Vector2(sw * 0.42, sh * 0.5), Vector2(0, sh)]), c[2])
		_:   # bicolor_star: vertical bicolour with a star in the hoist
			img.fill_rect(Rect2i(0, 0, sw / 3, sh), c[0])
			img.fill_rect(Rect2i(sw / 3, 0, sw - sw / 3, sh), c[1])
			_poly(img, _star(Vector2(sw / 6.0, sh * 0.5), sh * 0.2), c[2] if c[2] != c[0] else Color.WHITE)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return img


## Neutral fallback: a grey flag with the 3-letter code in a small pixel font. Used for an unknown country
## or a missing file, so a card never shows an empty hole.
static func fallback(code: String, w: int = WIDTH, h: int = HEIGHT) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#5c636a"))
	img.fill_rect(Rect2i(0, 0, w, maxi(h / 14, 1)), Color("#79818a"))
	img.fill_rect(Rect2i(0, h - maxi(h / 14, 1), w, maxi(h / 14, 1)), Color("#43494f"))
	var text := code.to_upper().substr(0, 3)
	var px := maxi(int(h / 12.0), 1)            # size of one font pixel
	var tw := text.length() * 4 * px - px
	var x0 := (w - tw) / 2
	var y0 := (h - 5 * px) / 2
	for i in text.length():
		var g: String = GLYPHS.get(text[i], GLYPHS["?"])
		for gy in 5:
			for gx in 3:
				if g[gy * 3 + gx] == "#":
					img.fill_rect(Rect2i(x0 + (i * 4 + gx) * px, y0 + gy * px, px, px), Color("#e7e3d8"))
	return img


static func _circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, img.get_height())):
		for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, img.get_width())):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.4
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


static func _poly(img: Image, pts: PackedVector2Array, col: Color) -> void:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	for y in range(maxi(int(box.position.y), 0), mini(int(box.end.y) + 1, img.get_height())):
		for x in range(maxi(int(box.position.x), 0), mini(int(box.end.x) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, col)


## 3 x 5 pixel glyphs (row-major, '#' = on) for the fallback flag.
const GLYPHS := {
	"A": ".#.#.#####.##.#", "B": "##.#.###.#.###.", "C": ".###..#..#...##", "D": "##.#.##.##.###.",
	"E": "####..##.#..###", "F": "####..##.#..#..", "G": ".###..#.##.#.##", "H": "#.##.#####.##.#",
	"I": "###.#..#..#.###", "J": "..#..#..##.#.#.", "K": "#.##.###.#.##.#", "L": "#..#..#..#..###",
	"M": "#.########.##.#", "N": "##.#.##.##.##.#", "O": ".#.#.##.##.#.#.", "P": "##.#.###.#..#..",
	"Q": ".#.#.##.###..##", "R": "##.#.###.#.##.#", "S": ".###...#...###.", "T": "###.#..#..#..#.",
	"U": "#.##.##.##.####", "V": "#.##.##.##.#.#.", "W": "#.##.########.#", "X": "#.##.#.#.#.##.#",
	"Y": "#.##.#.#..#..#.", "Z": "###..#.#.#..###", "?": "##...#.#.....#.",
}
