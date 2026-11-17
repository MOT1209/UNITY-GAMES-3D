class_name InputDeviceMonitor
extends Node

## Watches physical controller connections during a match (P2 input hardening)
## and shows/hides a KING-styled overlay when the last joypad disconnects or a
## joypad (re)connects. Mouse/keyboard-only play is untouched: the overlay only
## appears when a joypad was in use. No singleton — MatchManager owns it with
## the HUD and frees it with the match.

var _had_joypad := false
var _joypad_count := 0
var _layer: CanvasLayer
var _panel: Control


func _ready() -> void:
	_joypad_count = Input.get_connected_joypads().size()
	_had_joypad = _joypad_count > 0
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


## Attached to the match HUD layer; builds the hidden overlay lazily.
func attach(layer: CanvasLayer) -> void:
	_layer = layer


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	# The count is tracked here instead of re-reading the device list: the signal
	# is the authoritative transition, and this keeps the handler testable on a
	# machine without a physical controller.
	_joypad_count = maxi(0, _joypad_count + (1 if connected else -1))
	if connected and _joypad_count >= 1 and not _had_joypad:
		_had_joypad = true
		_show(false, Loc.t("INPUT_CONTROLLER_CONNECTED"))
		return
	if _joypad_count <= 0 and _had_joypad:
		_had_joypad = false
		_show(true, Loc.t("INPUT_CONTROLLER_DISCONNECTED"))
		return
	if connected and _had_joypad and _panel != null and _panel.visible:
		_show(false, "")


## Test seam: sets the joypad state without hardware (used by the validation suite).
func set_simulated_joypads(count: int) -> void:
	_joypad_count = maxi(0, count)
	_had_joypad = _joypad_count > 0


## Testable seam: builds and toggles the overlay directly.
func _show(blocking: bool, text: String) -> void:
	if _layer == null or text == "":
		return
	if _panel == null:
		_panel = _build_panel()
	_panel.get_node("Box/Text").text = text
	var box: PanelContainer = _panel.get_node("Box")
	box.self_modulate = UIKit.BAD if blocking else UIKit.GOOD
	_panel.visible = true
	if not blocking:
		# A connected notice hides itself again shortly after; a disconnected
		# overlay stays until the controller comes back.
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if _panel != null and Input.get_connected_joypads().size() > 0:
				_panel.visible = false)


func _build_panel() -> Control:
	var root := Control.new()
	root.name = "DeviceOverlay"
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.anchor_top = 0.08
	root.anchor_bottom = 0.08
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := PanelContainer.new()
	box.name = "Box"
	box.self_modulate = UIKit.BAD
	var text := Label.new()
	text.name = "Text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 20)
	text.add_theme_color_override("font_color", UIKit.GOLD)
	box.add_child(text)
	root.add_child(box)
	root.visible = false
	_layer.add_child(root)
	return root
