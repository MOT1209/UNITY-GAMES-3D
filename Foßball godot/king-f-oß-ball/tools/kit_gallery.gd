## Developer tool: draws kits (all patterns + a few clubs) with crests into a PNG, CPU only.
##   godot --headless --path . res://tools/kit_gallery.tscn -- out.png
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://kits.png"
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var items: Array = []
	for pat in KitEditor.PATTERNS:
		var t: TeamData = db.get_team("eng_arsenal")
		var kit := KitEditor.preview(t, "home")
		kit["pattern"] = pat
		items.append([kit, t])
	for id in ["eng_chelsea_fc", "esp_barcelona", "ita_juventus_fc", "ger_borussia_dortmund", "fra_paris_saint_germain_fc", "eng_leicester_city_fc"]:
		var t: TeamData = db.get_team(id)
		for slot in ["home", "away", "goalkeeper"]:
			items.append([KitEditor.preview(t, slot), t])
	var cw := 190
	var cols := 6
	var sheet := Image.create(cols * cw, ceili(float(items.size()) / cols) * 240, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.13, 0.17))
	for i in items.size():
		var crest: Image = CrestService.image(db, items[i][1], "kit")
		var img := KitRenderer.render(items[i][0], crest, 2)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cw + 7, (i / cols) * 240 + 8))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
