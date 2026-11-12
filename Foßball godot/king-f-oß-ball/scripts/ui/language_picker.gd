class_name LanguagePicker
extends HBoxContainer

## Three buttons (العربية · Deutsch · English) that switch the game language
## through the central `Loc` manager. The labels are always shown in each
## language's own name, and the row keeps the same visual order in every
## layout direction so the choice never moves around when RTL is switched on.
## Used by the first-run dialog, the main-menu settings panel and the hub
## settings screen.

signal chosen(code: String)

var _buttons: Dictionary = {}


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_theme_constant_override("separation", 10)
	for code in Loc.ORDER:
		var b := Button.new()
		b.name = "Lang_%s" % code
		b.text = Loc.native_name(code)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", 20)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_on_pressed.bind(code))
		add_child(b)
		_buttons[code] = b


func _ready() -> void:
	Loc.language_changed.connect(_refresh)
	_refresh(Loc.language)


func _on_pressed(code: String) -> void:
	var err := Loc.set_language(code)
	if err == "":
		chosen.emit(code)
	_refresh(Loc.language)


func _refresh(code: String) -> void:
	for c in _buttons:
		(_buttons[c] as Button).set_pressed_no_signal(c == code)


## Modal "initial game setup" dialog shown once, until a language is saved.
## Returns the dialog so callers/tests can inspect it.
static func show_first_run(host: Node) -> PanelContainer:
	var overlay := PanelContainer.new()
	overlay.name = "FirstRunLanguage"
	overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 0.96)
	overlay.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Label.new()
	title.text = "اختر اللغة  ·  Sprache wählen  ·  Choose your language"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.93, 0.75, 0.3))
	box.add_child(title)
	var picker := LanguagePicker.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(picker)
	picker.chosen.connect(func(_c: String) -> void: overlay.queue_free())
	host.add_child(overlay)
	return overlay
