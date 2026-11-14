extends HubScreen

## Settings: language (applies immediately and is saved), game world, and the game options of
## `GameSettings` — sound, graphics, controls and the default match camera. Every change is saved to
## user://settings.cfg and applied at once (`GameSettings.apply_*`).


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_SETTINGS")))
	var columns := HFlowContainer.new()
	columns.name = "SettingsColumns"
	columns.add_theme_constant_override("h_separation", 12)
	columns.add_theme_constant_override("v_separation", 12)
	add_child(UIKit.scroll(columns))
	var box := UIKit.vbox(10)
	box.add_child(UIKit.label(Loc.t("SETTINGS_LANGUAGE"), 18, UIKit.GOLD))
	box.add_child(UIKit.muted(Loc.t("SETTINGS_LANGUAGE_HINT")))
	var picker := LanguagePicker.new()
	picker.name = "LanguagePicker"
	box.add_child(picker)
	box.add_child(UIKit.label(Loc.f("SETTINGS_DIRECTION", Loc.t("SETTINGS_DIRECTION_RTL") if Loc.is_rtl() else Loc.t("SETTINGS_DIRECTION_LTR")), 15))
	columns.add_child(_card(box))
	columns.add_child(_card(_audio()))
	columns.add_child(_card(_graphics()))
	columns.add_child(_card(_controls()))
	var world := WorldPicker.new()
	world.name = "WorldPicker"
	world.world_changed.connect(func(_id: String) -> void: say(Loc.t("SETTINGS_WORLD_SWITCHED")))
	columns.add_child(_card(world))


func _card(content: Control) -> Control:
	var p := UIKit.panel(content)
	p.custom_minimum_size = Vector2(380, 0)
	return p


func _heading(box: VBoxContainer, key: String) -> void:
	box.add_child(UIKit.label(Loc.t(key), 18, UIKit.GOLD))


## Labelled slider 0..100 % bound to a 0..1 setting.
func _volume(box: VBoxContainer, key: String, setting: String) -> void:
	var row := UIKit.hbox(8)
	var l := UIKit.label(Loc.t(key), 15, UIKit.MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.name = "Slider_%s" % setting
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = float(GameSettings.get_value("audio", setting)) * 100.0
	s.custom_minimum_size = Vector2(150, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := UIKit.label(Loc.percent(s.value / 100.0), 14, UIKit.GOLD)
	v.custom_minimum_size = Vector2(48, 0)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		GameSettings.set_value("audio", setting, x / 100.0)
		GameSettings.apply_audio()
		v.text = Loc.percent(x / 100.0))
	box.add_child(row)


## Labelled dropdown bound to a setting with a fixed list of values.
func _choice(box: VBoxContainer, key: String, section_name: String, setting: String, values: Array, labels: Array, apply: Callable) -> void:
	var row := UIKit.hbox(8)
	var l := UIKit.label(Loc.t(key), 15, UIKit.MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var o := UIKit.option(labels, maxi(values.find(GameSettings.get_value(section_name, setting)), 0), func(i: int) -> void:
		GameSettings.set_value(section_name, setting, values[i])
		if apply.is_valid():
			apply.call())
	o.name = "Option_%s" % setting
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(o)
	box.add_child(row)


func _toggle(box: VBoxContainer, key: String, section_name: String, setting: String, apply: Callable) -> void:
	var c := CheckButton.new()
	c.name = "Toggle_%s" % setting
	c.text = Loc.t(key)
	c.button_pressed = bool(GameSettings.get_value(section_name, setting))
	c.custom_minimum_size = Vector2(0, 40)
	c.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(section_name, setting, on)
		if apply.is_valid():
			apply.call())
	box.add_child(c)


func _audio() -> Control:
	var box := UIKit.vbox(8)
	box.name = "AudioSettings"
	_heading(box, "SETTINGS_SOUND")
	_volume(box, "SETTINGS_VOLUME_MASTER", "master")
	_volume(box, "SETTINGS_VOLUME_CROWD", "crowd")
	_volume(box, "SETTINGS_VOLUME_EFFECTS", "effects")
	return box


func _graphics() -> Control:
	var box := UIKit.vbox(8)
	box.name = "GraphicsSettings"
	_heading(box, "SETTINGS_GRAPHICS")
	var apply := func() -> void: GameSettings.apply_graphics(get_tree().root)
	_choice(box, "SETTINGS_SHADOWS", "graphics", "shadows", GameSettings.SHADOW_LEVELS,
			GameSettings.SHADOW_LEVELS.map(func(v: String) -> String: return Loc.enum_name("SHADOWS", v)), Callable())
	_choice(box, "SETTINGS_ANTIALIASING", "graphics", "msaa", GameSettings.MSAA_LEVELS,
			GameSettings.MSAA_LEVELS.map(func(v: int) -> String: return Loc.t("SETTINGS_OFF") if v == 0 else Loc.f("SETTINGS_MSAA_N", v)), apply)
	_choice(box, "SETTINGS_FPS", "graphics", "fps_cap", GameSettings.FPS_CAPS,
			GameSettings.FPS_CAPS.map(func(v: int) -> String: return Loc.f("SETTINGS_FPS_N", v)), apply)
	var scales := [0.5, 0.75, 1.0]
	_choice(box, "SETTINGS_RENDER_SCALE", "graphics", "render_scale", scales,
			scales.map(func(v: float) -> String: return Loc.percent(v)), apply)
	box.add_child(UIKit.muted(Loc.t("SETTINGS_SHADOWS_NEXT_MATCH")))
	return box


func _controls() -> Control:
	var box := UIKit.vbox(8)
	box.name = "ControlSettings"
	_heading(box, "SETTINGS_CONTROLS")
	_choice(box, "SETTINGS_SWITCH_MODE", "match", "switch_mode", GameSettings.SWITCH_MODES,
			GameSettings.SWITCH_MODES.map(func(m: String) -> String: return Loc.enum_name("SWITCHMODE", m)), Callable())
	_choice(box, "SETTINGS_DEFAULT_CAMERA", "match", "camera", GameSettings.CAMERA_MODES,
			[Loc.t("HUD_CAMERA_DYNAMIC"), Loc.t("HUD_CAMERA_BROADCAST")], Callable())
	_toggle(box, "SETTINGS_AIM_ASSIST", "controls", "aim_assist", Callable())
	_toggle(box, "SETTINGS_VIBRATION", "controls", "vibration", GameSettings.apply_controls)
	var sizes := [0.8, 1.0, 1.2, 1.4]
	_choice(box, "SETTINGS_TOUCH_SIZE", "controls", "touch_button_scale", sizes,
			sizes.map(func(v: float) -> String: return Loc.percent(v)), Callable())
	return box
