## Developer tool: cost of saving and loading a real-world career (the career audit is part of validation).
##   godot --headless --path . res://tools/profile_save.tscn -- [weeks]
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var weeks := 23
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		weeks = int(a[0])
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var c := CareerState.start(db, "eng_leicester_city_fc")
	for i in weeks:
		c.advance_week()
	var t := Time.get_ticks_msec()
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(), "user_team_id": c.club_id})
	print("capture (week %d): %d ms" % [weeks, Time.get_ticks_msec() - t])
	t = Time.get_ticks_msec()
	var text := JSON.stringify(data, "\t", true, true)
	print("stringify: %d ms, %d KB" % [Time.get_ticks_msec() - t, text.length() / 1024])
	t = Time.get_ticks_msec()
	var parsed: Dictionary = JSON.parse_string(text)
	print("parse: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var m := SaveManager.migrate(parsed)
	print("migrate: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var errs := SaveManager.validate(m)
	var with_career := Time.get_ticks_msec() - t
	var no_career := m.duplicate()
	no_career["extras"] = {"user_team_id": c.club_id}
	t = Time.get_ticks_msec()
	SaveManager.validate(no_career)
	var without := Time.get_ticks_msec() - t
	print("validate: %d ms with the career block, %d ms without it (career audit = %d ms), %d errors" % [with_career, without, with_career - without, errs.size()])
	t = Time.get_ticks_msec()
	var res := SaveManager.restore(db, m)
	print("restore (validate + rebuild): %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var c2 := CareerState.from_dict(db, res["extras"]["career"])
	print("CareerState.from_dict: %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var audit := CareerValidator.validate(c2, false)
	print("CareerValidator.validate (no deep): %d ms, %d errors, %d warnings" % [Time.get_ticks_msec() - t, audit["errors"].size(), audit["warnings"].size()])
	get_tree().quit()
