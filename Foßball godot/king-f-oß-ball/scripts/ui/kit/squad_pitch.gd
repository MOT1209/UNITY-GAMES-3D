class_name SquadPitch
extends Control

## Starting XI drawn as player cards on a dark pitch, placed by the formation's slot
## coordinates (attack upwards, own goal at the bottom, like a "team of the year" graphic).
## It only DISPLAYS the lineup and reports clicks: all edits go through `Squad` in the screen.
## The pitch is drawn with `_draw()` and the control is pinned LTR, so Arabic (RTL) never
## mirrors the formation; card TEXT still follows the active language.

signal slot_pressed(slot: int, player_id: String)
## Drag and drop (desktop): `from` / `to` are {"kind": "slot"|"bench"|"reserve", "slot": int, "pid": String}.
signal swap_requested(from: Dictionary, to: Dictionary)

## Grass green with alternating mown stripes (was near-black); white lines.
const BG := Color(0.13, 0.42, 0.2)
const STRIPE := Color(0.15, 0.47, 0.23)
const STRIPES := 10
const LINE := Color(1, 1, 1, 0.7)
const MARGIN := 10.0
const MAX_CARD := 120.0
const TAG_H := 14.0
## Pitch cards are a little wider than the standalone card (1.4) so four lines of players fit a 0.78 pitch.
const CARD_ASPECT := 1.2
## Share of the pitch height between the goalkeeper and the first outfield line.
const GK_GAP := 0.2
## Formation x coordinates are spread a little wider than the data: the wings sit nearer the touchlines, which
## frees width for bigger cards on a narrow pitch.
const X_STRETCH := 1.15

var db: Node
var formation_id := "4-3-3"
var starting: Array = []
var captain_id := ""
var roles: Dictionary = {}    # set-piece kind ("penalty", "free_kick", "corner") -> player id (badges)
var _cards: Array = []        # per slot: {card, hit, tag, ring}


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	# The pitch takes whatever space its parent gives it (the squad screen keeps it at a 0.75-0.8 ratio);
	# card size and slot positions are computed from the real size in `_layout()`.
	custom_minimum_size = Vector2(280, 330)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	resized.connect(_layout)


## Builds one card per slot from the live PlayerData (no private copies).
func setup(p_db: Node, p_formation: String, p_starting: Array, p_captain: String, p_roles: Dictionary = {}) -> void:
	db = p_db
	roles = p_roles
	formation_id = p_formation
	starting = p_starting
	captain_id = p_captain
	for c in get_children():
		c.queue_free()
	_cards.clear()
	var slots := FormationData.slots(formation_id)
	for i in slots.size():
		var pid := str(starting[i]) if i < starting.size() else ""
		var card := PlayerCard.new(80.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.minimal = true
		card.name = "PitchCard_%d" % i
		add_child(card)
		card.setup(PlayerCardData.from_player(db, pid) if pid != "" and db.get_player(pid) != null else null, db)
		var tag := Label.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.text = "%s%s" % [Loc.position_code(FormationData.slot_position(formation_id, i)), _badges(pid)]
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(1, 0.84, 0.3) if pid != "" and pid == captain_id else Color(1, 1, 1, 0.8))
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 4)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(tag)
		var hit := Button.new()
		hit.flat = true
		# The theme gives buttons a fill that would hide the card: keep only a hover/focus outline.
		var clear := StyleBoxEmpty.new()
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0)
		ring.set_border_width_all(2)
		ring.border_color = Color(1, 0.84, 0.3)
		ring.set_corner_radius_all(6)
		for state in ["normal", "pressed", "disabled"]:
			hit.add_theme_stylebox_override(state, clear)
		for state in ["hover", "focus", "hover_pressed"]:
			hit.add_theme_stylebox_override(state, ring)
		hit.name = "PitchSlot_%d" % i
		hit.focus_mode = Control.FOCUS_ALL
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.pressed.connect(func() -> void: slot_pressed.emit(i, pid))
		hit.set_drag_forwarding(_drag_slot.bind(i, pid, hit), _can_drop.bind(i), _drop_on_slot.bind(i, pid))
		add_child(hit)
		var mark := Panel.new()          # selection / position-fit marker around the card
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.name = "Mark_%d" % i
		mark.visible = false
		add_child(mark)
		_cards.append({"card": card, "hit": hit, "tag": tag, "ring": mark})
	_layout()
	queue_redraw()


## Position code plus role badges: "  C P FK CK" (captain, penalty, free kick, corner taker).
func _badges(pid: String) -> String:
	if pid == "":
		return ""
	var parts: Array = []
	if pid == captain_id:
		parts.append(Loc.t("SQUAD_CAPTAIN_SHORT"))
	if roles.get("penalty", "") == pid:
		parts.append(Loc.t("SQUAD_BADGE_PENALTY"))
	if roles.get("free_kick", "") == pid:
		parts.append(Loc.t("SQUAD_BADGE_FREE_KICK"))
	if roles.get("corner", "") == pid:
		parts.append(Loc.t("SQUAD_BADGE_CORNER"))
	return "" if parts.is_empty() else "  " + " ".join(parts)


## Marks the selected slot (gold ring) and, per slot, a position-fit colour (`fits`: slot -> Color) for the
## slots a chosen substitute could fill. `selected` -1 = none; empty `fits` = no fit colours.
func set_marks(selected: int, fits: Dictionary) -> void:
	for i in _cards.size():
		var ring: Panel = _cards[i]["ring"]
		var col := Color(0, 0, 0, 0)
		var width := 0
		if fits.has(i):
			col = fits[i]
			width = 3
		if i == selected:
			col = Color(1, 0.84, 0.3)
			width = 4
		ring.visible = width > 0
		if width > 0:
			var st := StyleBoxFlat.new()
			st.bg_color = Color(col.r, col.g, col.b, 0.12)
			st.border_color = col
			st.set_border_width_all(width)
			st.set_corner_radius_all(6)
			ring.add_theme_stylebox_override("panel", st)


## Rect of a slot's card in the pitch's own coordinates (for layout checks).
func card_rect(slot: int) -> Rect2:
	var h: Button = _cards[slot]["hit"]
	return Rect2(h.position, h.size)


func _drag_slot(_at: Vector2, slot: int, pid: String, src: Control) -> Variant:
	if pid == "" or db == null or db.get_player(pid) == null:
		return null
	var l := Label.new()
	l.text = db.get_player(pid).display_name
	l.add_theme_color_override("font_color", Color(1, 0.84, 0.3))
	src.set_drag_preview(l)
	return {"squad_drag": true, "kind": "slot", "slot": slot, "pid": pid}


func _can_drop(_at: Vector2, data: Variant, slot: int) -> bool:
	return data is Dictionary and data.get("squad_drag", false) and not (data.get("kind") == "slot" and data.get("slot") == slot)


func _drop_on_slot(_at: Vector2, data: Variant, slot: int, pid: String) -> void:
	swap_requested.emit(data, {"kind": "slot", "slot": slot, "pid": pid})


## Largest card width (<= MAX_CARD) at which no two cards (plus their position tag) overlap.
func card_width() -> float:
	var cw := MAX_CARD
	while cw > 40.0:
		if not _overlaps(cw):
			return cw
		cw -= 2.0
	return 40.0


func _overlaps(cw: float) -> bool:
	var half := Vector2(cw, cw * CARD_ASPECT + TAG_H) * 0.5 + Vector2(3, 3)
	var n := FormationData.slots(formation_id).size()
	for i in n:
		var a := Rect2(slot_center(i, cw) - half, half * 2.0)
		for j in range(i + 1, n):
			if a.intersects(Rect2(slot_center(j, cw) - half, half * 2.0)):
				return true
	return false


func slot_center(slot: int, cw: float = -1.0) -> Vector2:
	var s: Array = FormationData.slots(formation_id)[slot]
	if cw < 0.0:
		cw = card_width()
	var ch := cw * CARD_ASPECT
	var left := MARGIN + cw * 0.5
	var right := size.x - MARGIN - cw * 0.5
	var top := MARGIN + ch * 0.5
	var bottom := size.y - MARGIN - ch * 0.5 - TAG_H
	return Vector2(lerpf(left, right, (clampf(float(s[1]) * X_STRETCH, -1.0, 1.0) + 1.0) * 0.5), lerpf(bottom, top, _depth(slot, float(s[2]))))


## Vertical position 0 (own goal line) .. 1 (top) of a slot. The keeper keeps a fixed gap to the first
## outfield line and the outfield lines are spread over the rest, so the cards of a short pitch never overlap.
func _depth(slot: int, y: float) -> float:
	if slot == 0:
		return 0.0
	var ymin := 1.0
	var ymax := 0.0
	for k in range(1, FormationData.slots(formation_id).size()):
		var yy := float(FormationData.slots(formation_id)[k][2])
		ymin = minf(ymin, yy)
		ymax = maxf(ymax, yy)
	return GK_GAP + (1.0 - GK_GAP) * (y - ymin) / maxf(ymax - ymin, 0.05)


func _layout() -> void:
	var cw := card_width()
	var ch := cw * CARD_ASPECT
	for i in _cards.size():
		var c: Vector2 = slot_center(i, cw)
		var e: Dictionary = _cards[i]
		var card: PlayerCard = e["card"]
		card.custom_minimum_size = Vector2(cw, ch)
		card.size = Vector2(cw, ch)
		card.position = c - Vector2(cw, ch) * 0.5
		card.relayout()
		var hit: Button = e["hit"]
		hit.size = Vector2(cw, ch)
		hit.position = card.position
		var ring: Panel = e["ring"]
		ring.size = Vector2(cw, ch) + Vector2(6, 6)
		ring.position = card.position - Vector2(3, 3)
		var tag: Label = e["tag"]
		tag.size = Vector2(cw + 20.0, TAG_H)
		tag.position = Vector2(c.x - (cw + 20.0) * 0.5, card.position.y + ch + 1.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
	var band := size.y / STRIPES
	for i in range(0, STRIPES, 2):
		draw_rect(Rect2(0.0, i * band, size.x, band), STRIPE)
	var f := r.grow(-MARGIN * 0.5)
	draw_rect(f, LINE, false, 2.0)
	var mid := f.position.y + f.size.y * 0.5
	draw_line(Vector2(f.position.x, mid), Vector2(f.end.x, mid), LINE, 1.5)
	draw_arc(Vector2(f.position.x + f.size.x * 0.5, mid), f.size.x * 0.13, 0.0, TAU, 48, LINE, 1.5)
	draw_circle(Vector2(f.position.x + f.size.x * 0.5, mid), 3.0, LINE)
	var pw := f.size.x * 0.58
	var ph := f.size.y * 0.15
	var gw := f.size.x * 0.28
	var gh := f.size.y * 0.055
	var cx := f.position.x + f.size.x * 0.5
	draw_rect(Rect2(cx - pw * 0.5, f.position.y, pw, ph), LINE, false, 1.5)
	draw_rect(Rect2(cx - gw * 0.5, f.position.y, gw, gh), LINE, false, 1.5)
	draw_rect(Rect2(cx - pw * 0.5, f.end.y - ph, pw, ph), LINE, false, 1.5)
	draw_rect(Rect2(cx - gw * 0.5, f.end.y - gh, gw, gh), LINE, false, 1.5)
	draw_arc(Vector2(cx, f.position.y + ph), f.size.x * 0.1, 0.15 * PI, 0.85 * PI, 24, LINE, 1.5)
	draw_arc(Vector2(cx, f.end.y - ph), f.size.x * 0.1, 1.15 * PI, 1.85 * PI, 24, LINE, 1.5)
