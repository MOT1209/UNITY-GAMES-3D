## Main menu controller. Every text comes from the central `Loc` manager and is
## refreshed when the language changes; the layout direction follows the
## language (RTL for Arabic) because the scene root inherits it.
## Play opens a real match setup (teams, squads, tactics) in the management
## hub; Settings opens the language selection; the first run asks for a language.
extends Control

@onready var _play: Button = %PlayButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _title: Label = $Center/MenuColumn/TitleLabel
@onready var _subtitle: Label = $Center/MenuColumn/SubtitleLabel
@onready var _status: Label = $Center/MenuColumn/StatusLabel
@onready var _version: Label = $VersionLabel

var _hub: Button


func _ready() -> void:
	_play.pressed.connect(_on_play_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_add_hub_button()
	Loc.language_changed.connect(_apply_texts)
	_apply_texts(Loc.language)
	_play.grab_focus()
	if not Loc.has_saved_language():
		LanguagePicker.show_first_run(self)


## (Re)applies every visible text. Called on start and on each language change.
func _apply_texts(_code: String = "") -> void:
	_title.text = Loc.t("MENU_TITLE")
	_subtitle.text = Loc.t("MENU_SUBTITLE")
	_play.text = Loc.t("MENU_PLAY")
	_hub.text = Loc.t("MENU_MANAGEMENT")
	_settings.text = Loc.t("MENU_SETTINGS")
	_quit.text = Loc.t("MENU_EXIT")
	_status.text = Loc.t("MENU_STATUS")
	_version.text = Loc.f("MENU_VERSION", "0.2.0")


## Adds the management entry (career, squad, academy, transfers...).
func _add_hub_button() -> void:
	var box := _play.get_parent()
	_hub = MenuItemButton.new()
	_hub.name = "HubButton"
	_hub.custom_minimum_size = _play.custom_minimum_size
	_hub.add_theme_font_size_override("font_size", 24)
	_hub.pressed.connect(_on_hub_pressed)
	box.add_child(_hub)
	box.move_child(_hub, _play.get_index() + 1)


func _on_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/hub/hub.tscn")


## Opens the real match setup in the hub (not the empty prototype arena).
func _on_play_pressed() -> void:
	AppHub.open_screen_on_start = "match_setup"
	get_tree().change_scene_to_file("res://ui/hub/hub.tscn")


func _on_settings_pressed() -> void:
	if get_node_or_null("SettingsPanel") != null:
		return
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var heading := Label.new()
	heading.text = Loc.t("MENU_SETTINGS")
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", Color(0.93, 0.75, 0.3))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var lang_label := Label.new()
	lang_label.text = Loc.t("SETTINGS_LANGUAGE")
	lang_label.add_theme_font_size_override("font_size", 22)
	lang_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lang_label)
	var picker := LanguagePicker.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(picker)
	var world := WorldPicker.new()
	world.name = "WorldPicker"
	world.custom_minimum_size = Vector2(420, 0)
	box.add_child(world)
	var close := Button.new()
	close.name = "CloseSettings"
	close.text = Loc.t("COMMON_CLOSE")
	close.custom_minimum_size = Vector2(200, 44)
	close.pressed.connect(panel.queue_free)
	box.add_child(close)
	# keep the panel's own texts in sync while it is open
	Loc.language_changed.connect(func(_c: String) -> void:
		if is_instance_valid(heading):
			heading.text = Loc.t("MENU_SETTINGS")
			lang_label.text = Loc.t("SETTINGS_LANGUAGE")
			close.text = Loc.t("COMMON_CLOSE"))
	add_child(panel)
	close.grab_focus()


func _on_quit_pressed() -> void:
	GameManager.quit_game()
