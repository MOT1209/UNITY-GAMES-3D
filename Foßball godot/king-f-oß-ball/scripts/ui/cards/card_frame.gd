class_name CardFrame
extends Control

## Card background + frame + rarity decoration + effect (Phase V5). One drawing
## routine, parameterised by `CardCategory.theme()` — the five categories are
## data, not five implementations.
##
## Effects are deliberately restrained: one soft diagonal sheen whose strength
## comes from the theme, optionally animated (`animate` = false for lists).

var kind: int = CardCategory.Kind.BRONZE:
	set(v):
		kind = v
		queue_redraw()
## Slow sheen sweep. Off in grids/lists; the static sheen is always drawn.
var animate := false:
	set(v):
		animate = v
		set_process(v)
var _phase := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * 0.18, 1.0)
	queue_redraw()


## Card silhouette: a rectangle with the top corners cut, as polygon points.
func shape(rect: Rect2, cut: float) -> PackedVector2Array:
	var r := rect
	return PackedVector2Array([
		r.position + Vector2(cut, 0), r.position + Vector2(r.size.x - cut, 0),
		r.position + Vector2(r.size.x, cut), r.position + Vector2(r.size.x, r.size.y - cut * 0.6),
		r.position + Vector2(r.size.x - cut * 0.6, r.size.y), r.position + Vector2(cut * 0.6, r.size.y),
		r.position + Vector2(0, r.size.y - cut * 0.6), r.position + Vector2(0, cut)])


func _draw() -> void:
	var th := CardCategory.theme(kind)
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var cut := w * 0.12
	var outer := shape(Rect2(Vector2.ZERO, size), cut)
	var border := float(th["border"]) * w / 220.0
	border = maxf(border, 1.5)
	# frame (metal gradient: light -> dark)
	var frame_cols := PackedColorArray()
	for i in outer.size():
		var t := outer[i].y / h
		frame_cols.append((th["frame"] as Color).lerp(th["frame_dark"], t))
	draw_polygon(outer, frame_cols)
	# inner background
	var inner_rect := Rect2(Vector2(border, border), size - Vector2(border, border) * 2.0)
	var inner := shape(inner_rect, cut - border * 0.5)
	var bg := PackedColorArray()
	for i in inner.size():
		bg.append((th["bg_top"] as Color).lerp(th["bg_bottom"], clampf(inner[i].y / h, 0.0, 1.0)))
	draw_polygon(inner, bg)
	_draw_ornament(th, inner_rect, cut, border)
	_draw_sheen(th, inner_rect)
	# thin inner highlight line
	var line := (th["frame"] as Color)
	line.a = 0.55
	draw_polyline(_closed(shape(inner_rect.grow(-border * 0.9), cut - border)), line, maxf(1.0, w / 220.0), true)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _draw_ornament(th: Dictionary, r: Rect2, cut: float, border: float) -> void:
	var level := int(th["ornament"])
	var col: Color = th["accent"]
	col.a = 0.85
	var u := r.size.x / 220.0
	# pitch-line arc behind the portrait (all classes, subtle)
	var arc := (th["frame"] as Color)
	arc.a = 0.10
	draw_arc(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.34), r.size.x * 0.36, 0.0, TAU, 48, arc, 2.0 * u, true)
	if level >= 1:   # divider above the stats
		var y := r.position.y + r.size.y * 0.722
		draw_line(Vector2(r.position.x + r.size.x * 0.12, y), Vector2(r.end.x - r.size.x * 0.12, y), col, 1.5 * u, true)
	if level >= 2:   # corner studs
		for c in [Vector2(r.position.x + cut, r.position.y + cut * 0.9), Vector2(r.end.x - cut, r.position.y + cut * 0.9)]:
			draw_circle(c, 3.0 * u, col)
	if level >= 3:   # elite: double rail along the sides
		for sx in [r.position.x + 7.0 * u, r.end.x - 7.0 * u]:
			draw_line(Vector2(sx, r.position.y + r.size.y * 0.25), Vector2(sx, r.position.y + r.size.y * 0.68), col, 1.2 * u, true)
	if level >= 4:   # legendary: crown-like chevrons + controlled red base band
		var red: Color = CardCategory.ROYAL_RED
		var band := Rect2(r.position.x, r.end.y - r.size.y * 0.035, r.size.x, r.size.y * 0.035)
		draw_rect(band, red)
		var cx := r.position.x + r.size.x * 0.5
		var y0 := r.position.y + 5.0 * u
		var gold: Color = CardCategory.GOLD
		draw_polyline(PackedVector2Array([Vector2(cx - 22 * u, y0 + 9 * u), Vector2(cx - 11 * u, y0 + 2 * u),
				Vector2(cx, y0 + 9 * u), Vector2(cx + 11 * u, y0 + 2 * u), Vector2(cx + 22 * u, y0 + 9 * u)]), gold, 2.0 * u, true)


func _draw_sheen(th: Dictionary, r: Rect2) -> void:
	var strength: float = th["shine"]
	var center := (0.28 if not animate else lerpf(-0.2, 1.2, _phase))
	var band := r.size.x * 0.22
	var x := r.position.x + r.size.x * center
	var c := Color(1, 1, 1, strength * 0.35)
	var clear := Color(1, 1, 1, 0)
	var quad := PackedVector2Array([Vector2(x - band, r.end.y), Vector2(x, r.end.y), Vector2(x + band * 0.8, r.position.y), Vector2(x - band * 0.2, r.position.y)])
	var quad2 := PackedVector2Array()
	for p in quad:
		quad2.append(Vector2(clampf(p.x, r.position.x, r.end.x), p.y))
	draw_polygon(quad2, PackedColorArray([clear, c, clear, clear]))
