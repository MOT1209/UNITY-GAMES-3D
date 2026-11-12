class_name PitchDiagram
extends Control

## Football pitch diagram with player markers, drawn directly with `_draw()`.
## Direct drawing is immune to the layout mirroring that Arabic (RTL) applies to
## child Controls, so the pitch keeps the same orientation in every language
## (own goal at the bottom, attack upwards) and the markers can never vanish.
## `points` are team-relative coordinates: x -1 (left) .. 1 (right), y 0 (own
## goal) .. 1 (opponent goal).

const ASPECT := 68.0 / 105.0         # width / length of a real pitch, drawn portrait-in-landscape

var points: Array[Vector2] = []


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	custom_minimum_size = Vector2(360, 230)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func set_points(p: Array[Vector2]) -> void:
	points = p
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.1, 0.4, 0.15))
	var line := Color(1, 1, 1, 0.55)
	draw_rect(r.grow(-6.0), line, false, 2.0)
	draw_line(Vector2(6, size.y * 0.5), Vector2(size.x - 6, size.y * 0.5), line, 1.5)
	draw_arc(Vector2(size.x * 0.5, size.y * 0.5), size.y * 0.14, 0.0, TAU, 32, line, 1.5)
	var box_w := size.x * 0.44
	var box_h := size.y * 0.16
	draw_rect(Rect2((size.x - box_w) * 0.5, 6.0, box_w, box_h), line, false, 1.5)
	draw_rect(Rect2((size.x - box_w) * 0.5, size.y - 6.0 - box_h, box_w, box_h), line, false, 1.5)
	for p in points:
		var pos := Vector2(8.0 + (p.x + 1.0) * 0.5 * (size.x - 16.0), 8.0 + (1.0 - p.y) * (size.y - 16.0))
		draw_circle(pos, 6.5, Color(0, 0, 0, 0.45))
		draw_circle(pos, 5.0, Color.WHITE)
