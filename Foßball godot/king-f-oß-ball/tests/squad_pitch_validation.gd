## Squad Management as a pitch of player cards (formation layout, same Squad data):
##   godot --headless --path . res://tests/squad_pitch_validation.tscn
extends Node

const TEAM := "club_royal_harbor"

var _passed := 0
var _failed := 0


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
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_layout(db: Node, squad: Squad) -> void:
	for fid in FormationData.ids():
		var pitch := SquadPitch.new()
		pitch.size = pitch.custom_minimum_size
		add_child(pitch)
		var s := Squad.new(TEAM, fid)
		s.auto_pick(db)
		pitch.setup(db, fid, s.starting, s.captain_id)
		await get_tree().process_frame
		var cw := pitch.card_width()
		var ch := cw * PlayerCard.ASPECT
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
