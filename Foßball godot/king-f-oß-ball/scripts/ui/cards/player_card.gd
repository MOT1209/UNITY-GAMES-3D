class_name PlayerCard
extends Control

## The KING FOOTBALL player card (Phase V5): ONE reusable control for all five
## categories. Compose: CardFrame (background + frame + decoration + effect),
## portrait, rating, position, name, club/nationality, six-attribute grid.
##
## It displays a `PlayerCardData` built from the live PlayerData and re-reads it
## on `refresh()`, so it never holds a private copy of the player. Layout is
## resolution independent: everything is placed from fractions of the control
## size, fonts scale with the width, long names shrink to fit (never clip).
## Text direction follows the active language (Arabic RTL, German/English LTR).

signal pressed(player_id: String)

const ASPECT := 1.4               # height / width
const MIN_NAME_FONT := 9

var data: PlayerCardData
var db: Node
## Compact cards (lists/grids) skip animation; `animate` is for the detail view.
var compact := true

var _frame: CardFrame
var _portrait: TextureRect
var _silhouette: Control
var _ovr: Label
var _pos: Label
var _name: Label
var _club: Label
var _gk: Label
var _stat_labels: Array = []      # [{code: Label, value: Label}]
var _grid: Control
var _token := 0
var _portrait_pending := false


func _init(card_width: float = 180.0) -> void:
	custom_minimum_size = Vector2(card_width, card_width * ASPECT)
	# The card is a fixed brand layout placed from absolute fractions: pin it to LTR so an
	# RTL root (Arabic) does not mirror the child positions. Arabic TEXT still shapes RTL.
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build()


## Shows `card` (null = empty placeholder card).
func setup(card: PlayerCardData, database: Node) -> void:
	data = card
	db = database
	refresh()


## Rebuilds the card from `PlayerData` again (call after the player changed).
func refresh(player: PlayerData = null) -> void:
	if db != null and data != null and not data.player_id.is_empty():
		var fresh := PlayerCardData.from_player(db, data.player_id, data.kit_slot)
		if fresh != null:
			data = fresh
	elif player != null and db != null:
		data = PlayerCardData.from_data(db, player)
	_apply()


## Texts currently shown (for tests and accessibility): ovr, position, name,
## club line, gk line and the six {code, value} pairs.
func texts() -> Dictionary:
	var stats: Array = []
	for s in _stat_labels:
		stats.append({"code": (s["code"] as Label).text, "value": (s["value"] as Label).text})
	return {"ovr": _ovr.text, "position": _pos.text, "name": _name.text, "club": _club.text,
			"gk": _gk.text, "stats": stats, "has_portrait": _portrait.texture != null}


## Font size the name label ended up with after fitting (tests: no clipping).
func name_font_size() -> int:
	return _name.get_theme_font_size("font_size")


func name_label() -> Label:
	return _name


func _build() -> void:
	clip_contents = false
	_frame = CardFrame.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_silhouette = Control.new()
	_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silhouette.draw.connect(_draw_silhouette)
	add_child(_silhouette)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_ovr = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_pos = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_name = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_club = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_gk = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	for i in 6:
		var code := _make_label(HORIZONTAL_ALIGNMENT_CENTER, _grid)
		var value := _make_label(HORIZONTAL_ALIGNMENT_CENTER, _grid)
		_stat_labels.append({"code": code, "value": value})
	resized.connect(_layout)
	gui_input.connect(_on_gui_input)
	_layout()


func _make_label(align: int, parent: Node = null) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align as HorizontalAlignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	(parent if parent != null else self).add_child(l)
	return l


func _font(l: Label, px: float, color: Color, bold_outline := false) -> void:
	l.add_theme_font_size_override("font_size", maxi(roundi(px), 6))
	l.add_theme_color_override("font_color", color)
	if bold_outline:
		l.add_theme_constant_override("outline_size", maxi(roundi(px / 14.0), 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x * size.x, y * size.y)
	c.size = Vector2(w * size.x, h * size.y)


func _layout() -> void:
	if _stat_labels.is_empty():
		return
	_place(_silhouette, 0.18, 0.08, 0.64, 0.54)
	_place(_portrait, 0.16, 0.07, 0.68, 0.56)
	_place(_ovr, 0.07, 0.07, 0.22, 0.12)
	_place(_pos, 0.07, 0.19, 0.22, 0.06)
	_place(_name, 0.06, 0.625, 0.88, 0.07)
	_place(_gk, 0.05, 0.255, 0.30, 0.05)
	_place(_club, 0.06, 0.90, 0.88, 0.045)
	_place(_grid, 0.0, 0.715, 1.0, 0.18)
	for i in 6:
		var col := i % 3
		var row := i / 3
		var cw := 0.84 / 3.0
		var x := 0.08 + col * cw
		var y := row * 0.5
		_place_in(_stat_labels[i]["code"], x, y, cw * 0.5, 0.5)
		_place_in(_stat_labels[i]["value"], x + cw * 0.5, y, cw * 0.5, 0.5)
	_apply_fonts()
	_silhouette.queue_redraw()


func _place_in(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x * size.x, y * _grid.size.y)
	c.size = Vector2(w * size.x, h * _grid.size.y)


func _apply_fonts() -> void:
	var w := maxf(size.x, 1.0)
	var th := CardCategory.theme(data.category if data != null else CardCategory.Kind.BRONZE)
	var text: Color = th["text"]
	var accent: Color = th["accent"]
	_font(_ovr, w * 0.17, accent if th["red"] == false else CardCategory.GOLD, true)
	_font(_pos, w * 0.075, text)
	_font(_club, w * 0.062, text.darkened(0.15))
	_font(_gk, w * 0.062, CardCategory.GOLD if th["red"] else accent)
	for s in _stat_labels:
		_font(s["code"], w * 0.058, text.darkened(0.2))
		_font(s["value"], w * 0.085, text, true)
	_fit_name()


## Shrinks the name font until it fits the label width (no clipping for long
## Latin or Arabic names); only at the minimum size does it end with an ellipsis.
func _fit_name() -> void:
	var th := CardCategory.theme(data.category if data != null else CardCategory.Kind.BRONZE)
	var px := size.x * 0.095
	var font := _name.get_theme_font("font")
	var avail := _name.size.x
	var text := _name.text
	if font != null and avail > 0.0:
		while px > MIN_NAME_FONT and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(px)).x > avail:
			px -= 1.0
	_font(_name, px, th["text"], true)


func _apply() -> void:
	_token += 1
	var empty := data == null
	var kind: int = CardCategory.Kind.BRONZE if empty else data.category
	_frame.kind = kind
	_frame.animate = not compact and not empty
	_ovr.text = "--" if empty else Loc.num(data.overall)
	_pos.text = "" if empty else data.position
	_name.text = "—" if empty else data.name
	var line := ""
	if not empty:
		line = data.nationality if data.club == "" else "%s · %s" % [data.club, data.nationality]
	_club.text = line
	_gk.text = "" if empty or not data.is_goalkeeper else "%s %s" % [Loc.t("CARD_STAT_GK"), Loc.num(data.goalkeeping)]
	for i in 6:
		var s: Dictionary = _stat_labels[i]
		(s["code"] as Label).text = "" if empty else Loc.t("CARD_STAT_" + str(data.stats[i]["code"]))
		(s["value"] as Label).text = "" if empty else Loc.num(int(data.stats[i]["value"]))
	tooltip_text = "" if empty else "%s — %s %s" % [data.name, Loc.t(CardCategory.loc_key(kind)), Loc.num(data.overall)]
	_portrait.texture = null
	_silhouette.visible = true
	_apply_fonts()
	_silhouette.queue_redraw()
	if not empty:
		_load_portrait(_token)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _portrait_pending:
		_portrait_pending = false
		_load_portrait(_token)


func _load_portrait(token: int) -> void:
	if db == null or data == null:
		return
	if not is_inside_tree():
		_portrait_pending = true          # screens call setup() before adding the card
		return
	var r := PlayerPortraitRenderer.shared(get_tree())
	var tex: Texture2D = r.cached(data, db)
	if tex == null:
		tex = await r.request(data, db)
	if token != _token or not is_inside_tree() or tex == null:
		return                       # card changed or freed meanwhile / no GPU: keep silhouette
	_portrait.texture = tex
	_silhouette.visible = false


func _draw_silhouette() -> void:
	var s := _silhouette.size
	var col := Color(1, 1, 1, 0.10)
	_silhouette.draw_circle(Vector2(s.x * 0.5, s.y * 0.34), s.x * 0.17, col)
	_silhouette.draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.18, s.y), Vector2(s.x * 0.24, s.y * 0.6),
			Vector2(s.x * 0.76, s.y * 0.6), Vector2(s.x * 0.82, s.y)]), col)


func _on_gui_input(event: InputEvent) -> void:
	var activate: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE))
	if activate and data != null:
		pressed.emit(data.player_id)
		accept_event()
