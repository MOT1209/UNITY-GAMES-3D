class_name ChartKit
extends RefCounted

## Shared chart tools of the UI (Nov 2026): a line chart with an area fill and a zero line, horizontal bar rows,
## and form chips (W / D / L). Screens build charts with these instead of drawing their own.


## Line chart of `values` (numbers, left to right). `fmt` turns a value into the axis text (default: Loc.money).
static func line(values: Array, px := Vector2(420, 150), color := UIKit.GOLD, fmt := Callable()) -> Control:
	var c := _Line.new()
	c.values = values
	c.color = color
	c.fmt = fmt if fmt.is_valid() else Loc.money
	c.custom_minimum_size = px
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.name = "LineChart"
	return c


## One bar row: label | bar filled to `ratio` (0..1) | value text. Used for income / expense and facility levels.
static func bar_row(label: String, value_text: String, ratio: float, color := UIKit.GOLD, label_w := 150.0) -> Control:
	var row := UIKit.hbox(10)
	var l := UIKit.label(label, 14, UIKit.MUTED)
	l.custom_minimum_size.x = label_w
	l.clip_text = true
	row.add_child(l)
	var bar := _Bar.new()
	bar.ratio = clampf(ratio, 0.0, 1.0)
	bar.color = color
	bar.custom_minimum_size = Vector2(80, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var v := UIKit.label(value_text, 14)
	v.custom_minimum_size.x = 110
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


## Small coloured chip for a result letter: W green, D neutral, L red. `text` is the shown label.
static func form_chip(result: String, text: String) -> Control:
	var col := UIKit.GOOD if result == "W" else (UIKit.BAD if result == "L" else UIKit.NEUTRAL)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.chip(col, 6, 8, 3, 0.28))
	var l := UIKit.label(text, 14, UIKit.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.tooltip_text = result
	return p


class _Line extends Control:
	var values: Array = []
	var color := UIKit.GOLD
	var fmt: Callable

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04))
		if values.size() < 2:
			return
		var lo := INF
		var hi := -INF
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if hi - lo < 1.0:
			hi = lo + 1.0
		var pad := (hi - lo) * 0.08
		lo -= pad
		hi += pad
		var font := get_theme_default_font()
		var left := 6.0
		var top := 18.0
		var bottom := size.y - 8.0
		var w := size.x - left - 8.0
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(left + w * i / float(values.size() - 1), bottom - (bottom - top) * (float(values[i]) - lo) / (hi - lo)))
		var zero_y := bottom - (bottom - top) * (0.0 - lo) / (hi - lo)
		var base := clampf(zero_y, top, bottom)
		if zero_y > top and zero_y < bottom:                 # the chart crosses zero: mark it
			draw_line(Vector2(left, zero_y), Vector2(left + w, zero_y), Color(1, 1, 1, 0.25), 1.0)
		for i in range(pts.size() - 1):                      # area fill as quads (works for any curve shape)
			draw_colored_polygon(PackedVector2Array([Vector2(pts[i].x, base), pts[i], pts[i + 1], Vector2(pts[i + 1].x, base)]),
					Color(color.r, color.g, color.b, 0.14))
		draw_polyline(pts, color, 2.0, true)
		draw_circle(pts[pts.size() - 1], 3.5, color)
		draw_string(font, Vector2(left, 13), str(fmt.call(int(hi - pad))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
		draw_string(font, Vector2(left, size.y - 1), str(fmt.call(int(lo + pad))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))


class _Bar extends Control:
	var ratio := 0.0
	var color := UIKit.GOLD

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		if ratio > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(maxf(3.0, size.x * ratio), size.y)), color)
