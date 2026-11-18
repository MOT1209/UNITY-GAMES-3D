extends HubScreen

## Career phase C9.1: the central inbox. Category tabs, unread marks, "needs a decision" badge and a direct action button.

var category := ""


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_INBOX")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	CareerFlow.sync(career)
	var tabs := HFlowContainer.new()
	tabs.name = "InboxTabs"
	var all := UIKit.button(Loc.t("INBOX_ALL"), _set_category.bind(""), 80)
	all.name = "Tab_all"
	tabs.add_child(all)
	for c in Inbox.CATEGORIES:
		var b := UIKit.button(Loc.t("INBOX_CAT_" + c.to_upper()), _set_category.bind(c), 80)
		b.name = "Tab_%s" % c
		tabs.add_child(b)
	add_child(tabs)
	var mark := UIKit.button(Loc.t("INBOX_MARK_ALL_READ"), _mark_all, 200)
	mark.name = "MarkAllRead"
	add_child(mark)
	var list := career.inbox.by_category(category)
	if list.is_empty():
		add_child(UIKit.empty_state(Loc.t("INBOX_EMPTY")))
		return
	for m: Dictionary in list.slice(0, 60):
		add_child(_row(m))


const CAT_ICON := {"board": "🏛", "players": "👤", "transfers": "🔁", "staff": "🧑‍💼", "medical": "🩺", "media": "🎙", "competitions": "🏆"}


## One compact line: unread dot, category icon, text with a muted meta line, small "open" button at the end.
func _row(m: Dictionary) -> Control:
	var unread := not bool(m["read"])
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.name = "Msg_%d" % int(m["id"])
	var dot := UIKit.label("●" if unread else " ", 12, UIKit.GOLD)
	dot.custom_minimum_size.x = 14
	row.add_child(dot)
	var icon := UIKit.label(str(CAT_ICON.get(str(m["category"]), "•")), 20)
	icon.custom_minimum_size.x = 30
	icon.tooltip_text = Loc.t("INBOX_CAT_" + str(m["category"]).to_upper())
	row.add_child(icon)
	var col := UIKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := UIKit.label(Loc.f(str(m["key"]), m["args"]), 15, UIKit.TEXT if unread else UIKit.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var meta := Loc.f("INBOX_WEEK_LINE", [int(m["season"]), int(m["week"])]) + "  ·  " + Loc.t("INBOX_CAT_" + str(m["category"]).to_upper())
	var decide := bool(m["needs_decision"]) and not bool(m["resolved"])
	if decide:
		meta += "  ·  " + Loc.t("INBOX_NEEDS_DECISION")
	col.add_child(UIKit.label(meta, 12, UIKit.BAD if decide else UIKit.MUTED))
	row.add_child(col)
	var action: Dictionary = m["action"]
	if not action.is_empty():
		var open := UIKit.button(Loc.t("INBOX_OPEN"), _open.bind(int(m["id"]), str(action.get("screen", "")), action.get("params", {})), 90)
		open.name = "Open_%d" % int(m["id"])
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(open)
	var p := UIKit.panel(row)
	p.name = "MsgPanel_%d" % int(m["id"])
	return p


func _set_category(c: String) -> void:
	category = c
	rebuild()


func _mark_all() -> void:
	(app().career as CareerState).inbox.mark_all_read()
	app().state_changed.emit()
	rebuild()


func _open(id: int, screen: String, params: Dictionary) -> void:
	(app().career as CareerState).inbox.mark_read(id)
	go(screen, params)
