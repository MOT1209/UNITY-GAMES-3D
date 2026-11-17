class_name MatchRadar
extends Control

## Phase H1: radar (mini-map) at the bottom centre of the 3D match: the pitch with its lines, both elevens as dots in their
## kit colours (home circles, away triangles), the ball, and the player the human controls ringed in gold. Pure view of
## `MatchManager.entries` (it never changes the match). Setting `[match] radar` (bool) shows / hides it, `radar_opacity` (0.2..1).
## The pitch's long axis (z) runs left to right; `project()` is the single mapping, also used by the projection test.

const SIZE := Vector2(260, 168)
var m: MatchManager
var _home_color := Color(0.9, 0.2, 0.2)
var _away_color := Color(0.2, 0.5, 0.95)


func _init(p_m: MatchManager = null) -> void:
	m = p_m
	name = "MatchRadar"
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -SIZE.x / 2.0
	offset_right = SIZE.x / 2.0
	offset_top = -SIZE.y - 8.0
	offset_bottom = -8.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func _ready() -> void:
	if m != null:
		_home_color = MatchPresentation.side_kit_color(m, "home") if MatchPresentation.side_kit_color(m, "home").a > 0.0 else _home_color
		_away_color = MatchPresentation.side_kit_color(m, "away") if MatchPresentation.side_kit_color(m, "away").a > 0.0 else _away_color
	apply_settings()


func apply_settings() -> void:
	visible = bool(GameSettings.get_value("match", "radar"))
	modulate.a = clampf(float(GameSettings.get_value("match", "radar_opacity")), 0.2, 1.0)


## Pitch plane (x, z in metres) -> a point inside `rect` (z along the width, x along the height; the centre is the centre).
static func project(x: float, z: float, rect: Rect2) -> Vector2:
	return Vector2(rect.position.x + (z / PitchSpace.HALF_LENGTH * 0.5 + 0.5) * rect.size.x,
			rect.position.y + (x / PitchSpace.HALF_WIDTH * 0.5 + 0.5) * rect.size.y)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if m == null or m.ball == null:
		return
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.12, 0.06, 0.75))
	draw_rect(r, Color(0.14, 0.42, 0.2, 0.9))
	var line := Color(1, 1, 1, 0.75)
	draw_rect(r, line, false, 1.5)
	draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), line, 1.0)
	draw_arc(r.get_center(), r.size.y * 0.15, 0.0, TAU, 28, line, 1.0)
	for side_x in [0.0, 1.0]:                                   # penalty boxes
		var bw := r.size.x * 0.16
		var bx := r.position.x if side_x == 0.0 else r.end.x - bw
		draw_rect(Rect2(Vector2(bx, r.position.y + r.size.y * 0.22), Vector2(bw, r.size.y * 0.56)), line, false, 1.0)
	var selected_id: String = str(m.selected.get("player_id", ""))
	for side in ["home", "away"]:
		var col := _home_color if side == "home" else _away_color
		for e in m.entries[side]:
			var p := (e["node"] as Node3D).global_position
			var pt := project(p.x, p.z, r)
			if side == "home":
				draw_circle(pt, 3.6, col)
			else:
				draw_colored_polygon(PackedVector2Array([pt + Vector2(0, -4.4), pt + Vector2(4.0, 3.2), pt + Vector2(-4.0, 3.2)]), col)
			if str(e["player_id"]) == selected_id:
				draw_arc(pt, 6.5, 0.0, TAU, 16, Color(1.0, 0.85, 0.2), 1.8)
	var bp := m.ball.global_position
	draw_circle(project(bp.x, bp.z, r), 3.0, Color.WHITE)
