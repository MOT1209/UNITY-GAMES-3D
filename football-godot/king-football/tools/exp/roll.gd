extends Node
func _ready() -> void:
	var arena: Node3D = (load("res://scenes/stadium/stadium_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	var p := arena.get_node_or_null("Player")
	if p: p.queue_free()
	var ball: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate()
	add_child(ball)
	ball.global_position = Vector3(0, 0.12, 20)
	for i in 30: await get_tree().physics_frame
	ball.strike(Vector3(1, 0, 0), 10.0)
	var x0 := ball.global_position.x
	for i in 241:
		if i % 15 == 0:
			print("t %.2f v %.2f x %.1f y %.2f w %.1f" % [i / 60.0, Vector2(ball.linear_velocity.x, ball.linear_velocity.z).length(), ball.global_position.x - x0, ball.global_position.y, ball.angular_velocity.length()])
		await get_tree().physics_frame
	print("damp ", ball.linear_damp, " ", ball.angular_damp, " mode ", ball.linear_damp_mode, " friction ", ball.physics_material_override.friction)
	get_tree().quit()
