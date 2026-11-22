extends Node
## Phase 1 shooting experiment: real keeper (TeamGoalkeeper) v real ball physics, AI-style shots.
## Every outfield player and the match manager are switched off; only the away keeper and the ball run, so the
## result is the keeper-v-shot balance alone (no blocks, no restarts). Each shot: ball placed, keeper settles for
## 1.5 s, the home striker's own spread (FootballActions.shot_spread_degrees) and power (default x his multiplier)
## are applied at PlayerAI.shot_target, exactly what an AI tap shot does.
##   godot --headless --fixed-fps 60 --path . res://tools/exp/shots.tscn -- n=8 [charge=0.0] [seed=1]

var _m: MatchManager
var _gk: TeamGoalkeeper
var _goal := Vector3.ZERO


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback


func _ready() -> void:
	var n := int(_arg("n", "8"))
	var charge := float(_arg("charge", "0.0"))
	seed(int(_arg("seed", "1")))
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 5
	setup.human_side = "none"
	setup.rng_seed = 7
	_m = MatchManager.new()
	_m.return_to_menu_on_finish = false
	add_child(_m)
	_m.begin(setup, db)
	for i in 30:
		await get_tree().physics_frame
	_goal = PitchSpace.opponent_goal(_m.frame_side("home"))
	var shooter: Dictionary = _m.entries["home"][_m.entries["home"].size() - 1]
	var acts := shooter["actions"] as FootballActions
	_gk = _m.entries["away"][0]["node"] as TeamGoalkeeper
	var gk_home := _gk.home
	# freeze everything but the keeper and the ball
	_m.process_mode = Node.PROCESS_MODE_DISABLED
	_gk.process_mode = Node.PROCESS_MODE_ALWAYS
	_m.ball.process_mode = Node.PROCESS_MODE_ALWAYS
	var park := 0
	for side in ["home", "away"]:
		for e: Dictionary in _m.entries[side]:
			var node := e["node"] as Node3D
			if node == _gk:
				continue
			node.global_position = Vector3(30.0 + float(park % 4), 0.0, float(park) * 1.5 - 15.0)
			park += 1
	var spread := acts.shot_spread_degrees(charge)
	var power := lerpf(acts.config.default_shoot_power, acts.config.max_shoot_power, charge)
	if acts.attribute_modifiers != null:
		power *= acts.attribute_modifiers.shot_power_multiplier()
	power = clampf(power, acts.config.min_shoot_power, acts.config.max_shoot_power)
	var lift := lerpf(acts.config.min_shot_lift, acts.config.max_shot_lift, charge)
	print("shooter spread +-%.1f deg, power %.1f m/s, lift %.1f; keeper factor %.2f" % [spread, power, lift, _gk._gk_factor()])
	var gs := signf(_goal.z)
	var totals := {"goal": 0, "caught": 0, "parried": 0, "wide": 0}
	for d: float in [11.0, 16.0, 20.0, 25.0]:
		for x: float in [0.0, 7.0, 13.0]:
			var row := {"goal": 0, "caught": 0, "parried": 0, "wide": 0}
			for i in n:
				var r := await _shot(Vector3(_goal.x + x * (1.0 if i % 2 == 0 else -1.0), 0.11, _goal.z - gs * d), spread, power, lift, gk_home)
				row[r] += 1
				totals[r] += 1
			print("dist %4.1f  off-centre %4.1f  %s" % [d, x, str(row)])
	var shots := 0
	for k in totals:
		shots += int(totals[k])
	var on := shots - int(totals["wide"])
	print("TOTAL %s  on target %.0f%%  goals / on target %.0f%%" % [str(totals), 100.0 * on / maxf(shots, 1), 100.0 * totals["goal"] / maxf(on, 1)])
	get_tree().quit()


func _shot(at: Vector3, spread: float, power: float, lift: float, gk_home: Vector3) -> String:
	_gk.reset_to(gk_home, -signf(_goal.z))
	_m.ball.reset_ball(at)
	for f in 90:                                   # 1.5 s: the keeper takes his position for this ball
		await get_tree().physics_frame
	var target := PlayerAI.shot_target(_goal, _gk.global_position)
	var dir := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
	dir = dir.rotated(Vector3.UP, deg_to_rad(randf_range(-spread, spread)))
	# straight-line crossing of the goal line (before the keeper / bounce): decides "wide"
	var t_line := (_goal.z - at.z) / dir.z
	var cross_x := at.x + dir.x * t_line
	_m.ball.strike(dir, power, lift)
	var caught := false
	var dbg := OS.get_cmdline_user_args().has("debug")
	var gk0 := _gk.global_position
	var dive_f := -1
	for f in 120:
		await get_tree().physics_frame
		if dive_f < 0 and _gk.state == TeamGoalkeeper.State.DIVE:
			dive_f = f
		if _gk.state == TeamGoalkeeper.State.HOLD and not caught:
			caught = true
			if dbg:
				print("    caught f%d  gk0 (%.1f,%.1f) gk (%.1f,%.1f) ball (%.1f,%.1f) cross_x %.1f dive_f %d" % [f, gk0.x, gk0.z, _gk.global_position.x, _gk.global_position.z, _m.ball.global_position.x, _m.ball.global_position.z, cross_x, dive_f])
		var p := _m.ball.global_position
		if (p.z - _goal.z) * signf(_goal.z) > 0.12:
			if absf(p.x - _goal.x) < 3.66 and p.y < 2.44:
				return "goal"
			return "wide" if absf(cross_x - _goal.x) >= 3.66 else "parried"
	if caught:
		return "caught"
	return "wide" if absf(cross_x - _goal.x) >= 3.66 else "parried"
