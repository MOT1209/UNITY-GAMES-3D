extends Node
func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	var app: Node = get_node("/root/AppHub")
	app.career = null
	app.start_career("club_royal_harbor")
	var c: CareerState = app.career
	var first := {}
	for s in 10:
		for w in CareerState.WEEKS_PER_SEASON:
			c.advance_week()
		c.end_season()
		if s == 0 or s == 9:
			var d := c.to_dict()
			var sizes := {}
			for k in d:
				sizes[k] = JSON.stringify(d[k]).length() / 1024
			if s == 0:
				first = sizes
			else:
				for k in sizes:
					if int(sizes[k]) - int(first.get(k, 0)) > 3:
						print("GROW ", k, " ", first.get(k, 0), " -> ", sizes[k])
	get_tree().quit()
