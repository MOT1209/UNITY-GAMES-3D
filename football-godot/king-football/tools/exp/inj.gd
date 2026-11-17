extends Node
func _ready() -> void:
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB"); db.reload()
	var uc := "club_desert_kings"
	var c := CareerState.start(db, uc)
	var squad := Squad.new(uc, "4-3-3"); squad.auto_pick(db)
	var s := db.get_player(squad.starting[4])
	s.status = PlayerData.Status.INJURED; s.unavailable_weeks = 2
	Availability.fix_lineup(squad, db)
	print("INJ before ", s.status, " ", s.unavailable_weeks, " ", s.unavailable_days)
	for step in c._week_steps():
		pass
	var run := c._begin_week({uc: squad}, {}, {}, {})
	print("INJ after begin ", s.status, " ", s.unavailable_weeks)
	for step in c._week_steps():
		c._run_step(step, run)
		print("INJ after ", step, " ", s.status, " ", s.unavailable_weeks, " ", s.unavailable_days)
	get_tree().quit()
