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
var _new_career: Button


func _ready() -> void:
	_play.pressed.connect(_on_play_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_add_background()
	_add_hub_button()
	_add_pairing_button()
	_add_continue_button()
	_add_new_career_button()
	Loc.language_changed.connect(_apply_texts)
	Loc.language_changed.connect(func(_c: String) -> void: _fit.call_deferred())
	_apply_texts(Loc.language)
	_style_column()
	_play.grab_focus()
	resized.connect(_fit)
	_fit.call_deferred()
	for b in (_play.get_parent() as Node).get_children():
		if b is Control:
			(b as Control).resized.connect(_fit)
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
	if _new_career != null:
		_new_career.text = Loc.t("SCREEN_CAREER_WIZARD")
	_pairing.text = Loc.t("MENU_KING_CONTROLLER")
	_settings.text = Loc.t("MENU_SETTINGS")
	_quit.text = Loc.t("MENU_EXIT")
	_status.text = Loc.t("MENU_STATUS")
	_version.text = Loc.f("MENU_VERSION", str(ProjectSettings.get_setting("application/config/version", "")))


## Live 3D stadium under floodlights behind the menu (the managed club's own stadium when a career exists), with a
## photo of the stadium as the fallback where 3D cannot render. Dark shades keep the buttons readable.
func _add_background() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	var at := bg.get_index() + 1 if bg != null else 0
	if ResourceLoader.exists(BACKGROUND):
		var tex := TextureRect.new()
		tex.name = "StadiumBackground"
		tex.texture = load(BACKGROUND)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
		move_child(tex, at)
		at += 1
	if PlayerPortraitRenderer.can_render():
		var live := MenuStadium.new(_menu_stadium_id())
		add_child(live)
		move_child(live, at)
		at += 1
	_shade = TextureRect.new()                 # side shade behind the column (flipped for Arabic in _fit)
	_shade.name = "SideShade"
	_shade.texture = _gradient(Color(0.01, 0.02, 0.05, 0.92), Color(0.01, 0.02, 0.05, 0.0), true)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	move_child(_shade, at)
	var bottom := TextureRect.new()
	bottom.name = "BottomShade"
	bottom.texture = _gradient(Color(0.01, 0.02, 0.05, 0.0), Color(0.01, 0.02, 0.05, 0.75), false)
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	move_child(bottom, at + 1)


var _shade: TextureRect


func _menu_stadium_id() -> String:
	var db := get_node_or_null("/root/TeamDB")
	var team: TeamData = db.get_team(AppHub.user_team_id) if db != null and AppHub.user_team_id != "" else null
	return StadiumCatalog.for_team(team) if team != null else StadiumCatalog.DEFAULT_ID


static func _gradient(from: Color, to: Color, horizontal: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	g.add_point(0.45, from.lerp(to, 0.25))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	return t


# --- look of the column: logo lockup, glass buttons with icons --------------------------------------------------

const ICONS := {"ContinueButton": "trophy", "PlayButton": "ball", "NewCareerButton": "sprout", "HubButton": "building",
		"PairingButton": "phone", "SettingsButton": "gear", "QuitButton": "power"}


func _style_column() -> void:
	var col := $Center/MenuColumn as VBoxContainer
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var crown := $Center/MenuColumn/CrownIcon as Control
	var rule := $Center/MenuColumn/RuleBar as Control
	# logo lockup: crown beside the title, the tagline under it
	var lock := HBoxContainer.new()
	lock.name = "Logo"
	lock.add_theme_constant_override("separation", 14)
	col.add_child(lock)
	col.move_child(lock, crown.get_index())
	crown.reparent(lock)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.reparent(lock)
	_title.add_theme_color_override("font_color", Color(1, 0.86, 0.45))
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	_title.add_theme_constant_override("outline_size", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rule.visible = false
	_subtitle.add_theme_color_override("font_color", Color(0.86, 0.9, 0.97, 0.85))
	_status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 0.7))
	for b in (_play.get_parent() as Node).get_children():
		if b is Button:
			_style_button(b as Button, b == _play)


func _style_button(b: Button, primary: bool) -> void:
	var fill := Color(0.93, 0.75, 0.3, 0.95) if primary else Color(0.06, 0.09, 0.17, 0.62)
	var rim := Color(1, 0.9, 0.55, 0.9) if primary else Color(1, 1, 1, 0.16)
	var normal := UIKit.box(fill, rim, 1, 12)
	var hover := UIKit.box(fill.lightened(0.12) if primary else Color(0.12, 0.17, 0.3, 0.8), UIKit.GOLD, 2, 12)
	var pressed := UIKit.box(fill.darkened(0.15) if primary else Color(0.04, 0.06, 0.12, 0.85), UIKit.GOLD, 2, 12)
	for st: StyleBoxFlat in [normal, hover, pressed]:
		st.content_margin_left = 58
		st.content_margin_right = 20
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	var text_col := Color(0.1, 0.07, 0.01) if primary else Color(0.93, 0.95, 1.0)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, text_col)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var kind: String = ICONS.get(str(b.name), "")
	if kind != "" and b.get_node_or_null("Icon") == null:
		var ic := NavIcon.new(kind, 24.0)
		ic.name = "Icon"
		ic.color = text_col if primary else UIKit.GOLD
		b.add_child(ic)


## Scales the column to the window height and puts the icons / shade on the reading side of the language.
func _fit() -> void:
	var k := clampf(size.y / 900.0, 0.55, 1.0)
	var rtl := is_layout_rtl()
	var col := $Center/MenuColumn as Control
	col.anchor_left = 0.0
	col.anchor_right = 0.0
	col.grow_horizontal = Control.GROW_DIRECTION_END
	var ins := UIKit.safe_insets(get_viewport())
	var side := float(ins["right"] if rtl else ins["left"])        # the column's side is mirrored in Arabic
	col.offset_left = 72.0 * k + side
	col.offset_right = 72.0 * k + side + 520.0 * maxf(k, 0.75)
	col.offset_top = 40.0 * k + float(ins["top"])
	col.offset_bottom = -(56.0 * k) - float(ins["bottom"])
	(col as BoxContainer).add_theme_constant_override("separation", roundi(10.0 * k))
	_title.add_theme_font_size_override("font_size", roundi(64.0 * k))
	_subtitle.add_theme_font_size_override("font_size", roundi(18.0 * maxf(k, 0.75)))
	($Center/MenuColumn/Logo/CrownIcon as Control).custom_minimum_size = Vector2(60, 46) * k
	_status.visible = size.y >= 620.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	for l: Label in [_subtitle, _status]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	if _shade != null:
		_shade.flip_h = rtl
	var box := _play.get_parent() as BoxContainer
	box.add_theme_constant_override("separation", roundi(10.0 * k))
	for b in box.get_children():
		if not (b is Button):
			continue
		var btn := b as Button
		btn.custom_minimum_size = Vector2(0, (66.0 if btn == _play else 52.0) * k)
		btn.add_theme_font_size_override("font_size", roundi((24.0 if btn == _play else 19.0) * maxf(k, 0.8)))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT          # mirrored by Godot in RTL: text sits next to the icon
		for st_name in ["normal", "hover", "focus", "pressed"]:
			var st := btn.get_theme_stylebox(st_name) as StyleBoxFlat
			if st != null:
				st.content_margin_left = 20.0 if rtl else 58.0
				st.content_margin_right = 58.0 if rtl else 20.0
		var ic := btn.get_node_or_null("Icon") as Control
		if ic != null:
			var px := 24.0 * maxf(k, 0.8)
			ic.size = Vector2(px, px)
			ic.position = Vector2((btn.size.x - 20.0 - px) if rtl else 20.0, (btn.size.y - px) * 0.5)
	var ver := get_node("VersionLabel") as Control
	ver.offset_top = -30.0 - float(ins["bottom"])
	ver.offset_bottom = -10.0 - float(ins["bottom"])
	ver.offset_left = -200.0 - float(ins["left"] if rtl else ins["right"])
	ver.offset_right = -16.0 - float(ins["left"] if rtl else ins["right"])


## "Continue career" at the top of the menu when a saved career exists.
func _add_continue_button() -> void:
	if not AppHub.has_saved_career():
		return
	var box := _play.get_parent()
	_continue = MenuItemButton.new()
	_continue.name = "ContinueButton"
	_continue.custom_minimum_size = Vector2(430, 50)
	_continue.add_theme_font_size_override("font_size", 19)
	_continue.pressed.connect(_on_continue_pressed)
	box.add_child(_continue)
	box.move_child(_continue, _play.get_index())
	_continue.text = Loc.t("MENU_CONTINUE_CAREER")


## "New career" right after Play: opens the hub on the new-career wizard.
func _add_new_career_button() -> void:
	var box := _play.get_parent()
	_new_career = MenuItemButton.new()
	_new_career.name = "NewCareerButton"
	_new_career.custom_minimum_size = Vector2(430, 50)
	_new_career.add_theme_font_size_override("font_size", 19)
	_new_career.pressed.connect(func() -> void:
		AppHub.open_screen_on_start = "career_wizard"
		get_tree().change_scene_to_file("res://ui/hub/hub.tscn"))
	box.add_child(_new_career)
	box.move_child(_new_career, _play.get_index() + 1)
	_new_career.text = Loc.t("SCREEN_CAREER_WIZARD")


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
	_hub.custom_minimum_size = Vector2(430, 50)
	_hub.add_theme_font_size_override("font_size", 19)
	_hub.pressed.connect(_on_hub_pressed)
	box.add_child(_hub)
	box.move_child(_hub, _play.get_index() + 1)


func _add_pairing_button() -> void:
	var box := _play.get_parent()
	_pairing = MenuItemButton.new()
	_pairing.name = "PairingButton"
	_pairing.custom_minimum_size = Vector2(430, 50)
	_pairing.add_theme_font_size_override("font_size", 19)
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
	panel.add_theme_stylebox_override("panel", UIKit.overlay_box())
	var center := CenterContainer.new()
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var heading := Label.new()
	heading.text = Loc.t("MENU_SETTINGS")
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", UIKit.GOLD)
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


## Android back button: closes an open panel first, otherwise asks before leaving the game.
## (Deferred: the notification is propagated through the tree, which cannot add or remove children meanwhile.)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back.call_deferred()


func _on_back() -> void:
	for n in ["SettingsPanel", "PairingScreen"]:
		var open := get_node_or_null(n)
		if open != null:
			open.queue_free()
			return
	if get_node_or_null("QuitConfirm") != null:
		return
	var d := UIKit.confirm(self, Loc.t("MENU_EXIT_CONFIRM"), _on_quit_pressed)
	d.name = "QuitConfirm"


func _on_quit_pressed() -> void:
	GameManager.quit_game()
