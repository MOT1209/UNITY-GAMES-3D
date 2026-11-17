extends Node
func _ready() -> void:
	var env := Node3D.new(); add_child(env)
	var ground := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(400,1,400); cs.shape = box; cs.position.y = -0.5; ground.add_child(cs); env.add_child(ground)
	for variant in ["normal", "no_damp", "no_contact_monitor"]:
		var b: BallController = (load("res://scenes/ball/football_ball.tscn") as PackedScene).instantiate(); b.position = Vector3(0,0.12,0); env.add_child(b)
		for i in 20: await get_tree().physics_frame
		if variant == "no_damp": b.linear_damp = 0.0; b.angular_damp = 0.0
		if variant == "no_contact_monitor": b.contact_monitor = false
		b.strike(Vector3(1,0,0), 21.0)
		var x0 := b.global_position.x
		for i in 61: await get_tree().physics_frame
		print("%s: after 1 s v %.2f x %.1f w %.1f" % [variant, b.linear_velocity.length(), b.global_position.x - x0, b.angular_velocity.length()])
		b.free()
	get_tree().quit()
