## Match visual QA (needs a real window — NOT headless):
##   KING_QA_OUT=/abs/dir godot --path . res://tests/match_visual.tscn --resolution 1280x720
## Plays a short real match in Arabic and English with the broadcast and the follow camera and saves
## PNGs (HUD scoreboard, selection ring, key-hint chips, lighting) to KING_QA_OUT (default docs/qa).
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

var _out := "res://docs/qa"


func _ready() -> void:
	if OS.get_environment("KING_QA_OUT") != "":
		_out = OS.get_environment("KING_QA_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var original: String = GameSettings.settings_path
	GameSettings.settings_path = "user://match_visual_settings.cfg"
	var db := get_node("/root/TeamDB")
	db.load_world("")          # fictional world, whatever pack was saved
	for code in ["ar", "en"]:
		Loc.set_language(code, false)
		for cam in ["broadcast", "follow"]:
			await _shot(db, code, cam)
	GameSettings.settings_path = original
	Loc.set_language("en", false)
	get_tree().quit(0)


func _shot(db: Node, code: String, cam: String) -> void:
	GameSettings.set_value("match", "camera", cam)
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 10
	setup.human_side = "home"
	setup.rng_seed = 7
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	if err != "":
		print("match failed: ", err)
		return
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/match_%s_%s.png" % [_out, cam, code]
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
