## Developer tool: screenshot of the Squad Management screen (needs a rendering device).
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/squad_shot.tscn -- out.png [lang] [pack] [club] [frames]
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://squad.png"
	Loc.set_language(a[1] if a.size() > 1 else "en", false)
	var pack: String = a[2] if a.size() > 2 else "real_2025"
	var club: String = a[3] if a.size() > 3 else "eng_leicester_city_fc"
	var frames := int(a[4]) if a.size() > 4 else 90
	var app: Node = get_node("/root/AppHub")
	(get_node("/root/TeamDB") as TeamDatabase).load_world(pack)
	app.career = null
	app.start_career(club)
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	hub.navigate("squad")
	for i in frames:
		await get_tree().process_frame
	var pitch := hub.current.find_child("SquadPitch", true, false) as SquadPitch
	if pitch != null:
		print("pitch size ", pitch.size, " card width ", pitch.card_width())
		for i in 11:
			var c := pitch.find_child("PitchCard_%d" % i, true, false) as PlayerCard
			print(i, " ", c.size, " ", c.texts())
	if pitch != null:
		var c0 := pitch.find_child("PitchCard_0", true, false) as PlayerCard
		print("card0 visible=", c0.visible, " modulate=", c0.modulate, " pos=", c0.position, " clip=", c0.clip_contents)
		for ch in c0.get_children():
			print("  ", ch.get_class(), " vis=", ch.visible, " pos=", ch.position, " size=", ch.size, " ", (ch.text if ch is Label else ""))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
