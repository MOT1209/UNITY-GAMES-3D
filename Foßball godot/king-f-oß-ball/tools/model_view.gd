## Developer tool: renders the player model from a given camera, optionally posing an
## animation at several times, and saves a PNG contact sheet (needs a rendering device).
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/model_view.tscn -- out.png face|anim [clip] [keeper]
extends Node

const TILE := Vector2i(320, 420)


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var mode: String = a[1]
	var clip: String = a[2] if a.size() > 2 else "Idle"
	var keeper: bool = a.size() > 3 and a[3] == "keeper"
	await get_tree().process_frame
	var tiles: Array = []
	var looks: Array = []
	if mode == "face" or mode == "kit":
		for s in [3, 11, 25, 40, 77, 123]:
			looks.append(s)
	else:
		looks = [0, 1, 2, 3, 4, 5]
	var count := looks.size()
	var sheet := Image.create(TILE.x * count, TILE.y, false, Image.FORMAT_RGBA8)
	for i in count:
		var vp := SubViewport.new()
		vp.size = TILE
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.25, 0.27, 0.3)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.85, 0.9)
		env.ambient_light_energy = 0.6
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-35, 25, 0)
		vp.add_child(l)
		var path := PlayerPortraitRenderer.KEEPER_SCENE if keeper else PlayerPortraitRenderer.OUTFIELD_SCENE
		var v := (load(path) as PackedScene).instantiate() as PlayerCharacterVisual
		v.look = PlayerAppearance.to_look(PlayerAppearance.generate(looks[i]))
		v.kit = TeamKit.new()
		if mode == "kit":
			v.kit.jersey = Color("#c8102e")
			v.kit.trim = Color("#ffffff")
			v.kit.shorts = Color("#ffffff")
			v.kit.socks = Color("#c8102e")
			v.kit.pattern = ["solid", "stripes", "hoops", "halves", "sash", "checks"][i]
		if mode == "kit" and i == 0:
			v.set_captain(true)
		vp.add_child(v)
		var cam := Camera3D.new()
		cam.current = true
		vp.add_child(cam)
		if mode == "kit":
			cam.fov = 26.0
			cam.position = Vector3(0.6, 1.25, -3.6)
			cam.look_at(Vector3(0, 1.1, 0))
		elif mode == "face":
			cam.fov = 14.0
			cam.position = Vector3(0, 1.62, -2.6)
			cam.look_at(Vector3(0, 1.62, 0))
		else:
			cam.fov = 30.0
			cam.position = Vector3(-4.2, 1.0, -0.0)   # side view
			cam.look_at(Vector3(0, 0.95, 0))
			var ap := v.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			if not ap.has_animation(clip):
				push_error("no clip " + clip)
			else:
				ap.play(clip)
				ap.seek(ap.get_animation(clip).length * float(i) / float(count), true)
				ap.pause()
		await get_tree().process_frame
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(TILE.x * i, 0))
		vp.queue_free()
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
