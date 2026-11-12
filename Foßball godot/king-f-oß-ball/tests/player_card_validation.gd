## Player card validation — categories, real-data binding, layout in 3 languages,
## portraits, filters (Phases V5-V8, V11).
##   godot --headless --path . res://tests/player_card_validation.tscn      (logic + layout)
##   xvfb-run godot --path . res://tests/player_card_validation.tscn        (adds portrait checks)
## Portrait checks need a rendering device; without one they are reported as
## SKIPPED (never as passed).
extends Node

var _passed := 0
var _failed := 0
var _skipped := 0
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _skip(name: String, why: String) -> void:
	_skipped += 1
	print("[SKIP] %s — %s" % [name, why])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Player card validation ===")
	db = get_node("/root/TeamDB")
	_test_categories()
	_test_card_data()
	await _test_card_control()
	await _test_languages_and_names()
	await _test_no_stale_copy()
	await _test_portraits()
	_test_collection_filters()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed (%d skipped) ===" % [_passed, _failed, _skipped])
	get_tree().quit(1 if _failed > 0 else 0)


func _any_players(n := 400) -> Array:
	var out: Array = []
	for t: TeamData in db.list_teams():
		out.append_array(db.get_squad(t.id))
		if out.size() >= n:
			break
	return out


## A real player whose stats are scaled so that it lands in `kind`. Used only to
## render every category; clearly test data, never shown in the game.
func _player_in(kind: int) -> PlayerData:
	var p: PlayerData = (_any_players()[0] as PlayerData)
	var c := PlayerData.from_dict(p.to_dict())
	c.id = "test_cat_%d" % kind
	var target: int = [60, 70, 80, 87, 93][kind]
	for a in PlayerData.ATTRIBUTES:
		c.set(a, target)
	c.potential = 99
	return c


func _test_categories() -> void:
	_check(CardCategory.all_kinds().size() == 5, "five card categories exist")
	var keys := {}
	for k in CardCategory.all_kinds():
		var th := CardCategory.theme(k)
		keys[th["key"]] = true
		_check(th.has("frame") and th.has("bg_top") and th.has("bg_bottom") and th.has("text"), "theme complete: %s" % th["key"])
	_check(keys.size() == 5, "five distinct theme keys")
	_check(CardCategory.for_overall(50) == CardCategory.Kind.BRONZE and CardCategory.for_overall(64) == CardCategory.Kind.BRONZE, "<65 is Bronze")
	_check(CardCategory.for_overall(65) == CardCategory.Kind.SILVER and CardCategory.for_overall(74) == CardCategory.Kind.SILVER, "65-74 is Silver")
	_check(CardCategory.for_overall(75) == CardCategory.Kind.GOLD and CardCategory.for_overall(84) == CardCategory.Kind.GOLD, "75-84 is Gold")
	_check(CardCategory.for_overall(85) == CardCategory.Kind.ELITE and CardCategory.for_overall(89) == CardCategory.Kind.ELITE, "85-89 is Elite")
	_check(CardCategory.for_overall(90) == CardCategory.Kind.LEGENDARY and CardCategory.for_overall(99) == CardCategory.Kind.LEGENDARY, "90+ is Legendary")
	_check(CardCategory.for_player(null) == CardCategory.Kind.BRONZE, "null player is safe")
	_check(CardCategory.theme(CardCategory.Kind.LEGENDARY)["red"] == true and CardCategory.theme(CardCategory.Kind.GOLD)["red"] == false, "red accent is legendary-only")
	_check(CardCategory.GOLD == Color("#D4AF37") and CardCategory.BLACK == Color("#111111") and CardCategory.ROYAL_RED == Color("#A51E2B"), "brand palette values")
	var seen := {}
	for p: PlayerData in _any_players():
		seen[CardCategory.for_player(p)] = true
	print("[INFO] categories present in the shipped player data: %s" % str(seen.keys()))


func _test_card_data() -> void:
	var players := _any_players()
	_check(not players.is_empty(), "player database has players")
	var all_match := true
	var detail := ""
	for p: PlayerData in players.slice(0, 120):
		var c := PlayerCardData.from_player(db, p.id)
		var ok: bool = c != null and c.name == p.display_name and c.overall == p.get_overall() \
				and c.position == PlayerData.Position.keys()[p.position] and c.age == p.age and c.nationality == p.nationality \
				and c.stats.size() == 6 and c.category == CardCategory.for_overall(p.get_overall())
		for i in 6:
			ok = ok and c.stats[i]["value"] == p.get_attribute(PlayerCardData.CORE[i][1])
		var team: TeamData = db.get_team(p.team_id)
		ok = ok and c.club == (team.display_name if team != null else "")
		if not ok:
			all_match = false
			detail = p.id
	_check(all_match, "card data equals live player data for 120 players (name/ovr/pos/age/nation/club/6 attrs/category)", detail)
	_check(PlayerCardData.from_player(db, "ghost_id") == null, "unknown player id -> null card data")
	var gk: PlayerData = players.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK)[0]
	var gc := PlayerCardData.from_data(db, gk)
	_check(gc.is_goalkeeper and gc.goalkeeping == gk.goalkeeping, "goalkeeper card carries the real goalkeeping rating")
	_check(gc.kit(db) is TeamKit, "kit resolves for the player's club")
	var key1 := gc.portrait_key(db)
	var team: TeamData = db.get_team(gk.team_id)
	var old_main: String = str(team.kits["home"]["main"])
	team.kits["goalkeeper"]["main"] = "ff00aa"
	_check(PlayerCardData.from_data(db, gk).portrait_key(db) != key1, "kit change changes the portrait cache key")
	team.kits["home"]["main"] = old_main


func _make_card(p: PlayerData, width := 220.0) -> PlayerCard:
	var card := PlayerCard.new(width)
	add_child(card)
	card.size = card.custom_minimum_size
	card.setup(PlayerCardData.from_data(db, p), db)
	return card


func _test_card_control() -> void:
	Loc.set_language("en", false)
	var shown := {}
	for kind in CardCategory.all_kinds():
		var p := _player_in(kind)
		var card := _make_card(p)
		await get_tree().process_frame
		var t := card.texts()
		shown[CardCategory.key(kind)] = true
		_check(card.data.category == kind, "card shows category %s" % CardCategory.key(kind))
		_check(t["name"] == p.display_name, "name is the player's (%s)" % CardCategory.key(kind))
		_check(t["ovr"] == str(p.get_overall()), "OVR is the player's (%s)" % CardCategory.key(kind), t["ovr"])
		_check(t["position"] == PlayerData.Position.keys()[p.position], "position is the player's (%s)" % CardCategory.key(kind))
		var stats_ok := true
		for i in 6:
			stats_ok = stats_ok and t["stats"][i]["value"] == str(p.get_attribute(PlayerCardData.CORE[i][1]))
		_check(stats_ok, "six attribute values are the player's (%s)" % CardCategory.key(kind))
		card.queue_free()
	_check(shown.size() == 5, "all five categories rendered by the one PlayerCard")
	var empty := PlayerCard.new(160.0)
	add_child(empty)
	empty.setup(null, db)
	_check(empty.texts()["name"] == "—", "empty card renders a placeholder")
	empty.queue_free()
	var small := _make_card(_any_players()[0], 60.0)
	var big := _make_card(_any_players()[0], 420.0)
	await get_tree().process_frame
	_check(big.name_font_size() > small.name_font_size(), "fonts scale with card size (resolution independent)")
	_check(is_equal_approx(big.custom_minimum_size.y / big.custom_minimum_size.x, PlayerCard.ASPECT), "fixed card aspect ratio")
	small.queue_free()
	big.queue_free()


func _test_languages_and_names() -> void:
	var p := _any_players()[0] as PlayerData
	var long_latin := PlayerData.from_dict(p.to_dict())
	long_latin.display_name = "Maximilian Alexander Wolfgang von Hohenzollern-Sigmaringen"
	var long_arabic := PlayerData.from_dict(p.to_dict())
	long_arabic.display_name = "عبد الرحمن محمد بن سلطان آل نهيان الشمري القحطاني"
	long_latin.id = "test_long_latin"
	long_arabic.id = "test_long_arabic"
	for code in ["en", "de", "ar"]:
		Loc.set_language(code, false)
		for pl in [p, long_latin, long_arabic]:
			var card := _make_card(pl, 180.0)
			await get_tree().process_frame
			var t := card.texts()
			var leaked := false
			for s in t["stats"]:
				leaked = leaked or str(s["code"]).begins_with("CARD_") or str(s["code"]) == ""
			_check(not leaked, "[%s] stat captions are translated (%s)" % [code, str(pl.id).left(18)])
			var lab := card.name_label()
			var font := lab.get_theme_font("font")
			var w := font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, card.name_font_size()).x
			_check(w <= lab.size.x + 1.0 or card.name_font_size() <= PlayerCard.MIN_NAME_FONT,
					"[%s] long name fits without clipping (%s)" % [code, str(pl.id).left(18)], "%.0f > %.0f" % [w, lab.size.x])
			card.queue_free()
		_check(Loc.t("CARD_CAT_LEGENDARY") != "" and not Loc.t("CARD_CAT_LEGENDARY").begins_with("CARD_"), "[%s] category names translated" % code)
	Loc.set_language("en", false)


func _test_no_stale_copy() -> void:
	var p := PlayerData.from_dict((_any_players()[3] as PlayerData).to_dict())
	p.id = "test_dynamic"
	p.team_id = ""
	db.players[p.id] = p
	var card := PlayerCard.new(200.0)
	add_child(card)
	card.size = card.custom_minimum_size
	card.setup(PlayerCardData.from_data(db, p), db)
	var before := card.texts()
	for a in PlayerData.ATTRIBUTES:
		p.set(a, 95)
	p.display_name = "Renamed Player"
	p.position = PlayerData.Position.ST
	var other_team := db.list_teams(TeamData.Category.CLUB)[1] as TeamData
	p.team_id = other_team.id
	card.refresh()
	var after := card.texts()
	_check(after["name"] == "Renamed Player" and after["ovr"] == str(p.get_overall()) and after["position"] == "ST",
			"refresh() shows improved attributes, new position and name")
	_check(card.data.category == CardCategory.Kind.LEGENDARY and before["ovr"] != after["ovr"], "category follows the new overall")
	_check(after["club"].begins_with(other_team.display_name), "transfer updates the club on the card")
	db.players.erase(p.id)
	card.queue_free()


func _test_portraits() -> void:
	if not PlayerPortraitRenderer.can_render():
		_skip("portrait rendering (4 checks)", "no rendering device (headless) — run with xvfb-run and without --headless")
		var r := PlayerPortraitRenderer.shared(get_tree())
		await get_tree().process_frame
		var c := PlayerCardData.from_data(db, _any_players()[0])
		var tex: Texture2D = await r.request(c, db)
		_check(tex == null, "renderer degrades to null (silhouette fallback) without a GPU instead of crashing")
		return
	var r := PlayerPortraitRenderer.shared(get_tree())
	await get_tree().process_frame
	var players: Array = _any_players().filter(func(p: PlayerData) -> bool: return p.position != PlayerData.Position.GK)
	var a := PlayerCardData.from_data(db, players[0])
	var b := PlayerCardData.from_data(db, players[7])
	var ta: Texture2D = await r.request(a, db)
	var tb: Texture2D = await r.request(b, db)
	_check(ta != null and tb != null, "portraits render")
	if ta == null or tb == null:
		return
	var ia := ta.get_image()
	var ib := tb.get_image()
	var opaque := 0
	for y in range(0, ia.get_height(), 4):
		for x in range(0, ia.get_width(), 4):
			if ia.get_pixel(x, y).a > 0.5:
				opaque += 1
	_check(opaque > 200, "portrait shows a model (not empty)", str(opaque))
	_check(ia.get_pixel(2, 2).a < 0.05, "portrait background is transparent (no artefacts)")
	_check(ia.get_data() != ib.get_data(), "different players give different portraits")
	var renders_before := r.renders
	var again: Texture2D = await r.request(a, db)
	_check(again == ta and r.renders == renders_before, "same player + kit + appearance is served from cache")
	var kit_team: TeamData = db.get_team((players[0] as PlayerData).team_id)
	var old_main: String = str(kit_team.kits["home"]["main"])
	kit_team.kits["home"]["main"] = "00ff00" if old_main != "00ff00" else "ff0000"
	var recolored: Texture2D = await r.request(PlayerCardData.from_data(db, players[0]), db)
	_check(recolored != ta and r.renders == renders_before + 1, "kit change renders a fresh portrait")
	kit_team.kits["home"]["main"] = old_main
	var viewports_before := get_tree().root.find_children("*", "SubViewport", true, false).size()
	var t0 := Time.get_ticks_msec()
	for i in 12:
		await r.request(PlayerCardData.from_data(db, players[i]), db)
	print("[INFO] 12 portraits rendered/cached in %d ms (software GL); texture size %s" % [Time.get_ticks_msec() - t0, str(PlayerPortraitRenderer.SIZE)])
	var viewports_after := get_tree().root.find_children("*", "SubViewport", true, false).size()
	_check(viewports_after == viewports_before, "rendering 12 portraits creates no additional viewports", "%d -> %d" % [viewports_before, viewports_after])
	_check(r.cache_size() <= PlayerPortraitRenderer.MAX_CACHE, "portrait cache is bounded")
	var card := _make_card(players[0])
	await get_tree().create_timer(0.5).timeout
	_check(card.texts()["has_portrait"], "card control displays the rendered portrait")
	card.queue_free()
	r.release(true)
	await get_tree().process_frame
	_check(get_tree().root.find_children("*", "SubViewport", true, false).size() == 0 and r.cache_size() == 0, "release() frees the viewport and the cache")


func _test_collection_filters() -> void:
	var script: GDScript = load("res://scripts/ui/screens/player_collection_screen.gd")
	var pool: Array = _any_players(150)
	var all: Array = script.filter_and_sort(pool, "", -1, 0, -1, "ovr")
	_check(all.size() == pool.size(), "no filter keeps every player")
	var sorted_ok := true
	for i in range(1, all.size()):
		sorted_ok = sorted_ok and (all[i - 1] as PlayerData).get_overall() >= (all[i] as PlayerData).get_overall()
	_check(sorted_ok, "sort by rating is descending")
	var sts: Array = script.filter_and_sort(pool, "", PlayerData.Position.ST, 0, -1, "ovr")
	_check(sts.all(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.ST), "position filter")
	var strong: Array = script.filter_and_sort(pool, "", -1, 70, -1, "ovr")
	_check(strong.all(func(p: PlayerData) -> bool: return p.get_overall() >= 70), "rating filter")
	var first_name := (pool[0] as PlayerData).display_name
	var found: Array = script.filter_and_sort(pool, first_name.to_upper().left(5), -1, 0, -1, "name")
	_check(found.any(func(p: PlayerData) -> bool: return p.display_name == first_name), "search is case-insensitive")
	var cat: Array = script.filter_and_sort(pool, "", -1, 0, CardCategory.Kind.GOLD, "ovr")
	_check(cat.all(func(p: PlayerData) -> bool: return CardCategory.for_player(p) == CardCategory.Kind.GOLD), "category filter")
	var by_name: Array = script.filter_and_sort(pool, "", -1, 0, -1, "name")
	_check(by_name.size() == pool.size(), "sort by name keeps every player")
