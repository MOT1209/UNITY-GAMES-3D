extends Node
func _ready() -> void:
	var env := Node3D.new(); add_child(env)
	var ground := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(200,1,200); cs.shape = box; cs.position.y = -0.5; ground.add_child(cs); env.add_child(ground)
	var p: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate(); p.position = Vector3(0,0.05,0); env.add_child(p)
	var ai := AIIntent.new(); p.intent = ai; var acts := p.get_node("BallActions") as FootballActions; acts.intent = ai
	acts.shot_started.connect(func(pw: float, l: float) -> void: print("shot_started power %.1f lift %.1f" % [pw, l]))
	var b: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate(); b.position = Vector3(0,0.12,-0.55); env.add_child(b)
	for i in 10: await get_tree().physics_frame
	ai.begin_tick(); ai.set_aim_world(Vector3(0,0,-1)); ai.press(&"shoot")
	await get_tree().physics_frame
	for i in 2:
		ai.begin_tick(); await get_tree().physics_frame
	ai.begin_tick(); ai.release(&"shoot")
	await get_tree().physics_frame
	ai.begin_tick()
	for f in 60:
		if f % 4 == 0: print("f%d z %.1f y %.2f v %.1f vy %.1f" % [f, b.global_position.z, b.global_position.y, b.linear_velocity.length(), b.linear_velocity.y])
		await get_tree().physics_frame
	get_tree().quit()
