## Developer tool (round 3, C): one row of the five card categories for an outfield player or a goalkeeper,
## from the real-league pack. A category that no real player reaches is shown with a real player's copy whose
## attributes are scaled into it (marked in the console; never saved). Needs a rendering device:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/card_matrix.tscn -- out.png <en|ar|de> <outfield|gk> [pack]
extends Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://card_matrix.png"
	Loc.set_language(a[1] if a.size() > 1 else "en", false)
	var gk := (a[2] if a.size() > 2 else "outfield") == "gk"
	var db: Node = get_node("/root/TeamDB")
	db.load_world(a[3] if a.size() > 3 else "real_2025")
	await get_tree().process_frame
	var by_kind := {}
	for p: PlayerData in db.players.values():
		if (p.position == PlayerData.Position.GK) != gk or p.team_id == "" or db.get_team(p.team_id).category != TeamData.Category.CLUB:
			continue
		var k := CardCategory.for_player(p)
		if not by_kind.has(k) or (p.traits.size() > (by_kind[k] as PlayerData).traits.size()):
			by_kind[k] = p
	var root := ColorRect.new()
	root.color = Color("#0d1018")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	row.add_theme_constant_override("separation", 16)
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR      # same order in every language
	row.position = Vector2(20, 180)
	root.add_child(row)
	var template: PlayerData = by_kind.values()[0]
	for k in CardCategory.all_kinds():
		var p: PlayerData = by_kind.get(k)
		if p == null:
			p = PlayerData.from_dict(template.to_dict())
			p.id = "matrix_%d" % k
			var target: int = [58, 70, 80, 87, 93][k]
			for attr in PlayerData.ATTRIBUTES:
				p.set(attr, target if attr != "goalkeeping" or gk else 15)
			db.players[p.id] = p
			print("category %s: scaled copy of %s" % [CardCategory.key(k), template.display_name])
		var c := PlayerCard.new(228.0)
		c.compact = false
		row.add_child(c)
		c.setup(PlayerCardData.from_data(db, p), db)
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
