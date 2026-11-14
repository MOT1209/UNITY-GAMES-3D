## Developer tool: measures match start-up cost, face-system cost, node/object counts and (with a
## rendering device) frame times. Prints a JSON block and a readable table.
##   godot --headless --path . res://tools/profile_match.tscn            (CPU timings, no rendering)
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/profile_match.tscn -- frames   (adds FPS)
##   add `single` to the user args (-- frames single) to run every section once — for slow GPUs.
## Numbers from a software renderer (llvmpipe) are NOT representative of a real GPU.
extends Node

const RUNS := 5


func _runs() -> int:
	return 1 if OS.get_cmdline_user_args().has("single") else RUNS


func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _ms(f: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	f.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _ready() -> void:
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	var out := {"engine": Engine.get_version_info()["string"], "renderer": RenderingServer.get_video_adapter_name(),
			"display": DisplayServer.get_name()}
	var players: Array = db.get_squad("club_royal_harbor").slice(0, 22)
	while players.size() < 22:
		players.append_array(db.get_squad("club_northgate_utd"))
	players = players.slice(0, 22)
	# --- A: 22 dressed players, with / without the face system
	for variant in ["with_face", "without_face"]:
		var times: Array = []
		var nodes := 0
		for run in _runs():
			var held: Array = []
			var t := _ms(func() -> void:
				for p: PlayerData in players:
					var v := (load(PlayerPortraitRenderer.OUTFIELD_SCENE) as PackedScene).instantiate() as PlayerCharacterVisual
					var look := PlayerAppearance.look_for(p)
					if variant == "without_face":
						look.face_shape = -1
					v.look = look
					v.kit = TeamKit.new()
					add_child(v)
					held.append(v))
			times.append(t)
			if run == RUNS - 1:
				nodes = _count(self) / 1
			if run == 0:
				out["%s_cold_ms" % variant] = t
			for v in held:
				v.queue_free()
			await get_tree().process_frame
		out["%s_22_players_median_ms" % variant] = _median(times)
		out["%s_nodes_total_22" % variant] = nodes
	# --- A2: memory of 22 dressed players (second batch, so one-off shared resources are not counted)
	var held2: Array = []
	for batch in 2:
		var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
		var o0 := Performance.get_monitor(Performance.OBJECT_COUNT)
		for p: PlayerData in players:
			var v := (load(PlayerPortraitRenderer.OUTFIELD_SCENE) as PackedScene).instantiate() as PlayerCharacterVisual
			v.look = PlayerAppearance.look_for(p)
			v.kit = TeamKit.new()
			add_child(v)
			held2.append(v)
		if batch == 1:
			out["22_players_static_memory_delta_kb"] = snappedf((Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / 1024.0, 1.0)
			out["22_players_object_delta"] = Performance.get_monitor(Performance.OBJECT_COUNT) - o0
	for v in held2:
		v.queue_free()
	await get_tree().process_frame
	# --- B: FaceBuilder alone on 22 models
	var models: Array = []
	for p: PlayerData in players:
		var v := (load(PlayerPortraitRenderer.OUTFIELD_SCENE) as PackedScene).instantiate() as PlayerCharacterVisual
		v.look = PlayerAppearance.look_for(p)
		add_child(v)
		models.append(v)
	await get_tree().process_frame
	var face_times: Array = []
	for run in _runs():
		face_times.append(_ms(func() -> void:
			for v: PlayerCharacterVisual in models:
				FaceBuilder.apply(v, v.look)))
	out["face_apply_22_players_median_ms"] = _median(face_times)
	var face_nodes := 0
	for v: Node in models:
		var sk := v.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var att := sk.get_node_or_null(FaceBuilder.ATTACH_NAME)
		face_nodes += _count(att) if att != null else 0
	out["face_nodes_22_players"] = face_nodes
	for v in models:
		v.queue_free()
	await get_tree().process_frame
	# --- C0: where the rest of the match start-up goes (arena / ball / full player scenes)
	var arena_times: Array = []
	var ball_times: Array = []
	var team_times: Array = []
	var times_run := _runs()
	for run in times_run:
		var holder := Node3D.new()
		add_child(holder)
		arena_times.append(_ms(func() -> void: holder.add_child((load(MatchManager.ARENA_SCENE) as PackedScene).instantiate())))
		ball_times.append(_ms(func() -> void: holder.add_child((load(MatchManager.BALL_SCENE) as PackedScene).instantiate())))
		team_times.append(_ms(func() -> void:
			for i in 21:
				holder.add_child((load(MatchManager.PLAYER_SCENE) as PackedScene).instantiate())
			holder.add_child((load(MatchManager.KEEPER_SCENE) as PackedScene).instantiate())))
		holder.queue_free()
		await get_tree().process_frame
	out["arena_instantiate_median_ms"] = _median(arena_times)
	out["ball_instantiate_median_ms"] = _median(ball_times)
	out["22_player_scenes_instantiate_median_ms"] = _median(team_times)
	# --- C: real match start-up
	var begin_times: Array = []
	var objs := {}
	for run in _runs():
		var setup := MatchSetup.new()
		setup.home_id = "club_royal_harbor"
		setup.away_id = "club_northgate_utd"
		setup.duration_minutes = 2
		setup.human_side = "none"
		var m := MatchManager.new()
		m.return_to_menu_on_finish = false
		add_child(m)
		var t := _ms(func() -> void: m.begin(setup, db))
		begin_times.append(t)
		if run == 0:
			out["match_begin_cold_ms"] = t
		if run == RUNS - 1:
			objs = {"objects": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
					"static_memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
					"match_scene_nodes": _count(m)}
			if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("frames"):
				out["frames"] = await _frame_stats(m)
		m.queue_free()
		await get_tree().process_frame
	out["match_begin_median_ms"] = _median(begin_times)
	out["match_memory"] = objs
	# --- D: portrait (needs a renderer; skipped in single mode)
	if not OS.get_cmdline_user_args().has("single") and PlayerPortraitRenderer.can_render():
		var r := PlayerPortraitRenderer.shared(get_tree())
		await get_tree().process_frame
		var ptimes: Array = []
		for i in 10:
			var c := PlayerCardData.from_data(db, players[i])
			var t0 := Time.get_ticks_usec()
			await r.request(c, db)
			ptimes.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		out["portrait_render_median_ms"] = _median(ptimes)
		out["portrait_cache_size"] = r.cache_size()
	print("PROFILE_JSON ", JSON.stringify(out))
	for k in out:
		print("%-36s %s" % [k, str(out[k])])
	get_tree().quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## Runs the (AI vs AI) match for 300 frames and reports frame statistics.
func _frame_stats(m: MatchManager) -> Dictionary:
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	for i in 60:
		await get_tree().process_frame               # warm-up
	var frame_ms: Array = []
	var proc: Array = []
	var phys: Array = []
	for i in 300:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		frame_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	frame_ms.sort()
	var avg := 0.0
	for f in frame_ms:
		avg += f
	avg /= frame_ms.size()
	var worst1: Array = frame_ms.slice(int(frame_ms.size() * 0.99))
	var w := 0.0
	for f in worst1:
		w += f
	w /= worst1.size()
	return {"avg_fps": snappedf(1000.0 / avg, 0.1), "avg_frame_ms": snappedf(avg, 0.01), "one_percent_low_fps": snappedf(1000.0 / w, 0.1),
			"process_ms_median": snappedf(_median(proc), 0.01), "physics_ms_median": snappedf(_median(phys), 0.01),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"note": "software renderer: not representative of a real GPU" if "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower() else ""}
