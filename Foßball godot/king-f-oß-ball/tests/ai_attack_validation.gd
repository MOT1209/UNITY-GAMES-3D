## AI attack: shooting lane, early / sideways passes, dodging a blocker, pushing up with the ball, and a short full-engine match.
##   godot --headless --path . res://tests/ai_attack_validation.tscn
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
	print("=== KING FOOTBALL — AI attack validation ===")
	_test_rules()
	_test_team_shape()
	await _test_engine_match()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _ctx(pos: Vector3, mates: Array, opps: Array, shoot_range := 24.0, profile := {}) -> Dictionary:
	return {"pos": pos, "ball": pos, "has_ball": true, "is_chaser": false, "target": pos, "goal": Vector3(0, 0, -52.5), "own_goal": Vector3(0, 0, 52.5),
			"teammates": mates, "opponents": opps, "is_keeper": false, "difficulty": 1, "attributes": null, "shoot_range": shoot_range,
			"profile": profile if not profile.is_empty() else TacticsPreset.new().pass_profile()}


func _test_rules() -> void:
	var pos := Vector3(0, 0, -20.0)                      # 32.5 m from the goal: outside 24 m, inside 1.3 x 24 = 31.2? no: 32.5 > 31.2
	var shot_pos := Vector3(0, 0, -23.0)                 # 29.5 m from goal
	_check(PlayerAI._lane_open(shot_pos, Vector3(0, 0, -52.5), []), "an empty lane is open")
	_check(not PlayerAI._lane_open(shot_pos, Vector3(0, 0, -52.5), [Vector3(1.0, 0, -35.0)]), "a defender on the line closes the lane")
	_check(PlayerAI._lane_open(shot_pos, Vector3(0, 0, -52.5), [Vector3(9.0, 0, -35.0)]), "a defender far to the side does not")
	_check(PlayerAI.decide(_ctx(shot_pos, [], []))["action"] == &"shoot", "with an open lane the carrier shoots from 30 m (24 m range x 1.3)")
	_check(PlayerAI.decide(_ctx(shot_pos, [], [Vector3(0.5, 0, -40.0)]))["action"] != &"shoot", "with the lane closed he does not shoot from 30 m")
	_check(PlayerAI.decide(_ctx(Vector3(0, 0, -35.0), [], [Vector3(0.5, 0, -45.0)]))["action"] == &"shoot", "inside the plain range he shoots whatever the lane")
	_check(PlayerAI.decide(_ctx(pos, [], []))["action"] != &"shoot", "beyond 1.3 x the range he runs on")
	# early pass: blocked ahead (not yet pressured) with a free forward team-mate
	var blocked_opp := Vector3(0.5, 0, 0.0 - 8.0)
	var carrier := Vector3(0, 0, 0)
	var mate := Vector3(12.0, 0, -22.0)
	_check(PlayerAI._blocked_ahead(carrier, Vector3(0, 0, -52.5), [blocked_opp]), "an opponent 8 m ahead blocks the way")
	var early := PlayerAI.decide(_ctx(carrier, [mate], [blocked_opp]))
	_check(early["action"] == &"pass" and (early["move"] as Vector3).x > 0.3, "blocked ahead: the carrier passes to the free forward team-mate before being pressed")
	# pressured with only a backward option: sideways / back pass instead of running into the defender
	var pressing := Vector3(0.5, 0, -1.5)
	var back := Vector3(6.0, 0, 8.0)
	var rel := PlayerAI.decide(_ctx(carrier, [back], [pressing]))
	_check(rel["action"] == &"pass", "pressured with nothing ahead: a back pass is played", str(rel["action"]))
	var strict := TacticsPreset.new()
	strict.passing_style = TacticsPreset.PassingStyle.RISKY
	var no_mates := PlayerAI.decide(_ctx(carrier, [], [pressing], 24.0, strict.pass_profile()))
	_check(no_mates["action"] != &"pass", "with no team-mate at all nobody is passed to")
	# dodge: the run bends away from the blocker
	var dodge_right := PlayerAI._dodge(carrier, Vector3(0, 0, -52.5), [Vector3(-1.0, 0, -5.0)])
	var dodge_left := PlayerAI._dodge(carrier, Vector3(0, 0, -52.5), [Vector3(1.0, 0, -5.0)])
	_check(dodge_right.x > 0.3 and dodge_left.x < -0.3 and dodge_right.z < 0.0 and dodge_left.z < 0.0, "the carrier runs around the blocker, still towards the goal")
	_check(PlayerAI._dodge(carrier, Vector3(0, 0, -52.5), []).is_equal_approx(Vector3(0, 0, -1)), "nobody in the way: straight to goal")
	# a keeper-less empty context never crashes
	_check(PlayerAI.decide(_ctx(carrier, [], []))["move"] is Vector3, "decisions are always well-formed")


func _test_team_shape() -> void:
	var t := TacticsPreset.new()
	var with_ball := TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, 0), true)
	var without := TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, 0), false)
	var forward_gain := 0.0
	for slot in range(1, 11):
		forward_gain += without[slot].z - with_ball[slot].z          # home attacks -Z: a smaller z is further up the pitch
	_check(forward_gain > 10.0, "with the ball the team pushes up the pitch", "%.1f m in total" % forward_gain)
	_check(with_ball[0].is_equal_approx(TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, 0), false)[0]), "the goalkeeper does not move up")
	var att := TacticsPreset.new()
	att.mentality = TacticsPreset.Mentality.ULTRA_ATTACKING
	var def := TacticsPreset.new()
	def.mentality = TacticsPreset.Mentality.ULTRA_DEFENSIVE
	var st_slot := 9
	_check(TeamAI.formation_targets("home", "4-3-3", att, Vector3.ZERO, true)[st_slot].z < TeamAI.formation_targets("home", "4-3-3", def, Vector3.ZERO, true)[st_slot].z,
			"an attacking mentality sends the striker higher up than a defensive one")


## Full engine, no script: two AI teams for 45 seconds each (two seeds). They must keep the ball moving (no midfield stalemate).
func _test_engine_match() -> void:
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var total_passes := 0
	var furthest := 1000.0
	for seed_value in [100, 102]:
		var setup := MatchSetup.new()
		setup.home_id = "club_royal_harbor"
		setup.away_id = "club_northgate_utd"
		setup.duration_minutes = 2
		setup.human_side = "none"
		setup.difficulty = 1
		setup.rng_seed = seed_value
		var m := MatchManager.new()
		m.return_to_menu_on_finish = false
		add_child(m)
		m.begin(setup, db)
		m._needs_reset = false
		m._pause_left = 0.0
		m.state.kick_off()
		var frames := 0
		while frames < 60 * 45:
			await get_tree().physics_frame
			frames += 1
			var own := m._owner_entry()
			if not own.is_empty():
				var goal := PitchSpace.opponent_goal(m.frame_side(own["side"]))
				furthest = minf(furthest, Vector2((own["node"] as Node3D).global_position.x - goal.x, (own["node"] as Node3D).global_position.z - goal.z).length())
		total_passes += int(m.state.stats.teams["home"]["passes"]) + int(m.state.stats.teams["away"]["passes"])
		_check(m.state != null and m.state.phase != MatchState.Phase.FINISHED and frames == 60 * 45, "seed %d: 45 seconds of play run without a crash or a premature end" % seed_value)
		m.process_mode = Node.PROCESS_MODE_DISABLED
		m.queue_free()
		await get_tree().process_frame
	_check(total_passes >= 12, "the teams keep passing the ball (no midfield stalemate)", "%d passes in two 45-second spells" % total_passes)
	_check(furthest < 30.0, "attacks do reach the final third", "closest carrier %.0f m from goal" % furthest)
