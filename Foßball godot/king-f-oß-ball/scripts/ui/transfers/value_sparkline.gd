class_name ValueSparkline
extends Control

## Small line chart of a player's last market values (transfers v2, player profile). Newest value on the reading end:
## right in left-to-right languages, left in Arabic.

var values: Array = []
var line_color := UIKit.GOLD


func _init(p_values: Array = [], p_size := Vector2(220, 56)) -> void:
	values = p_values
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.PANEL.lightened(0.05))
	if values.size() < 2:
		return
	var lo := float(values.min())
	var hi := float(values.max())
	var span := maxf(hi - lo, 1.0)
	var pts := PackedVector2Array()
	var n := values.size()
	for i in n:
		var x := 6.0 + (size.x - 12.0) * i / float(n - 1)
		if Loc.is_rtl():
			x = size.x - x
		var y := size.y - 6.0 - (size.y - 12.0) * (float(values[i]) - lo) / span
		pts.append(Vector2(x, y))
	draw_polyline(pts, line_color, 2.0, true)
	draw_circle(pts[n - 1], 3.5, UIKit.GOOD if float(values[n - 1]) >= float(values[0]) else UIKit.BAD)
