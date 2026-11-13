## Developer tool: writes the kits of every club that needed a repair at load (KitEditor.repair: unreadable
## numbers, clashing away/goalkeeper kits) so they can be stored in the pack files themselves.
##   godot --headless --path . res://tools/export_kit_repairs.tscn -- <output.json>
## Apply with tools/apply_kit_repairs.py. After that, `TeamDB.kit_repairs` is empty for the pack.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "user://kit_repairs.json"
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var out := {}
	for tid: String in db.kit_repairs:
		out[tid] = (db.teams[tid] as TeamData).to_dict()["kits"]
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"kits": out}, "\t"))
	f.close()
	print("clubs with repaired kits: %d" % out.size())
	get_tree().quit()
