class_name MatchQualityRunner
extends RefCounted

## Plays one full-engine 3D match (AI vs AI, or `SimulatedHuman` on the home side) with a `MatchQualityProbe`
## attached, and returns the probe's report (Phase M0). Used by `tools/qa_m3d.tscn` and
## `tests/match_quality_validation.tscn`. `host` is any node in the tree; the match is freed afterwards.
## Determinism: the match RNG and the global RNG are seeded with `seed_value`.

static func run_match(host: Node, seed_value: int, minutes: float, human: bool,
		home := "club_royal_harbor", away := "club_northgate_utd") -> Dictionary:
	var db: Node = host.get_node("/root/TeamDB")
	var setup := MatchSetup.new()
	setup.home_id = home
	setup.away_id = away
	setup.duration_minutes = 5                  # an allowed setup value; the real length is set below
	setup.human_side = "home" if human else "none"
	setup.difficulty = 1
	setup.rng_seed = seed_value
	seed(seed_value)
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	host.add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		return {"error": err}
	m.state.duration_seconds = minutes * 60.0
	var probe := MatchQualityProbe.new()
	host.add_child(probe)
	probe.attach(m)
	var sim: SimulatedHuman = null
	if human:
		sim = SimulatedHuman.new()
		host.add_child(sim)
		sim.attach(m, seed_value)
	var limit := int(minutes * 60.0 * 60.0) + 60 * 60
	var frames := 0
	while frames < limit and m.state.phase != MatchState.Phase.FINISHED:
		await host.get_tree().physics_frame
		frames += 1
		if frames % 600 == 0 and OS.get_cmdline_user_args().has("verbose"):
			print("  frame %d t=%.1f phase %d ms=%d" % [frames, m.state.elapsed, m.state.phase, Time.get_ticks_msec()])
	var out := probe.report()
	if OS.get_cmdline_user_args().has("dump"):
		for p in probe.pass_log:
			print("  pass %s %s power %.1f speed %.1f err %.0f result %s mind %.1f dt %.2f travel %.1f len %.1f" % [p["side"], p["kind"], p["power"], p["kick_speed"], p["dir_err"], p["result"], p["min_dist_target"], p.get("dt", 0.0), p.get("travel", 0.0), p.get("pass_len", 0.0)], " hits ", p.get("hits", []))
	if OS.get_cmdline_user_args().has("dump_shots"):
		for sh in probe.shot_log:
			print("  shot %s dist %.1f xg %.2f gk_off %.1f gk_state %d -> %s%s" % [sh["side"], sh.get("dist", 0.0), sh.get("xg", 0.0), sh.get("gk_off", 0.0), sh.get("gk_state", -1), sh["result"], " GOAL" if sh.get("goal", false) else ""])
	out["seed"] = seed_value
	m.process_mode = Node.PROCESS_MODE_DISABLED
	for n in [probe, sim, m]:
		if n != null:
			n.queue_free()
	await host.get_tree().process_frame
	return out


static func average(rows: Array) -> Dictionary:
	var keys := ["passes", "pass_pct", "home_pass_pct", "dir_err_median", "dir_err_p90", "kick_speed_avg", "probe_pass_pct", "reached_target_pct", "flyby_losses", "on_target_pct", "frame_pct", "goals", "offsides",
			"out_samples", "still_pct", "crowd", "human_crowd", "support_pct", "human_support_pct"]
	var out := {}
	for k in keys:
		var s := 0.0
		var lo := INF
		var hi := -INF
		for r in rows:
			s += float(r.get(k, 0.0))
			lo = minf(lo, float(r.get(k, 0.0)))
			hi = maxf(hi, float(r.get(k, 0.0)))
		out[k] = s / maxf(rows.size(), 1.0)
		out[k + "_min"] = lo
		out[k + "_max"] = hi
	return out


static func line(r: Dictionary) -> String:
	return "seed %d  %s  passes %d (%.0f%% ok, probe %.0f%%, at target %.0f%%, flyby %d, dir err med %.0f p90 %.0f deg, kick %.1f m/s) %s  goals %s  shots %d on %.0f%% (frame %.0f%% %s)  offs %d  out %d (%s)  still %.1f%%  crowd %.2f / human %.2f  support %.0f%% / human %.0f%%" % [
			int(r.get("seed", 0)), r["score"], r["passes"], r["pass_pct"], r["probe_pass_pct"], r["reached_target_pct"], r["flyby_losses"], r["dir_err_median"], r["dir_err_p90"], r["kick_speed_avg"],
			str(r["pass_results"]), str(r["goal_sources"]), r["shots"], r["on_target_pct"], r["frame_pct"], str(r["shot_results"]), r["offsides"], r["out_samples"], r["worst_out"], r["still_pct"],
			r["crowd"], r["human_crowd"], r["support_pct"], r["human_support_pct"]]


