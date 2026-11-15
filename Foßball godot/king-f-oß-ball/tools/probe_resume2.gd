extends Node
func _snap(db, c: CareerState) -> Dictionary:
	var pl := {}
	for p in db.players.values(): pl[p.id] = JSON.stringify(p.to_dict(), "", true)
	return {"career": c.to_dict(), "players": pl, "teams": db.teams.values().map(func(t): return JSON.stringify(t.to_dict(), "", true))}
func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("")
	var c := CareerState.start(db, "club_royal_harbor"); c.add_default_league()
	for i in 46: c.advance_week()
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
	c.end_season()
	var ref := _snap(db, c)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	var res := SaveManager.restore(db, parsed)
	var b := CareerState.from_dict(db, res["extras"]["career"])
	b.end_season()
	var s := _snap(db, b)
	print("career equal: ", JSON.stringify(s["career"], "", true) == JSON.stringify(ref["career"], "", true), " players equal: ", s["players"] == ref["players"], " teams equal: ", s["teams"] == ref["teams"])
	for k in s["career"]:
		if JSON.stringify(s["career"][k], "", true) != JSON.stringify(ref["career"][k], "", true): print("   career key: ", k, "\n     ", JSON.stringify(s["career"][k]).left(300), "\n     ", JSON.stringify(ref["career"][k]).left(300))
	var n := 0
	for pid in s["players"]:
		if s["players"][pid] != ref["players"][pid] and n < 3:
			n += 1
			var x: Dictionary = JSON.parse_string(s["players"][pid]); var y: Dictionary = JSON.parse_string(ref["players"][pid])
			print("   player ", pid)
			for k in x:
				if JSON.stringify(x[k]) != JSON.stringify(y[k]): print("      ", k, ": ", str(x[k]).left(70), " vs ", str(y[k]).left(70))
	get_tree().quit()
