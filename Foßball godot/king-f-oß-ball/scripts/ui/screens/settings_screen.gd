extends HubScreen

## Settings: language (applies immediately and is saved) and a short read-out
## of the active text direction / font stack.


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_SETTINGS")))
	var box := UIKit.vbox(10)
	box.add_child(UIKit.label(Loc.t("SETTINGS_LANGUAGE"), 18, UIKit.GOLD))
	box.add_child(UIKit.muted(Loc.t("SETTINGS_LANGUAGE_HINT")))
	var picker := LanguagePicker.new()
	picker.name = "LanguagePicker"
	box.add_child(picker)
	box.add_child(UIKit.label(Loc.f("SETTINGS_DIRECTION", Loc.t("SETTINGS_DIRECTION_RTL") if Loc.is_rtl() else Loc.t("SETTINGS_DIRECTION_LTR")), 15))
	add_child(UIKit.panel(box))
	var world := WorldPicker.new()
	world.name = "WorldPicker"
	world.world_changed.connect(func(_id: String) -> void: say(Loc.t("SETTINGS_WORLD_SWITCHED")))
	add_child(UIKit.panel(world))
