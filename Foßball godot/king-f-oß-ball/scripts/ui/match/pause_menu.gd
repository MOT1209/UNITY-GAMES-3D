class_name PauseMenu
extends Control

## In-match pause menu (Phase 7.2). Pausing uses `SceneTree.paused`: the match scene (pausable) stops
## simulating — physics, AI, clock — while this overlay (`PROCESS_MODE_ALWAYS`) keeps running.
## Resume / Match settings / Controls / Save match / Restart (confirmed) / Quit to menu (confirmed).
## Everything is reachable with keyboard or gamepad (focus + ui_accept); `pause` / `ui_cancel` resumes.

signal resume_requested
signal restart_requested
signal quit_requested
signal save_requested

const CONTROL_ACTIONS: Array[String] = ["move_forward", "move_backward", "move_left", "move_right", "sprint", "pass",
		"shoot", "lob_pass", "dribble", "switch_player", "camera_toggle", "pause"]

var manager: Node            # MatchManager (difficulty, save)
var _main: Control
var _sub: Control
var _resume: Button


static func create(p_manager: Node) -> PauseMenu:
	var m := PauseMenu.new()
	m.manager = p_manager
	m.name = "PauseMenu"
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	m._build()
	return m


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel()
	center.add_child(panel)
	var col := UIKit.vbox(10)
	col.custom_minimum_size = Vector2(380, 0)
	panel.add_child(col)
	col.add_child(UIKit.label(Loc.t("PAUSE_TITLE"), 30, CardCategory.GOLD))
	_main = UIKit.vbox(8)
	col.add_child(_main)
	_sub = UIKit.vbox(8)
	_sub.visible = false
	col.add_child(_sub)
	_resume = _button("PAUSE_RESUME", func() -> void: resume_requested.emit(), "ResumeButton")
	_button("PAUSE_SETTINGS", _show_settings, "SettingsButton")
	_button("PAUSE_CONTROLS", _show_controls, "ControlsButton")
	if manager != null and manager.has_method("save_match"):
		_button("PAUSE_SAVE", func() -> void: save_requested.emit(), "SaveButton")
	_button("PAUSE_RESTART", func() -> void: UIKit.confirm(self, Loc.t("PAUSE_RESTART_CONFIRM"), func() -> void: restart_requested.emit()), "RestartButton")
	_button("PAUSE_QUIT", func() -> void: UIKit.confirm(self, Loc.t("PAUSE_QUIT_CONFIRM"), func() -> void: quit_requested.emit()), "QuitButton")
	_resume.grab_focus.call_deferred()


func _button(key: String, cb: Callable, node_name: String) -> Button:
	var b := UIKit.button(Loc.t(key), cb, 300)
	b.name = node_name
	_main.add_child(b)
	return b


func _show_sub(title_key: String) -> void:
	for c in _sub.get_children():
		_sub.remove_child(c)        # removed first: a queued-for-deletion sibling would rename the new nodes
		c.queue_free()
	_main.visible = false
	_sub.visible = true
	_sub.add_child(UIKit.label(Loc.t(title_key), 20, UIKit.GOLD))


func _back_button() -> void:
	var b := UIKit.button(Loc.t("PAUSE_BACK"), _show_main, 200)
	b.name = "BackButton"
	_sub.add_child(b)
	b.grab_focus.call_deferred()


func _show_main() -> void:
	_sub.visible = false
	_main.visible = true
	_resume.grab_focus.call_deferred()


func _show_settings() -> void:
	_show_sub("PAUSE_SETTINGS")
	_sub.add_child(UIKit.label(Loc.t("SETUP_DIFFICULTY"), 15, UIKit.MUTED))
	var names: Array = MatchSetup.DIFFICULTIES.map(func(d: String) -> String: return Loc.enum_name("DIFFICULTY", d))
	var opt := UIKit.option(names, manager.setup.difficulty if manager != null else 1, func(i: int) -> void:
		if manager != null:
			manager.setup.difficulty = i)
	opt.name = "DifficultyOption"
	_sub.add_child(opt)
	_sub.add_child(UIKit.label(Loc.t("SETTINGS_LANGUAGE"), 15, UIKit.MUTED))
	var picker := LanguagePicker.new()
	picker.name = "LanguagePicker"
	_sub.add_child(picker)
	_back_button()


func _show_controls() -> void:
	_show_sub("PAUSE_CONTROLS")
	var grid := GridContainer.new()
	grid.name = "ControlsList"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for action in CONTROL_ACTIONS:
		if not InputMap.has_action(action):
			continue
		grid.add_child(UIKit.label(Loc.t("CONTROL_" + action.to_upper()), 14))
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			keys.append(ev.as_text().replace(" (Physical)", ""))
		var l := UIKit.label(" · ".join(keys), 14, UIKit.MUTED)
		l.text_direction = Control.TEXT_DIRECTION_LTR
		grid.add_child(l)
	_sub.add_child(grid)
	_back_button()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _sub.visible:
			_show_main()
		else:
			resume_requested.emit()
