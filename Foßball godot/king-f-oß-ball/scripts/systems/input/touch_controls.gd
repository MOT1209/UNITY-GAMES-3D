class_name TouchControls
extends CanvasLayer

## P4 mobile foundations: virtual joystick + action buttons that drive the
## shared human `IntentProvider` in driven mode. The layout mirrors the
## gamepad: stick bottom-left, kick buttons bottom-right, pause top-right.
##
## Edge discipline follows the driven-intent contract: buttons queue
## press/release requests from input events, and `_physics_process` applies
## them exactly once per physics tick after `intent.begin_tick()`, together
## with the stick's current `output`. Gameplay therefore sees one clean edge,
## no matter how the engine interleaves input and physics.
##
## No singleton — the MatchManager owns it with the HUD and frees it with the
## match. Shown only on touch devices (`DisplayServer.is_touchscreen_available()`)
## unless forced for tests or desktop debugging (`set_active(true)`).

signal pause_pressed

## Kick/hold buttons in display order (bottom-right cluster, two rows).
const BUTTON_ACTIONS: Array[StringName] = [&"sprint", &"tackle", &"switch_player",
		&"pass", &"shoot", &"lob_pass", &"through_pass", &"cross"]

var intent: IntentProvider
var active := false

var _joystick: TouchJoystick
var _pending_press: Array[StringName] = []
var _pending_release: Array[StringName] = []
var _layer_root: Control


## Feeds the match's human intent; activates immediately on a touch device.
func attach(p_intent: IntentProvider) -> void:
	intent = p_intent
	if DisplayServer.is_touchscreen_available():
		set_active(true)


## Turns the touch layer (and driven mode) on or off.
func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if value:
		_ensure_built()
		_layer_root.visible = true
		if intent != null:
			intent.set_driven(true)
	else:
		_pending_press.clear()
		_pending_release.clear()
		if intent != null:
			intent.set_driven(false)          # clears held actions + move
		if _layer_root != null:
			_layer_root.visible = false


func _exit_tree() -> void:
	# Never leave the shared intent in driven mode after the layer dies.
	set_active(false)


func _physics_process(_delta: float) -> void:
	if not active or intent == null or not intent.driven:
		return
	intent.begin_tick()
	var press := _pending_press
	var release := _pending_release
	_pending_press = []
	_pending_release = []
	for action in press:
		intent.press(action)
	for action in release:
		intent.release(action)
	intent.set_move(_joystick.output if _joystick != null else Vector2.ZERO)


# --- build ----------------------------------------------------------------------

func _ensure_built() -> void:
	if _layer_root != null:
		return
	_layer_root = Control.new()
	_layer_root.name = "TouchRoot"
	_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)
	_build_joystick()
	_build_buttons()
	_build_pause()


## Everything is offset into the display safe area (notches / rounded corners).
func _safe_offset() -> Vector2:
	var safe := DisplayServer.get_display_safe_area()
	return Vector2(maxf(safe.position.x, 0.0), maxf(safe.position.y, 0.0)) \
			+ Vector2(24.0, 24.0)


func _build_joystick() -> void:
	_joystick = TouchJoystick.new(90.0)
	_joystick.name = "Joystick"
	_joystick.position = _safe_offset() + Vector2(16.0, 0.0)
	_joystick.anchor_top = 1.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_top = -196.0
	_layer_root.add_child(_joystick)


func _build_buttons() -> void:
	var radius := 46.0
	var gap := 12.0
	for i in BUTTON_ACTIONS.size():
		var action := BUTTON_ACTIONS[i]
		var col := i % 3
		var row := floori(i / 3.0)
		var b := _action_button(action, radius)
		b.position = Vector2(16.0 + col * (radius * 2.0 + gap),
				-196.0 + row * (radius * 2.0 + gap))
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		_layer_root.add_child(b)


func _action_button(action: StringName, radius: float) -> Button:
	var b := Button.new()
	b.name = "Btn_" + action
	b.custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	b.text = _action_label(action)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", UIKit.TEXT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIKit.PANEL.r, UIKit.PANEL.g, UIKit.PANEL.b, 0.72)
	style.set_corner_radius_all(int(radius))
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, 0.35)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# queue the edge; _physics_process applies it once per tick
	b.button_down.connect(func() -> void: _pending_press.append(action))
	b.button_up.connect(func() -> void: _pending_release.append(action))
	return b


func _action_label(action: StringName) -> String:
	match action:
		&"sprint": return Loc.t("TOUCH_SPRINT")
		&"tackle": return Loc.t("TOUCH_TACKLE")
		&"switch_player": return Loc.t("TOUCH_SWITCH")
		&"pass": return Loc.t("TOUCH_PASS")
		&"shoot": return Loc.t("TOUCH_SHOOT")
		&"lob_pass": return Loc.t("TOUCH_LOB")
		&"through_pass": return Loc.t("TOUCH_THROUGH")
		&"cross": return Loc.t("TOUCH_CROSS")
	return String(action)


func _build_pause() -> void:
	var b := Button.new()
	b.name = "Btn_pause"
	b.text = Loc.t("TOUCH_PAUSE")
	b.custom_minimum_size = Vector2(72.0, 48.0)
	b.add_theme_font_size_override("font_size", 20)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -96.0
	b.offset_right = -24.0
	b.offset_top = 12.0
	b.pressed.connect(func() -> void: pause_pressed.emit())
	_layer_root.add_child(b)


## Test seams ----------------------------------------------------------------

## Queues a synthetic press exactly like a real button-down would.
func test_press(action: StringName) -> void:
	_pending_press.append(action)


## Queues a synthetic release exactly like a real button-up would.
func test_release(action: StringName) -> void:
	_pending_release.append(action)
