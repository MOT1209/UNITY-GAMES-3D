## Database phase 4 validation — original crests: records, generation, rendering, cache,
## registry, custom crests and UI integration:
##   godot --headless --path . res://tests/db_crests_validation.tscn
extends Node

const TMP_DIR := "user://test_crests"

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
	print("=== KING FOOTBALL — database phase 4 (crests) validation ===")
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_test_data()
	_test_shipped()
	_test_generator()
	_test_rendering()
	_test_cache_and_service()
	_test_registry()
	_test_custom_crests()
	_test_kits()
	await _test_ui()
	_test_performance()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db(world: String) -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.load_world(world)
	return db


func _crest(id := "c1", club := "club_a") -> CrestData:
	var c := CrestData.new()
	c.crest_id = id
	c.club_id = club
	c.asset_type = CrestData.AssetType.ORIGINAL_ALTERNATIVE
	c.license_status = "ORIGINAL_NOT_AFFILIATED"
	c.created_at = "2026-11-12"
	c.primary_color = Color("c8102e")
	c.secondary_color = Color("ffffff")
	return c


func _test_data() -> void:
	var c := _crest()
	_check(c.validate().is_empty(), "a complete crest record is valid", str(c.validate()))
	var back := CrestData.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.to_dict() == c.to_dict(), "crest record JSON round-trip identical")
	for field in ["crest_id", "club_id", "asset_path", "asset_type", "version", "shape_style", "symbol", "primary_color",
			"secondary_color", "accent_color", "transparent_background", "license_status", "source", "created_at"]:
		if not c.to_dict().has(field):
			_check(false, "record has field %s" % field)
	_check(true, "record carries every specified metadata field")
	var bad := _crest("", "")
	bad.shape_style = "triangle"
	bad.symbol = "dragon"
	bad.version = 0
	_check(bad.validate().size() == 5, "empty ids, unknown shape/symbol and version 0 are reported", str(bad.validate()))
	var wrong := _crest()
	wrong.license_status = "LICENSED"
	_check(not wrong.validate().is_empty(), "an ORIGINAL_ALTERNATIVE crest cannot claim a LICENSED status")
	var off := _crest()
	off.asset_type = CrestData.AssetType.OFFICIAL_LICENSED
	off.license_status = "LICENSED"
	_check(off.validate().is_empty(), "an official licensed crest with a licence record is accepted")
	var gone := _crest()
	gone.asset_path = "user://does_not_exist.png"
	_check(not gone.validate().is_empty(), "a missing asset file is reported")


func _test_shipped() -> void:
	for world in ["", "real_2025"]:
		var db := _new_db(world)
		var clubs := db.list_teams(TeamData.Category.CLUB)
		_check(db.crests.errors.is_empty(), "[%s] crest file loads without errors" % ("default" if world == "" else world), str(db.crests.errors.slice(0, 2)))
		var missing := 0
		for t: TeamData in clubs:
			missing += 0 if db.crests.crests.has("crest_" + t.id) and t.crest_id == "crest_" + t.id else 1
		_check(missing == 0, "[%s] every club (%d) has a shipped crest record linked by crest_id" % [world, clubs.size()], str(missing))
		var problems := db.crests.validate(db)
		_check(problems.is_empty(), "[%s] crest validation reports nothing" % world, str(problems.slice(0, 3)))
	var db := _new_db("real_2025")
	_check(db.crests.crests.size() == 206, "206 shipped crests (198 real-pack clubs + 8 fictional)", str(db.crests.crests.size()))
	var designs := {}
	for c: CrestData in db.crests.crests.values():
		designs[c.signature()] = true
	_check(designs.size() == db.crests.crests.size(), "no two shipped crests have the same design")
	var real_ok := true
	var fict_ok := true
	for c: CrestData in db.crests.crests.values():
		var club: TeamData = db.get_team(c.club_id)
		if club != null:
			real_ok = real_ok and (c.asset_type == CrestData.AssetType.ORIGINAL_ALTERNATIVE)
		else:
			fict_ok = fict_ok and (c.asset_type == CrestData.AssetType.FICTIONAL)
	_check(real_ok, "crests of real clubs are ORIGINAL_ALTERNATIVE (never official)")
	var none_official := true
	for c: CrestData in db.crests.crests.values():
		none_official = none_official and c.asset_type != CrestData.AssetType.OFFICIAL_LICENSED and c.is_procedural()
	_check(none_official, "no official artwork is shipped (all crests are procedural originals)")
	var stats := db.crests.stats()
	_check(stats["missing_assets"] == 0, "no missing assets", str(stats))


func _test_generator() -> void:
	var used := {}
	var a := CrestGenerator.generate("x_club", Color.RED, Color.WHITE, Color.WHITE, true, used)
	var b := CrestGenerator.generate("x_club", Color.RED, Color.WHITE, Color.WHITE, true, {})
	_check(a.to_dict() == b.to_dict(), "generation is deterministic for the same club and colours")
	var c := CrestGenerator.generate("y_club", Color.RED, Color.WHITE, Color.WHITE, true, used)
	_check(c.signature() != a.signature(), "a second club with the same colours gets a different design")
	var d := CrestGenerator.generate("x_club", Color.RED, Color.WHITE, Color.WHITE, true, used)
	_check(d.signature() == a.signature() and used.size() == 2, "re-generating the same club reuses its own design")
	var blocked := CrestGenerator.generate("z_club", Color.BLUE, Color.WHITE, Color.WHITE, true, {}, CrestData.SYMBOLS.slice(0, 11))
	_check(blocked.symbol == CrestData.SYMBOLS[11], "blocked symbols are never used (only 'castle' left)")
	var db := _new_db("real_2025")
	var bl := JSON.parse_string(FileAccess.get_file_as_string(CrestRegistry.BLOCKLIST_PATH))["blocked_symbols"] as Dictionary
	var ok := not bl.is_empty()
	for club_id in bl:
		var cr: CrestData = db.crests.get_crest("crest_" + club_id)
		ok = ok and cr != null and not (cr.symbol in bl[club_id])
	_check(ok, "shipped crests respect the blocklist of real clubs (%d entries)" % bl.size())
	# the shipped file is exactly what the generator produces from the clubs (nothing hand-edited, nothing stale)
	var regen := {}
	var used2 := {}
	var reg := CrestRegistry.new()
	reg.load_blocklist()
	for world in ["", "real_2025"]:
		var w := _new_db(world)
		for t: TeamData in w.list_teams(TeamData.Category.CLUB):
			regen[t.id] = CrestGenerator.generate(t.id, t.primary_color, t.secondary_color, t.accent_color, t.is_real, used2, reg.blocked_symbols(t.id)).to_dict()
	var same := regen.size() == db.crests.crests.size()
	for club_id in regen:
		var shipped: CrestData = db.crests.get_crest("crest_" + club_id)
		same = same and shipped != null and shipped.to_dict() == regen[club_id]
	_check(same, "crests.json matches a fresh deterministic generation of all %d clubs" % regen.size())


func _test_rendering() -> void:
	var db := _new_db("real_2025")
	var c: CrestData = db.crests.get_crest("crest_eng_arsenal")
	var sizes := {"full": 128, "icon": 40, "mono": 64, "kit": 64, "card": 72}
	var ok := true
	for v in sizes:
		var img := CrestRenderer.render(c, v)
		ok = ok and img.get_width() == sizes[v] and img.get_height() == sizes[v] and img.get_format() == Image.FORMAT_RGBA8
	_check(ok, "five variants (full, icon, mono, kit, card) render at their sizes from ONE record")
	var full := CrestRenderer.render(c, "full")
	_check(full.get_pixel(0, 0).a == 0.0 and full.get_pixel(127, 127).a == 0.0, "corners are transparent (transparent background)")
	_check(full.get_pixel(64, 40).a > 0.99, "the crest body is opaque")
	_check(full.get_data() == CrestRenderer.render(c, "full").get_data(), "rendering is deterministic (same bytes)")
	var mono := CrestRenderer.render(c, "mono")
	var all_white := true
	var any := false
	for y in mono.get_height():
		for x in mono.get_width():
			var p := mono.get_pixel(x, y)
			if p.a > 0.0:
				any = true
				all_white = all_white and p.r == 1.0 and p.g == 1.0 and p.b == 1.0
	_check(any and all_white, "the mono variant is a single-colour (white) silhouette")
	var hashes := {}
	var n := 0
	for cr: CrestData in db.crests.crests.values():
		if n >= 60:
			break
		hashes[CrestRenderer.render(cr, "icon").get_data().hex_encode().sha256_text()] = true
		n += 1
	_check(hashes.size() == 60, "60 different clubs render 60 different icons", str(hashes.size()))
	_check(CrestRenderer.render(c, "icon", 24).get_width() == 24, "an explicit pixel size overrides the variant size")
	var low := _crest("lowcon")
	low.primary_color = Color.WHITE
	low.secondary_color = Color.WHITE
	_check(CrestRenderer.contrast(Color.WHITE, Color.BLACK) > 20.0 and CrestRenderer.contrast(Color.WHITE, Color.WHITE) < 1.01, "contrast helper works")
	var img_low := CrestRenderer.render(low, "full")
	_check(img_low.get_pixel(64, 64).a > 0.0, "an all-white club colour set still renders")
	for shape in CrestData.SHAPES:
		for sym in CrestData.SYMBOLS:
			var t := _crest("t")
			t.shape_style = shape
			t.symbol = sym
			var im := CrestRenderer.render(t, "full", 48)
			if im.get_pixel(24, 24).a == 0.0:
				_check(false, "shape %s + symbol %s renders a filled centre" % [shape, sym])
	_check(true, "all 6 shapes x 12 symbols render")


func _test_cache_and_service() -> void:
	var cache := CrestCache.new()
	var tex := ImageTexture.new()
	for i in CrestCache.MAX_ENTRIES + 40:
		cache.store("k%d" % i, tex)
	_check(cache.size() == CrestCache.MAX_ENTRIES and cache.evictions == 40, "LRU keeps %d textures and evicts the oldest" % CrestCache.MAX_ENTRIES, "%d/%d" % [cache.size(), cache.evictions])
	_check(not cache.has("k0") and cache.has("k%d" % (CrestCache.MAX_ENTRIES + 39)), "the oldest entry is gone, the newest stays")
	cache.fetch("k50")
	cache.store("another", tex)
	_check(cache.has("k50") and not cache.has("k40") and cache.has("k41"), "a recently used entry survives, the least recently used one is evicted")
	var db := _new_db("real_2025")
	CrestService.cache.clear()
	var t1 := CrestService.texture(db, "eng_arsenal", "icon")
	var h := CrestService.cache.hits
	var t2 := CrestService.texture(db, "eng_arsenal", "icon")
	_check(t1 != null and t1 == t2 and CrestService.cache.hits == h + 1, "a repeated request reuses the same texture (cache hit)")
	_check(CrestService.texture(db, "eng_arsenal", "card") != t1, "another variant is another cache entry")
	_check(CrestService.cache.size() == 2, "nothing is drawn before it is requested (2 entries after 2 requests)", str(CrestService.cache.size()))
	_check(CrestService.texture(db, "no_such_team") == null and CrestService.image(db, "no_such_team") == null, "an unknown team has no crest (no crash)")
	var nat := _new_db("")
	_check(CrestService.texture(nat, "nat_aldoria") == null, "a national team has no club crest")


func _test_registry() -> void:
	var db := _new_db("real_2025")
	var ars: TeamData = db.get_team("eng_arsenal")
	var orig: CrestData = db.crests.for_team(ars)
	_check(orig.crest_id == "crest_eng_arsenal" and db.crests.crests_of("eng_arsenal").size() == 1, "a club resolves to its shipped crest")
	# alternative design for the same club
	var alt := _crest("crest_eng_arsenal_alt1", "eng_arsenal")
	alt.shape_style = "hex"
	alt.symbol = "sun"
	alt.division = "band"
	_check(db.crests.add_alternative(alt) == "", "an alternative crest design can be added")
	_check(db.crests.add_alternative(alt) != "", "the same crest id cannot be added twice")
	var clash := _crest("crest_eng_arsenal_alt2", "eng_arsenal")
	clash.shape_style = orig.shape_style
	clash.symbol = orig.symbol
	clash.division = orig.division
	clash.primary_color = orig.primary_color
	clash.secondary_color = orig.secondary_color
	clash.accent_color = orig.accent_color
	clash.club_id = "eng_chelsea_fc"
	_check(db.crests.add_alternative(clash) != "", "a design already used by another club is refused")
	_check(db.crests.assign(ars, "crest_eng_arsenal_alt1") == "" and ars.crest_id == "crest_eng_arsenal_alt1", "the alternative crest is assigned to the club")
	_check(db.crests.for_team(ars).crest_id == "crest_eng_arsenal_alt1", "the club now shows the alternative crest")
	_check(CrestService.cache_key(orig, "icon", 0) != CrestService.cache_key(alt, "icon", 0), "alternative and original crest use different cache entries")
	_check(db.crests.assign(ars, "crest_eng_chelsea_fc") != "", "a club cannot take another club's crest")
	_check(db.crests.assign(ars, "crest_nope") != "", "an unknown crest id is refused")
	# problems are detected
	var broken := _crest("crest_broken", "eng_arsenal")
	broken.asset_type = CrestData.AssetType.USER_CUSTOM
	broken.license_status = "USER_SUPPLIED"
	broken.asset_path = TMP_DIR + "/missing.png"
	db.crests.register(broken)
	_check("crest_broken" in db.crests.missing_assets(), "a crest whose asset file is missing is detected")
	db.crests.crests.erase("crest_broken")
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(TMP_DIR + "/dup_a.png")
	img.save_png(TMP_DIR + "/dup_b.png")
	for pair in [["crest_dup_a", "dup_a.png", "eng_arsenal"], ["crest_dup_b", "dup_b.png", "eng_chelsea_fc"]]:
		var d := _crest(pair[0], pair[2])
		d.asset_type = CrestData.AssetType.USER_CUSTOM
		d.license_status = "USER_SUPPLIED"
		d.asset_path = TMP_DIR + "/" + pair[1]
		db.crests.register(d)
	var found := db.crests.validate(db).filter(func(s: String) -> bool: return "identical image" in s)
	_check(found.size() == 1, "two crests with identical image files are detected", str(found))
	db.crests.crests.erase("crest_dup_a")
	db.crests.crests.erase("crest_dup_b")
	# a club without a shipped crest gets a stable derived one
	var db2 := _new_db("")
	var r := ClubCreator.create_club(db2, {"name": "Test Rovers", "short_name": "TRV", "country": "Aldoria", "strength": 40, "primary": Color.GREEN, "secondary": Color.WHITE}, false)
	var team := db2.get_team(r["team_id"])
	team.logo_path = ""
	var d1 := db2.crests.for_team(team)
	var d2 := db2.crests.for_team(team)
	_check(d1 == d2 and d1.asset_type == CrestData.AssetType.USER_CUSTOM and d1.is_procedural(), "a custom club gets one stable derived crest (USER_CUSTOM)")
	var again := CrestGenerator.generate(team.id, team.primary_color, team.secondary_color, team.accent_color, false, db2.crests._used.duplicate(), [])
	_check(d1.shape_style == again.shape_style and d1.symbol == again.symbol, "the derived crest follows the deterministic generator")


func _test_custom_crests() -> void:
	var db := _new_db("")
	var team: TeamData = db.get_team("club_sunvale")
	var bad_path := TMP_DIR + "/notes.txt"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("not an image")
	f.close()
	var res := db.crests.import_custom(team, bad_path)
	_check(not res["ok"], "importing a non-image file is refused", str(res))
	var small := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	small.save_png(TMP_DIR + "/small.png")
	_check(not db.crests.import_custom(team, TMP_DIR + "/small.png")["ok"], "an image that is too small is refused")
	var good := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	good.fill(Color(0.2, 0.6, 0.3))
	good.save_png(TMP_DIR + "/good.png")
	var ok := db.crests.import_custom(team, TMP_DIR + "/good.png")
	_check(ok["ok"] and team.logo_path == ok["path"], "a valid image is imported and stored", str(ok))
	var c := db.crests.for_team(team)
	_check(c.asset_type == CrestData.AssetType.USER_CUSTOM and c.asset_path == team.logo_path and c.license_status == "USER_SUPPLIED", "the imported image is a USER_CUSTOM crest with a user licence status")
	var img := CrestService.image(db, team, "full")
	_check(img.get_width() == 128 and img.get_pixel(64, 64).g > 0.5, "the imported crest renders from its image file")
	team.logo_path = LogoService.template_ref("circle")
	_check(db.crests.for_team(team).is_template() and CrestService.image(db, team, "icon").get_width() == 40, "a template logo from the customise screen still works")
	team.logo_path = ""
	team.logo_path = "user://missing_logo.png"
	_check(db.crests.for_team(team).is_procedural(), "a missing logo file falls back to the club's own crest (never breaks)")
	DirAccess.remove_absolute(ok["path"])


func _test_ui() -> void:
	var db := _new_db("real_2025")
	var c := UIKit.crest(db, "eng_arsenal", 32)
	_check(c is TextureRect and (c as TextureRect).texture != null and c.custom_minimum_size == Vector2(32, 32), "UIKit.crest returns a textured control of the asked size")
	var nat := _new_db("")
	_check(UIKit.crest(nat, "nat_aldoria", 32) is Control and not (UIKit.crest(nat, "nat_aldoria", 32) is TextureRect), "a national team gets an empty spacer, not a crest")
	c.free()
	# card shows the CURRENT club's crest and follows a transfer
	var card := PlayerCard.new(140.0)
	add_child(card)
	var team: TeamData = db.get_team("eng_arsenal")
	var pid := team.squad_ids[3]
	card.setup(PlayerCardData.from_player(db, pid), db)
	var tex_a := (card.find_child("ClubCrest", true, false) as TextureRect).texture
	_check(tex_a == CrestService.texture(db, "eng_arsenal", "card"), "the player card shows the crest of the player's club")
	var p: PlayerData = db.get_player(pid)
	var chelsea: TeamData = db.get_team("eng_chelsea_fc")
	(team.squad_ids as PackedStringArray).remove_at(team.squad_ids.find(pid))
	chelsea.squad_ids.append(pid)
	p.team_id = "eng_chelsea_fc"
	card.refresh()
	var tex_b := (card.find_child("ClubCrest", true, false) as TextureRect).texture
	_check(tex_b == CrestService.texture(db, "eng_chelsea_fc", "card") and tex_b != tex_a, "after a transfer the same player's card shows the new club's crest")
	var mini := PlayerCard.new(100.0)
	mini.minimal = true
	add_child(mini)
	mini.setup(PlayerCardData.from_player(db, pid), db)
	_check(not (mini.find_child("ClubCrest", true, false) as TextureRect).visible, "minimal (pitch) cards keep the crest hidden")
	card.queue_free()
	mini.queue_free()
	# screens
	var app: Node = get_node("/root/AppHub")
	app.db.load_world("real_2025")
	app.career = null
	app.squads.clear()
	app.start_career("eng_leicester_city_fc")
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	for pair in [["leagues", 40], ["team_select", 10], ["career", 1], ["team_details", 1], ["squad", 0]]:
		hub.navigate(pair[0])
		await get_tree().process_frame
		await get_tree().process_frame
		var crests := _crest_controls(hub.current)
		_check(crests.size() >= pair[1], "screen '%s' shows %d+ crests" % [pair[0], pair[1]], str(crests.size()))
	hub.queue_free()
	# match results view
	var report := {"home_id": "eng_arsenal", "away_id": "eng_chelsea_fc", "home_goals": 2, "away_goals": 1, "source": "engine",
			"players": [], "scorers": [], "team_stats": {}, "measured": ["score"], "motm": "", "outcome_human": ""}
	var view := MatchResultsView.create(report, app.db)
	add_child(view)
	_check(_crest_controls(view).size() == 2, "the results screen shows both club crests")
	view.queue_free()
	app.career = null
	app.squads.clear()
	app.db.reload()


func _test_kits() -> void:
	var db := _new_db("real_2025")
	var team: TeamData = db.get_team("eng_arsenal")
	var kit := {"main": Color("c8102e"), "secondary": Color.WHITE, "accent": Color.WHITE, "shorts": Color("101010"), "socks": Color("c8102e"), "pattern": "solid"}
	var plain := KitRenderer.render(kit, null, 1)
	_check(plain.get_width() == 88 and plain.get_height() == 112, "kit image has the base size (88 x 112)")
	_check(plain.get_pixel(44, 45).r > 0.6 and plain.get_pixel(44, 45).g < 0.25, "shirt body is painted in the main colour")
	_check(plain.get_pixel(30, 75).r < 0.2, "shorts are painted in the shorts colour")
	_check(plain.get_pixel(2, 2).a == 0.0, "outside the garments is transparent")
	var crest := CrestService.image(db, team, "kit")
	var with_crest := KitRenderer.render(kit, crest, 1)
	_check(with_crest.get_data() != plain.get_data(), "the club crest is drawn on the chest")
	var distinct := {}
	for pat in KitEditor.PATTERNS:
		var k := kit.duplicate()
		k["pattern"] = pat
		distinct[KitRenderer.render(k, null, 1).get_data().hex_encode().sha256_text()] = true
	_check(distinct.size() == KitEditor.PATTERNS.size(), "all %d patterns look different" % KitEditor.PATTERNS.size())
	var t1 := KitService.texture(db, team, "home")
	_check(t1 != null and t1 == KitService.texture(db, team, "home"), "kit textures are cached")
	KitEditor.set_field(team, "home", "main", "00ff00")
	_check(KitService.texture(db, team, "home") != t1, "a changed kit colour gives a new texture")
	_check(KitService.texture(db, team, "nope") == null, "a missing kit slot gives no texture")


func _crest_controls(root: Node) -> Array:
	return root.find_children("*", "TextureRect", true, false).filter(func(n: Node) -> bool: return n.has_meta("crest_club"))


func _test_performance() -> void:
	var db := _new_db("real_2025")
	var clubs := db.list_teams(TeamData.Category.CLUB)
	var t0 := Time.get_ticks_msec()
	for t: TeamData in clubs:
		CrestRenderer.render(db.crests.for_team(t), "icon")
	var icon_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	for i in 20:
		CrestRenderer.render(db.crests.for_team(clubs[i]), "full")
	var full_ms := Time.get_ticks_msec() - t0
	print("[PERF] %d icons (40 px) in %d ms; 20 full crests (128 px) in %d ms" % [clubs.size(), icon_ms, full_ms])
	_check(icon_ms < 10000 and full_ms < 10000, "rendering is fast enough to do lazily (%d ms / %d ms)" % [icon_ms, full_ms])
