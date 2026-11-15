## Captures hub screens as PNGs (non-headless, e.g. under xvfb-run). Usage:
##   xvfb-run -a godot --path . --resolution 1280x720 res://tests/ui_shots.tscn -- <lang> <outdir> <screen> [<screen> ...]
## The window size is the logical canvas (phone 2400x1080 = 1600x720 canvas).
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var lang := args[0]
	var outdir := args[1]
	var screens := args.slice(2)
	DirAccess.make_dir_recursive_absolute(outdir)
	await get_tree().process_frame
	var app: Node = get_node("/root/AppHub")
	app.db.load_world("")
	app.start_career("club_royal_harbor")
	Loc.set_language(lang, false)
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	for id: String in screens:
		var p := {}
		if id == "player_profile":
			p = {"player_id": app.db.get_team("club_royal_harbor").squad_ids[0]}
		if id == "team_details" or id == "kit_editor":
			p = {"team_id": "club_royal_harbor"}
		hub.navigate(id, p)
		for i in 90:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s_%dx%d.png" % [outdir, id, lang, img.get_width(), img.get_height()])
		print("saved ", id)
	get_tree().quit()
