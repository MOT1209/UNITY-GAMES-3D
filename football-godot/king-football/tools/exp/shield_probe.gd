extends Node
## Phase 2 probe: prints the ball's position relative to a standing shielder every 10 ticks.
##   godot --headless --path . res://tools/exp/shield_probe.tscn

func _ready() -> void:
	var env := Node3D.new()
	add_child(env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	env.add_child(ground)
	var p: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var ai := AIIntent.new()
	p.intent = ai
	env.add_child(p)
	var acts := p.get_node("BallActions") as FootballActions
	acts.intent = ai
	var b: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate()
	b.position = Vector3(0, 0.11, -0.5)
	env.add_child(b)
	var opp := Vector3(0, 0, -1.1)
	acts.nearest_opponent = func(_x: Vector3) -> Vector3: return opp
	for i in 3:
		await get_tree().physics_frame
	ai.press(&"shield")
	for i in 120:
		await get_tree().physics_frame
		if i % 10 == 0:
			var rel := b.global_position - p.global_position
			print("t%3d ball rel (%.2f, %.2f, %.2f) v %.2f active %s prot %.2f yaw %.2f pl (%.2f,%.2f) state %s" % [i, rel.x, rel.y, rel.z,
					b.linear_velocity.length(), acts.shielding.is_active(), acts.shielding.protection(), p.rotation.y,
					p.global_position.x, p.global_position.z, acts.get_action_state_name()])
	get_tree().quit()
