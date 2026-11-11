class_name UIKit
extends RefCounted

## Reusable UI building blocks (Phase T10). Everything is built in code on top
## of standard Controls so screens share one look: consistent colours, spacing,
## empty / error / confirm states. Colours follow the main-menu palette.

const BG := Color(0.05, 0.08, 0.15)
const PANEL := Color(0.09, 0.13, 0.22)
const GOLD := Color(0.93, 0.75, 0.3)
const TEXT := Color(0.85, 0.9, 0.97)
const MUTED := Color(0.55, 0.64, 0.78)
const GOOD := Color(0.35, 0.8, 0.5)
const BAD := Color(0.9, 0.35, 0.35)


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String) -> Label:
	return label(text, 28, GOLD)


static func muted(text: String) -> Label:
	var l := label(text, 14, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, callback: Callable = Callable(), min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if min_width > 0.0:
		b.custom_minimum_size = Vector2(min_width, 36)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func panel(child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", style)
	if child != null:
		p.add_child(child)
	return p


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Table: headers + rows (Array of Arrays). Optional per-row click callback(row_index).
static func table(headers: Array, rows: Array, on_row: Callable = Callable()) -> Control:
	var grid := GridContainer.new()
	grid.columns = headers.size() + (1 if on_row.is_valid() else 0)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for h in headers:
		grid.add_child(label(str(h), 14, GOLD))
	if on_row.is_valid():
		grid.add_child(label("", 14))
	for i in rows.size():
		for cell in rows[i]:
			grid.add_child(label(str(cell), 15))
		if on_row.is_valid():
			grid.add_child(button("Open", on_row.bind(i)))
	return grid


static func stat_bar(stat_name: String, value: int, max_value: int = 99) -> Control:
	var row := hbox(8)
	var l := label(stat_name, 14, MUTED)
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 18)
	row.add_child(bar)
	row.add_child(label(str(value), 14))
	return row


## Dropdown with string items. Returns the OptionButton (`selected` = index).
static func option(items: Array, selected: int = 0, on_changed: Callable = Callable()) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	if on_changed.is_valid():
		o.item_selected.connect(on_changed)
	return o


static func empty_state(text: String) -> Control:
	var box := vbox(4)
	box.add_child(label("Nothing here yet", 18, MUTED))
	box.add_child(muted(text))
	return panel(box)


static func color_swatch(color: Color, size: Vector2 = Vector2(28, 28)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = size
	return r


## Kit preview built from the saved kit dictionary (shirt, shorts, socks, number).
static func kit_preview(team: TeamData, slot: String) -> Control:
	var pv := KitEditor.preview(team, slot)
	var box := vbox(2)
	box.custom_minimum_size = Vector2(70, 0)
	if pv.is_empty():
		box.add_child(muted("no %s kit" % slot))
		return box
	var shirt := color_swatch(pv["main"], Vector2(60, 48))
	var stripe := color_swatch(pv["secondary"], Vector2(60, 8))
	var shorts := color_swatch(pv["shorts"], Vector2(60, 24))
	var socks := color_swatch(pv["socks"], Vector2(60, 20))
	for c in [shirt, stripe, shorts, socks]:
		box.add_child(c)
	box.add_child(label("%s · %s" % [slot, pv["pattern"]], 12, MUTED))
	return box


## Modal confirmation for destructive actions. `host` = any Node in the tree.
static func confirm(host: Node, text: String, on_yes: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.dialog_text = text
	d.confirmed.connect(func() -> void:
		on_yes.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()
	return d
