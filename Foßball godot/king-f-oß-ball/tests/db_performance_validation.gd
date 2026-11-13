## Database phase 9 — performance guard: measures the real database (298 clubs, 8013 players) and fails only on
## a catastrophic regression (generous limits, so a slow machine does not break it). The numbers are printed.
##   godot --headless --path . res://tests/db_performance_validation.tscn
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — database phase 9 (performance) validation ===")
	var db: TeamDatabase = get_node("/root/TeamDB")
	var r := DbProfiler.run(db, "real_2025")
	for k in ["load_world_ms", "player_lookup_us_each", "get_squad_all_clubs_ms", "team_rating_all_clubs_ms", "search_players_text_ms", "validate_all_ms",
			"crest_first_pass_per_crest_ms", "crest_cached_pass_ms", "kit_texture_ms_each", "save_capture_ms", "save_write_ms", "save_read_ms",
			"save_restore_ms", "save_file_mb", "migrate_v2_to_v3_ms", "memory_added_mb"]:
		print("[PERF] %-32s %.2f" % [k, float(r[k])])
	_check(r["clubs"] == 298 and r["players"] == 8013, "measured at the real size: 298 clubs, 8013 players")
	_check(float(r["load_world_ms"]) < 10000.0, "starting the real world takes under 10 s (%.0f ms)" % float(r["load_world_ms"]))
	_check(float(r["memory_added_mb"]) < 400.0, "the loaded database adds under 400 MB of memory (%.0f MB)" % float(r["memory_added_mb"]))
	_check(float(r["player_lookup_us_each"]) < 50.0 and float(r["team_lookup_us_each"]) < 50.0, "indexed id lookup stays in the microsecond range (%.2f us)" % float(r["player_lookup_us_each"]))
	_check(r["lookup_hits"] == 400000, "all lookups found their record")
	_check(float(r["get_squad_all_clubs_ms"]) < 2000.0 and float(r["team_rating_all_clubs_ms"]) < 3000.0, "loading every squad and rating takes well under 2-3 s")
	_check(float(r["search_players_text_ms"]) < 5000.0 and float(r["search_clubs_ms"]) < 1000.0, "text search over all players is interactive")
	_check(int(r["validate_critical"]) == 0 and int(r["validate_relations_problems"]) == 0, "validation of the real world finds nothing critical")
	_check(float(r["validate_all_ms"]) < 30000.0, "a full validation stays outside gameplay and finishes in seconds (%.0f ms)" % float(r["validate_all_ms"]))
	_check(float(r["crest_first_pass_per_crest_ms"]) < 100.0, "a crest icon is drawn in well under 100 ms (%.1f ms)" % float(r["crest_first_pass_per_crest_ms"]))
	_check(int(r["crest_cache_hits"]) == 298 and float(r["crest_cached_pass_ms"]) < float(r["crest_first_pass_ms"]), "a second pass over all 298 clubs comes from the crest cache (no thrashing)", "%s hits" % str(r["crest_cache_hits"]))
	_check(CrestService.cache.bytes <= CrestCache.MAX_BYTES, "the crest cache stays within its memory budget (%.1f MB)" % (float(CrestService.cache.bytes) / 1048576.0))
	_check(float(r["kit_texture_ms_each"]) < 1500.0, "a kit texture is drawn in well under 1.5 s (%.0f ms) and then cached" % float(r["kit_texture_ms_each"]))
	_check(r["save_error"] == "" and r["save_restore_ok"] and float(r["save_file_mb"]) < 60.0, "a full save of the whole world is %.1f MB and restores" % float(r["save_file_mb"]))
	_check(float(r["save_capture_ms"]) + float(r["save_write_ms"]) < 20000.0 and float(r["save_read_ms"]) + float(r["save_restore_ms"]) < 30000.0, "saving and loading the whole world take seconds, not minutes")
	_check(r["migrate_ok"] and float(r["migrate_v2_to_v3_ms"]) < 20000.0, "migrating an old save of this size takes %.0f ms" % float(r["migrate_v2_to_v3_ms"]))
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
