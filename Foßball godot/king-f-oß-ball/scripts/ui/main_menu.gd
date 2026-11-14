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

const BACKGROUND := "res://assets/ui/stadium_blur.jpg"

var _hub: Button
var _pairing: Button
var _continue: Button


func _ready() -> void:
	_play.pressed.connect(_on_play_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_add_background()
	_add_hub_button()
	_add_pairing_button()
	_add_continue_button()
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
	if _continue != null:
		_continue.text = Loc.t("MENU_CONTINUE_CAREER")
	_pairing.text = Loc.t("MENU_KING_CONTROLLER")
	_settings.text = Loc.t("MENU_SETTINGS")
	_quit.text = Loc.t("MENU_EXIT")
	_status.text = Loc.t("MENU_STATUS")
	_version.text = Loc.f("MENU_VERSION", "0.2.0")


## Blurred stadium photo (a real in-game frame) behind the menu, darkened for contrast, and a slowly
## turning 3D player (the same model and kit as in a match) on the side.
func _add_background() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if ResourceLoader.exists(BACKGROUND):
		var tex := TextureRect.new()
		tex.name = "StadiumBackground"
		tex.texture = load(BACKGROUND)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
		move_child(tex, bg.get_index() + 1 if bg != null else 0)
		if bg != null:
			bg.color = Color(0.03, 0.05, 0.1, 1.0)
	var db := get_node_or_null("/root/TeamDB")
	if db == null or not PlayerPortraitRenderer.can_render():
		return
	var team: TeamData = db.get_team(AppHub.user_team_id) if AppHub.user_team_id != "" else null
	if team == null:
		var clubs: Array = db.list_teams(TeamData.Category.CLUB)
		team = clubs[0] if not clubs.is_empty() else null
	if team == null or team.squad_ids.is_empty():
		return
	var star: PlayerData = null
	for pid in team.squad_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and p.position != PlayerData.Position.GK and (star == null or p.get_overall() > star.get_overall()):
			star = p
	if star == null:
		return
	var preview := PlayerPreview.new(Vector2(300, 420))
	preview.name = "MenuPlayer"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.anchor_left = 1.0
	preview.anchor_right = 1.0
	preview.anchor_top = 0.5
	preview.anchor_bottom = 0.5
	preview.offset_left = -340.0
	preview.offset_right = -40.0
	preview.offset_top = -210.0
	preview.offset_bottom = 210.0
	add_child(preview)
	move_child(preview, get_node("Center").get_index())
	preview.setup(PlayerCardData.from_data(db, star), db)


## "Continue career" at the top of the menu when a saved career exists.
func _add_continue_button() -> void:
	if not FileAccess.file_exists(AppHub.SAVE_PATH):
		return
	var box := _play.get_parent()
	_continue = MenuItemButton.new()
	_continue.name = "ContinueButton"
	_continue.custom_minimum_size = _play.custom_minimum_size
	_continue.add_theme_font_size_override("font_size", 24)
	_continue.pressed.connect(_on_continue_pressed)
	box.add_child(_continue)
	box.move_child(_continue, _play.get_index())
	_continue.text = Loc.t("MENU_CONTINUE_CAREER")


func _on_continue_pressed() -> void:
	var err: String = AppHub.load_game()
	if err != "":
		_status.text = ErrorText.localize(err)
		return
	AppHub.open_screen_on_start = "career"
	get_tree().change_scene_to_file("res://ui/hub/hub.tscn")


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


func _add_pairing_button() -> void:
	var box := _play.get_parent()
	_pairing = MenuItemButton.new()
	_pairing.name = "PairingButton"
	_pairing.custom_minimum_size = _play.custom_minimum_size
	_pairing.add_theme_font_size_override("font_size", 24)
	_pairing.pressed.connect(_on_pairing_pressed)
	box.add_child(_pairing)
	box.move_child(_pairing, _hub.get_index() + 1)


func _on_pairing_pressed() -> void:
	if get_node_or_null("PairingScreen") != null:
		return
	var ps := PairingScreen.new()
	ps.name = "PairingScreen"
	ps.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ps)


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
	# keep the panel's own texts in sync while it is open; disconnected when the panel closes (the lambda
	# used to stay connected and fire on freed labels: "Lambda capture ... was freed").
	var sync := func(_c: String) -> void:
		heading.text = Loc.t("MENU_SETTINGS")
		lang_label.text = Loc.t("SETTINGS_LANGUAGE")
		close.text = Loc.t("COMMON_CLOSE")
	Loc.language_changed.connect(sync)
	panel.tree_exiting.connect(func() -> void:
		if Loc.language_changed.is_connected(sync):
			Loc.language_changed.disconnect(sync))
	add_child(panel)
	close.grab_focus()


func _on_quit_pressed() -> void:
	GameManager.quit_game()
