extends Node
func _ready() -> void:
	var env := Node3D.new(); add_child(env)
	var ground := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(200,1,200); cs.shape = box; cs.position.y = -0.5; ground.add_child(cs); env.add_child(ground)
	var p: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate(); p.position = Vector3(0,0.05,0); env.add_child(p)
	var ai := AIIntent.new(); p.intent = ai; (p.get_node("BallActions") as FootballActions).intent = ai
	var b: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate(); b.position = Vector3(0,0.12,-0.6); env.add_child(b)
	for i in 10: await get_tree().physics_frame
	for f in 300:
		ai.begin_tick(); ai.press(&"dribble")
		var dir := Vector3(0,0,-1)
		if p.global_position.z <= -5.0: dir = Vector3(1,0,0)
		ai.set_move_world(dir)
		await get_tree().physics_frame
		var rel := b.global_position - p.global_position
		if f % 6 == 0 or Vector2(rel.x, rel.z).length() > 1.6:
			print("f%d p(%.1f,%.1f) v%.1f rel(%.2f,%.2f) bv(%.1f,%.1f) drib %s" % [f, p.global_position.x, p.global_position.z, p.velocity.length(), rel.x, rel.z, b.linear_velocity.x, b.linear_velocity.z, (p.get_node("BallActions") as FootballActions).get_action_state_name()])
		if Vector2(rel.x, rel.z).length() > 2.0: break
		if p.global_position.x > 5.0: print("OK"); break
	get_tree().quit()
