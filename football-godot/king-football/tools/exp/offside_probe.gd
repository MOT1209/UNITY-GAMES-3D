## Offside probe: one AI-v-AI match; counts passes played while a team-mate stood offside, early runs, and offsides called.
##   godot --headless --fixed-fps 60 --path . res://tools/exp/offside_probe.tscn -- seed=300 min=5
extends Node

func _arg(name: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return float(a.split("=")[1])
	return def

func _ready() -> void:
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 5
	setup.human_side = "none"
	setup.difficulty = 1
	setup.rng_seed = int(_arg("seed", 300))
	seed(setup.rng_seed)
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	m.state.duration_seconds = _arg("min", 5.0) * 60.0
	var last_t := -1.0
	var passes := 0
	var with_offside_mate := 0
	var early_frames := 0
	var beyond_frames := 0
	var frames := 0
	var margins: Array = []
	var lead: Array = []
	var st_t: Array = []
	var intents := {}
	var fdepth: Array = []
	var ball_d: Array = []
	var line_d: Array = []
	var dist_from_owner: Array = []
	while m.state.phase != MatchState.Phase.FINISHED and frames < 60 * 60 * 8:
		await get_tree().physics_frame
		frames += 1
		var p: Dictionary = m.rules.restarts._pending
		if not p.is_empty() and float(p["t"]) != last_t:
			last_t = float(p["t"])
			passes += 1
			if not (p["offside"] as Array).is_empty():
				with_offside_mate += 1
		for side in ["home", "away"]:
			for e in m.entries[side]:
				if float(e.get("early_run", 0.0)) > 0.0:
					early_frames += 1
					if frames % 10 == 0:
						var r := m.rules.restarts
						var opp: Array[float] = []
						for o in m.entries["away" if side == "home" else "home"]:
							opp.append(r._depth((o["node"] as Node3D).global_position.z, side))
						opp.sort()
						opp.reverse()
						var me: float = r._depth((e["node"] as Node3D).global_position.z, side)
						var tgt: Vector3 = (e["ai"] as AIIntent).get("move_vector") if false else Vector3.ZERO
						margins.append(me - opp[1])
						dist_from_owner.append(me)
		if m.state.phase == MatchState.Phase.PLAYING and frames % 30 == 0:
			var own := m._owner_entry()
			if not own.is_empty():
				beyond_frames += m.rules.restarts.offside_positioned(own["side"], m.ball.global_position.z).size()
				var r := m.rules.restarts
				var sd: String = own["side"]
				var opp: Array[float] = []
				for o in m.entries["away" if sd == "home" else "home"]:
					opp.append(r._depth((o["node"] as Node3D).global_position.z, sd))
				opp.sort()
				opp.reverse()
				var best := -INF
				for e in m.entries[sd]:
					if int(e["slot"]) != 0:
						best = maxf(best, r._depth((e["node"] as Node3D).global_position.z, sd))
				lead.append(best - opp[1])
				var tg := TeamAI.formation_targets(m.frame_side(sd), m.sides[sd]["formation"], m.sides[sd]["tactics"], m.ball.global_position, true)
				for i in 11:
					if FormationData.slot_position(m.sides[sd]["formation"], i) == PlayerData.Position.ST:
						st_t.append(r._depth(tg[i].z, sd) - opp[1])
				for e in m.entries[sd]:
					var sp := FormationData.slot_position(m.sides[sd]["formation"], int(e["slot"]))
					if sp in [PlayerData.Position.ST, PlayerData.Position.LW, PlayerData.Position.RW] and e != own:
						var k := str(e.get("intent", "?"))
						intents[k] = int(intents.get(k, 0)) + 1
						fdepth.append(r._depth((e["node"] as Node3D).global_position.z, sd) - opp[1])
				ball_d.append(r._depth(m.ball.global_position.z, sd))
				line_d.append(opp[1])
	var st := m.state.stats
	fdepth.sort()
	st_t.sort()
	print("ST formation target vs line (before hold-the-line clamp): p10 %.1f p50 %.1f p90 %.1f" % [st_t[st_t.size() / 10], st_t[st_t.size() / 2], st_t[int(st_t.size() * 0.9)]])
	print("FORWARDS intents ", intents, " | depth vs line p50 %.1f p90 %.1f" % [fdepth[fdepth.size() / 2], fdepth[int(fdepth.size() * 0.9)]])
	for arr in [lead, ball_d, line_d]:
		arr.sort()
	print("LEAD most-advanced attacker vs 2nd-last defender: p10 %.1f p50 %.1f p90 %.1f | ball depth p50 %.1f | line depth p50 %.1f (n=%d)" % [lead[lead.size() / 10], lead[lead.size() / 2], lead[int(lead.size() * 0.9)], ball_d[ball_d.size() / 2], line_d[line_d.size() / 2], lead.size()])
	margins.sort()
	if not margins.is_empty():
		print("RUNNER margin vs 2nd-last (m, + = beyond): min %.1f p50 %.1f p90 %.1f max %.1f n=%d | runner depth p50 %.1f" % [margins[0], margins[margins.size() / 2], margins[int(margins.size() * 0.9)], margins[-1], margins.size(), dist_from_owner[dist_from_owner.size() / 2]])
	print("OFFSIDE seed=%d passes=%d passes_with_offside_mate=%d early_run_frames=%d offside_samples=%d called=%d/%d score=%d-%d" % [setup.rng_seed, passes, with_offside_mate, early_frames, beyond_frames,
			int(st.teams["home"].get("offsides", 0)), int(st.teams["away"].get("offsides", 0)), int(m.state.score["home"]), int(m.state.score["away"])])
	get_tree().quit()
