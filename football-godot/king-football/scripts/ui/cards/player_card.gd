class_name PlayerCard
extends Control

## The KING FOOTBALL player card: ONE reusable control for all five categories and both sizes.
##
## Full card (round 3, C1) — vertical, width : height = 1 : 1.4 (~0.7):
##   * first top corner: rating (big), position, national flag, club crest
##   * centre: the 3D portrait, chest up, head and shoulders never cropped (aspect kept), on a gradient
##     panel in the category colour
##   * name bar: last name (shrinks to fit; ellipsis only at the minimum size) + shirt number
##   * 2 x 3 attribute grid: big value + fixed 3-letter abbreviation (muted) under it — goalkeepers get
##     their goalkeeper set
##   * footer: club · league on one line (ellipsis)
##   * badges in the other top corner when they apply: injured, suspended, on loan, captain, youth (U21),
##     potential arrow (potential >= rating + 5)
## Minimal card (C2, squad pitch / lists): rating, position, small flag, portrait and last name only.
##
## The layout is placed from fractions of the control size (resolution independent). It is a brand layout
## pinned LTR so containers never shuffle it, and it mirrors ITSELF in RTL languages: the rating corner moves
## to the right in Arabic (`_rtl`). It displays a `PlayerCardData` built from the live PlayerData and re-reads
## it on `refresh()`, so it never holds a private copy of the player.

signal pressed(player_id: String)

const ASPECT := 1.4               # height / width (width : height ~ 0.71)
const MIN_NAME_FONT := 9
## Goalkeeper attribute set, in display order: [abbreviation key, PlayerData attribute].
const GK_CORE := [["GKP", "goalkeeping"], ["DEF", "defending"], ["PHY", "physical"],
		["PAS", "passing"], ["PAC", "pace"], ["DRI", "dribbling"]]
const BADGE_KINDS := ["injured", "suspended", "loan", "captain", "youth", "potential"]

var data: PlayerCardData
var db: Node
## Compact cards (lists/grids) skip animation; `animate` is for the detail view.
var compact := true
## Minimal cards (e.g. on the squad pitch): portrait, rating, position, flag and last name only.
var minimal := false

var _frame: CardFrame
var _panel: Control          # gradient panel behind the portrait
var _portrait: TextureRect
var _silhouette: Control
var _ovr: Label
var _pos: Label
var _flag: TextureRect
var _crest: TextureRect
var _name: Label
var _number: Label
var _club: Label
var _gk: Label               # kept for texts()["gk"]; never shown (the goalkeeper set is in the grid)
var _badges: Control
var _stat_labels: Array = []      # [{code: Label, value: Label}]
var _grid: Control
var _token := 0
var _rtl := false
var _portrait_pending := false
## Extra render attempts for a portrait whose first frames came out empty.
const PORTRAIT_RETRIES := 5
var _waiting_key := ""          # portrait key this card waits for (see PlayerPortraitRenderer.portrait_ready)


func _init(card_width: float = 180.0) -> void:
	custom_minimum_size = Vector2(card_width, card_width * ASPECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_PASS      # drags that start on a card still scroll the screen
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
		var captain := data.is_captain
		var fresh := PlayerCardData.from_player(db, data.player_id, data.kit_slot)
		if fresh != null:
			fresh.is_captain = captain
			data = fresh
	elif player != null and db != null:
		data = PlayerCardData.from_data(db, player)
	_apply()


## Texts currently shown (tests, accessibility). `name` is the player's full name (the card's identity, also the
## tooltip); `shown_name` is what the name bar displays (the last name). `club` is the footer line.
func texts() -> Dictionary:
	var stats: Array = []
	for s in _stat_labels:
		stats.append({"code": (s["code"] as Label).text, "value": (s["value"] as Label).text})
	return {"ovr": _ovr.text, "position": _pos.text, "name": data.full_name if data != null else _name.text,
			"shown_name": _name.text, "number": _number.text, "club": _club.text, "gk": _gk.text, "stats": stats,
			"has_portrait": _portrait.texture != null, "has_flag": _flag.texture != null and _flag.visible,
			"has_crest": _crest.texture != null and _crest.visible, "badges": badge_kinds()}


## Font size the name label ended up with after fitting (tests: no clipping).
func name_font_size() -> int:
	return _name.get_theme_font_size("font_size")


func name_label() -> Label:
	return _name


## Visible badge kinds, in display order.
func badge_kinds() -> Array:
	var out: Array = []
	for b in _badges.get_children():
		if (b as Control).visible:
			out.append(str(b.get_meta("kind")))
	return out


## Rect of the portrait area (card coordinates) — the 3D head must project inside it.
func portrait_rect() -> Rect2:
	return Rect2(_portrait.position, _portrait.size)


## Every text / image node that must stay inside the card (layout tests).
func content_nodes() -> Array:
	var out: Array = [_ovr, _pos, _name, _flag, _portrait]
	if not minimal:
		out.append_array([_crest, _number, _club, _badges])
		for s in _stat_labels:
			out.append_array([s["value"], s["code"]])
	return out


func _build() -> void:
	clip_contents = false
	_frame = CardFrame.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_panel = Control.new()
	_panel.name = "PortraitPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_silhouette = Control.new()
	_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silhouette.draw.connect(_draw_silhouette)
	add_child(_silhouette)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT (not COVERED): the whole rendered head-and-shoulders picture is shown, never cropped.
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_ovr = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_ovr.name = "Rating"
	_pos = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_pos.name = "Position"
	_flag = TextureRect.new()
	_flag.name = "CountryFlag"
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_flag)
	_crest = TextureRect.new()
	_crest.name = "ClubCrest"
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_crest)
	_name = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_name.name = "NameLabel"
	_number = _make_label(HORIZONTAL_ALIGNMENT_RIGHT)
	_number.name = "ShirtNumber"
	_club = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_club.name = "ClubLine"
	_gk = Label.new()
	_gk.visible = false
	add_child(_gk)
	_badges = Control.new()
	_badges.name = "Badges"
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badges)
	for kind in BADGE_KINDS:
		var b := Control.new()
		b.name = "Badge_" + kind
		b.set_meta("kind", kind)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.visible = false
		b.draw.connect(_draw_badge.bind(b))
		_badges.add_child(b)
	_grid = Control.new()
	_grid.name = "StatGrid"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	for i in 6:
		var value := _make_label(HORIZONTAL_ALIGNMENT_CENTER, _grid)
		var code := _make_label(HORIZONTAL_ALIGNMENT_CENTER, _grid)
		value.name = "StatValue_%d" % i
		code.name = "StatCode_%d" % i
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


## Places `c` at fractions of the card size; in RTL the x axis is mirrored (rating corner on the right).
func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	var xx := (1.0 - x - w) if _rtl else x
	c.position = Vector2(xx * size.x, y * size.y)
	c.size = Vector2(w * size.x, h * size.y)


## Same, with the size in pixels (square crest, 3:2 flag) centred in a column of the card.
func _place_px(c: Control, col_x: float, col_w: float, y: float, px: Vector2) -> void:
	var x := col_x * size.x + (col_w * size.x - px.x) * 0.5
	if _rtl:
		x = size.x - x - px.x
	c.position = Vector2(x, y * size.y)
	c.size = px


## The rating corner below the rating: position, flag and crest stacked in PIXELS (font height + gap), so they can never overlap
## whatever the card's aspect (the pitch cards are shorter than the 2:3 card; fractions of the height let the flag cover "RB").
func _stack_corner(col_x: float, col_w: float, top_frac: float, pos_font_px: float, flag_px: Vector2, crest_px: Vector2) -> void:
	var y := top_frac * size.y
	var pos_h := pos_font_px * 1.3
	var xx := (1.0 - col_x - col_w) if _rtl else col_x
	_pos.position = Vector2(xx * size.x, y)
	_pos.size = Vector2(col_w * size.x, pos_h)
	y += pos_h + size.x * 0.015
	_place_px(_flag, col_x, col_w, y / maxf(size.y, 1.0), flag_px)
	y += flag_px.y + size.x * 0.03
	if crest_px != Vector2.ZERO:
		_place_px(_crest, col_x, col_w, y / maxf(size.y, 1.0), crest_px)


## Re-places every child from the current size. Needed when a parent that is not a Container
## sets `size` directly (e.g. SquadPitch): `resized` is not emitted when the size already equals
## the minimum size.
func relayout() -> void:
	_layout()


func _layout() -> void:
	if _stat_labels.is_empty():
		return
	_rtl = Loc.is_rtl()
	_grid.visible = not minimal
	_crest.visible = not minimal and _crest.texture != null
	_club.visible = not minimal
	_number.visible = not minimal
	_badges.visible = not minimal
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if minimal else (HORIZONTAL_ALIGNMENT_RIGHT if _rtl else HORIZONTAL_ALIGNMENT_LEFT)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _rtl else HORIZONTAL_ALIGNMENT_RIGHT
	var w := size.x
	if minimal:
		_place(_panel, 0.05, 0.035, 0.90, 0.70)
		_place(_silhouette, 0.20, 0.07, 0.72, 0.64)
		_place(_portrait, 0.18, 0.04, 0.78, 0.69)
		_place(_ovr, 0.04, 0.025, 0.32, 0.21)
		_stack_corner(0.04, 0.32, 0.025 + 0.21, w * 0.085, Vector2(w * 0.24, w * 0.16), Vector2.ZERO)
		_place(_name, 0.03, 0.765, 0.94, 0.19)
	else:
		_place(_panel, 0.055, 0.035, 0.89, 0.525)
		_place(_silhouette, 0.32, 0.08, 0.58, 0.47)
		_place(_portrait, 0.26, 0.04, 0.70, 0.515)
		_place(_ovr, 0.05, 0.03, 0.25, 0.155)
		var flag_px := Vector2(w * 0.135, w * 0.135 * 19.0 / 28.0)     # 28 x 19 at a 207 px card
		var crest_px := Vector2(w * 0.13, w * 0.13)                      # 26 x 26 at a 200 px card
		_stack_corner(0.05, 0.25, 0.03 + 0.155, w * 0.064, flag_px, crest_px)
		_place(_name, 0.06, 0.563, 0.70, 0.092)
		_place(_number, 0.76, 0.563, 0.18, 0.092)
		_place(_grid, 0.06, 0.664, 0.88, 0.232)
		_place(_club, 0.06, 0.896, 0.88, 0.052)
		_layout_badges()
	# 3 columns x 2 rows: big value, fixed 3-letter abbreviation centred under it (fixed spacing).
	for i in 6:
		var col := i % 3
		var row := i / 3
		var cx := col / 3.0
		if _rtl:
			cx = 1.0 - cx - 1.0 / 3.0
		var v: Label = _stat_labels[i]["value"]
		var c: Label = _stat_labels[i]["code"]
		v.position = Vector2(cx * _grid.size.x, row * 0.5 * _grid.size.y)
		v.size = Vector2(_grid.size.x / 3.0, _grid.size.y * 0.30)
		c.position = Vector2(cx * _grid.size.x, row * 0.5 * _grid.size.y + _grid.size.y * 0.30)
		c.size = Vector2(_grid.size.x / 3.0, _grid.size.y * 0.20)
	_apply_fonts()
	_silhouette.queue_redraw()
	_panel.queue_redraw()


## Badges stack down the top corner opposite the rating (only the visible ones take a slot).
func _layout_badges() -> void:
	var bs := size.x * 0.115
	var gap := size.x * 0.02
	var x := 0.83 * size.x
	if _rtl:
		x = size.x - x - bs
	_badges.position = Vector2(x, 0.045 * size.y)
	var shown := 0
	for b: Control in _badges.get_children():
		if b.visible:
			b.position = Vector2(0, shown * (bs + gap))
			b.size = Vector2(bs, bs)
			shown += 1
	_badges.size = Vector2(bs, maxf(shown * (bs + gap) - gap, 0.0))


func _apply_fonts() -> void:
	var w := maxf(size.x, 1.0)
	var th := CardCategory.theme(data.category if data != null else CardCategory.Kind.BRONZE)
	var text: Color = th["text"]
	var muted: Color = th["muted"]
	_font(_ovr, w * (0.18 if minimal else 0.15), th["rating"], true)
	_font(_pos, w * (0.085 if minimal else 0.064), text)
	_font(_club, w * 0.048, muted)
	_font(_number, w * 0.058, muted)
	var code_px := _fit_codes(w * 0.046)
	for s in _stat_labels:
		_font(s["code"], code_px, muted)
		_font(s["value"], w * 0.07, text, true)
	_fit_name()


## Largest abbreviation font size (<= `px`) at which every abbreviation fits its cell (min 7 px).
func _fit_codes(px: float) -> float:
	var font := (_stat_labels[0]["code"] as Label).get_theme_font("font")
	var avail := (_stat_labels[0]["code"] as Label).size.x - 2.0
	if font == null or avail <= 0.0:
		return px
	while px > 7.0:
		var fits := true
		for s in _stat_labels:
			if font.get_string_size((s["code"] as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(px)).x > avail:
				fits = false
				break
		if fits:
			break
		px -= 0.5
	return px


## Shrinks the name font until it fits the label width (no clipping for long Latin or Arabic names);
## only at the minimum size does it end with an ellipsis.
func _fit_name() -> void:
	var th := CardCategory.theme(data.category if data != null else CardCategory.Kind.BRONZE)
	var px := size.x * (0.15 if minimal else 0.088)
	var font := _name.get_theme_font("font")
	var avail := _name.size.x - 2.0
	var text := _name.text
	if font != null and avail > 0.0:
		while px > MIN_NAME_FONT and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(px)).x > avail:
			px -= 1.0
	_font(_name, px, th["text"], true)


func _apply() -> void:
	_token += 1
	_waiting_key = ""
	var empty := data == null
	var kind: int = CardCategory.Kind.BRONZE if empty else data.category
	_frame.kind = kind
	_frame.animate = not compact and not empty
	_ovr.text = "--" if empty else Loc.num(data.overall)
	_pos.text = "" if empty else data.position
	_name.text = "—" if empty else data.last_name
	_number.text = "" if empty or data.shirt_number <= 0 else Loc.num(data.shirt_number)
	var line := ""
	if not empty:
		var club := data.club_name if data.club_name != "" else Loc.t("PROFILE_FREE_AGENT")
		line = Loc.iso(club) if data.league_name == "" else "%s · %s" % [Loc.iso(club), Loc.iso(data.league_name)]
	_club.text = line
	_gk.text = "" if empty or not data.is_goalkeeper else "%s %s" % [Loc.t("CARD_STAT_GK"), Loc.num(data.goalkeeping)]
	var set_: Array = GK_CORE if not empty and data.is_goalkeeper else PlayerCardData.CORE
	for i in 6:
		var s: Dictionary = _stat_labels[i]
		(s["code"] as Label).text = "" if empty else Loc.t("CARD_ABBR_" + str(set_[i][0]))
		(s["value"] as Label).text = "" if empty else Loc.num(_attr(set_[i][1]))
	tooltip_text = "" if empty else "%s — %s %s · %s" % [Loc.iso(data.full_name), Loc.t(CardCategory.loc_key(kind)), Loc.num(data.overall), data.country_name]
	_flag.texture = null if empty else data.flag
	_flag.visible = not empty
	_flag.tooltip_text = "" if empty else data.country_name
	_crest.texture = null if empty or minimal else data.club_crest
	var shown: Array = [] if empty else data.badges()
	for b: Control in _badges.get_children():
		var k := str(b.get_meta("kind"))
		b.visible = k in shown
		b.tooltip_text = Loc.t("CARD_BADGE_" + k.to_upper())
		b.queue_redraw()
	_layout()
	_portrait.texture = null
	_silhouette.visible = true
	_apply_fonts()
	_silhouette.queue_redraw()
	if not empty:
		_load_portrait(_token)


func _attr(attr: String) -> int:
	if data == null:
		return 0
	if attr == "goalkeeping":
		return data.goalkeeping
	for s in data.stats:
		if s["attr"] == attr:
			return int(s["value"])
	return 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _portrait_pending:
		_portrait_pending = false
		_load_portrait(_token)
	elif what == NOTIFICATION_TRANSLATION_CHANGED and data != null and is_inside_tree():
		_layout()


func _load_portrait(token: int) -> void:
	if db == null or data == null:
		return
	if not is_inside_tree():
		_portrait_pending = true          # screens call setup() before adding the card
		return
	var r := PlayerPortraitRenderer.shared(get_tree())
	var key := data.portrait_key(db)
	var tex: Texture2D = r.cached(data, db)
	var tries := 0
	while tex == null:
		tex = await r.request(data, db)
		if token != _token or not is_inside_tree():
			return                       # card changed or freed meanwhile
		# A fresh viewport can fail its first frames: try again a few times instead of leaving the grey silhouette.
		if tex != null or not PlayerPortraitRenderer.can_render() or tries >= PORTRAIT_RETRIES:
			break
		tries += 1
		await get_tree().create_timer(0.25).timeout
		if token != _token or not is_inside_tree():
			return
		tex = r.cached(data, db)
	if token != _token or not is_inside_tree():
		return
	if tex == null:
		# Not ready (busy renderer / empty first frame): show the portrait as soon as it is rendered.
		_waiting_key = key
		if PlayerPortraitRenderer.can_render() and not r.portrait_ready.is_connected(_on_portrait_ready):
			r.portrait_ready.connect(_on_portrait_ready)
		return
	_portrait.texture = tex
	_silhouette.visible = false


func _on_portrait_ready(key: String, tex: Texture2D) -> void:
	if key != _waiting_key or not is_inside_tree():
		return
	_waiting_key = ""
	var r := PlayerPortraitRenderer.shared(get_tree())
	if r.portrait_ready.is_connected(_on_portrait_ready):
		r.portrait_ready.disconnect(_on_portrait_ready)
	_portrait.texture = tex
	_silhouette.visible = false


## Gradient panel in the category colour behind the portrait (top lighter, fading into the card).
func _draw_panel() -> void:
	var th := CardCategory.theme(data.category if data != null else CardCategory.Kind.BRONZE)
	var s := _panel.size
	var top: Color = th["panel_top"]
	var bottom: Color = th["panel_bottom"]
	var steps := 12
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var c := top.lerp(bottom, (t0 + t1) * 0.5)
		_panel.draw_rect(Rect2(0, s.y * t0, s.x, s.y * (t1 - t0) + 0.5), c)
	# soft spotlight behind the head
	var spot := (th["frame"] as Color)
	spot.a = 0.10
	_panel.draw_circle(Vector2(s.x * (0.42 if _rtl else 0.58), s.y * 0.38), s.x * 0.30, spot)
	var line := (th["frame"] as Color)
	line.a = 0.55
	_panel.draw_line(Vector2(0, s.y - 1), Vector2(s.x, s.y - 1), line, maxf(1.0, s.x / 200.0))


func _draw_silhouette() -> void:
	var s := _silhouette.size
	var col := Color(1, 1, 1, 0.10)
	_silhouette.draw_circle(Vector2(s.x * 0.5, s.y * 0.34), s.x * 0.17, col)
	_silhouette.draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.18, s.y), Vector2(s.x * 0.24, s.y * 0.6),
			Vector2(s.x * 0.76, s.y * 0.6), Vector2(s.x * 0.82, s.y)]), col)


## One badge: a dark disc with a simple drawn symbol (no icon font needed, same in every language).
func _draw_badge(b: Control) -> void:
	var s := b.size.x
	if s < 2.0:
		return
	var c := Vector2(s, s) * 0.5
	var kind := str(b.get_meta("kind"))
	var ring := {"injured": Color("#e5484d"), "suspended": Color("#e5484d"), "loan": Color("#4cc2ff"),
			"captain": CardCategory.GOLD, "youth": Color("#7ee081"), "potential": Color("#7ee081")}.get(kind, Color.WHITE) as Color
	b.draw_circle(c, s * 0.5, Color(0.05, 0.05, 0.06, 0.88))
	b.draw_arc(c, s * 0.46, 0.0, TAU, 24, ring, maxf(1.0, s * 0.08), true)
	var u := s / 20.0
	match kind:
		"injured":       # medical cross
			b.draw_rect(Rect2(c.x - 1.6 * u, c.y - 5.5 * u, 3.2 * u, 11 * u), ring)
			b.draw_rect(Rect2(c.x - 5.5 * u, c.y - 1.6 * u, 11 * u, 3.2 * u), ring)
		"suspended":     # red card
			b.draw_rect(Rect2(c.x - 3.2 * u, c.y - 5 * u, 6.4 * u, 10 * u), ring)
		"loan":          # two opposite arrows
			b.draw_line(c + Vector2(-5, -2) * u, c + Vector2(5, -2) * u, ring, 1.6 * u)
			b.draw_line(c + Vector2(5, -2) * u, c + Vector2(2.5, -4.5) * u, ring, 1.6 * u)
			b.draw_line(c + Vector2(-5, 2.5) * u, c + Vector2(5, 2.5) * u, ring, 1.6 * u)
			b.draw_line(c + Vector2(-5, 2.5) * u, c + Vector2(-2.5, 5) * u, ring, 1.6 * u)
		"captain":       # armband "C"
			b.draw_arc(c, 4.6 * u, 0.25 * PI, 1.75 * PI, 16, ring, 2.0 * u, true)
		"youth":         # sprout: stem + two leaves
			b.draw_line(c + Vector2(0, 5) * u, c + Vector2(0, -2) * u, ring, 1.6 * u)
			b.draw_circle(c + Vector2(-2.6, -3) * u, 2.2 * u, ring)
			b.draw_circle(c + Vector2(2.6, -1.5) * u, 2.2 * u, ring)
		"potential":     # up arrow
			b.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6) * u, c + Vector2(5, 0) * u, c + Vector2(-5, 0) * u]), ring)
			b.draw_rect(Rect2(c.x - 1.6 * u, c.y, 3.2 * u, 5.5 * u), ring)


func _on_gui_input(event: InputEvent) -> void:
	var activate: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE))
	if activate and data != null:
		pressed.emit(data.player_id)
		accept_event()
