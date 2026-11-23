extends Node
## Phase 2 probe: a ball thrown at a standing player arriving at `h` m; prints the header window, the request, the jump
## and the contact.   godot --headless --path . res://tools/exp/header_probe.tscn -- h=2.35

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback


func _ready() -> void:
	var h := float(_arg("h", "2.35"))
	var env := Node3D.new()
	add_child(env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	env.add_child(ground)
	var pd := PlayerData.new()
	pd.id = "probe"
	pd.height_cm = 192
	pd.detail = {"jumping": 90, "heading": 85}
	var mods := AttributeModifiers.new(pd)
	var p: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var ai := AIIntent.new()
	p.intent = ai
	p.attribute_modifiers = mods
	env.add_child(p)
	var acts := p.get_node("BallActions") as FootballActions
	acts.intent = ai
	acts.attribute_modifiers = mods
	var b: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate()
	b.position = Vector3(0, 0.11, -20)
	env.add_child(b)
	for i in 5:
		await get_tree().physics_frame
	print("reach ", HeaderSystem.reach_of(mods), " gravity ", p.config.gravity)
	var t := 0.9
	var start := Vector3(0, 1.0, -9.0)
	b.reset_ball(start)
	b.linear_velocity = Vector3(0, (h - start.y + 0.5 * 9.8 * t * t) / t, 9.0 / t) * 1.04
	acts.header_played.connect(func(k: StringName, sp: float, q: float) -> void:
		print("  PLAYED %s speed %.1f q %.2f ball y %.2f body y %.2f" % [k, sp, q, b.global_position.y, p.global_position.y]))
	var pressed := false
	for f in 70:
		await get_tree().physics_frame
		ai.begin_tick()
		var w := acts.header.window()
		if f % 3 == 0 or (not w.is_empty() and not pressed):
			print("f%2d ball (%.2f, %.2f, %.2f) body y %.2f window %s req %s" % [f, b.global_position.x, b.global_position.y,
					b.global_position.z, p.global_position.y, str(w), acts.header.request_kind()])
		if not pressed and acts.header.window_open():
			ai.press(&"pass")
			pressed = true
	get_tree().quit()
