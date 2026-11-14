class_name HubRoot
extends Control

## Management hub (Phase T10): navigation bar + content area + message bar.
## Scene: ui/hub/hub.tscn. Screens are created on demand from `ScreenRegistry`.

var app: Node
var current_id: String = ""
var current: HubScreen = null
var history: Array[String] = []
var current_params: Dictionary = {}

## Width of the navigation column.
const NAV_WIDTH := 220.0
## -1 = phone detection, 0 / 1 forced (tests): compact mode shows the navigation as a drawer.
static var force_compact := -1

var _content: PanelContainer
var _message: Label
var _nav: VBoxContainer
var _nav_scroll: ScrollContainer
var _team_label: Label
var _back_btn: Button
var _drawer_btn: Button
var _nav_buttons: Dictionary = {}       # screen id -> Button
var _section_boxes: Dictionary = {}     # section id -> VBoxContainer
var _history_params: Array = []         # params of every history entry (same order as `history`)


func _ready() -> void:
	app = get_node("/root/AppHub")
	_build_frame()
	app.state_changed.connect(_refresh_header)
	Loc.language_changed.connect(_on_language_changed)
	var start_id := "team_select" if app.user_team_id == "" else "career"
	if app.open_screen_on_start != "":
		start_id = app.open_screen_on_start
		app.open_screen_on_start = ""
	navigate(start_id)


func _build_frame() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var root := UIKit.vbox(8)
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 12.0
	root.offset_top = 12.0
	root.offset_right = -12.0
	root.offset_bottom = -12.0
	add_child(root)
	var top := UIKit.hbox(8)
	root.add_child(top)
	_back_btn = UIKit.button("", go_back, 48)
	_back_btn.name = "BackButton"
	_back_btn.custom_minimum_size = Vector2(48, 40)
	_back_btn.tooltip_text = Loc.t("HUB_BACK")
	_back_btn.add_child(_icon_centered("back"))
	top.add_child(_back_btn)
	_drawer_btn = UIKit.button("", toggle_drawer, 48)
	_drawer_btn.name = "NavToggle"
	_drawer_btn.custom_minimum_size = Vector2(48, 40)
	_drawer_btn.add_child(_icon_centered("menu"))
	top.add_child(_drawer_btn)
	_team_label = UIKit.label("", 16, UIKit.GOLD)
	_team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_team_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_team_label)
	var body := UIKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_nav = UIKit.vbox(4)
	_nav_scroll = UIKit.scroll(_nav)
	_nav_scroll.name = "NavPanel"
	_nav_scroll.custom_minimum_size = Vector2(NAV_WIDTH + 10.0, 0)
	_nav_scroll.size_flags_horizontal = Control.SIZE_FILL
	_nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_nav_scroll)
	_build_nav()
	_content = UIKit.panel()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	_message = UIKit.label("", 15, UIKit.MUTED)
	root.add_child(_message)
	_drawer_btn.visible = is_compact()
	_nav_scroll.visible = not is_compact()
	_refresh_header()


## Prominent "Play next match" on top, then collapsible sections with an icon each; the section of the
## open screen is expanded. Buttons are >= 48 px tall (touch). Button names stay "Nav_<screen id>".
func _build_nav() -> void:
	var play := UIKit.button(Loc.t("NAV_PLAY_NEXT"), play_next_match, NAV_WIDTH)
	play.name = "PlayNextButton"
	play.custom_minimum_size.y = 56.0
	play.add_theme_font_size_override("font_size", 18)
	play.add_theme_stylebox_override("normal", _nav_style(UIKit.GOLD.darkened(0.25), UIKit.GOLD))
	play.add_theme_stylebox_override("hover", _nav_style(UIKit.GOLD.darkened(0.1), UIKit.GOLD))
	play.add_theme_color_override("font_color", UIKit.BG)
	play.add_theme_color_override("font_hover_color", UIKit.BG)
	_nav.add_child(play)
	_nav_buttons.clear()
	_section_boxes.clear()
	for sec in ScreenRegistry.SECTIONS:
		var ids: Array = (sec[3] as Array).filter(func(id: String) -> bool: return ScreenRegistry.in_navigation(id))
		if ids.is_empty():
			continue
		var head := Button.new()
		head.name = "Section_%s" % sec[0]
		head.flat = true
		head.custom_minimum_size = Vector2(NAV_WIDTH, 40)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_theme_color_override("font_color", UIKit.MUTED)
		head.add_theme_font_size_override("font_size", 14)
		var row := UIKit.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8.0
		row.offset_right = -8.0
		row.add_child(NavIcon.new(str(sec[2]), 18.0))
		var title := UIKit.label(Loc.t(str(sec[1])), 14, UIKit.MUTED)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.size_flags_vertical = Control.SIZE_FILL
		row.add_child(title)
		head.add_child(row)
		_nav.add_child(head)
		var box := UIKit.vbox(4)
		box.name = "SectionBox_%s" % sec[0]
		_nav.add_child(box)
		_section_boxes[sec[0]] = box
		head.pressed.connect(func() -> void: box.visible = not box.visible)
		for id in ids:
			var b := UIKit.button(Loc.t(ScreenRegistry.SCREENS[id][0]), navigate.bind(id), NAV_WIDTH)
			b.custom_minimum_size.y = 48.0
			b.name = "Nav_%s" % id
			box.add_child(b)
			_nav_buttons[id] = b
	var menu_btn := UIKit.button(Loc.t("HUB_MAIN_MENU"), _to_main_menu, NAV_WIDTH)
	menu_btn.custom_minimum_size.y = 48.0
	menu_btn.name = "Nav_main_menu"
	_nav.add_child(menu_btn)


func _icon_centered(kind: String) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(NavIcon.new(kind, 20.0))
	return c


static func _nav_style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	return st


## Highlights the open screen's button and expands only its section (and "home").
func _mark_active(screen_id: String) -> void:
	for id in _nav_buttons:
		var b: Button = _nav_buttons[id]
		if id == screen_id:
			b.add_theme_stylebox_override("normal", _nav_style(UIKit.PANEL.lightened(0.12), UIKit.GOLD))
			b.add_theme_color_override("font_color", UIKit.GOLD)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")
	var active := ScreenRegistry.section_of(screen_id)
	for sec in _section_boxes:
		(_section_boxes[sec] as Control).visible = sec == active or sec == "home"


## Phones (and tests forcing it) get the navigation as a drawer behind a menu button.
func is_compact() -> bool:
	if force_compact >= 0:
		return force_compact == 1
	return OS.has_feature("mobile")


func toggle_drawer() -> void:
	_nav_scroll.visible = not _nav_scroll.visible


## Plays the user's next due fixture in 3D; without one, opens the match setup.
func play_next_match() -> void:
	var due: Array = app.due_user_fixtures()
	if due.is_empty():
		navigate("match_setup")
		say(Loc.t("NAV_NO_DUE_MATCH"))
		return
	var err: String = app.play_fixture((due[0][0] as Competition).id, due[0][1])
	if err != "":
		say(ErrorText.localize(err, app.db), true)


## Back to the previous screen (Esc, Android back button, the back arrow). Returns false at the start.
func go_back() -> bool:
	if history.size() < 2:
		return false
	history.pop_back()                       # the open screen
	_history_params.pop_back()
	var id: String = history.pop_back()      # the one before (navigate() records it again)
	var p: Dictionary = _history_params.pop_back()
	navigate(id, p)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if go_back():
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
		go_back()


func _refresh_header() -> void:
	var text := Loc.t("HUB_NO_CLUB_SELECTED")
	if app.user_team_id != "":
		var t: TeamData = app.db.get_team(app.user_team_id)
		if t != null:
			text = Loc.f("HUB_CLUB_RATING", [Loc.iso(t.display_name), app.db.get_team_rating(t.id)])
	if app.career != null:
		text += Loc.f("HUB_SEASON_WEEK", [app.career.season, app.career.week])
	_team_label.text = text
	if app.last_message != "":
		say(app.last_message)
		app.last_message = ""


## Opens a screen. Unknown ids are reported instead of crashing.
func navigate(screen_id: String, p: Dictionary = {}) -> bool:
	var screen := ScreenRegistry.create(screen_id)
	if screen == null:
		say(Loc.f("HUB_UNKNOWN_SCREEN", screen_id), true)
		return false
	if current != null:
		_content.remove_child(current)
		current.queue_free()
	screen.hub = self
	screen.params = p
	current_params = p
	_content.add_child(screen)
	screen.rebuild()
	current = screen
	current_id = screen_id
	history.append(screen_id)
	_history_params.append(p)
	if history.size() > 50:
		history.pop_front()
		_history_params.pop_front()
	_mark_active(screen_id)
	if _back_btn != null:
		_back_btn.disabled = history.size() < 2
	if is_compact() and _nav_scroll != null:
		_nav_scroll.visible = false         # the drawer closes after a choice
	_refresh_header()
	return true


func say(text: String, is_error: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UIKit.BAD if is_error else UIKit.GOOD)


func _to_main_menu() -> void:
	get_node("/root/GameManager").return_to_menu()


## Language switched at runtime: rebuild the frame (navigation texts, layout
## direction) and the open screen in place, keeping the current screen.
func _on_language_changed(_code: String) -> void:
	var id := current_id
	var p := current_params
	for c in get_children():
		c.queue_free()
	current = null
	_build_frame()
	if id != "":
		navigate(id, p)
