## Generated crest artwork of the fictional clubs (assets/crests/fictional/).
##   godot --headless --path . res://tests/crest_assets_validation.tscn
extends Node

const DIR := "res://assets/crests/fictional/"

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Crest assets validation ===")
	var db: Node = get_node("/root/TeamDB")
	db.load_world("")
	var fictional: Array = db.list_teams(TeamData.Category.CLUB)      # the default world: eight fictional clubs
	_check(fictional.size() == 8, "the default world has eight fictional clubs", str(fictional.size()))
	var hashes := {}
	for t: TeamData in fictional:
		var path := DIR + t.id + ".png"
		_check(t.logo_path == path, "%s points at its crest" % t.id, t.logo_path)
		var img := Image.load_from_file(path)
		_check(img != null and not img.is_empty() and img.get_width() == 512 and img.get_height() == 512, "%s: crest is a 512 x 512 image" % t.id)
		if img == null or img.is_empty():
			continue
		var corner := img.get_pixel(2, 2)
		var centre := img.get_pixel(256, 256)
		_check(corner.a < 0.05 and centre.a > 0.95, "%s: transparent outside, opaque inside" % t.id, "%.2f / %.2f" % [corner.a, centre.a])
		var covered := 0
		for y in range(0, 512, 8):
			for x in range(0, 512, 8):
				if img.get_pixel(x, y).a > 0.5:
					covered += 1
		_check(covered > 1200 and covered < 3800, "%s: the emblem fills a sensible part of the image" % t.id, str(covered))
		var h := hash(img.get_data())
		_check(not hashes.has(h), "%s: no two clubs share an identical image" % t.id)
		hashes[h] = t.id
		var resolved := LogoService.resolve(t, 64)
		_check(resolved.get_width() == 64 and resolved.get_pixel(32, 32).a > 0.95 and resolved.get_pixel(1, 1).a < 0.1, "%s: LogoService resolves the real artwork, not a template" % t.id)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
