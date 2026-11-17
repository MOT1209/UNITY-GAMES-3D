## Release readiness validation (UX phase 5): Android preset and icons, signing material kept out of
## the repository, detail LOD, developer performance overlay, quick/full test runner and CI workflow,
## KING CONTROLLER pairing limits, match teardown without leaked objects.
##   godot --headless --path . res://tests/release_readiness_validation.tscn
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
	print("=== KING FOOTBALL — Release readiness validation ===")
	_test_android_preset()
	_test_public_preset()
	_test_repository_hygiene()
	await _test_lod_and_overlay()
	_test_runner_and_ci()
	_test_controller_limits()
	await _test_match_teardown()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## The public (Google Play) release leaves the real club / player data pack out until a legal review.
func _test_public_preset() -> void:
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var section := ""
	var normal := ""
	for i in 10:
		var s := "preset.%d" % i
		if cfg.has_section(s) and str(cfg.get_value(s, "name", "")) == "release_public":
			section = s
		elif cfg.has_section(s) and str(cfg.get_value(s, "platform", "")) == "Android" and normal == "":
			normal = s
	_check(section != "", "a 'release_public' export preset exists")
	_check(str(cfg.get_value(section, "exclude_filter", "")).contains("data/packs/real_2025"), "release_public excludes data/packs/real_2025")
	_check(not str(cfg.get_value(normal, "exclude_filter", "")).contains("real_2025"), "the normal preset keeps the real pack (development builds)")
	_check(str(cfg.get_value(section, "platform", "")) == "Android" and str(cfg.get_value(section + ".options", "package/unique_name", "")) == str(cfg.get_value(normal + ".options", "package/unique_name", "")),
			"release_public is the same Android app")
	var script := FileAccess.get_file_as_string("res://tools/export_android.sh")
	_check(script.contains("--public") and script.contains("release_public"), "tools/export_android.sh has a --public option")
	_check(not TeamDatabase.configured_pack().contains("real") or OS.get_environment("KING_DATA_PACK") != "", "the default world is the fictional one, not the real pack")


func _test_android_preset() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load("res://export_presets.cfg") == OK, "export presets load")
	var section := ""
	for i in 10:
		var s := "preset.%d" % i
		if cfg.has_section(s) and str(cfg.get_value(s, "platform", "")) == "Android":
			section = s + ".options"
	_check(section != "", "an Android preset exists")
	_check(str(cfg.get_value(section, "version/name", "")) != "" and int(cfg.get_value(section, "version/code", 0)) >= 1, "version name and code are set")
	# Min/target SDK are set explicitly (round 3). Godot refuses any SDK override without a Gradle build, so
	# the Gradle build is on and tools/export_android.sh installs the build template. Google Play requires
	# new apps and updates to target API 36 (Android 16) from 31 Aug 2026; Godot 4.7 needs API 24+.
	var gradle := bool(cfg.get_value(section, "gradle_build/use_gradle_build", false))
	var min_sdk := str(cfg.get_value(section, "gradle_build/min_sdk", ""))
	var target_sdk := str(cfg.get_value(section, "gradle_build/target_sdk", ""))
	_check(min_sdk.is_valid_int() and int(min_sdk) >= 24, "min SDK is set explicitly (>= 24)", min_sdk)
	_check(target_sdk.is_valid_int() and int(target_sdk) >= 36, "target SDK is set explicitly and meets Google Play (>= 36)", target_sdk)
	_check(target_sdk.is_valid_int() and min_sdk.is_valid_int() and int(target_sdk) >= int(min_sdk), "target SDK >= min SDK")
	_check(gradle, "SDK overrides come with a Gradle build (else the export is refused)")
	_check(FileAccess.get_file_as_string("res://tools/export_android.sh").contains("--install-android-build-template"),
			"the export script installs the Android build template the Gradle build needs")
	_check(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)),
			"ETC2/ASTC texture compression is on (required for any Android export)")
	_check(bool(cfg.get_value(section, "permissions/internet", false)) and bool(cfg.get_value(section, "permissions/access_wifi_state", false)),
			"network permissions for the KING CONTROLLER server")
	for key in ["launcher_icons/main_192x192", "launcher_icons/adaptive_foreground_432x432", "launcher_icons/adaptive_background_432x432"]:
		var path := str(cfg.get_value(section, key, ""))
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if path != "" else null
		var want := 192 if key.ends_with("192x192") else 432
		_check(img != null and img.get_width() == want and img.get_height() == want, "%s: %s (%d px)" % [key, path, want])
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	_check(not svg.contains("478cbf"), "the app icon is the game's own (not the engine logo)")


func _test_repository_hygiene() -> void:
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	_check(ignore.contains("*.keystore") and ignore.contains("*.jks") and ignore.contains("export_credentials.cfg"),
			"release keystores and export credentials are git-ignored")
	_check(FileAccess.file_exists("res://docs/ANDROID_RELEASE.md"), "the keystore / release procedure is documented")
	var found: Array = []
	_find_keystores("res://", found)
	_check(found.is_empty(), "no keystore inside the project", str(found))


func _find_keystores(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".keystore") or f.ends_with(".jks"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_find_keystores(dir.path_join(sub), out)


func _test_lod_and_overlay() -> void:
	var db := get_node("/root/TeamDB")
	db.load_world("")
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 2
	setup.rng_seed = 9
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	await get_tree().process_frame
	var badges := m.find_children("Badge", "MeshInstance3D", true, false)
	_check(not badges.is_empty() and badges.all(func(b: MeshInstance3D) -> bool: return b.visibility_range_end > 0.0 and b.visibility_range_end <= 40.0),
			"crest badges have a visibility range (LOD)", "%d badges" % badges.size())
	var faces := m.find_children("Face", "MeshInstance3D", true, false)
	_check(not faces.is_empty() and faces.all(func(f: MeshInstance3D) -> bool: return f.visibility_range_end == PlayerCharacterVisual.FACE_LOD_END),
			"face features have a visibility range (LOD)", "%d faces" % faces.size())
	var ref_hair := m.referee.find_children("*_Hair_*", "MeshInstance3D", true, false).filter(func(h: MeshInstance3D) -> bool: return h.visible)
	_check(ref_hair.size() <= 1, "the referee draws one hair mesh, not every variant", str(ref_hair.size()))
	m.queue_free()
	await get_tree().process_frame
	for glb in ["player", "goalkeeper", "referee"]:
		var imp := FileAccess.get_file_as_string("res://assets/models/characters/%s.glb.import" % glb)
		_check(imp.contains("meshes/generate_lods=true"), "%s meshes are imported with generated LODs" % glb)
	_check(FileAccess.get_file_as_string("res://assets/models/stadium/stadium.glb.import").contains("meshes/generate_lods=true"), "stadium meshes have generated LODs")
	var cfg_path: String = GameSettings.settings_path
	GameSettings.settings_path = "user://test_rr_settings.cfg"
	GameSettings.set_value("graphics", "shadows", "low")
	GameSettings.apply_graphics(get_tree().root)
	var low_lod := get_tree().root.mesh_lod_threshold
	GameSettings.set_value("graphics", "shadows", "high")
	GameSettings.apply_graphics(get_tree().root)
	_check(low_lod > get_tree().root.mesh_lod_threshold, "phone quality switches to simpler meshes earlier (mesh LOD threshold)",
			"%.1f vs %.1f" % [low_lod, get_tree().root.mesh_lod_threshold])
	DirAccess.remove_absolute("user://test_rr_settings.cfg")
	GameSettings.settings_path = cfg_path
	GameSettings.apply_graphics(get_tree().root)
	_check(StandCrowd.MAX_SPECTATORS_LOW < StandCrowd.MAX_SPECTATORS, "phones draw fewer spectators")
	var vis := PlayerCharacterVisual.new()
	_check(vis.anim_fade >= 0.1 and vis.run_clip_speed > vis.walk_clip_speed, "locomotion clips cross-fade (blend) and play at speed-matched rates")
	vis.free()
	var overlay := PerfOverlay.new()
	add_child(overlay)
	var snap := PerfOverlay.snapshot()
	_check(snap.has("fps") and snap.has("draw_calls") and snap.has("memory_mb") and PerfOverlay.format(snap).contains("draw calls"),
			"performance overlay reports FPS, draw calls and memory")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.pressed = true
	overlay._unhandled_input(ev)
	_check(overlay.visible, "F3 shows the overlay")
	overlay.queue_free()
	ScreenRegistry.force_developer = 0
	_check(not ScreenRegistry.developer_mode(), "release builds create no overlay (developer mode off)")
	ScreenRegistry.force_developer = -1


func _test_runner_and_ci() -> void:
	var runner := FileAccess.get_file_as_string("res://tests/run_all.sh")
	_check(runner.contains("--quick") and runner.contains("SLOW_SUITES") and runner.contains("career_longevity_validation"),
			"run_all.sh has --quick (skips the long career / performance suites) and --full")
	var wf := ProjectSettings.globalize_path("res://").path_join("../../.github/workflows/king-football-tests.yml").simplify_path()
	var text := FileAccess.get_file_as_string(wf)
	_check(text.contains("run_all.sh") and text.contains("--headless") and text.contains("push:"), "GitHub Actions runs the suites headless on every push", wf)


func _test_controller_limits() -> void:
	# P9: the pairing rules live in KingControllerRegistry (full coverage: controller_session_validation).
	var reg := KingControllerRegistry.new(1)
	reg.rotate_token(0)
	var first := reg.token
	_check(reg.try_pair("AAAAAAAA", "x", 1000)["reason"] == "bad_token" and reg.try_pair(first, "x", KingControllerProtocol.TOKEN_TTL_MS + 5)["reason"] == "token_expired", "an old token expires")
	reg.rotate_token(0)
	first = reg.token
	var last := {}
	for i in KingControllerProtocol.MAX_FAILED_PAIRINGS:
		last = reg.try_pair("AAAAAAAA", "x", 10)
	_check(last.get("reason", "") == "too_many_attempts" and reg.token != first, "after %d wrong tokens a new token (new QR) is issued" % KingControllerProtocol.MAX_FAILED_PAIRINGS)
	var used := reg.token
	var ok := reg.try_pair(used, "x", 20)
	_check(bool(ok["ok"]), "the new token pairs")
	_check(reg.token != used and not bool(reg.try_pair(used, "y", 30)["ok"]), "a token is single-use: it is replaced after a pairing and cannot be replayed")


func _test_match_teardown() -> void:
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 2:
		var setup := MatchSetup.new()
		setup.home_id = "club_royal_harbor"
		setup.away_id = "club_northgate_utd"
		setup.duration_minutes = 2
		setup.rng_seed = 20 + i
		var m := MatchManager.new()
		m.return_to_menu_on_finish = false
		add_child(m)
		m.begin(setup, get_node("/root/TeamDB"))
		for f in 5:
			await get_tree().physics_frame
		var rules: WeakRef = weakref(m.rules)
		var restarts: WeakRef = weakref(m.rules.restarts)
		m.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(rules.get_ref() == null and restarts.get_ref() == null, "match %d: rules and restarts are freed with the match (no reference cycle)" % i)
	var after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	_check(after - before < 200, "building and freeing matches leaves no growing object count", "%d -> %d" % [int(before), int(after)])
