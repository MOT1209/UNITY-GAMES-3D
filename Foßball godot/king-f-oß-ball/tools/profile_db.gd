## Developer tool: measures the database at its real size and prints the numbers (database phase 9).
##   godot --headless --path . res://tools/profile_db.tscn
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	var r := DbProfiler.run(db, "real_2025")
	for k in r:
		var v: Variant = r[k]
		print("%-34s %s" % [k, ("%.3f" % v) if v is float else str(v)])
	db.load_world("")
	get_tree().quit()
