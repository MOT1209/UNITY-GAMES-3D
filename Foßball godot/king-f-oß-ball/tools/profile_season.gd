## Developer tool: per-phase timing of every career week (performance baseline / regression check).
##   godot --headless --path . res://tools/profile_season.tscn -- [seasons] [pack]
## Plays `seasons` full seasons (default 1) with the real pack (default real_2025; "" = fictional world) and prints
## the time of each `advance_week()` phase (from `CareerState.last_timings`), the slowest weeks, the season total,
## `end_season()` time and static memory before / after. Output is plain text so runs can be diffed.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var seasons := 1
	var pack := "real_2025"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seasons = int(a[0])
	if a.size() > 1:
		pack = "" if a[1] == "fictional" else a[1]
	var db: TeamDatabase = get_node("/root/TeamDB")
	var t0 := Time.get_ticks_msec()
	db.load_world(pack)
	print("pack '%s': load %d ms, %d clubs, %d players" % [pack, Time.get_ticks_msec() - t0,
			db.list_teams(TeamData.Category.CLUB).size(), db.players.size()])
	var club: String = db.list_teams(TeamData.Category.CLUB)[0].id
	if pack == "real_2025":
		club = "eng_leicester_city_fc"
	t0 = Time.get_ticks_msec()
	var c := CareerState.start(db, club)
	if c.pyramids.is_empty():
		c.add_default_league()
	print("career start: %d ms" % (Time.get_ticks_msec() - t0))
	var mem0 := OS.get_static_memory_usage()
	var all_weeks_ms: Array[float] = []
	for s in seasons:
		var phase_total := {}
		var season_us := 0
		var worst := 0.0
		var worst_week := 0
		for w in CareerState.WEEKS_PER_SEASON:
			var t := Time.get_ticks_usec()
			c.advance_week()
			var dt := Time.get_ticks_usec() - t
			season_us += dt
			all_weeks_ms.append(dt / 1000.0)
			if dt / 1000.0 > worst:
				worst = dt / 1000.0
				worst_week = c.week
			for k in c.last_timings:
				phase_total[k] = int(phase_total.get(k, 0)) + int(c.last_timings[k])
		var t_end := Time.get_ticks_usec()
		c.end_season()
		var end_ms := (Time.get_ticks_usec() - t_end) / 1000.0
		var end_parts := []
		for k in c.last_timings:
			end_parts.append("%s=%.0f" % [k.substr(4), c.last_timings[k] / 1000.0])
		print("   end_season phases (ms): %s" % ", ".join(end_parts))
		var parts := []
		for k in phase_total:
			parts.append("%s=%.0f" % [k, phase_total[k] / 1000.0])
		print("season %d: 46 weeks %.0f ms (avg %.1f, worst %.1f in week %d) | end_season %.0f ms | phases(ms): %s | mem %.1f MB" % [
				s + 1, season_us / 1000.0, season_us / 46000.0, worst, worst_week, end_ms, ", ".join(parts),
				OS.get_static_memory_usage() / 1048576.0])
	all_weeks_ms.sort()
	print("weeks: n=%d median %.1f ms p95 %.1f ms max %.1f ms" % [all_weeks_ms.size(), all_weeks_ms[all_weeks_ms.size() / 2],
			all_weeks_ms[int(all_weeks_ms.size() * 0.95)], all_weeks_ms[-1]])
	print("static memory: start %.1f MB -> end %.1f MB" % [mem0 / 1048576.0, OS.get_static_memory_usage() / 1048576.0])
	get_tree().quit()
