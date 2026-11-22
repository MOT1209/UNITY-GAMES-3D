## UI scroll validation: no content of any hub screen may be unreachable. Every visible Button / Label /
## OptionButton must lie inside the content area or be reachable by scrolling an ancestor ScrollContainer;
## there is no ScrollContainer inside a ScrollContainer on the same axis; a vertical touch drag that
## starts on a button scrolls; rebuild() keeps the scroll position.
##   godot --headless --path . res://tests/ui_scroll_validation.tscn
extends Node

const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720)]   # 1600x720 = 2400x1080 phone canvas
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
	print("=== KING FOOTBALL — UI scroll validation ===")
	app = get_node("/root/AppHub")
	app.db.load_world("")
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career("club_royal_harbor")
	for code in LANGS:
		for sz in SIZES:
			await _test_all_screens(code, sz)
	await _test_drag_and_rebuild()
	await _test_pack_leagues()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _params(id: String) -> Dictionary:
	if id == "player_profile":
		return {"player_id": app.db.get_team("club_royal_harbor").squad_ids[0]}
	if id == "kit_editor" or id == "team_details":
		return {"team_id": "club_royal_harbor"}
	return {}


func _make_hub(code: String, sz: Vector2) -> HubRoot:
	Loc.set_language(code, false)
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hub.size = sz
	await get_tree().process_frame
	return hub


func _walk(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for ch in n.get_children():
		_walk(ch, out)


func _scroll_ancestor(c: Control, stop: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and p != stop:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


func _test_all_screens(code: String, sz: Vector2) -> void:
	var hub := await _make_hub(code, sz)
	var tag := "[%s %dx%d]" % [code, int(sz.x), int(sz.y)]
	var unreachable: Array = []
	var nested: Array = []
	var content: Control = hub._content
	for id in ScreenRegistry.SCREENS:
		hub.navigate(id, _params(id))
		for i in 3:
			await get_tree().process_frame
		var area := content.get_global_rect().grow(1.0)
		var controls: Array = []
		_walk(hub.current, controls)
		for c: Control in controls:
			if not (c is Button or c is Label):
				continue
			if not c.is_visible_in_tree() or c.size.x <= 1.0 or c.size.y <= 1.0:
				continue
			if area.encloses(c.get_global_rect()):
				continue
			var sc := _scroll_ancestor(c, hub._content)
			if sc == null:
				unreachable.append("%s: %s" % [id, c.name])
				continue
			sc.ensure_control_visible(c)
			await get_tree().process_frame
			if not sc.get_global_rect().grow(2.0).encloses(c.get_global_rect()) and \
					not (c.get_global_rect().size.y > sc.size.y):
				unreachable.append("%s: %s (scroll cannot reach it)" % [id, c.name])
		var scrolls: Array = hub._content.find_children("*", "ScrollContainer", true, false)
		for s: ScrollContainer in scrolls:
			if s.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				continue
			if _in_popup(s):
				continue       # the internal scroll of an OptionButton / PopupMenu
			var a := s.get_parent()
			while a != null and a != hub._content:
				if a is ScrollContainer and (a as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
					nested.append("%s: %s in %s" % [id, s.name, a.name])
					break
				a = a.get_parent()
	_check(unreachable.is_empty(), "%s every visible Button/Label is inside the content area or reachable by scrolling" % tag, str(unreachable.slice(0, 8)))
	_check(nested.is_empty(), "%s no vertical ScrollContainer inside another one" % tag, str(nested.slice(0, 6)))
	hub.queue_free()
	await get_tree().process_frame


## A real-pack career in a 24-club division: the last row of the league table must be reachable (the screen once
## claimed its own scroll without laying one out, so rows 19-24 were cut off — invisible with the 4-club fictional league).
func _test_pack_leagues() -> void:
	app.db.load_world("real_2026")
	app.career = null
	app.start_career("eng_birmingham_city_fc")
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1600, 720)]:
		var hub := await _make_hub("en", sz)
		hub.navigate("leagues", {})
		for i in 3:
			await get_tree().process_frame
		var last: Label = null
		for l in hub.current.find_children("*", "Label", true, false):
			if (l as Label).text == "24":
				last = l as Label
		_check(last != null, "[real_2026 %dx%d] the 24-club table is built" % [int(sz.x), int(sz.y)])
		if last != null:
			var sc := _scroll_ancestor(last, hub._content)
			while sc != null and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				sc = _scroll_ancestor(sc, hub._content)
			if sc != null:
				sc.ensure_control_visible(last)
				await get_tree().process_frame
			_check(sc != null and hub._content.get_global_rect().grow(2.0).encloses(last.get_global_rect()),
					"[real_2026 %dx%d] scrolling reaches row 24 of the league table" % [int(sz.x), int(sz.y)])
		hub.queue_free()
		await get_tree().process_frame
	app.db.load_world("")
	app.career = null


func _in_popup(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is Popup or p is PopupMenu:
			return true
		p = p.get_parent()
	return false


func _first_button(root: Node) -> Button:
	for b in root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.is_visible_in_tree() and bt.size.x > 20.0 and not bt.disabled and not (bt is OptionButton):
			return bt
	return null


func _test_drag_and_rebuild() -> void:
	var hub := await _make_hub("en", Vector2(1280, 720))
	hub.navigate("transfers")
	for i in 3:
		await get_tree().process_frame
	var sc := hub.current.get_parent() as ScrollContainer
	_check(sc != null and sc.get_v_scroll_bar().max_value > sc.size.y, "the transfer market is taller than the screen and wrapped in a ScrollContainer")
	if sc == null:
		hub.queue_free()
		return
	_check(sc.scroll_vertical == 0, "a newly opened screen starts at the top")
	# Touch drags: the headless engine has no touchscreen, so synthetic InputEventScreenDrag cannot be
	# delivered to a ScrollContainer here. The conditions that make a drag starting on a button / card scroll
	# on a device are asserted instead: a deadzone (a tap is still a tap), vertical auto scrolling, and
	# cards that PASS input on to the scroll container instead of swallowing it.
	_check(sc.scroll_deadzone >= 8 and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO \
			and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"the screen wrapper has a touch deadzone and scrolls vertically only")
	var probe := PlayerCard.new(80.0)
	_check(probe.mouse_filter == Control.MOUSE_FILTER_PASS, "player cards pass drags on to the scroll container")
	probe.free()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = sc.get_global_rect().get_center()
	wheel.pressed = true
	sc.scroll_vertical = 0
	var before := sc.scroll_vertical
	sc.scroll_vertical += int(sc.get_v_scroll_bar().page)    # what a wheel / Page Down does
	_check(sc.scroll_vertical > before, "the screen can be scrolled down programmatically (wheel / Page Down path)")
	sc.scroll_vertical = 0
	# Keyboard / wheel: the wrapper follows focus.
	_check(sc.follow_focus, "the wrapper follows keyboard focus")
	# rebuild() keeps the scroll position.
	sc.scroll_vertical = 150
	await get_tree().process_frame
	hub.current.rebuild()
	for i in 4:
		await get_tree().process_frame
	_check(absi(sc.scroll_vertical - 150) <= 2, "rebuild() keeps the scroll position", "scroll_vertical=%d" % sc.scroll_vertical)
	# Opening another screen resets the position to the top.
	hub.navigate("academy")
	for i in 3:
		await get_tree().process_frame
	var sc2 := hub.current.get_parent() as ScrollContainer
	_check(sc2 != null and sc2.scroll_vertical == 0, "a newly opened screen starts at the top (academy)")
	hub.queue_free()
	await get_tree().process_frame
