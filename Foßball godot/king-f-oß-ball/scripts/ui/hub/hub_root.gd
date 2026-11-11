class_name HubRoot
extends Control

## Management hub (Phase T10): navigation bar + content area + message bar.
## Scene: ui/hub/hub.tscn. Screens are created on demand from `ScreenRegistry`.

var app: Node
var current_id: String = ""
var current: HubScreen = null
var history: Array[String] = []

var _content: PanelContainer
var _message: Label
var _nav: VBoxContainer
var _team_label: Label


func _ready() -> void:
	app = get_node("/root/AppHub")
	_build_frame()
	app.state_changed.connect(_refresh_header)
	var start_id := "team_select" if app.user_team_id == "" else "career"
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
	_team_label = UIKit.label("", 16, UIKit.GOLD)
	root.add_child(_team_label)
	var body := UIKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_nav = UIKit.vbox(4)
	var nav_scroll := UIKit.scroll(_nav)
	nav_scroll.custom_minimum_size = Vector2(210, 0)
	nav_scroll.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(nav_scroll)
	for id in ScreenRegistry.SCREENS:
		if id in ScreenRegistry.NAV_HIDDEN:
			continue
		var b := UIKit.button(ScreenRegistry.SCREENS[id][0], navigate.bind(id), 200)
		b.name = "Nav_%s" % id
		_nav.add_child(b)
	var menu_btn := UIKit.button("Main Menu", _to_main_menu, 200)
	menu_btn.name = "Nav_main_menu"
	_nav.add_child(menu_btn)
	_content = UIKit.panel()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	_message = UIKit.label("", 15, UIKit.MUTED)
	root.add_child(_message)
	_refresh_header()


func _refresh_header() -> void:
	var text := "No club selected"
	if app.user_team_id != "":
		var t: TeamData = app.db.get_team(app.user_team_id)
		if t != null:
			text = "%s  ·  rating %d" % [t.display_name, app.db.get_team_rating(t.id)]
	if app.career != null:
		text += "  ·  Season %d, week %d" % [app.career.season, app.career.week]
	_team_label.text = text
	if app.last_message != "":
		say(app.last_message)
		app.last_message = ""


## Opens a screen. Unknown ids are reported instead of crashing.
func navigate(screen_id: String, p: Dictionary = {}) -> bool:
	var screen := ScreenRegistry.create(screen_id)
	if screen == null:
		say("Unknown screen '%s'" % screen_id, true)
		return false
	if current != null:
		_content.remove_child(current)
		current.queue_free()
	screen.hub = self
	screen.params = p
	_content.add_child(screen)
	screen.rebuild()
	current = screen
	current_id = screen_id
	history.append(screen_id)
	_refresh_header()
	return true


func say(text: String, is_error: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UIKit.BAD if is_error else UIKit.GOOD)


func _to_main_menu() -> void:
	get_node("/root/GameManager").return_to_menu()
