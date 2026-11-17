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
	_check(LogoService.file_ok(DIR + "club_sunvale.png") and not LogoService.file_ok(DIR + "nope.png") and LogoService.load_image(DIR + "nope.png") == null, "res:// artwork is found through the importer; a missing file is not")
	var hashes := {}
	for t: TeamData in fictional:
		var path := DIR + t.id + ".png"
		_check(t.logo_path == path, "%s points at its crest" % t.id, t.logo_path)
		var img := LogoService.load_image(path)           # through the importer, as an exported game must
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
	_test_logo_references()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])


## Every non-empty "logo" in the club data (default world and every data pack) must name a file that
## really exists: a deleted crest (e.g. club_cedar_city.png, removed by mistake once) falls back to a
## generated template silently, so it is rejected here.
func _test_logo_references() -> void:
	var files: Array = []
	_collect_json("res://data/clubs/", files)
	_collect_json("res://data/packs/", files)
	var checked := 0
	var missing: Array = []
	for path: String in files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var entries: Array = []
		if parsed is Dictionary:
			entries.append(parsed)
			if (parsed as Dictionary).get("team") is Dictionary:
				entries.append(parsed["team"])
			for key in ["clubs", "teams"]:
				if (parsed as Dictionary).get(key) is Array:
					entries.append_array(parsed[key])
		elif parsed is Array:
			entries.append_array(parsed)
		for e: Variant in entries:
			if not (e is Dictionary):
				continue
			var logo := str((e as Dictionary).get("logo", ""))
			if logo == "":
				continue
			checked += 1
			if not LogoService.file_ok(logo):
				missing.append("%s -> %s" % [path.get_file(), logo])
	_check(checked >= 8, "club data names its crest files (%d logo references found)" % checked)
	_check(missing.is_empty(), "every club 'logo' reference points at an existing file", ", ".join(missing))


func _collect_json(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect_json(dir.path_join(sub), out)
	get_tree().quit(1 if _failed > 0 else 0)
