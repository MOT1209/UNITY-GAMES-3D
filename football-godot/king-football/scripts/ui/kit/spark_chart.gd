class_name SparkChart
extends Control

## Small line chart (development of a prospect's overall rating). Values are drawn left to right.

var values: Array = []
var color := UIKit.GOLD


func _init(p_values: Array = [], p_size := Vector2(260, 90)) -> void:
	values = p_values
	custom_minimum_size = p_size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04))
	if values.size() < 2:
		return
	var lo := 99.0
	var hi := 0.0
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if hi - lo < 4.0:
		hi = lo + 4.0
	var pts := PackedVector2Array()
	for i in values.size():
		var x := 6.0 + (size.x - 12.0) * i / float(values.size() - 1)
		var y := size.y - 6.0 - (size.y - 12.0) * (float(values[i]) - lo) / (hi - lo)
		pts.append(Vector2(x, y))
	draw_polyline(pts, color, 2.0, true)
	for p in pts:
		draw_circle(p, 2.5, color)
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 14), str(int(hi)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(4, size.y - 4), str(int(lo)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
