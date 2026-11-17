class_name DbProfiler
extends RefCounted

## Measures the database operations that matter at 298 clubs / 8,000+ players (database phase 9).
## Everything is wall-clock time of the real code on the machine that runs it (the numbers in
## docs/PERFORMANCE_REPORT.md come from a headless CPU run). Portrait rendering needs a GPU
## (SubViewport) and is therefore not measured here.

const SAVE_PATH := "user://profile_save.json"


static func _ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


## Runs every measurement on `db` (a TeamDatabase autoload/instance). `world` is loaded first.
static func run(db: Node, world: String = "real_2025") -> Dictionary:
	var r := {}
	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_usec()
	db.load_world(world)
	r["load_world_ms"] = _ms(t0)
	r["clubs"] = db.teams.size()
	r["players"] = db.players.size()
	r["memory_mb_after_load"] = float(OS.get_static_memory_usage()) / 1048576.0
	r["memory_added_mb"] = float(OS.get_static_memory_usage() - mem0) / 1048576.0
	var t1 := Time.get_ticks_usec()
	db.load_world(world)
	r["reload_ms"] = _ms(t1)

	# indexed lookups
	var ids: Array = db.players.keys()
	var team_ids: Array = db.teams.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var n := 200000
	var t2 := Time.get_ticks_usec()
	var hit := 0
	for i in n:
		hit += 1 if db.get_player(ids[rng.randi() % ids.size()]) != null else 0
	r["player_lookup_us_each"] = _ms(t2) * 1000.0 / n
	var t3 := Time.get_ticks_usec()
	for i in n:
		hit += 1 if db.get_team(team_ids[rng.randi() % team_ids.size()]) != null else 0
	r["team_lookup_us_each"] = _ms(t3) * 1000.0 / n
	r["lookup_hits"] = hit

	# squads and ratings
	var t4 := Time.get_ticks_usec()
	var members := 0
	for tid in team_ids:
		members += db.get_squad(tid).size()
	r["get_squad_all_clubs_ms"] = _ms(t4)
	r["squad_members"] = members
	var t5 := Time.get_ticks_usec()
	for tid in team_ids:
		db.get_team_rating(tid)
	r["team_rating_all_clubs_ms"] = _ms(t5)

	# search and validation
	var t6 := Time.get_ticks_usec()
	var found := DatabaseTools.search_players(db, {"text": "mar"})
	r["search_players_text_ms"] = _ms(t6)
	r["search_players_hits"] = found.size()
	var t7 := Time.get_ticks_usec()
	DatabaseTools.search_clubs(db, {"text": "united"})
	r["search_clubs_ms"] = _ms(t7)
	var t8 := Time.get_ticks_usec()
	var v := DatabaseTools.validate_all(db)
	r["validate_all_ms"] = _ms(t8)
	r["validate_critical"] = (v["critical"] as Array).size()
	var t9 := Time.get_ticks_usec()
	var rel: Array = db.validate_relations()
	r["validate_relations_ms"] = _ms(t9)
	r["validate_relations_problems"] = rel.size()

	# crests: lazy drawing, cache behaviour
	CrestService.cache.clear()
	var clubs: Array = db.list_teams(TeamData.Category.CLUB)
	var t10 := Time.get_ticks_usec()
	for t in clubs:
		CrestService.texture(db, t, "icon")
	r["crest_first_pass_ms"] = _ms(t10)
	r["crest_first_pass_per_crest_ms"] = _ms(t10) / clubs.size()
	var t11 := Time.get_ticks_usec()
	for t in clubs:
		CrestService.texture(db, t, "icon")
	r["crest_cached_pass_ms"] = _ms(t11)
	r["crest_cache_entries"] = CrestService.cache.size()
	r["crest_cache_hits"] = CrestService.cache.hits
	var t12 := Time.get_ticks_usec()
	for i in 20:
		CrestRenderer.render(db.crests.for_team(clubs[i]), "full")
	r["crest_full_128px_ms_each"] = _ms(t12) / 20.0
	var t13 := Time.get_ticks_usec()
	for i in 20:
		KitService.texture(db, clubs[i], "home")
	r["kit_texture_ms_each"] = _ms(t13) / 20.0

	# save and restore of the whole world
	var t14 := Time.get_ticks_usec()
	var data := SaveManager.capture(db)
	r["save_capture_ms"] = _ms(t14)
	var t15 := Time.get_ticks_usec()
	var err := SaveManager.write_file(SAVE_PATH, data)
	r["save_write_ms"] = _ms(t15)
	r["save_error"] = err
	r["save_file_mb"] = float(FileAccess.get_file_as_bytes(SAVE_PATH).size()) / 1048576.0
	var t16 := Time.get_ticks_usec()
	var rd := SaveManager.read_file(SAVE_PATH)
	r["save_read_ms"] = _ms(t16)
	var t17 := Time.get_ticks_usec()
	var res := SaveManager.restore(db, rd["data"])
	r["save_restore_ms"] = _ms(t17)
	r["save_restore_ok"] = res["ok"]
	# an old (v2) file: migration cost
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	old["save_version"] = 2
	for t in old["teams"]:
		for k in ["club_type", "country_id", "crest_id"]:
			t.erase(k)
	for p in old["players"]:
		for k in ["first_name", "last_name", "nationality_id", "player_type"]:
			p.erase(k)
	var t18 := Time.get_ticks_usec()
	var mig := SaveManager.migrate(old)
	r["migrate_v2_to_v3_ms"] = _ms(t18)
	r["migrate_ok"] = not mig.has("error")
	DirAccess.remove_absolute(SAVE_PATH)

	# portraits: not measurable without a GPU
	r["portrait_rendering"] = "not measured (needs a rendering device)"
	r["environment"] = "%s, %s, %d cores" % [OS.get_name(), DisplayServer.get_name(), OS.get_processor_count()]
	return r
