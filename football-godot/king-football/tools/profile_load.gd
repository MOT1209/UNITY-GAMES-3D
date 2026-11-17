## Developer tool: breaks the world load down into its cost centres (temporary profiling aid).
##   godot --headless --path . res://tools/profile_load.tscn
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var t_all := Time.get_ticks_msec()
	var db: TeamDatabase = get_node("/root/TeamDB")
	var t0 := Time.get_ticks_msec()
	db.load_countries()
	var t_countries := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	db.crests.load_defaults()
	var t_crest_defaults := Time.get_ticks_msec() - t0

	# Per-file breakdown of the pack.
	var base := "res://data/packs/real_2025/clubs"
	var dir := DirAccess.open(base)
	var files := dir.get_files()
	files.sort()
	var t_read := 0
	var t_parse := 0
	var t_from_dict := 0
	var t_validate := 0
	var t_ensure := 0
	var t_repair := 0
	var t_link := 0
	var n_players := 0
	var n_missing_appearance := 0
	for f in files:
		if f.get_extension() != "json":
			continue
		var a := Time.get_ticks_msec()
		var text := FileAccess.get_file_as_string("%s/%s" % [base, f])
		var b := Time.get_ticks_msec()
		var parsed: Variant = JSON.parse_string(text)
		var c := Time.get_ticks_msec()
		var team := TeamData.from_dict((parsed as Dictionary)["team"])
		var d := Time.get_ticks_msec()
		var roster: Array[PlayerData] = []
		for pd in (parsed as Dictionary).get("players", []):
			if typeof(pd) == TYPE_DICTIONARY:
				roster.append(PlayerData.from_dict(pd))
		var e := Time.get_ticks_msec()
		for p in roster:
			p.validate()
			if p.appearance.is_empty():
				n_missing_appearance += 1
		var g := Time.get_ticks_msec()
		for p in roster:
			PlayerAppearance.ensure(p)
		var h := Time.get_ticks_msec()
		KitEditor.repair(team)
		var i2 := Time.get_ticks_msec()
		for p in roster:
			db.link_player(p)
		var j := Time.get_ticks_msec()
		t_read += b - a
		t_parse += c - b
		t_from_dict += d - c
		t_validate += g - e
		t_ensure += h - g
		t_repair += i2 - h
		t_link += j - i2
		n_players += roster.size()
	print("files=%d players=%d missing_appearance=%d" % [files.size(), n_players, n_missing_appearance])
	print("read=%d ms  json_parse=%d ms  from_dict=%d ms  validate=%d ms  appearance_ensure=%d ms  kit_repair=%d ms  link_player=%d ms"
			% [t_read, t_parse, t_from_dict, t_validate, t_ensure, t_repair, t_link])
	print("countries=%d ms  crest_defaults=%d ms  total=%d ms" % [t_countries, t_crest_defaults, Time.get_ticks_msec() - t_all])
	get_tree().quit()
