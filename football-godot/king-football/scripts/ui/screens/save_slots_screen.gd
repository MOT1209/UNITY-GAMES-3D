extends HubScreen

const Wizard := preload("res://scripts/ui/screens/career_wizard_screen.gd")

## Career phase C9.5: five manual save slots plus the autosave, the quick save and the backup made before a new career.


func build() -> void:
	add_child(UIKit.title(Loc.t("NAV_SAVE_SLOTS")))
	for n in range(1, app().SLOT_COUNT + 1):
		add_child(_row(Loc.f("SLOT_N", n), app().slot_path(n), n, true, "Slot_%d" % n))
	add_child(_row(Loc.t("SLOT_AUTOSAVE"), app().AUTOSAVE_PATH, 0, false, "Slot_auto"))
	add_child(_row(Loc.t("SLOT_MANUAL"), app().SAVE_PATH, 0, false, "Slot_quick"))
	add_child(_row(Loc.t("SLOT_BACKUP"), app().BACKUP_PATH, 0, false, "Slot_backup"))


func _row(title_text: String, path: String, slot: int, can_save: bool, node_name: String) -> Control:
	var info: Dictionary = app().save_info(path)
	var box := UIKit.vbox(4)
	box.name = node_name
	box.add_child(UIKit.label(title_text, 16, UIKit.GOLD))
	if bool(info["exists"]):
		var world := Loc.t("SLOT_WORLD_DEFAULT") if str(info["pack_id"]) == "" else _pack_label(str(info["pack_id"]))
		var when := Time.get_datetime_string_from_unix_time(int(info["saved_unix"]), true)
		var line := UIKit.label(Loc.f("SLOT_INFO", [Loc.iso(str(info["club"])), int(info["season"]), int(info["week"]), world]), 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
		box.add_child(UIKit.muted(Loc.ltr(when)))
	else:
		box.add_child(UIKit.muted(Loc.t("SLOT_EMPTY")))
	var row := UIKit.hbox(UIKit.SPACE_S)
	if can_save:
		var sv := UIKit.button(Loc.t("SLOT_SAVE"), _save.bind(slot), 110)
		sv.name = "Save_%d" % slot
		sv.disabled = app().career == null
		row.add_child(sv)
	var ld := UIKit.button(Loc.t("SLOT_LOAD"), _load.bind(path), 110)
	ld.name = "Load_" + node_name
	ld.disabled = not bool(info["exists"])
	row.add_child(ld)
	box.add_child(row)
	return UIKit.panel(box)


func _pack_label(pid: String) -> String:
	for p in TeamDatabase.available_packs():
		if str(p["id"]) == pid:
			return Wizard.pack_name(pid, str(p.get("name", pid)))
	return pid


func _save(slot: int) -> void:
	var err: String = app().save_to_slot(slot)
	say(Loc.t("SLOT_SAVED") if err == "" else err, err != "")
	rebuild()


func _load(path: String) -> void:
	var err: String = app().load_game(path)
	say(Loc.t("SLOT_LOADED") if err == "" else err, err != "")
	if err == "":
		go("career")
