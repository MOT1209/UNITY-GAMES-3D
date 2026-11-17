## Developer tool (round 3, D): a 6 x 4 grid of player portraits (the same renderer the cards use) from the
## real-league pack, players picked at fixed strides so before / after grids show the same people. Needs a
## rendering device:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/portrait_grid.tscn -- out.png [pack] [stride]
extends Node

const COLS := 6
const ROWS := 4


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://portraits.png"
	var db: Node = get_node("/root/TeamDB")
	db.load_world(a[1] if a.size() > 1 else "real_2025")
	var stride := int(a[2]) if a.size() > 2 else 97
	await get_tree().process_frame
	var ids: Array = db.players.keys()
	ids.sort()
	var picked: Array = []
	var gk := 0
	var i := 0
	while picked.size() < COLS * ROWS and i < ids.size() * 3:
		var p: PlayerData = db.players[ids[(i * stride) % ids.size()]]
		i += 1
		if p.team_id == "" or p in picked:
			continue
		if p.position == PlayerData.Position.GK:
			if gk >= 4:
				continue
			gk += 1
		picked.append(p)
	var r := PlayerPortraitRenderer.shared(get_tree())
	await get_tree().process_frame
	var cell := PlayerPortraitRenderer.SIZE
	var sheet := Image.create(cell.x * COLS, cell.y * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#1b2230"))
	for k in picked.size():
		var tex: Texture2D = await r.request(PlayerCardData.from_data(db, picked[k]), db)
		if tex == null:
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((k % COLS) * cell.x, (k / COLS) * cell.y))
	sheet.save_png(out)
	print("saved ", out, " (", picked.size(), " players)")
	get_tree().quit()
