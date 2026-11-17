## Developer tool: renders the five card categories (+ a goalkeeper) from real
## player data and saves a PNG. Needs a rendering device:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/card_gallery.tscn -- /tmp/cards.png [en|de|ar]
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://card_gallery.png"
	Loc.set_language(args[1] if args.size() > 1 else "en", false)
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("#111111")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var flow := HFlowContainer.new()
	flow.set_anchors_preset(Control.PRESET_FULL_RECT)
	flow.offset_left = 16
	flow.offset_top = 16
	flow.offset_right = -16
	flow.offset_bottom = -16
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	root.add_child(flow)
	var by_kind := {}
	var gk: PlayerData = null
	for t: TeamData in db.list_teams():
		for p: PlayerData in db.get_squad(t.id):
			var k := CardCategory.for_player(p)
			if not by_kind.has(k) and p.position != PlayerData.Position.GK:
				by_kind[k] = p
			if gk == null and p.position == PlayerData.Position.GK:
				gk = p
	var shown: Array = []
	for k in CardCategory.all_kinds():
		if by_kind.has(k):
			shown.append(by_kind[k])
	shown.append(gk)
	for p: PlayerData in shown:
		var c := PlayerCard.new(220.0)
		c.compact = true
		flow.add_child(c)
		c.setup(PlayerCardData.from_data(db, p), db)
	var small := PlayerCard.new(96.0)
	flow.add_child(small)
	small.setup(PlayerCardData.from_data(db, shown[0]), db)
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
