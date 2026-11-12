class_name SquadPitch
extends Control

## Starting XI drawn as player cards on a dark pitch, placed by the formation's slot
## coordinates (attack upwards, own goal at the bottom, like a "team of the year" graphic).
## It only DISPLAYS the lineup and reports clicks: all edits go through `Squad` in the screen.
## The pitch is drawn with `_draw()` and the control is pinned LTR, so Arabic (RTL) never
## mirrors the formation; card TEXT still follows the active language.

signal slot_pressed(slot: int, player_id: String)

const BG := Color(0.055, 0.058, 0.065)
const LINE := Color(1, 1, 1, 0.55)
const MARGIN := 10.0
const MAX_CARD := 120.0
const TAG_H := 16.0

var db: Node
var formation_id := "4-3-3"
var starting: Array = []
var captain_id := ""
var _cards: Array = []        # per slot: {card, hit, tag}


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	custom_minimum_size = Vector2(620, 700)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	clip_contents = true
	resized.connect(_layout)


## Builds one card per slot from the live PlayerData (no private copies).
func setup(p_db: Node, p_formation: String, p_starting: Array, p_captain: String) -> void:
	db = p_db
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
		tag.text = "%s%s" % [PlayerData.Position.keys()[FormationData.slot_position(formation_id, i)],
				"  C" if pid != "" and pid == captain_id else ""]
		tag.add_theme_font_size_override("font_size", 12)
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
		add_child(hit)
		_cards.append({"card": card, "hit": hit, "tag": tag})
	_layout()
	queue_redraw()


## Largest card width (<= MAX_CARD) at which no two cards (plus their position tag) overlap.
func card_width() -> float:
	var cw := MAX_CARD
	while cw > 40.0:
		if not _overlaps(cw):
			return cw
		cw -= 2.0
	return 40.0


func _overlaps(cw: float) -> bool:
	var half := Vector2(cw, cw * PlayerCard.ASPECT + TAG_H) * 0.5 + Vector2(3, 3)
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
	var ch := cw * PlayerCard.ASPECT
	var left := MARGIN + cw * 0.5
	var right := size.x - MARGIN - cw * 0.5
	var top := MARGIN + ch * 0.5
	var bottom := size.y - MARGIN - ch * 0.5 - TAG_H
	return Vector2(lerpf(left, right, (float(s[1]) + 1.0) * 0.5), lerpf(bottom, top, float(s[2]) / 0.9))


func _layout() -> void:
	var cw := card_width()
	var ch := cw * PlayerCard.ASPECT
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
		var tag: Label = e["tag"]
		tag.size = Vector2(cw + 20.0, 16.0)
		tag.position = Vector2(c.x - (cw + 20.0) * 0.5, card.position.y + ch + 1.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
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
