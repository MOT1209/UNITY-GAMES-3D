## Phase 6 visual QA (needs a real window — NOT headless):
##   KING_QA_OUT=/abs/dir godot --path . res://tests/match_content_visual.tscn --resolution 1280x720
## Saves the team walk-out, a goal-replay angle (behind the goal) and the penalty shoot-out.
extends Node

var _out := "res://docs/qa"


func _ready() -> void:
	if OS.get_environment("KING_QA_OUT") != "":
		_out = OS.get_environment("KING_QA_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var db := get_node("/root/TeamDB")
	db.load_world("")
	Loc.set_language("ar", false)
	var m := _match(db, true, false)
	await get_tree().create_timer(2.0).timeout
	await _save("walkout_ar")
	m.end_walkout()
	await get_tree().create_timer(3.0).timeout
	m.ball.reset_ball(Vector3(1.0, 0.3, PitchSpace.HALF_LENGTH - 3.0))
	m._start_goal_replay()
	if m.replay_player != null and m.replay_player.playing:
		m.replay_player.seek(float(m.replay_player.clip_data["duration"]) * 0.5)
		m.replay_director._update()
		await get_tree().process_frame
		await _save("replay_behind_goal_ar")
		m.replay_player.skip()
	_free(m)
	await get_tree().process_frame
	var k := _match(db, false, true)
	k.state.half = 2
	k.state.elapsed = k.state.duration_seconds - 0.01
	await get_tree().create_timer(2.2).timeout
	await _save("shootout_ar")
	_free(k)
	Loc.set_language("en", false)
	get_tree().quit(0)


func _match(db: Node, walkout: bool, knockout: bool) -> MatchManager:
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 10
	setup.human_side = "home"
	setup.walkout = walkout
	setup.knockout = knockout
	setup.rng_seed = 12
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	if not walkout:
		m._needs_reset = false
		m._pause_left = 0.0
		m.state.kick_off()
	return m


func _free(m: MatchManager) -> void:
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [_out, file]))
	print("saved ", file)
