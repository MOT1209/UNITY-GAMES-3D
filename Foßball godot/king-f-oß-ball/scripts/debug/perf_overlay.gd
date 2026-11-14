class_name PerfOverlay
extends CanvasLayer

## Developer performance read-out (UX phase 5.2): frames per second, frame time, draw calls, rendered
## objects, static memory and node count, refreshed twice a second. Only created in developer mode
## (`ScreenRegistry.developer_mode()`: debug builds or the hidden setting); toggled with F3.

const REFRESH := 0.5

var _label: Label
var _left := 0.0


func _init() -> void:
	name = "PerfOverlay"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.6)
	st.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", st)
	panel.position = Vector2(8, 8)
	_label = Label.new()
	_label.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	panel.add_child(_label)
	add_child(panel)
	visible = false


## One-line snapshot of the counters (also used by tests and logs).
static func snapshot() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


static func format(s: Dictionary) -> String:
	return "FPS %d  ·  %.1f ms  ·  draw calls %d  ·  objects %d  ·  RAM %.0f MB  ·  nodes %d" % [
			int(s["fps"]), float(s["frame_ms"]), int(s["draw_calls"]), int(s["objects"]), float(s["memory_mb"]), int(s["nodes"])]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible
		_left = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH
	_label.text = format(snapshot())
