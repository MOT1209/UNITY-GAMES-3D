## Developer tool: screenshot of a hub screen in a data-pack career (needs a rendering device).
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/hub_shot.tscn -- out.png <screen> <lang> <pack> <club> <weeks>
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var screen: String = a[1] if a.size() > 1 else "leagues"
	Loc.set_language(a[2] if a.size() > 2 else "en", false)
	var pack: String = a[3] if a.size() > 3 else "real_2025"
	var club: String = a[4] if a.size() > 4 else "eng_leicester_city_fc"
	var weeks := int(a[5]) if a.size() > 5 else 10
	var app: Node = get_node("/root/AppHub")
	(get_node("/root/TeamDB") as TeamDatabase).load_world(pack)
	app.career = null
	if club != "-":
		app.start_career(club)
		for i in weeks:
			app.advance_week()
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var params := {}
	if a.size() > 6:                       # player id, or "first" = the managed club's first outfield player
		var pid: String = a[6]
		if pid == "first" and app.career != null:
			for p: PlayerData in app.db.get_squad(app.career.club_id):
				if p.position != PlayerData.Position.GK:
					pid = p.id
					break
		params = {"player_id": pid}
	hub.navigate(screen, params)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
