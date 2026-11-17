## Developer tool: draws a sheet of crests into a PNG (CPU only, no GPU needed).
##   godot --headless --path . res://tools/crest_gallery.tscn -- out.png [world] [first] [count] [variant]
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://crests.png"
	var world: String = a[1] if a.size() > 1 and a[1] != "-" else "real_2025"
	var first := int(a[2]) if a.size() > 2 else 0
	var count := int(a[3]) if a.size() > 3 else 48
	var variant: String = a[4] if a.size() > 4 else "full"
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world(world)
	var clubs := db.list_teams(TeamData.Category.CLUB).slice(first, first + count)
	var cell := CrestRenderer.size_of(variant) + 16
	var cols := 8
	var rows := ceili(float(clubs.size()) / cols)
	var sheet := Image.create(cols * cell, rows * (cell + 14), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.13, 0.17))
	var t0 := Time.get_ticks_msec()
	for i in clubs.size():
		var img := CrestService.image(db, clubs[i], variant)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cell + 8, (i / cols) * (cell + 14) + 8))
	print("rendered %d crests (%s) in %d ms" % [clubs.size(), variant, Time.get_ticks_msec() - t0])
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
