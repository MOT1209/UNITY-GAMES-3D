class_name ControlHints
extends HFlowContainer

## Match key hints built as separate chips — a framed key cap next to its action — instead of one
## sentence. In Arabic the old single string let the bidi algorithm pair "Shift" with the wrong
## action ("Shift" beside "مسافة"); a chip keeps key and action together, and each key cap is an
## LTR isolate. Shown for `SHOW_SECONDS` when a match starts (then fades), and on demand from the
## pause menu ("Controls").

const SHOW_SECONDS := 8.0
const FADE_SECONDS := 0.6
## [key cap (translation key or literal key name), action translation key]. Key names that are
## words ("Space") are translated; letters and "WASD" / "Tab" / "Esc" / "Shift" are key legends.
const PAIRS: Array = [
	["WASD", "HINT_MOVE"], ["Shift", "HINT_SPRINT"], ["HINT_KEY_SPACE", "HINT_PASS"], ["E", "HINT_SHOOT"],
	["Q", "HINT_LOB"], ["C", "HINT_DRIBBLE"], ["R", "HINT_THROUGH"], ["T", "HINT_CROSS"],
	["Tab", "HINT_SWITCH"], ["V", "HINT_CAMERA"], ["Esc", "HINT_PAUSE"],
]

var _left := 0.0


func _init() -> void:
	name = "ControlHints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = FlowContainer.ALIGNMENT_CENTER
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 6)


func _ready() -> void:
	rebuild()
	Loc.language_changed.connect(func(_c: String) -> void: rebuild())


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for pair in PAIRS:
		add_child(_chip(str(pair[0]), str(pair[1])))


## Key text shown on the cap for `pair_key` (translated when it is a HINT_KEY_* key).
static func key_text(cap: String) -> String:
	return Loc.ltr(Loc.t(cap) if cap.begins_with("HINT_KEY_") else cap)


func _chip(cap: String, action_key: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Hint_%s" % action_key
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var cap_panel := PanelContainer.new()
	cap_panel.name = "Key"
	cap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	style.border_color = Color(0.93, 0.75, 0.3, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	cap_panel.add_theme_stylebox_override("panel", style)
	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = key_text(cap)
	key_label.add_theme_font_size_override("font_size", 14)
	key_label.add_theme_color_override("font_color", UIKit.GOLD)
	cap_panel.add_child(key_label)
	row.add_child(cap_panel)
	var action := Label.new()
	action.name = "ActionLabel"
	action.text = Loc.t(action_key)
	action.add_theme_font_size_override("font_size", 14)
	action.add_theme_color_override("font_color", UIKit.TEXT)
	action.add_theme_color_override("font_outline_color", Color.BLACK)
	action.add_theme_constant_override("outline_size", 3)
	row.add_child(action)
	return row


## Shows the hints for `seconds` (0 = until hidden), then fades them out.
func show_for(seconds: float = SHOW_SECONDS) -> void:
	if DisplayServer.is_touchscreen_available():
		visible = false        # keyboard caps are meaningless on a phone and sat on top of the touch buttons
		return
	visible = true
	modulate.a = 1.0
	_left = seconds


func _process(delta: float) -> void:
	if _left <= 0.0 or not visible:
		return
	_left -= delta
	if _left <= FADE_SECONDS:
		modulate.a = clampf(_left / FADE_SECONDS, 0.0, 1.0)
	if _left <= 0.0:
		visible = false
		modulate.a = 1.0
