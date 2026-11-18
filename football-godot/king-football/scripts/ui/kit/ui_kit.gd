class_name UIKit
extends RefCounted

## Reusable UI building blocks (Phase T10). Everything is built in code on top
## of standard Controls so screens share one look: consistent colours, spacing,
## empty / error / confirm states. Colours follow the main-menu palette.

## Pixels a touch drag must move before a ScrollContainer takes over (so taps on buttons still work).
const SCROLL_DEADZONE := 12
const BG := Color(0.05, 0.08, 0.15)
const PANEL := Color(0.09, 0.13, 0.22)
const GOLD := Color(0.93, 0.75, 0.3)
const TEXT := Color(0.85, 0.9, 0.97)
const MUTED := Color(0.55, 0.64, 0.78)
const GOOD := Color(0.35, 0.8, 0.5)
const BAD := Color(0.9, 0.35, 0.35)
## Unified theme (Nov 2026): every other colour of the UI has a name here, so a palette change is one edit.
const GOLD_BRIGHT := Color(1, 0.84, 0.3)          # selection rings, captain, highlights on the pitch
const WARN := Color(0.95, 0.78, 0.25)             # warnings, "fits with a penalty"
const NEUTRAL := Color(0.4, 0.45, 0.55)           # inactive markers, empty bars
const OVERLAY := Color(0.03, 0.05, 0.1, 1.0)      # full-screen panels (settings, pairing)
const SCRIM := Color(0, 0, 0, 0.72)               # dark veil behind dialogs
const CLEAR := Color(0, 0, 0, 0)
## Theme type variations (built by tools/build_theme.gd): set `theme_type_variation` instead of local styles.
const V_PRIMARY := &"PrimaryButton"              # gold call to action ("Play next match")
const V_ACTIVE := &"ActiveButton"                # the open screen in the sidebar / the open tab
const V_CARD_PANEL := &"CardPanel"               # panel with a gold rim (detail views)
## Spacing scale (UX phase 4.4): small / medium / large margins and gaps.
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24
## Type scale: body text, section headings, screen titles.
const FONT_S := 14
const FONT_M := 16
const FONT_L := 28
## The game's UI theme (built by tools/build_theme.gd); `Loc` adds the font stack to it.
const THEME_PATH := "res://resources/theme/main_theme.tres"


## One flat style box: background, border colour / width, corner radius, inner margin.
static func box(bg: Color, border: Color = CLEAR, border_w: int = 0, radius: int = 6, margin: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	if margin >= 0:
		s.set_content_margin_all(margin)
	return s


## Small rounded label background ("chip" / badge): tinted fill, coloured rim, horizontal / vertical margins.
static func chip(color: Color, radius: int = 8, h_margin: int = 8, v_margin: int = 2, fill_alpha: float = 0.16) -> StyleBoxFlat:
	var s := box(Color(color.r, color.g, color.b, fill_alpha), color, 1, radius)
	s.content_margin_left = h_margin
	s.content_margin_right = h_margin
	s.content_margin_top = v_margin
	s.content_margin_bottom = v_margin
	return s


## Opaque full-screen background (settings, language choice, pairing, match results).
static func overlay_box() -> StyleBoxFlat:
	return box(OVERLAY, CLEAR, 0, 0)


## Applies a theme variation (V_PRIMARY / V_ACTIVE ...) to a button; "" goes back to the plain button.
static func variant(b: Control, name: StringName) -> void:
	b.theme_type_variation = name


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
	p.add_theme_stylebox_override("panel", box(PANEL, CLEAR, 0, 6, 12))
	if child != null:
		p.add_child(child)
	return p


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.scroll_deadzone = SCROLL_DEADZONE
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
	if tex == null and team is String and TransferMarket.is_external(team):
		tex = CrestService.external_texture(team, variant)          # clubs outside the loaded leagues get a drawn crest
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
	var nm := label(Loc.iso(t.display_name if t != null else team_id), font_size, color)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(150, 0)
	row.add_child(nm)
	return row


## One fixture / result as a fixed row: [home name | home crest | score | away crest | away name]. The row is always laid
## out left to right (home on the left, as in the score "home - away"), so crests, names and goals never swap places in
## Arabic; the names are isolated so mixed-script names keep their own order.
static func fixture_row(db: Node, home_id: String, away_id: String, score_text: String = "", font_size: int = 14,
		dim: bool = false, highlight_id: String = "") -> Control:
	var row := HBoxContainer.new()
	row.name = "FixtureRow"
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in 2:
		var tid := home_id if i == 0 else away_id
		var t: TeamData = db.get_team(tid)
		var nm := label(Loc.iso(t.display_name if t != null else tid), font_size,
				GOLD if tid == highlight_id else (MUTED if dim else TEXT))
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_stretch_ratio = 1.0
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT
		var cr := crest(db, t, font_size + 6)
		if i == 0:
			row.add_child(nm)
			row.add_child(cr)
			var sc := label(score_text if score_text != "" else "–", font_size + 1, GOLD if score_text != "" else MUTED)
			sc.name = "FixtureScore"
			sc.text_direction = Control.TEXT_DIRECTION_LTR
			sc.language = "en"
			sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sc.custom_minimum_size = Vector2(maxf(54.0, font_size * 4.2), 0)
			var bg := PanelContainer.new()
			var sb := box(Color(0, 0, 0, 0.35) if score_text != "" else Color(0, 0, 0, 0.15), CLEAR, 0, 4)
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			bg.add_theme_stylebox_override("panel", sb)
			bg.add_child(sc)
			row.add_child(bg)
		else:
			row.add_child(cr)
			row.add_child(nm)
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


## Empty state: an illustration, the explanation and — when given — a button for the logical next step.
static func empty_state(text: String, action_text: String = "", action: Callable = Callable(), icon: String = "ball") -> Control:
	var row := hbox(SPACE_M)
	row.name = "EmptyState"
	var art := NavIcon.new(icon, 56.0)
	art.color = MUTED
	row.add_child(art)
	var box := vbox(4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label(Loc.t("COMMON_NOTHING_HERE_YET"), 18, MUTED))
	box.add_child(muted(text))
	if action_text != "" and action.is_valid():
		var b := button(action_text, action, 200)
		b.name = "EmptyStateAction"
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(b)
	row.add_child(box)
	return panel(row)


static func color_swatch(color: Color, size: Vector2 = Vector2(28, 28)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = size
	return r


## Kit preview: a drawn shirt, shorts and socks in the saved colours and pattern, with the club
## crest on the chest. `db` defaults to the TeamDB autoload.
static func kit_preview(team: TeamData, slot: String, db: Node = null, scale: int = 2) -> Control:
	var pv := KitEditor.preview(team, slot)
	var box := vbox(2)
	box.custom_minimum_size = Vector2(96, 0)
	if pv.is_empty():
		# One or two lines at most ("No third kit" wrapped onto three lines in a 70 px column).
		var none := muted(Loc.f("KIT_NO_KIT", Loc.enum_name("KITSLOT", slot)))
		none.custom_minimum_size = Vector2(96, 0)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
		return box
	if db == null and Engine.get_main_loop() is SceneTree:
		db = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("TeamDB")
	var shirt := TextureRect.new()
	shirt.name = "KitShirt"
	shirt.texture = KitService.texture(db, team, slot, scale)
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
