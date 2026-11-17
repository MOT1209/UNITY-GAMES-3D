## Developer tool (round 3, C3): screenshot of the card detail panel for a real-pack player.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/detail_shot.tscn -- out.png [lang] [player_id]
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://detail.png"
	Loc.set_language(a[1] if a.size() > 1 else "en", false)
	var db: Node = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var pid: String = a[2] if a.size() > 2 else ""
	if pid == "":
		for p: PlayerData in db.get_squad("eng_arsenal"):
			if not p.traits.is_empty() and p.position != PlayerData.Position.GK:
				pid = p.id
				break
		if pid == "":
			pid = (db.get_squad("eng_arsenal")[0] as PlayerData).id
	var root := ColorRect.new()
	root.color = UIKit.BG
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var log := [{"players": [{"player_id": pid, "rating": 7.6}]}, {"players": [{"player_id": pid, "rating": 6.4}]},
			{"players": [{"player_id": pid, "rating": 8.1}]}]
	CardDetailView.open(root, db, pid, log, true)
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " ", pid)
	get_tree().quit()
