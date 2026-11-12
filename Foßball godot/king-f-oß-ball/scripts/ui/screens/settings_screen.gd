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
	add_child(UIKit.panel(_world_box()))


## Default fictional world or a data pack (real leagues). Switching ends the running career.
func _world_box() -> Control:
	var box := UIKit.vbox(8)
	box.add_child(UIKit.label(Loc.t("SETTINGS_WORLD"), 18, UIKit.GOLD))
	var packs := TeamDatabase.available_packs()
	var names: Array = [Loc.t("SETTINGS_WORLD_DEFAULT")]
	var ids: Array = [""]
	for p in packs:
		names.append(str(p.get("name", p["id"])))
		ids.append(p["id"])
	var current: int = maxi(ids.find(db().pack_id), 0)
	var opt := UIKit.option(names, current, func(i: int) -> void:
		if ids[i] == db().pack_id:
			return
		if app().career != null:
			UIKit.confirm(self, Loc.t("SETTINGS_WORLD_CONFIRM"), _switch.bind(ids[i]))
		else:
			_switch(ids[i]))
	opt.name = "WorldOption"
	box.add_child(opt)
	if db().pack_id != "":
		box.add_child(UIKit.muted(str(db().pack_info.get("rating_note", ""))))
		box.add_child(UIKit.muted(str(db().pack_info.get("generated_note", ""))))
		box.add_child(UIKit.muted(Loc.t("SETTINGS_WORLD_SOURCES")))
	return box


func _switch(pack_id: String) -> void:
	var err: String = app().switch_world(pack_id)
	say(err if err != "" else Loc.t("SETTINGS_WORLD_SWITCHED"), err != "")
	rebuild()
