## UI layout validation (UX phase 3): every hub screen in Arabic and English at 1280x720 (desktop) and
## 1600x720 (a 2400x1080 phone: the project stretches canvas_items with aspect "expand", so the logical
## canvas is 1600x720) must fit horizontally, must not clip text without an ellipsis, and every
## navigation button must be touch-sized. Latin text in Arabic is covered by `arabic_ui_validation`.
##   godot --headless --path . res://tests/ui_layout_validation.tscn
extends Node

const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720)]
const LANGS: Array[String] = ["ar", "en"]

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — UI layout validation ===")
	app = get_node("/root/AppHub")
	app.db.load_world("")
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career("club_royal_harbor")
	for code in LANGS:
		for sz in SIZES:
			await _test_all_screens(code, sz)
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _params(id: String) -> Dictionary:
	if id == "player_profile":
		return {"player_id": app.db.get_team("club_royal_harbor").squad_ids[0]}
	if id == "kit_editor" or id == "team_details":
		return {"team_id": "club_royal_harbor"}
	return {}


## Text of a Label / Button that is cut off without an ellipsis ("" = fine).
func _clipped(c: Control) -> String:
	if not c.is_visible_in_tree() or c.size.x <= 1.0:
		return ""
	var text := ""
	var clip := false
	var overrun := TextServer.OVERRUN_NO_TRIMMING
	var font_size := 16
	if c is Label:
		var l := c as Label
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return ""
		text = l.text
		clip = l.clip_text
		overrun = l.text_overrun_behavior
		font_size = l.get_theme_font_size("font_size")
	elif c is Button and not (c is OptionButton):
		var b := c as Button
		if b.autowrap_mode != TextServer.AUTOWRAP_OFF:
			return ""
		text = b.text
		clip = b.clip_text
		overrun = b.text_overrun_behavior
		font_size = b.get_theme_font_size("font_size")
	else:
		return ""
	if text == "" or (not clip and overrun == TextServer.OVERRUN_NO_TRIMMING):
		return ""      # unclipped text makes its control grow instead (caught by the width check)
	if overrun != TextServer.OVERRUN_NO_TRIMMING:
		return ""      # ellipsis / trimming is shown
	var font := c.get_theme_font("font")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return text if w > c.size.x + 2.0 else ""


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for ch in n.get_children():
		_walk(ch, out)


func _test_all_screens(code: String, sz: Vector2) -> void:
	Loc.set_language(code, false)
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hub.size = sz
	await get_tree().process_frame
	var tag := "[%s %dx%d]" % [code, int(sz.x), int(sz.y)]
	var too_wide: Array = []
	var clipped: Array = []
	var small_nav: Array = []
	# Width of the content panel with a narrow screen open = the space every screen must fit in
	# (an over-wide screen silently stretches the panel and pushes it past the window edge).
	hub.navigate("promotion")
	await get_tree().process_frame
	await get_tree().process_frame
	var base_width := (hub.current.get_parent() as Control).size.x
	for id in ScreenRegistry.SCREENS:
		hub.navigate(id, _params(id))
		await get_tree().process_frame
		await get_tree().process_frame
		var content := hub.current.get_parent() as Control
		var avail := content.size.x
		var need := hub.current.get_combined_minimum_size().x
		var hub_need := hub.get_combined_minimum_size().x
		if OS.get_environment("KING_LAYOUT_DEBUG") != "":
			print("%s %s need %.0f avail %.0f hub_need %.0f hub %.0f end %.0f" % [tag, id, need, avail, hub_need, hub.size.x, hub.current.get_global_rect().end.x])
		if avail > base_width + 1.0 or need > base_width - 23.0 or hub_need > sz.x + 1.0:
			too_wide.append("%s (needs %.0f, has %.0f, hub %.0f)" % [id, need, avail, hub_need])
		var controls: Array = []
		_walk(hub.current, controls)
		for c in controls:
			var t := _clipped(c)
			if t != "":
				clipped.append("%s: '%s'" % [id, t.left(30)])
	for b in hub.find_children("Nav_*", "Button", true, false):
		if (b as Control).is_visible_in_tree() and (b as Control).size.y < 44.0:
			small_nav.append("%s %.0f" % [b.name, (b as Control).size.y])
	_check(too_wide.is_empty(), "%s every screen fits horizontally (no control outside the content area)" % tag, str(too_wide))
	_check(clipped.is_empty(), "%s no text is cut off without an ellipsis" % tag, str(clipped.slice(0, 6)))
	_check(small_nav.is_empty(), "%s navigation buttons are touch-sized (>= 44 px ~ 48 dp)" % tag, str(small_nav.slice(0, 4)))
	hub.queue_free()
	await get_tree().process_frame
