## Match UX validation (UX phase 2): selection indicator, automatic player switching, camera
## (follow default, broadcast ball tracking + zoom, persisted choice), HUD scoreboard (RTL order,
## stamina, 2-second camera label, key hints) and lighting / shadow settings.
##   godot --headless --path . res://tests/match_ux_validation.tscn
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"
const TEST_SETTINGS := "user://test_match_ux_settings.cfg"

var _passed := 0
var _failed := 0
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Match UX validation ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	var original: String = GameSettings.settings_path
	GameSettings.settings_path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)
	_test_settings_store()
	_test_policy()
	await _test_indicator()
	await _test_auto_switch()
	await _test_semi_and_manual()
	await _test_camera()
	await _test_hud()
	await _test_results_order()
	await _test_lighting()
	DirAccess.remove_absolute(TEST_SETTINGS)
	GameSettings.settings_path = original
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _match(human := "home", switch_mode := "auto") -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 10
	setup.human_side = human
	setup.switch_mode = switch_mode
	setup.rng_seed = 5
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		_check(false, "match builds", err)
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	return m


func _discard(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame


## Puts the ball at the feet of `e` (as a received pass / won ball would) and lets possession update.
func _give_ball(m: MatchManager, e: Dictionary) -> void:
	var p := (e["node"] as Node3D).global_position
	m.ball.reset_ball(Vector3(p.x, 0.3, p.z))
	await _frames(3)


# --- settings ---------------------------------------------------------------------------------

func _test_settings_store() -> void:
	_check(GameSettings.get_value("match", "camera") == "follow" and GameSettings.get_value("match", "switch_mode") == "auto",
			"defaults: follow camera, automatic switching")
	GameSettings.set_value("match", "switch_mode", "semi")
	GameSettings.set_value("match", "camera", "broadcast")
	_check(GameSettings.get_value("match", "switch_mode") == "semi" and GameSettings.get_value("match", "camera") == "broadcast",
			"match settings are saved and loaded")
	GameSettings.set_value("match", "switch_mode", "nonsense")
	_check(GameSettings.get_value("match", "switch_mode") == "auto", "an invalid value falls back to the default")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	cfg.set_value("game", "language", "de")
	cfg.save(TEST_SETTINGS)
	GameSettings.set_value("match", "camera", "follow")
	cfg = ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	_check(cfg.get_value("game", "language", "") == "de", "saving a game setting keeps the other sections (language)")
	var s := MatchSetup.new()
	s.switch_mode = "manual"
	_check(MatchSetup.from_dict(s.to_dict()).switch_mode == "manual", "the match setup carries the switch mode (save / restart)")
	GameSettings.set_value("match", "switch_mode", "auto")


func _test_policy() -> void:
	var p := AutoSwitchPolicy.new("auto", "home")
	var mate := {"side": "home", "slot": 7, "player_id": "b"}
	_check(p.on_owner({"side": "home", "slot": 9, "player_id": "a"}, "a", false, 1.0) == "", "own player keeps the ball: no switch")
	_check(p.on_owner(mate, "a", false, 2.0) == "receiver", "a team-mate receives the ball: he is selected")
	_check(p.on_owner({"side": "home", "slot": 3, "player_id": "c"}, "b", false, 2.2) == "", "no second switch within the 0.4 s cooldown")
	_check(p.on_owner({"side": "away", "slot": 5, "player_id": "x"}, "c", false, 3.0) == "closest", "losing the ball selects the closest player (auto)")
	_check(p.on_owner(mate, "c", true, 5.0) == "", "never switches while the human charges a kick")
	_check(p.on_owner({"side": "home", "slot": 0, "player_id": "gk"}, "c", false, 6.0) == "", "the goalkeeper is never selected")
	var semi := AutoSwitchPolicy.new("semi", "home")
	semi.on_owner({"side": "home", "slot": 9, "player_id": "a"}, "a", false, 1.0)
	_check(semi.on_owner({"side": "away", "slot": 5, "player_id": "x"}, "a", false, 2.0) == "", "semi: losing the ball does not switch")
	_check(semi.on_owner(mate, "a", false, 3.0) == "receiver", "semi: the pass receiver is selected")
	var manual := AutoSwitchPolicy.new("manual", "home")
	_check(manual.on_owner(mate, "a", false, 3.0) == "", "manual: never switches on its own")


# --- indicator ----------------------------------------------------------------------------------------

func _test_indicator() -> void:
	var m := _match()
	await _frames(2)
	var ind := m.selection_indicator
	_check(ind != null and ind.get_parent() == m.selected["node"], "the selection ring is a child of the selected player")
	_check(ind != null and ind.find_child("Ring", true, false) is MeshInstance3D and ind.find_child("HeadMarker", true, false) is Label3D,
			"indicator = ground ring + head marker")
	var mat := (ind.find_child("Ring", true, false) as MeshInstance3D).material_override as StandardMaterial3D
	_check(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			"ring is unshaded and transparent")
	var before: Node = m.selected["node"]
	m.switch_player()
	await _frames(1)
	_check(m.selected["node"] != before and ind.get_parent() == m.selected["node"], "after switch_player() the ring moves at once to the new player")
	var only_one := 0
	for side in m.entries:
		for e in m.entries[side]:
			only_one += (e["node"] as Node).find_children("*", "SelectionIndicator", true, false).size()
	_check(only_one == 1, "exactly one indicator in the match", str(only_one))
	m.human_intent.set_driven(true)
	m.human_intent.set_move(Vector2(1, 0))
	await _frames(20)
	await get_tree().process_frame
	_check((ind.find_child("RunArrow", true, false) as Node3D).visible, "run-direction arrow shows while the player runs",
			"speed %.2f" % (m.selected["node"] as CharacterBody3D).velocity.length())
	m.human_intent.set_move(Vector2.ZERO)
	m.human_intent.set_driven(false)
	await _discard(m)
	var cpu := _match("none")
	await _frames(2)
	var any := cpu.find_children("*", "SelectionIndicator", true, false)
	_check(cpu.selection_indicator == null and any.is_empty(), "no indicator when nobody is human-controlled (human_side none)")
	await _discard(cpu)
	var second := SelectionIndicator.new(1)
	_check(second.color == SelectionIndicator.SLOT_COLORS[1], "second controller slot has its own colour")
	second.free()
	var dark := SelectionIndicator.readable(Color(0.05, 0.08, 0.3))
	_check(dark.get_luminance() > 0.45, "dark kit colours are lightened so the ring stays visible")


# --- automatic switching ---------------------------------------------------------------------------------

func _mate(m: MatchManager, exclude: Dictionary) -> Dictionary:
	for e in m.entries["home"]:
		if int(e["slot"]) != 0 and e != exclude:
			return e
	return {}


func _test_auto_switch() -> void:
	var m := _match("home", "auto")
	await _frames(2)
	await _give_ball(m, m.selected)
	var first: Dictionary = m.selected
	m._clock += 1.0
	var receiver := _mate(m, first)
	await _give_ball(m, receiver)
	_check(m.selected == receiver, "auto: the team-mate who receives the ball becomes the selected player",
			"selected slot %s, receiver slot %s" % [str(m.selected.get("slot")), str(receiver.get("slot"))])
	m._clock += 1.0
	var opp: Dictionary = m.entries["away"][6]
	await _give_ball(m, opp)
	var closest := m._closest_to_ball("home", -1)
	_check(m.selected == closest,
			"auto: losing the ball selects the home player closest to the ball")
	_check(m.selection_indicator.get_parent() == m.selected["node"], "the ring follows automatic switches")
	await _discard(m)


func _test_semi_and_manual() -> void:
	var m := _match("home", "manual")
	await _frames(2)
	await _give_ball(m, m.selected)
	var first: Dictionary = m.selected
	m._clock += 1.0
	await _give_ball(m, _mate(m, first))
	_check(m.selected == first, "manual: receiving team-mate is NOT selected automatically")
	await _discard(m)


# --- camera -----------------------------------------------------------------------------------------------

func _test_camera() -> void:
	GameSettings.set_value("match", "camera", "follow")
	var m := _match()
	await _frames(2)
	var cam := m.camera as GameCamera
	_check(cam != null and cam.mode == GameCamera.Mode.FOLLOW, "follow camera is the default in human play")
	_check(cam.follow_target == m.selected["node"], "follow camera targets the selected player")
	await _discard(m)
	GameSettings.set_value("match", "camera", "broadcast")
	m = _match()
	await _frames(2)
	cam = m.camera as GameCamera
	_check(cam.mode == GameCamera.Mode.BROADCAST, "the saved camera choice (broadcast) is used")
	_check(cam.tracked_ball == m.ball, "broadcast camera tracks the ball")
	m.ball.reset_ball(Vector3(0.0, 0.3, 30.0))
	for i in 120:
		await get_tree().process_frame
	var look_z := cam.global_position.z - cam.config.broadcast_position_offset.z
	_check(absf(look_z - m.ball.global_position.z) < 6.0, "broadcast camera follows the ball along the pitch (smoothed)",
			"camera look z %.1f, ball z %.1f" % [look_z, m.ball.global_position.z])
	_check(cam.fov >= cam.config.broadcast_fov - 0.01 and cam.fov <= cam.config.broadcast_wide_fov + 0.01, "dynamic zoom stays between the two fields of view", str(cam.fov))
	m.ball.linear_velocity = Vector3(0, 0, 25)
	var fov_slow := cam.fov
	for i in 20:
		m.ball.linear_velocity = Vector3(0, 0, 25)
		await get_tree().process_frame
	_check(cam.fov > fov_slow, "fast play widens the view", "%.2f -> %.2f" % [fov_slow, cam.fov])
	var arena := m.arena_root as StadiumPrototype
	var ev := InputEventAction.new()
	ev.action = &"camera_toggle"
	ev.pressed = true
	arena._unhandled_input(ev)
	_check(cam.mode == GameCamera.Mode.FOLLOW and GameSettings.get_value("match", "camera") == "follow", "toggling the camera in a match saves the choice")
	_check(arena.camera_mode_label.visible and arena.camera_label_seconds_left() > 1.5, "camera label appears on a camera change")
	await get_tree().create_timer(2.3).timeout
	_check(not arena.camera_mode_label.visible, "camera label hides itself after 2 seconds")
	await _discard(m)
	GameSettings.set_value("match", "camera", "follow")


# --- HUD ----------------------------------------------------------------------------------------------------

func _crest_x(hud: Control, club: String) -> float:
	for c in hud.find_children("*", "TextureRect", true, false):
		if (c as Node).has_meta("crest_club") and (c as Node).get_meta("crest_club") == club:
			return (c as Control).get_global_rect().get_center().x
	return -1.0


func _test_hud() -> void:
	for code in ["en", "ar"]:
		Loc.set_language(code, false)
		var m := _match()
		await _frames(3)
		await get_tree().process_frame
		var hud := m.hud
		_check(hud != null and hud.find_child("Scoreboard", true, false) is PanelContainer, "[%s] scoreboard panel exists" % code)
		var sb := (hud.find_child("Scoreboard", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		_check(sb != null and sb.bg_color.a > 0.5 and sb.bg_color.a < 1.0 and sb.corner_radius_top_left > 0,
				"[%s] scoreboard has a dark, semi-transparent, rounded background" % code)
		var hx := _crest_x(hud, TEAM_H)
		var ax := _crest_x(hud, TEAM_A)
		if code == "ar":
			_check(hx > ax, "[ar] home team is on the RIGHT of the scoreboard", "home x %.0f away x %.0f" % [hx, ax])
		else:
			_check(hx < ax and hx > 0.0, "[en] home team is on the left of the scoreboard", "home x %.0f away x %.0f" % [hx, ax])
		_check((hud.find_child("Half", true, false) as Label).text == Loc.f("HUD_HALF_N", 1), "[%s] half indicator" % code)
		_check((hud.find_child("StaminaPanel", true, false) as Control).visible, "[%s] stamina of the controlled player is shown" % code)
		m.state.goal("home", "")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(hud.score_text() == "1-0", "[%s] score updates after a goal" % code, hud.score_text())
		var hints := m.arena_root.find_child("ControlHints", true, false) as ControlHints
		_check(hints != null and hints.visible and hints.get_child_count() == ControlHints.PAIRS.size(), "[%s] key-hint chips shown at kick-off" % code)
		await _discard(m)
	Loc.set_language("en", false)
	var cpu := _match("none")
	await _frames(2)
	_check(not (cpu.hud.find_child("StaminaPanel", true, false) as Control).visible, "no stamina panel when nobody is human-controlled")
	await _discard(cpu)


func _test_results_order() -> void:
	for code in ["en", "ar"]:
		Loc.set_language(code, false)
		var m := _match()
		await _frames(2)
		m.state.goal("home", "")
		m._finish()
		await get_tree().process_frame
		await get_tree().process_frame
		var rv := m.results_view
		var hx := _crest_x(rv, TEAM_H)
		var ax := _crest_x(rv, TEAM_A)
		var score := rv.find_child("ScoreLabel", true, false) as Label
		if code == "ar":
			_check(hx > ax and score.text == "0 - 1", "[ar] results screen: home on the right, its goal next to its name",
					"home x %.0f away x %.0f score '%s'" % [hx, ax, score.text])
		else:
			_check(hx < ax and score.text == "1 - 0", "[en] results screen: home on the left", "score '%s'" % score.text)
		await _discard(m)
	Loc.set_language("en", false)


# --- lighting ----------------------------------------------------------------------------------------------

func _test_lighting() -> void:
	var m := _match()
	await _frames(1)
	var sun := m.arena_root.get_node("Sun") as DirectionalLight3D
	_check(sun.directional_shadow_max_distance <= 90.0, "shadow distance reduced for phones (<= 90 m, was 220)", str(sun.directional_shadow_max_distance))
	_check(sun.shadow_opacity < 1.0 and sun.shadow_opacity >= 0.4, "stand shadows are softened (opacity < 1)")
	_check(sun.rotation.x <= -1.0, "steeper sun: the stand shadow no longer reaches across the pitch", str(sun.rotation.x))
	_check(MatchEnvironment.apply_shadow_quality(sun, "off") == "off" and not sun.shadow_enabled, "graphics setting 'off' disables sun shadows")
	_check(MatchEnvironment.apply_shadow_quality(sun, "low") == "low" and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
			and sun.directional_shadow_max_distance <= 60.0, "graphics setting 'low': one cheap shadow map")
	_check(MatchEnvironment.apply_shadow_quality(sun, "high") == "high" and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			"graphics setting 'high': two splits")
	await _discard(m)
