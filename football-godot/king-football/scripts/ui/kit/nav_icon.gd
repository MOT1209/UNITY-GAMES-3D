class_name NavIcon
extends Control

## Small vector icon for the hub navigation sections, drawn with `_draw()` (no font glyphs or image
## assets needed, crisp at any scale, identical on every platform). Kinds: home, shirt, sprout, trophy,
## building, gear, menu, back, ball, phone, power.

var kind := "home"
var color := UIKit.GOLD


func _init(p_kind: String = "home", px: float = 20.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_direction = Control.LAYOUT_DIRECTION_LTR


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x * s, y * s)
	var w := maxf(1.5, s * 0.09)
	match kind:
		"home":
			draw_polyline(PackedVector2Array([p.call(0.1, 0.5), p.call(0.5, 0.12), p.call(0.9, 0.5)]), color, w)
			draw_rect(Rect2(p.call(0.22, 0.48), Vector2(0.56 * s, 0.42 * s)), color, false, w)
			draw_rect(Rect2(p.call(0.42, 0.64), Vector2(0.16 * s, 0.26 * s)), color)
		"shirt":
			draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.12), p.call(0.42, 0.18), p.call(0.58, 0.18),
					p.call(0.7, 0.12), p.call(0.95, 0.32), p.call(0.82, 0.48), p.call(0.74, 0.42), p.call(0.74, 0.9),
					p.call(0.26, 0.9), p.call(0.26, 0.42), p.call(0.18, 0.48), p.call(0.05, 0.32)]), color)
		"sprout":
			draw_line(p.call(0.5, 0.92), p.call(0.5, 0.42), color, w)
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.5), p.call(0.15, 0.4), p.call(0.1, 0.15), p.call(0.4, 0.22)]), color)
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.42), p.call(0.62, 0.12), p.call(0.92, 0.08), p.call(0.85, 0.35)]), color)
		"trophy":
			draw_colored_polygon(PackedVector2Array([p.call(0.25, 0.1), p.call(0.75, 0.1), p.call(0.7, 0.45), p.call(0.5, 0.6),
					p.call(0.3, 0.45)]), color)
			draw_arc(p.call(0.25, 0.28), 0.14 * s, PI * 0.5, PI * 1.5, 8, color, w)
			draw_arc(p.call(0.75, 0.28), 0.14 * s, -PI * 0.5, PI * 0.5, 8, color, w)
			draw_rect(Rect2(p.call(0.45, 0.58), Vector2(0.1 * s, 0.2 * s)), color)
			draw_rect(Rect2(p.call(0.3, 0.78), Vector2(0.4 * s, 0.12 * s)), color)
		"building":
			draw_rect(Rect2(p.call(0.15, 0.3), Vector2(0.7 * s, 0.6 * s)), color, false, w)
			draw_polyline(PackedVector2Array([p.call(0.08, 0.32), p.call(0.5, 0.08), p.call(0.92, 0.32)]), color, w)
			for x in [0.3, 0.5, 0.7]:
				draw_line(p.call(x, 0.42), p.call(x, 0.84), color, w)
		"gear":
			draw_arc(p.call(0.5, 0.5), 0.26 * s, 0.0, TAU, 20, color, w * 1.6)
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(p.call(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3), p.call(0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44), color, w * 1.4)
		"menu":
			for y in [0.25, 0.5, 0.75]:
				draw_line(p.call(0.12, y), p.call(0.88, y), color, w * 1.3)
		"back":
			draw_polyline(PackedVector2Array([p.call(0.6, 0.15), p.call(0.25, 0.5), p.call(0.6, 0.85)]), color, w * 1.4)
		"ball":
			draw_arc(p.call(0.5, 0.5), 0.4 * s, 0.0, TAU, 24, color, w)
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.32), p.call(0.66, 0.44), p.call(0.6, 0.63),
					p.call(0.4, 0.63), p.call(0.34, 0.44)]), color)
		"phone":
			draw_rect(Rect2(p.call(0.28, 0.08), Vector2(0.44 * s, 0.84 * s)), color, false, w)
			draw_line(p.call(0.42, 0.8), p.call(0.58, 0.8), color, w)
		"power":
			draw_arc(p.call(0.5, 0.55), 0.34 * s, -PI * 0.3, PI * 1.3, 18, color, w * 1.2)
			draw_line(p.call(0.5, 0.08), p.call(0.5, 0.5), color, w * 1.2)
