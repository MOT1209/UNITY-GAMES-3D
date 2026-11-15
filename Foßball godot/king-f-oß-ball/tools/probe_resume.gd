extends Node
func _snap(db, c: CareerState) -> Dictionary:
	var pl := {}
	for p in db.players.values(): pl[p.id] = JSON.stringify(p.to_dict(), "", true)
	return {"career": c.to_dict(), "players": pl, "teams": db.teams.values().map(func(t): return JSON.stringify(t.to_dict(), "", true))}
func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	var cut := 8
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: cut = int(a[0])
	# continuous run: snapshots per week
	db.load_world("")
	var c := CareerState.start(db, "club_royal_harbor"); c.add_default_league()
	var snaps: Array = []
	for i in 24:
		c.advance_week()
		snaps.append(_snap(db, c))
	# resumed run
	db.load_world("")
	var b := CareerState.start(db, "club_royal_harbor"); b.add_default_league()
	for i in cut: b.advance_week()
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": b.to_dict()})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	var res := SaveManager.restore(db, parsed)
	b = CareerState.from_dict(db, res["extras"]["career"])
	for i in range(cut, 24):
		b.advance_week()
		var s := _snap(db, b)
		var ref: Dictionary = snaps[i]
		var cd := JSON.stringify(s["career"], "", true) == JSON.stringify(ref["career"], "", true)
		var pd: bool = s["players"] == ref["players"]
		var td: bool = s["teams"] == ref["teams"]
		if not (cd and pd and td):
			print("week %d diverges: career %s players %s teams %s" % [b.week, cd, pd, td])
			if not cd:
				for k in s["career"]:
					if JSON.stringify(s["career"][k], "", true) != JSON.stringify(ref["career"][k], "", true):
						print("   career key: ", k)
						if k == "ledgers":
							for t in s["career"][k]:
								var e1: Array = s["career"][k][t]["entries"]; var e2: Array = ref["career"][k][t]["entries"]
								if JSON.stringify(e1) != JSON.stringify(e2):
									print("     ledger ", t, " entries ", e1.size(), " vs ", e2.size())
									for j in mini(e1.size(), e2.size()):
										if JSON.stringify(e1[j]) != JSON.stringify(e2[j]):
											print("       first diff #", j, ": ", e1[j], " vs ", e2[j]); break
									if e1.size() != e2.size(): print("       extra: ", (e1 if e1.size() > e2.size() else e2).slice(mini(e1.size(), e2.size())))
									break
			if not pd:
				var n := 0
				for pid in s["players"]:
					if s["players"][pid] != ref["players"][pid] and n < 3:
						n += 1
						print("   player ", pid)
						var x: Dictionary = JSON.parse_string(s["players"][pid]); var y: Dictionary = JSON.parse_string(ref["players"][pid])
						for k in x:
							if JSON.stringify(x[k]) != JSON.stringify(y[k]): print("      ", k, ": ", str(x[k]).left(60), " vs ", str(y[k]).left(60))
			break
	print("done cut=", cut)
	get_tree().quit()
