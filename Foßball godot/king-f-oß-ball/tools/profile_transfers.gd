## Developer tool: measures AITransfers.run_week in isolation (before/after optimization).
##   godot --headless --path . res://tools/profile_transfers.tscn -- [weeks]
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var weeks := 6
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		weeks = int(a[0])
	var db: TeamDatabase = get_node("/root/TeamDB")
	var t0 := Time.get_ticks_msec()
	db.load_world("real_2025")
	print("load_world: %d ms" % (Time.get_ticks_msec() - t0))
	var c := CareerState.start(db, "eng_leicester_city_fc")
	for w in weeks:
		c.week = w + 1
		t0 = Time.get_ticks_msec()
		var deals := AITransfers.run_week(c, {})
		print("week %d: run_week = %d ms, deals=%d" % [w + 1, Time.get_ticks_msec() - t0, deals.size()])
	get_tree().quit()
