class_name CountryPicker
extends Button

## A country field that stays one line tall: the button shows the chosen country; pressing it opens a fixed-size popup with
## a search field and a scrolling list (mouse wheel, drag and tap). Built for long lists (every country of the database),
## which a plain OptionButton drew as a menu taller than the screen. Item indexes are the caller's: `on_pick(i)` gets the
## index into the `labels` passed to `make`, whatever the search shows.

const POPUP_SIZE := Vector2i(380, 460)

var labels: Array = []
var selected := -1
var on_pick: Callable
var popup: PopupPanel
var search: LineEdit
var list: ItemList
var _shown: Array[int] = []           # list row -> caller index


static func make(p_labels: Array, p_selected: int, p_on_pick: Callable, node_name := "CountryPicker") -> CountryPicker:
	var b := CountryPicker.new()
	b.name = node_name
	b.labels = p_labels
	b.on_pick = p_on_pick
	b.custom_minimum_size = Vector2(220, 48)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.focus_mode = Control.FOCUS_ALL
	b._set_selected(p_selected)
	b.pressed.connect(b.open)
	return b


func _set_selected(i: int) -> void:
	selected = i
	text = "%s  ▾" % (str(labels[i]) if i >= 0 and i < labels.size() else Loc.t("COUNTRY_PICK"))


## Opens the popup below the button (inside the window; moved up when there is no room), the search field focused.
func open() -> void:
	if popup == null:
		_build_popup()
	search.text = ""
	filter("")
	var vp := get_viewport().get_visible_rect().size
	var sz := Vector2i(mini(POPUP_SIZE.x, int(vp.x) - 16), mini(POPUP_SIZE.y, int(vp.y) - 16))
	var at := Vector2i(get_screen_position() + Vector2(0, size.y + 4))
	at.x = clampi(at.x, 8, maxi(int(vp.x) - sz.x - 8, 8))
	if at.y + sz.y > int(vp.y) - 8:
		at.y = maxi(int(vp.y) - sz.y - 8, 8)
	popup.popup(Rect2i(at, sz))
	search.grab_focus()
	if selected >= 0:
		var row := _shown.find(selected)
		if row >= 0:
			list.select(row)
			list.ensure_current_is_visible()


func _build_popup() -> void:
	popup = PopupPanel.new()
	popup.name = "CountryPopup"
	var box := UIKit.vbox(6)
	search = LineEdit.new()
	search.name = "CountrySearch"
	search.placeholder_text = Loc.t("COUNTRY_SEARCH")
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 44.0
	search.text_changed.connect(filter)
	search.text_submitted.connect(func(_t: String) -> void:
		if not _shown.is_empty():
			pick(_shown[0]))
	box.add_child(search)
	list = ItemList.new()
	list.name = "CountryList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 200)
	list.allow_reselect = true
	list.item_selected.connect(func(row: int) -> void:
		if row < _shown.size():
			pick(_shown[row]))
	box.add_child(list)
	popup.add_child(box)
	add_child(popup)


## Shows the countries whose name contains `query` (case-insensitive); an empty query shows all.
func filter(query: String) -> void:
	if list == null:
		_build_popup()
	list.clear()
	_shown.clear()
	var q := query.strip_edges().to_lower()
	for i in labels.size():
		if q == "" or str(labels[i]).to_lower().contains(q):
			list.add_item(str(labels[i]))
			_shown.append(i)
	if _shown.is_empty():
		list.add_item(Loc.t("COUNTRY_NONE_FOUND"))
		list.set_item_disabled(0, true)
		list.set_item_selectable(0, false)


## Number of countries the search currently shows.
func shown_count() -> int:
	return _shown.size()


## Chooses caller index `i`, closes the popup and reports the choice.
func pick(i: int) -> void:
	if i < 0 or i >= labels.size():
		return
	_set_selected(i)
	if popup != null:
		popup.hide()
	if on_pick.is_valid():
		on_pick.call(i)
