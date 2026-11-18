## Developer tool: screenshot of the live simulation screen after N minutes.
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/live_shot.tscn -- out.png <lang> <club> <minutes>
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Loc.set_language(a[1] if a.size() > 1 else "ar", false)
	var club: String = a[2] if a.size() > 2 else "eng_leicester_city_fc"
	var minutes := int(a[3]) if a.size() > 3 else 40
	var app: Node = get_node("/root/AppHub")
	(get_node("/root/TeamDB") as TeamDatabase).load_world("real_2025")
	app.career = null
	app.start_career(club)
	var career: CareerState = app.career
	var cid := ""
	var fx: Dictionary = {}
	for k in career.competitions:
		for f in (career.competitions[k] as Competition).pending_fixtures():
			if club in [f["home"], f["away"]]:
				cid = k
				fx = f
				break
		if cid != "":
			break
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("live_match", {"competition_id": cid, "match_id": fx["match_id"]})
	for i in 5:
		await get_tree().process_frame
	var scr: Node = hub.find_child("LiveScore", true, false)
	var live_screen: Node = scr
	while live_screen != null and not ("live" in live_screen):
		live_screen = live_screen.get_parent()
	for i in minutes:
		for ev in live_screen.live.step():
			live_screen._add_feed(ev)
	for id in [live_screen.live.home_id, live_screen.live.away_id]:
		var t: TeamData = app.db.get_team(id)
		print(id, " prim ", t.primary_color.to_html(), " sec ", t.secondary_color.to_html(), " kits ", t.kits)
	print("colors ", live_screen._colors)
	live_screen._refresh()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[0])
	print("saved ", a[0])
	get_tree().quit()
