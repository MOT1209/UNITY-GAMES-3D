## Squad Management as a pitch of player cards (formation layout, same Squad data):
##   godot --headless --path . res://tests/squad_pitch_validation.tscn
extends Node

const TEAM := "club_royal_harbor"

var _passed := 0
var _failed := 0


const PITCH_SIZE := Vector2(380, 488)


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — squad pitch validation ===")
	var app: Node = get_node("/root/AppHub")
	var db: Node = app.db
	db.reload()
	app.career = null
	app.squads.clear()
	app.select_team(TEAM)
	var squad: Squad = app.squad()
	squad.auto_pick(db)
	await _test_layout(db, squad)
	await _test_screen(app, db, squad)
	await _test_one_screen_layout(app, db)
	_test_roles(app, db)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_layout(db: Node, squad: Squad) -> void:
	for fid in FormationData.ids():
		var pitch := SquadPitch.new()
		pitch.size = PITCH_SIZE      # what the squad screen gives it at 1280x720 (~0.78 ratio)
		add_child(pitch)
		var s := Squad.new(TEAM, fid)
		s.auto_pick(db)
		pitch.setup(db, fid, s.starting, s.captain_id)
		await get_tree().process_frame
		var cw := pitch.card_width()
		var ch := cw * SquadPitch.CARD_ASPECT
		var inside := true
		var rects: Array[Rect2] = []
		for i in 11:
			var c := pitch.slot_center(i, cw)
			var r := Rect2(c - Vector2(cw, ch) * 0.5, Vector2(cw, ch))
			inside = inside and Rect2(Vector2.ZERO, pitch.size).encloses(r)
			rects.append(r)
		var overlap := false
		for i in 11:
			for j in range(i + 1, 11):
				overlap = overlap or rects[i].intersects(rects[j])
		_check(inside and not overlap, "%s: 11 cards inside the pitch, none overlapping" % fid)
		_check(cw >= 48.0, "%s: cards are readable (width %.0f)" % [fid, cw])
		var names_ok := true
		for i in 11:
			var card := pitch.find_child("PitchCard_%d" % i, true, false) as PlayerCard
			names_ok = names_ok and card.texts()["name"] == db.get_player(s.starting[i]).display_name
		_check(names_ok, "%s: every card shows the player of its slot" % fid)
		pitch.queue_free()
	var p := SquadPitch.new()
	_check(p.layout_direction == Control.LAYOUT_DIRECTION_LTR, "pitch is pinned LTR (no Arabic mirroring)")
	p.free()


func _test_screen(app: Node, db: Node, squad: Squad) -> void:
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("squad")
	await get_tree().process_frame
	await get_tree().process_frame
	var pitch := hub.current.find_child("SquadPitch", true, false) as SquadPitch
	_check(pitch != null, "squad screen shows the pitch")
	if pitch == null:
		return
	_check(hub.current.find_child("AutoPick", true, false) != null and hub.current.find_child("Slot_0", true, false) != null, "existing controls (auto-pick, slot list) are still there")
	var pressed := []
	pitch.slot_pressed.connect(func(slot: int, pid: String) -> void: pressed.append([slot, pid]))
	(pitch.find_child("PitchSlot_3", true, false) as Button).pressed.emit()
	_check(pressed == [[3, squad.starting[3]]], "clicking a slot reports the slot and its player", str(pressed))
	# picking a different player through the picker path changes the lineup via Squad
	var screen := hub.current
	var bench_pid := ""
	for pid in squad.bench:
		if db.get_player(pid).position != PlayerData.Position.GK:
			bench_pid = pid
			break
	var before: String = squad.starting[3]
	if bench_pid != "":
		var err := squad.assign_starter(db, 3, bench_pid)
		_check(err == "" and squad.starting[3] == bench_pid, "assigning a bench player to slot 3 works through Squad", err)
		screen.rebuild()
		await get_tree().process_frame
		await get_tree().process_frame
		var pitch2 := screen.find_child("SquadPitch", true, false) as SquadPitch
		var card := pitch2.find_child("PitchCard_3", true, false) as PlayerCard
		_check(card.texts()["name"] == db.get_player(bench_pid).display_name, "the pitch shows the new player after rebuild")
		_check(squad.validate(db).is_empty(), "lineup stays valid", str(squad.validate(db)))
	else:
		_check(false, "test team has a bench player")
	var toggle := screen.find_child("ToggleSlotList", true, false) as Button
	var panel := screen.find_child("SlotListPanel", true, false) as Control
	var was := panel.visible
	toggle.pressed.emit()
	_check(panel.visible != was, "slot list can be shown and hidden")
	hub.queue_free()


## The squad screen needs no scrolling: the goalkeeper, all 11 cards and the 7 substitutes are inside the
## visible content area at 1280x720 and on a 2400x1080 phone (1600x720 canvas), in Arabic and English.
func _test_one_screen_layout(app: Node, db: Node) -> void:
	app.career = null
	app.squads.clear()
	app.start_career(TEAM)
	for code in ["ar", "en"]:
		for sz in [Vector2(1280, 720), Vector2(1600, 720)]:
			Loc.set_language(code, false)
			var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
			add_child(hub)
			hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
			hub.size = sz
			await get_tree().process_frame
			hub.navigate("squad")
			for i in 4:
				await get_tree().process_frame
			var tag := "[%s %dx%d]" % [code, int(sz.x), int(sz.y)]
			var area: Rect2 = (hub._content as Control).get_global_rect().grow(1.0)
			var pitch := hub.current.find_child("SquadPitch", true, false) as SquadPitch
			var hidden: Array = []
			for i in 11:
				var hit := pitch.find_child("PitchSlot_%d" % i, true, false) as Control
				if not area.encloses(hit.get_global_rect()):
					hidden.append(i)
			_check(hidden.is_empty(), "%s the goalkeeper and all 11 pitch cards are visible without scrolling" % tag, str(hidden))
			var gk := pitch.find_child("PitchSlot_0", true, false) as Control
			_check(area.encloses(gk.get_global_rect()), "%s the goalkeeper card is on screen" % tag)
			var rows: Array = hub.current.find_child("BenchList", true, false).get_children().filter(
					func(n: Node) -> bool: return n.name.begins_with("Row_") and n.get_parent().name == "BenchList")
			var bench_vis := 0
			for r: Control in rows:
				if area.encloses(r.get_global_rect()):
					bench_vis += 1
			_check(rows.size() == Squad.MAX_BENCH and bench_vis == Squad.MAX_BENCH, "%s the bench panel shows all 7 substitutes without scrolling" % tag, "%d rows, %d visible" % [rows.size(), bench_vis])
			if PlayerPortraitRenderer.can_render() and code == "en" and sz.x == 1280.0:
				# Only with a real renderer (not headless): every starter's portrait must arrive, no grey silhouette left.
				var waited := 0.0
				var missing := 11
				while waited < 8.0 and missing > 0:
					await get_tree().create_timer(0.25).timeout
					waited += 0.25
					missing = 0
					for card: PlayerCard in pitch.find_children("PitchCard_*", "PlayerCard", true, false):
						if not card.texts()["has_portrait"]:
							missing += 1
				_check(missing == 0, "every starting card shows its rendered portrait (no default silhouette)", "%d still grey" % missing)
			_check(hub.current.find_child("CardStrip", true, false) == null, "%s the duplicate starting-cards strip is gone" % tag)
			var sc := hub.current.get_parent()
			_check(not (sc is ScrollContainer), "%s the squad screen is one fixed screen (no page scroll)" % tag)
			if code == "en" and sz.x == 1280.0:
				await _test_swap(hub, app, db)
			hub.queue_free()
			await get_tree().process_frame
	Loc.set_language("en", false)


## Tap a starter and then a substitute: they trade places through Squad; the lineup stays valid.
func _test_swap(hub: HubRoot, app: Node, db: Node) -> void:
	var squad: Squad = app.squad()
	var pitch := hub.current.find_child("SquadPitch", true, false) as SquadPitch
	var slot := 5
	var out_pid: String = squad.starting[slot]
	var in_pid := ""
	var slot_pos := FormationData.slot_position(squad.formation_id, slot)
	for pid in squad.bench:
		if FormationData.position_fit(db.get_player(pid).position, slot_pos) > 0.0:
			in_pid = pid
			break
	_check(in_pid != "", "a compatible substitute exists for slot 5")
	(pitch.find_child("PitchSlot_%d" % slot, true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var row := hub.current.find_child("Row_%s" % in_pid, true, false) as Button
	_check(row != null, "the substitute has a row in the bench panel")
	var fit_bar := row.find_child("FitBar", true, false) as ColorRect
	var f := FormationData.position_fit(db.get_player(in_pid).position, slot_pos)
	var fit_expected: Color = UIKit.GOOD if f >= 1.0 else Color(0.95, 0.78, 0.25)
	_check(fit_bar != null and fit_bar.color.is_equal_approx(fit_expected), "selecting a slot shows the substitute's position fit (green / yellow / red)")
	row.pressed.emit()
	for i in 3:
		await get_tree().process_frame
	_check(squad.starting[slot] == in_pid and out_pid in squad.bench and not (in_pid in squad.bench),
			"tapping a starter and then a substitute swaps them in Squad.starting / Squad.bench")
	_check(squad.validate(db).is_empty(), "the lineup is still valid after the swap", str(squad.validate(db)))
	_check(app.squad().bench.size() == Squad.MAX_BENCH, "the bench keeps its 7 players")
	# Drag and drop goes through the same swap: drag a starter onto a bench row.
	var screen := hub.current
	var pitch2 := screen.find_child("SquadPitch", true, false) as SquadPitch
	var cur: String = squad.starting[slot]
	var other_bench: String = squad.bench[0]
	var gk_slot_ok: bool = db.get_player(other_bench).position != PlayerData.Position.GK
	if gk_slot_ok:
		var payload: Variant = pitch2._drag_slot(Vector2.ZERO, slot, cur, pitch2.find_child("PitchSlot_%d" % slot, true, false))
		_check(payload is Dictionary and payload["pid"] == cur and pitch2._can_drop(Vector2.ZERO, {"squad_drag": true, "kind": "bench", "slot": -1, "pid": other_bench}, slot),
				"a pitch card can be dragged and accepts a dropped substitute")
		screen._drop_on_row(Vector2.ZERO, payload, other_bench, "bench")
		for i in 3:
			await get_tree().process_frame
		_check(squad.starting[slot] == other_bench and cur in squad.bench, "dropping a starter on a substitute swaps them", "%s / %s" % [squad.starting[slot], str(squad.bench)])
		_check(squad.validate(db).is_empty(), "the lineup is valid after the drag-and-drop swap", str(squad.validate(db)))


func _test_roles(app: Node, db: Node) -> void:
	app.career = null
	app.squads.clear()
	app.start_career(TEAM)
	var squad: Squad = app.squad()
	var gk_ids := squad.starting.filter(func(id: String) -> bool: return id != "" and db.get_player(id).position == PlayerData.Position.GK)
	for kind in ["penalty", "free_kick", "corner"]:
		_check(squad.set_pieces[kind] != "" and not (squad.set_pieces[kind] in gk_ids), "after start_career the %s taker is a field player, not the goalkeeper" % kind, str(squad.set_pieces[kind]))
	squad.auto_pick(db)
	for kind in ["penalty", "free_kick", "corner"]:
		_check(not (squad.set_pieces[kind] in gk_ids) and squad.set_pieces[kind] in squad.starting, "after auto-pick the %s taker is a starting field player" % kind)
	# Roles of a starter who leaves the XI are re-assigned to another field player.
	var taker: String = squad.set_pieces["penalty"]
	var bench_pid: String = squad.bench[0]
	var slot := squad.starting.find(taker)
	squad.substitute(db, slot, bench_pid)
	squad.ensure_roles(db)
	_check(squad.set_pieces["penalty"] in squad.starting, "roles stay valid after a substitution")
	_check(squad.validate(db).is_empty(), "the squad validates after role changes", str(squad.validate(db)))
	# swap_starters guards the goalkeeper slot.
	var field_slot := 5
	_check(squad.swap_starters(db, 0, field_slot) != "", "a goalkeeper cannot be swapped with an outfield slot")
	var a: String = squad.starting[3]
	var b: String = squad.starting[5]
	_check(squad.swap_starters(db, 3, 5) == "" and squad.starting[3] == b and squad.starting[5] == a, "two outfield starters swap their slots")
