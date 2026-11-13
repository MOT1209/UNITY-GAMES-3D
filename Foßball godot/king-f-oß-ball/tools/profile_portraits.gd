## Developer tool: measures player portrait rendering (needs a rendering device, e.g. a GPU under xvfb).
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/profile_portraits.tscn -- [count] [out.json]
## Prints the adapter name, first-render times (model + SubViewport), cached lookups, cache size and memory.
## Without a rendering device (headless) it says so and measures nothing.
extends Node


func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if not s.is_empty() else 0.0


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 60
	var out_path := args[1] if args.size() > 1 else ""
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var out := {"display_driver": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(),
			"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")), "count": count}
	if not PlayerPortraitRenderer.can_render():
		out["measured"] = false
		out["note"] = "no rendering device (headless): portrait rendering was NOT measured"
	else:
		var r := PlayerPortraitRenderer.shared(get_tree())
		await get_tree().process_frame
		var ids: Array = db.players.keys()
		ids.sort()
		var cards: Array = []
		var step := maxi(1, ids.size() / count)
		for i in count:
			cards.append(PlayerCardData.from_data(db, db.players[ids[(i * step) % ids.size()]]))
		var mem0 := OS.get_static_memory_usage()
		var first: Array = []
		for c in cards:
			var t0 := Time.get_ticks_usec()
			await r.request(c, db)
			first.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		var cached: Array = []
		for c in cards:
			var t0 := Time.get_ticks_usec()
			await r.request(c, db)
			cached.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		out["measured"] = true
		out["first_render_median_ms"] = _median(first)
		out["first_render_max_ms"] = first.max()
		out["first_render_total_ms"] = first.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
		out["cached_median_ms"] = _median(cached)
		out["renders"] = r.renders
		out["cache_hits"] = r.cache_hits
		out["cache_size"] = r.cache_size()
		out["max_cache"] = PlayerPortraitRenderer.MAX_CACHE
		out["static_memory_added_mb"] = float(OS.get_static_memory_usage() - mem0) / 1048576.0
		out["video_memory_mb"] = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	print("PORTRAIT_JSON ", JSON.stringify(out))
	for k in out:
		print("%-28s %s" % [k, str(out[k])])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	get_tree().quit()
