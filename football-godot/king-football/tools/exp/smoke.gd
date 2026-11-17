extends Node
func _ready() -> void:
	await get_tree().process_frame
	var app: Node = get_node("/root/AppHub")
	app.switch_world("")
	app.start_career("club_desert_kings")
	var seen := 0
	for i in 8:
		var info: Dictionary = app.advance_week()
		for pair in app.career.friendly_comps():
			seen += 1
	print("SMOKE week ", app.career.week, " friendlies seen ", seen, " due ", app.career.due_user_fixtures().size())
	var days := CareerCalendar.season_days(app.career).filter(func(e: Dictionary) -> bool: return e["kind"] == "friendly")
	print("SMOKE friendly days ", days.size())
	var info2: Dictionary = app.advance_day()
	print("SMOKE day ", info2.get("day", -1), " ", CareerDate.format(app.career.date()))
	var rep := CareerValidator.validate(app.career, false)
	print("SMOKE validator errors ", (rep["errors"] as Array).slice(0, 3))
	get_tree().quit()
