class_name HubScreen
extends VBoxContainer

## Base class of every management screen (Phase T10). Screens are built in
## code from `UIKit` components, read/write the shared `AppHub` state and
## navigate through the `HubRoot`. Override `build()`.

var hub: Control            # HubRoot
var params: Dictionary = {}
## True for screens that lay out their own ScrollContainer (header fixed, body scrolls). All other
## screens are wrapped by `HubRoot.navigate()` in a vertical ScrollContainer so nothing is ever cut off.
var own_scroll := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func app() -> Node:
	return hub.app


func db() -> Node:
	return hub.app.db


func rebuild() -> void:
	var keep := _outer_scroll()
	var keep_pos := keep.scroll_vertical if keep != null else 0
	for c in get_children():
		remove_child(c)
		c.queue_free()      # deferred: rebuild() is often called from a child's own signal
	build()
	if keep != null and keep_pos > 0:
		_restore_scroll.call_deferred(keep, keep_pos)


## The ScrollContainer the hub wrapped around this screen (null for `own_scroll` screens).
func _outer_scroll() -> ScrollContainer:
	return get_parent() as ScrollContainer


func _restore_scroll(sc: ScrollContainer, pos: int) -> void:
	if not is_instance_valid(sc):
		return
	await get_tree().process_frame     # the rebuilt content gets its size first
	if is_instance_valid(sc):
		sc.scroll_vertical = pos


func build() -> void:
	pass


func go(screen_id: String, p: Dictionary = {}) -> void:
	hub.navigate(screen_id, p)


func say(text: String, is_error: bool = false) -> void:
	hub.say(ErrorText.localize(text, db()) if is_error else text, is_error)


## Adds the standard screen title; returns false (after an empty state) when
## the screen needs a selected team and none is chosen.
func header(title_text: String, needs_team: bool = false, needs_career: bool = false) -> bool:
	add_child(UIKit.title(title_text))
	if needs_team and app().user_team_id == "":
		add_child(UIKit.empty_state(Loc.t("HUB_SELECT_TEAM_FIRST"), Loc.t("HUB_GO_TEAM_SELECTION"), go.bind("team_select"), "shirt"))
		return false
	if needs_career and app().career == null:
		add_child(UIKit.empty_state(Loc.t("HUB_START_CAREER_FIRST"), Loc.t("SCREEN_CAREER_WIZARD"), go.bind("career_wizard"), "trophy"))
		return false
	return true


func team_names(category: int = -1) -> Array:
	var out: Array = []
	for t: TeamData in db().list_teams(category):
		out.append(t.display_name)
	return out


func team_id_at(index: int, category: int = -1) -> String:
	var list: Array = db().list_teams(category)
	if index < 0 or index >= list.size():
		return ""
	return (list[index] as TeamData).id


func overall_text(p: PlayerData) -> String:
	return Loc.ratio(p.get_overall(), p.potential)
