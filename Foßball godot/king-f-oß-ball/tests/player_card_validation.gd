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
	await _test_round3_layout()
	_test_contrast_and_themes()
	await _test_badges_and_shine()
	await _test_detail_view()
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
	# two players identical except for the face must render differently
	var twin_a := PlayerData.from_dict(players[0].to_dict())
	var twin_b := PlayerData.from_dict(players[0].to_dict())
	twin_a.id = "twin_a"
	twin_b.id = "twin_b"
	twin_b.appearance = twin_a.appearance.duplicate()
	twin_a.appearance = PlayerAppearance.ensure(twin_a).duplicate()
	twin_b.appearance["eyes"] = (int(twin_a.appearance["eyes"]) + 2) % FaceBuilder.EYES.size()
	twin_b.appearance["mouth"] = (int(twin_a.appearance["mouth"]) + 2) % FaceBuilder.MOUTHS.size()
	twin_b.appearance["face"] = (int(twin_a.appearance["face"]) + 1) % FaceBuilder.SHAPES.size()
	db.players["twin_a"] = twin_a
	db.players["twin_b"] = twin_b
	var tw_a: Texture2D = await r.request(PlayerCardData.from_data(db, twin_a), db)
	var tw_b: Texture2D = await r.request(PlayerCardData.from_data(db, twin_b), db)
	_check(tw_a != null and tw_b != null and tw_a.get_image().get_data() != tw_b.get_image().get_data(), "players that differ only in face parts render different portraits")
	db.players.erase("twin_a")
	db.players.erase("twin_b")
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


# --- round 3 (C1-C4) ------------------------------------------------------------------------------------

## Longest display name in the shipped data (fictional world + real-league pack).
func _longest_name_player() -> PlayerData:
	var best: PlayerData = null
	for pack in ["real_2025", ""]:
		db.load_world(pack)
		for p: PlayerData in db.players.values():
			if best == null or p.display_name.length() > best.display_name.length():
				best = PlayerData.from_dict(p.to_dict())
	db.load_world("")
	best.id = "test_longest_name"
	best.team_id = (db.list_teams(TeamData.Category.CLUB)[0] as TeamData).id
	var parts := PlayerData.split_name(best.display_name)
	best.first_name = parts[0]
	best.last_name = parts[1]
	return best


## Problems of one card's layout ("" = fine): every content node inside the card, every label's line height
## inside its box, fixed-size texts (rating, position, stat values, abbreviations, shirt number) not trimmed,
## the name either fitting or at the minimum size with an ellipsis.
func _layout_problems(card: PlayerCard) -> Array:
	var out: Array = []
	var bounds := Rect2(Vector2.ZERO, card.size).grow(0.5)
	for n: Control in card.content_nodes():
		if not n.visible:
			continue
		var r := Rect2(n.position, n.size)
		if n.get_parent() != card:
			r.position += (n.get_parent() as Control).position
		if not bounds.encloses(r):
			out.append("%s outside the card %s" % [n.name, str(r)])
		if n is Label:
			var l := n as Label
			if l.text == "":
				continue
			var font := l.get_theme_font("font")
			var fs := l.get_theme_font_size("font_size")
			var line_h := font.get_height(fs)
			if line_h > l.size.y + 1.5:
				out.append("%s line %.0f px > box %.0f px" % [n.name, line_h, l.size.y])
			var tw := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var fixed: bool = l != card.name_label() and n.name != "ClubLine"
			if fixed and tw > l.size.x + 1.0:
				out.append("%s '%s' %.0f px wide > %.0f" % [n.name, l.text, tw, l.size.x])
			if l == card.name_label() and tw > l.size.x + 1.0 and card.name_font_size() > PlayerCard.MIN_NAME_FONT:
				out.append("name trimmed above the minimum font size")
	return out


func _test_round3_layout() -> void:
	var longest := _longest_name_player()
	print("[INFO] longest name in the data: '%s' (%d chars)" % [longest.display_name, longest.display_name.length()])
	var gk: PlayerData = _any_players().filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK)[0]
	var outfield: PlayerData = _any_players().filter(func(p: PlayerData) -> bool: return p.position != PlayerData.Position.GK)[0]
	for code in ["en", "de", "ar"]:
		Loc.set_language(code, false)
		# fixed 3-letter abbreviations in every language
		var abbr_ok := true
		for k in ["PAC", "SHO", "PAS", "DRI", "DEF", "PHY", "GKP"]:
			abbr_ok = abbr_ok and Loc.t("CARD_ABBR_" + k).length() == 3
		_check(abbr_ok, "[%s] every stat abbreviation has exactly 3 letters" % code)
		for pl: PlayerData in [outfield, gk, longest]:
			for width in [150.0, 220.0, 300.0]:
				var card := _make_card(pl, width)
				await get_tree().process_frame
				var tag := "[%s %d] %s" % [code, int(width), str(pl.id).left(16)]
				var probs := _layout_problems(card)
				_check(probs.is_empty(), "%s: no text or image outside its box / the card" % tag, str(probs.slice(0, 3)))
				if width == 220.0:
					var t := card.texts()
					_check(t["has_flag"] and t["has_crest"] and t["club"] != "", "%s: full card shows flag, club crest and club line" % tag)
					var rating := card.find_child("Rating", true, false) as Control
					var on_right := rating.position.x + rating.size.x * 0.5 > card.size.x * 0.5
					_check(on_right == (code == "ar"), "%s: rating corner mirrors in RTL (right in Arabic, left otherwise)" % tag)
					var codes: Array = t["stats"].map(func(x: Dictionary) -> String: return str(x["code"]))
					if pl == gk:
						_check(Loc.t("CARD_ABBR_GKP") in codes, "%s: goalkeeper card shows the goalkeeper attribute set" % tag, str(codes))
					else:
						_check(not (Loc.t("CARD_ABBR_GKP") in codes) and codes.size() == 6, "%s: outfield card shows the six outfield attributes" % tag)
					_check(t["shown_name"] == card.data.last_name and t["name"] == pl.display_name, "%s: name bar shows the last name" % tag, t["shown_name"])
				card.queue_free()
		# minimal (pitch) card
		var mini := PlayerCard.new(96.0)
		mini.minimal = true
		add_child(mini)
		mini.size = Vector2(96, 96 * 1.2)
		mini.setup(PlayerCardData.from_data(db, outfield), db)
		mini.relayout()
		await get_tree().process_frame
		var mt := mini.texts()
		var probs := _layout_problems(mini)
		_check(mt["has_flag"] and not mt["has_crest"] and not (mini.find_child("StatGrid", true, false) as Control).visible
				and not (mini.find_child("ClubLine", true, false) as Control).visible,
				"[%s] minimal card: rating, position, flag, portrait and last name only" % code)
		_check(probs.is_empty(), "[%s] minimal card: everything inside its box" % code, str(probs.slice(0, 3)))
		mini.queue_free()
	Loc.set_language("en", false)


func _test_contrast_and_themes() -> void:
	var worst := 99.0
	var detail := ""
	for k in CardCategory.all_kinds():
		var th := CardCategory.theme(k)
		for fg in ["text", "muted", "rating"]:
			for bg in ["bg_top", "bg_bottom", "panel_top", "panel_bottom"]:
				var c := CardCategory.contrast(th[fg], th[bg])
				if c < worst:
					worst = c
					detail = "%s %s on %s = %.2f" % [th["key"], fg, bg, c]
				_check(c >= 4.5, "%s: %s on %s has contrast >= 4.5:1 (WCAG AA)" % [th["key"], fg, bg], "%.2f" % c)
	print("[INFO] lowest text contrast: %s" % detail)
	_check(is_equal_approx(CardCategory.contrast(Color.BLACK, Color.WHITE), 21.0), "contrast formula: black on white = 21")
	var kinds := CardCategory.all_kinds()
	var distinct := true
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var a := CardCategory.theme(kinds[i])
			var b := CardCategory.theme(kinds[j])
			var d := _cdist(a["frame"], b["frame"]) + _cdist(a["bg_top"], b["bg_top"]) + _cdist(a["frame_dark"], b["frame_dark"])
			if d < 0.25:
				distinct = false
				detail = "%s vs %s (%.2f)" % [a["key"], b["key"], d]
	_check(distinct, "every category has its own frame and background colours", detail)


func _cdist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _test_badges_and_shine() -> void:
	var base := PlayerData.from_dict((_any_players()[2] as PlayerData).to_dict())
	base.id = "test_badges"
	base.age = 19
	base.status = PlayerData.Status.INJURED
	base.loan_parent = ""
	db.players[base.id] = base
	base.potential = mini(base.get_overall() + 8, 99)
	var card := _make_card(base)
	await get_tree().process_frame
	var b: Array = card.texts()["badges"]
	_check("injured" in b and "youth" in b and "potential" in b and not ("captain" in b), "badges: injured, youth (U21) and potential arrow shown", str(b))
	card.data.is_captain = true
	card.refresh()
	_check("captain" in card.texts()["badges"], "captain badge follows the squad's captain")
	base.status = PlayerData.Status.SUSPENDED
	base.age = 27
	base.potential = base.get_overall()
	card.refresh()
	b = card.texts()["badges"]
	_check("suspended" in b and not ("injured" in b) and not ("youth" in b) and not ("potential" in b), "badges follow the player (suspended; no youth / potential)", str(b))
	base.status = PlayerData.Status.LOANED
	card.refresh()
	_check("loan" in card.texts()["badges"], "loan badge for a loaned player")
	var badge_probs := _layout_problems(card)
	_check(badge_probs.is_empty(), "badges stay inside the card", str(badge_probs))
	card.queue_free()
	db.players.erase(base.id)
	# shader gloss: upper classes only, never in low-performance mode
	var path: String = GameSettings.settings_path
	GameSettings.settings_path = "user://test_card_shine_settings.cfg"
	DirAccess.remove_absolute(GameSettings.settings_path)
	var shine := {}
	for k in CardCategory.all_kinds():
		var f := CardFrame.new()
		f.kind = k
		shine[k] = f.has_shader_shine()
		f.free()
	_check(not shine[CardCategory.Kind.BRONZE] and not shine[CardCategory.Kind.SILVER] and shine[CardCategory.Kind.GOLD]
			and shine[CardCategory.Kind.ELITE] and shine[CardCategory.Kind.LEGENDARY], "shader gloss only on the upper classes (gold, elite, legendary)", str(shine))
	GameSettings.set_value("graphics", "shadows", "off")
	var low := CardFrame.new()
	low.kind = CardCategory.Kind.LEGENDARY
	_check(not low.has_shader_shine(), "shader gloss is off in low-performance mode")
	low.free()
	DirAccess.remove_absolute(GameSettings.settings_path)
	GameSettings.settings_path = path


func _test_detail_view() -> void:
	var p: PlayerData = _any_players().filter(func(x: PlayerData) -> bool: return not x.traits.is_empty())[0] if _any_players().any(func(x: PlayerData) -> bool: return not x.traits.is_empty()) else _any_players()[0]
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	var log := [{"players": [{"player_id": p.id, "rating": 7.4}]}, {"players": [{"player_id": "other", "rating": 5.0}]},
			{"players": [{"player_id": p.id, "rating": 6.1}]}]
	for code in ["en", "ar"]:
		Loc.set_language(code, false)
		var v := CardDetailView.open(host, db, p.id, log)
		await get_tree().process_frame
		var c := v.card_data
		var facts := v.find_child("DetailFacts", true, false)
		var need := ["CARD_DETAIL_L_AGE", "CARD_DETAIL_L_BODY", "CARD_DETAIL_L_FOOT", "CARD_DETAIL_L_POSITIONS", "CARD_DETAIL_L_NUMBER",
				"CARD_DETAIL_L_RATING", "CARD_DETAIL_L_CONTRACT", "CARD_DETAIL_L_VALUE"]
		var missing: Array = need.filter(func(n: String) -> bool: return facts.find_child(n, false, false) == null)
		_check(missing.is_empty(), "[%s] detail lists age, height/weight, foot, positions, number, rating/potential, contract, value" % code, str(missing))
		var country := v.find_child("DetailCountry", true, false)
		_check(country != null and (country.find_child("Icon", false, false) as TextureRect).texture != null
				and (country.find_child("Text", false, false) as Label).text == c.country_name, "[%s] detail shows flag + country name" % code)
		var club := v.find_child("DetailClub", true, false)
		_check(club != null and (club.find_child("Text", false, false) as Label).text.contains(c.club_name), "[%s] detail shows crest + club (+ league)" % code)
		_check(c.recent_ratings == [7.4, 6.1] and v.find_child("DetailForm", true, false) != null, "[%s] last match ratings from the career log" % code, str(c.recent_ratings))
		_check(p.traits.is_empty() or v.find_child("DetailTraits", true, false).get_child_count() == p.traits.size(), "[%s] traits shown as chips" % code)
		v.free()
	host.queue_free()
	Loc.set_language("en", false)
