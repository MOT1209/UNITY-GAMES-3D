class_name HubRoot
extends Control

## Management hub (Phase T10): navigation bar + content area + message bar.
## Scene: ui/hub/hub.tscn. Screens are created on demand from `ScreenRegistry`.

var app: Node
var current_id: String = ""
var current: HubScreen = null
var _current_host: Control = null          # `current` itself or the ScrollContainer wrapped around it
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


var _root_box: Control


## Keeps the whole hub out of the phone's notch / rounded corners (12 px frame plus the cut-out insets).
func _apply_safe_area() -> void:
	if _root_box == null:
		return
	var s := UIKit.safe_insets(get_viewport())
	_root_box.offset_left = 12.0 + float(s["left"])
	_root_box.offset_top = 12.0 + float(s["top"])
	_root_box.offset_right = -12.0 - float(s["right"])
	_root_box.offset_bottom = -12.0 - float(s["bottom"])


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
	_root_box = root
	add_child(root)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
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
	# The menu button is always there: on desktop it hides / shows the sidebar to give the screen more room
	# (remembered in the settings); on phones the sidebar is a drawer, closed by default.
	_drawer_btn.tooltip_text = Loc.t("HUB_TOGGLE_MENU")
	_nav_scroll.visible = false if is_compact() else not bool(GameSettings.get_value("ui", "nav_hidden"))
	_refresh_header()


## Prominent "Play next match" on top, then collapsible sections with an icon each; the section of the
## open screen is expanded. Buttons are >= 48 px tall (touch). Button names stay "Nav_<screen id>".
func _build_nav() -> void:
	var play := UIKit.button(Loc.t("NAV_PLAY_NEXT"), play_next_match, NAV_WIDTH)
	play.name = "PlayNextButton"
	play.custom_minimum_size.y = 56.0
	UIKit.variant(play, UIKit.V_PRIMARY)
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


## Highlights the open screen's button and expands only its section (and "home").
func _mark_active(screen_id: String) -> void:
	screen_id = ScreenRegistry.nav_entry(screen_id)
	for id in _nav_buttons:
		var b: Button = _nav_buttons[id]
		UIKit.variant(b, UIKit.V_ACTIVE if id == screen_id else &"")
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
	if not is_compact():
		GameSettings.set_value("ui", "nav_hidden", not _nav_scroll.visible)


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
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button (deferred: the tree is busy propagating it)
		go_back.call_deferred()


## Red dot with a count on "Transfer market" (and its section) while offers or decisions wait for the user.
func refresh_badges() -> void:
	var n := 0
	var unread := 0
	if app.career != null and app.career.market != null:
		n = app.career.market.needs_user_action()
	if app.career != null:
		unread = app.career.inbox.unread_count()
	_apply_badge([_nav_buttons.get("transfers"), _nav.find_child("Section_club", false, false) if _nav != null else null], n)
	_apply_badge([_nav_buttons.get("inbox"), _nav.find_child("Section_home", false, false) if _nav != null else null], unread)


func _apply_badge(targets: Array, n: int) -> void:
	for target in targets:
		if target == null or not is_instance_valid(target):
			continue
		var dot: Label = (target as Node).get_node_or_null("Badge")
		if n <= 0:
			if dot != null:
				dot.queue_free()
			continue
		if dot == null:
			dot = Label.new()
			dot.name = "Badge"
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.add_theme_font_size_override("font_size", 12)
			dot.add_theme_color_override("font_color", Color.WHITE)
			var sb := UIKit.chip(UIKit.BAD, 9, 5, 0, 1.0)
			sb.set_border_width_all(0)
			dot.add_theme_stylebox_override("normal", sb)
			# Inside the button, at the end of its line: the dot has its own LTR layout, so the anchors are not mirrored
			# in Arabic (a mirrored dot used to hang over the screen edge and was cut off).
			dot.layout_direction = Control.LAYOUT_DIRECTION_LTR
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dot.custom_minimum_size = Vector2(22, 20)
			var at_left := Loc.is_rtl()
			dot.anchor_left = 0.0 if at_left else 1.0
			dot.anchor_right = dot.anchor_left
			dot.anchor_top = 0.5
			dot.anchor_bottom = 0.5
			dot.offset_left = 6.0 if at_left else -30.0
			dot.offset_right = 28.0 if at_left else -8.0
			dot.offset_top = -10.0
			dot.offset_bottom = 10.0
			(target as Node).add_child(dot)
		dot.text = Loc.num(n)


func _refresh_header() -> void:
	refresh_badges()
	var text := Loc.t("HUB_NO_CLUB_SELECTED")
	if app.user_team_id != "":
		var t: TeamData = app.db.get_team(app.user_team_id)
		if t != null:
			text = Loc.f("HUB_CLUB_RATING", [Loc.iso(t.display_name), app.db.get_team_rating(t.id)])
	if app.career != null:
		text += Loc.f("HUB_SEASON_WEEK", [app.career.season, app.career.week])
	# The line starts with a Latin club name: without an explicit paragraph direction the whole Arabic
	# line is laid out left-to-right and the week number lands at the far end ("... الأسبوع · Club").
	_team_label.text_direction = Control.TEXT_DIRECTION_RTL if Loc.is_rtl() else Control.TEXT_DIRECTION_AUTO
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
	if _current_host != null:
		_content.remove_child(_current_host)
		_current_host.queue_free()
	screen.hub = self
	screen.screen_id = screen_id
	screen.params = p
	current_params = p
	var host: Control = screen
	if not screen.own_scroll:
		var sc := ScrollContainer.new()
		sc.name = "ScreenScroll"
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		sc.follow_focus = true
		sc.scroll_deadzone = UIKit.SCROLL_DEADZONE
		sc.add_child(screen)
		host = sc
	_current_host = host
	_content.add_child(host)
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
	_current_host = null
	_build_frame()
	if id != "":
		navigate(id, p)
