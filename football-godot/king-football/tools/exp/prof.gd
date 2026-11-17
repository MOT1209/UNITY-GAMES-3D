extends Node
func _ready() -> void:
	await get_tree().process_frame
	var app: Node = get_node("/root/AppHub")
	app.switch_world("real_2025")
	for t in app.db.list_teams(TeamData.Category.CLUB):
		if app.start_career(t.id) == "": break
	var c: CareerState = app.career
	for i in 14:
		var t0 := Time.get_ticks_usec()
		var t1 := t0
		app.advance_day()
		print("PROF day %d: %.1f ms" % [i, (Time.get_ticks_usec() - t0) / 1000.0])
	var t0 := Time.get_ticks_usec()
	DailyLife.day(c, CareerDate.jdn_of(c.season, c.week, c.day))
	print("PROF DailyLife.day alone: %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	t0 = Time.get_ticks_usec()
	var d := c.training.day_plan(c, CareerDate.jdn_of(c.season, c.week, c.day))
	print("PROF day_plan: %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	var fs: Array = []
	for k in c.pyramids:
		var pyr: LeaguePyramid = c.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = c.competitions.get(pyr.comp[role])
			if comp != null:
				for f in comp.fixtures:
					fs.append(f)
					if fs.size() >= 100: break
			if fs.size() >= 100: break
		break
	var ts := Time.get_ticks_usec()
	for f in fs:
		var r := MatchResult.make(str(f["match_id"]), f["home"], f["away"], 2, 1)
		SeasonStats.record_simulated(c, r, "x")
	print("PROF record_simulated x100: %.1f ms" % [(Time.get_ticks_usec() - ts) / 1000.0])
	ts = Time.get_ticks_usec()
	for f in fs:
		MatchSimulator.career_result(c, f, 1)
	print("PROF career_result x100: %.1f ms" % [(Time.get_ticks_usec() - ts) / 1000.0])
	ts = Time.get_ticks_usec()
	var comp0: Competition = c.competitions[c.pyramids[c.pyramids.keys()[0]].comp.values()[0]]
	var n := 0
	for f in comp0.pending_fixtures():
		if n >= 100: break
		c.submit_result(comp0.id, MatchSimulator.career_result(c, f, 1))
		n += 1
	print("PROF submit_result(+sim) x%d: %.1f ms" % [n, (Time.get_ticks_usec() - ts) / 1000.0])
	ts = Time.get_ticks_usec()
	var pending := comp0.pending_fixtures()
	print("PROF pending_fixtures (%d): %.1f ms" % [pending.size(), (Time.get_ticks_usec() - ts) / 1000.0])
	var pend2 := comp0.pending_fixtures()
	var tA := 0; var tB := 0; var tC := 0; var tD := 0
	var m := 0
	for f in pend2:
		if m >= 80: break
		m += 1
		var res := MatchSimulator.career_result(c, f, 2)
		var a0 := Time.get_ticks_usec()
		WorldLife.is_derby(c.db, res.home_id, res.away_id)
		var a1 := Time.get_ticks_usec()
		comp0.submit_result(res)
		var a2 := Time.get_ticks_usec()
		c.record_match_revenue(res.home_id)
		var a3 := Time.get_ticks_usec()
		c.has_engine_report(res.match_id)
		var a4 := Time.get_ticks_usec()
		tA += a1 - a0; tB += a2 - a1; tC += a3 - a2; tD += a4 - a3
	print("PROF split derby %.1f submit %.1f revenue %.1f report %.1f ms per 80" % [tA / 1000.0, tB / 1000.0, tC / 1000.0, tD / 1000.0])
	get_tree().quit()
