class_name WorldPicker
extends VBoxContainer

## Game-world choice (default fictional world or a data pack such as real leagues), shared by the
## hub's Settings screen and the main-menu Settings panel. Switching ends a running career, so it
## asks first when one exists. Emits `world_changed` after a successful switch.

signal world_changed(pack_id: String)

var _ids: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var app: Node = get_node("/root/AppHub")
	var db: Node = app.db
	add_child(UIKit.label(Loc.t("SETTINGS_WORLD"), 18, UIKit.GOLD))
	add_child(UIKit.muted(Loc.t("SETTINGS_WORLD_HINT")))
	var names: Array = [Loc.t("SETTINGS_WORLD_DEFAULT")]
	_ids = [""]
	for p in TeamDatabase.available_packs():
		names.append(str(p.get("name", p["id"])))
		_ids.append(p["id"])
	var opt := UIKit.option(names, maxi(_ids.find(db.pack_id), 0), _on_selected)
	opt.name = "WorldOption"
	add_child(opt)
	if db.pack_id != "":
		add_child(UIKit.muted(str(db.pack_info.get("rating_note", ""))))
		add_child(UIKit.muted(str(db.pack_info.get("generated_note", ""))))
		add_child(UIKit.muted(Loc.t("SETTINGS_WORLD_SOURCES")))


func _on_selected(index: int) -> void:
	var app: Node = get_node("/root/AppHub")
	var pack_id: String = _ids[index]
	if pack_id == app.db.pack_id:
		return
	if app.career != null:
		UIKit.confirm(self, Loc.t("SETTINGS_WORLD_CONFIRM"), _switch.bind(pack_id))
	else:
		_switch(pack_id)


func _switch(pack_id: String) -> void:
	var app: Node = get_node("/root/AppHub")
	var err: String = app.switch_world(pack_id)
	if err == "":
		world_changed.emit(pack_id)
	_build()
