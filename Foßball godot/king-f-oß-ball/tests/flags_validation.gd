## National flags and the extended card data (round 3, task B).
##   godot --headless --path . res://tests/flags_validation.tscn
## Every country in data/countries.json has a flag file in two sizes that loads through the importer;
## FlagService caches and falls back to a neutral flag; fictional flags are deterministic; every player of
## the fictional world and of the real-league pack has a known country; PlayerCardData.from_player() fills
## the new display fields for every player of both worlds; every country name is translated (ar/de/en).
extends Node

const SAME_AS_FRANCE := ["fra", "glp", "guf"]

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
	print("=== KING FOOTBALL — Flags validation ===")
	var db: Node = get_node("/root/TeamDB")
	db.load_world("")
	_test_flag_files(db)
	_test_service()
	_test_generator()
	_test_translations(db)
	for pack in ["", "real_2025"]:
		db.load_world(pack)
		_test_players(db, "fictional world" if pack == "" else "real-league pack")
	db.load_world("")
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_flag_files(db: Node) -> void:
	_check(db.countries.size() >= 115, "the country database is loaded", str(db.countries.size()))
	var bad: Array = []
	var asset_bad: Array = []
	var hashes := {}
	var dup: Array = []
	for c: CountryData in db.countries.values():
		if c.flag_asset != FlagService.path_of(c.country_id):
			asset_bad.append(c.country_id)
		for small in [false, true]:
			var path := FlagService.path_of(c.country_id, small)
			var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
			var want := Vector2i(64, 42) if small else Vector2i(128, 84)
			if tex == null or Vector2i(tex.get_size()) != want:
				bad.append(path.get_file())
				continue
			if not small:
				var img := tex.get_image()
				img.decompress()
				var h := hash(img.get_data())
				# overseas regions of France officially fly the French flag
				if hashes.has(h) and not (c.country_id in SAME_AS_FRANCE or str(hashes[h]) in SAME_AS_FRANCE):
					dup.append("%s=%s" % [c.country_id, hashes[h]])
				hashes[h] = c.country_id
				# a real flag image, not a blank: opaque corners and more than one colour
				var a := img.get_pixel(2, 2)
				var colours := {}
				for y in range(0, img.get_height(), 7):
					for x in range(0, img.get_width(), 7):
						colours[img.get_pixel(x, y).to_html(false)] = true
				if a.a < 0.9 or colours.size() < 2:
					bad.append(path.get_file() + " (blank)")
	_check(asset_bad.is_empty(), "every country's flag_asset names its flag file", ", ".join(asset_bad))
	_check(bad.is_empty(), "every country has a 128x84 and a 64x42 flag that loads through the importer", ", ".join(bad))
	_check(dup.is_empty(), "no two countries share an identical flag image", ", ".join(dup))
	var license := FileAccess.get_file_as_string("res://assets/flags/LICENSE-flag-icons.txt")
	_check(license.contains("MIT License") and license.contains("Panayiotis Lipiridis"), "flag-icons MIT licence ships next to the flags")
	var doc := FileAccess.get_file_as_string("res://docs/DATA_SOURCE_AND_LICENSES.md")
	_check(doc.contains("flag-icons") and doc.contains("FlagGenerator"), "flag sources documented in DATA_SOURCE_AND_LICENSES.md")


func _test_service() -> void:
	FlagService.clear_cache()
	var a := FlagService.texture("ger")
	_check(a != null and FlagService.texture("ger") == a, "FlagService caches the texture (same object on the second call)")
	_check(FlagService.texture("ger", true).get_size() == Vector2(64, 42), "small flag is 64x42")
	var before := FlagService.fallbacks_served
	var f := FlagService.texture("xyz_unknown")
	_check(f != null and f.get_size() == Vector2(128, 84) and FlagService.fallbacks_served == before + 1, "unknown country -> neutral fallback flag, never null")
	var img := f.get_image()
	var grey := img.get_pixel(3, 20)
	_check(absf(grey.r - grey.g) < 0.05 and absf(grey.g - grey.b) < 0.08, "fallback flag is neutral grey")
	var lit := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r > 0.85:
				lit += 1
	_check(lit > 40, "fallback flag shows the country code letters", str(lit))
	_check(FlagService.texture("") != null, "empty id is safe")


func _test_generator() -> void:
	var a := FlagGenerator.generate("ald")
	var b := FlagGenerator.generate("ald")
	_check(a.get_data() == b.get_data(), "fictional flag generation is deterministic")
	var designs := {}
	for id in ["ald", "nor", "sol", "zam"]:
		designs[str(FlagGenerator.design(id))] = true
	_check(designs.size() == 4, "the four fictional countries get four different designs")
	var file := (load(FlagService.path_of("zam")) as Texture2D).get_image()
	file.decompress()
	var gen := FlagGenerator.generate("zam", 256, 168)
	gen.resize(128, 84, Image.INTERPOLATE_LANCZOS)
	var diff := 0.0
	for p in [Vector2i(10, 10), Vector2i(64, 42), Vector2i(120, 80), Vector2i(30, 60)]:
		var c1 := file.get_pixelv(p)
		var c2 := gen.get_pixelv(p)
		diff = maxf(diff, absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b))
	_check(diff < 0.1, "the shipped fictional flag file equals the generator output (rebuildable)", str(diff))


func _test_translations(db: Node) -> void:
	var missing: Array = []
	for lang in ["en", "de", "ar"]:
		Loc.set_language(lang, false)
		for c: CountryData in db.countries.values():
			if not Loc.has_key(Loc.country_key(c.country_name), lang):
				missing.append("%s:%s" % [lang, c.country_name])
	Loc.set_language("ar", false)
	var ar := Loc.country("Korea, South")
	Loc.set_language("de", false)
	var de := Loc.country("Cote d'Ivoire")
	Loc.set_language("en", false)
	_check(missing.is_empty(), "every country name is translated in ar, de and en", ", ".join(missing.slice(0, 12)))
	_check(ar == "كوريا الجنوبية" and de == "Elfenbeinküste", "names with commas / apostrophes resolve", "%s / %s" % [ar, de])


func _test_players(db: Node, label: String) -> void:
	var total := 0
	var no_country: Array = []
	var bad_card: Array = []
	var with_league := 0
	var fallbacks_before := FlagService.fallbacks_served
	for p: PlayerData in db.players.values():
		total += 1
		if p.nationality_id == "" or not db.countries.has(p.nationality_id):
			no_country.append("%s (%s)" % [p.id, p.nationality])
		var c := PlayerCardData.from_player(db, p.id)
		var team: TeamData = db.get_team(p.team_id)
		var ok: bool = c != null and c.country_id == p.nationality_id and c.flag != null and c.country_name != "" \
				and c.age == p.age and c.height_cm > 0 and c.preferred_foot in ["RIGHT", "LEFT", "BOTH"] \
				and c.shirt_number == p.shirt_number and c.secondary_positions == p.secondary_positions \
				and c.potential == p.potential and c.traits == p.traits and c.status == PlayerData.Status.keys()[p.status] \
				and c.last_name != ""
		if team != null:
			ok = ok and c.club_name == team.display_name
			if team.category == TeamData.Category.CLUB:
				ok = ok and c.club_crest != null        # national teams have no club crest
			if team.league_id != "":
				ok = ok and c.league_name != ""
		if c != null and c.league_name != "":
			with_league += 1
		if not ok:
			bad_card.append(p.id)
	_check(total > 0 and no_country.is_empty(), "%s: 100%% of %d players have a known country" % [label, total], ", ".join(no_country.slice(0, 10)))
	_check(bad_card.is_empty(), "%s: from_player() fills country, flag, crest, club, league, age, height, foot, number, positions, potential, traits, status" % label,
			"%d bad, e.g. %s" % [bad_card.size(), ", ".join(bad_card.slice(0, 5))])
	_check(FlagService.fallbacks_served == fallbacks_before, "%s: no player needed the neutral fallback flag" % label)
	if label.begins_with("real"):
		_check(with_league > total * 0.9, "real-league pack: league names on the cards", "%d / %d" % [with_league, total])
