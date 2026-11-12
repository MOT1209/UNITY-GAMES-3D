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
			if cell is Control:
				grid.add_child(cell)          # e.g. UIKit.team_cell
			else:
				grid.add_child(label(str(cell), 15))
		if on_row.is_valid():
			grid.add_child(button(Loc.t("COMMON_OPEN"), on_row.bind(i)))
	return grid


## Crest of a club (TeamData or id) as a TextureRect of `px` x `px`; an empty spacer for teams
## without a club crest (national teams) so rows stay aligned. Textures come from the shared cache.
static func crest(db: Node, team: Variant, px: int = 28, variant: String = "icon") -> Control:
	var tex: Texture2D = CrestService.texture(db, team, variant) if db != null else null
	if tex == null:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(px, px)
		spacer.name = "NoCrest"
		return spacer
	var r := TextureRect.new()
	r.name = "Crest"
	r.set_meta("crest_club", t_id(team))      # lets tests and tools find crest controls whatever their node name
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func t_id(team: Variant) -> String:
	return (team as TeamData).id if team is TeamData else str(team)


## Crest + club name in one row (follows the language direction).
static func team_cell(db: Node, team_id: String, px: int = 22, color: Color = TEXT, font_size: int = 15) -> Control:
	var t: TeamData = db.get_team(team_id)
	var row := hbox(6)
	row.add_child(crest(db, t, px))
	row.add_child(label(t.display_name if t != null else team_id, font_size, color))
	return row


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
	box.add_child(label(Loc.t("COMMON_NOTHING_HERE_YET"), 18, MUTED))
	box.add_child(muted(text))
	return panel(box)


static func color_swatch(color: Color, size: Vector2 = Vector2(28, 28)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = size
	return r


## Kit preview: a drawn shirt, shorts and socks in the saved colours and pattern, with the club
## crest on the chest. `db` defaults to the TeamDB autoload.
static func kit_preview(team: TeamData, slot: String, db: Node = null) -> Control:
	var pv := KitEditor.preview(team, slot)
	var box := vbox(2)
	box.custom_minimum_size = Vector2(70, 0)
	if pv.is_empty():
		box.add_child(muted(Loc.f("KIT_NO_KIT", Loc.enum_name("KITSLOT", slot))))
		return box
	if db == null and Engine.get_main_loop() is SceneTree:
		db = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("TeamDB")
	var shirt := TextureRect.new()
	shirt.name = "KitShirt"
	shirt.texture = KitService.texture(db, team, slot)
	shirt.custom_minimum_size = Vector2(88, 112)
	shirt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shirt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shirt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shirt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(shirt)
	box.add_child(label("%s · %s" % [Loc.enum_name("KITSLOT", slot), Loc.enum_name("PATTERN", str(pv["pattern"]))], 12, MUTED))
	return box


## Modal confirmation for destructive actions. `host` = any Node in the tree.
static func confirm(host: Node, text: String, on_yes: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.dialog_text = text
	d.title = Loc.t("COMMON_CONFIRM")
	d.ok_button_text = Loc.t("COMMON_OK")
	d.cancel_button_text = Loc.t("COMMON_CANCEL")
	d.confirmed.connect(func() -> void:
		on_yes.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()
	return d
