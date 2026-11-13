extends HubScreen

## Database tools (database phase 7): Club Manager, Player Manager, Crest Manager and database
## operations in one developer screen. Every button calls DatabaseTools / CrestRegistry, the same
## functions `tools/db_cli.gd` uses, and changes the live database.

const TABS: Array[String] = ["clubs", "players", "crests", "database"]
const POSITION_FILTER: Array[String] = ["", "GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"]
const TYPE_FILTER: Array[String] = ["", "REAL", "FICTIONAL", "CUSTOM"]
const MAX_ROWS := 40

var _tab := 0
var _club_text := ""
var _club_country := ""
var _club_type := ""
var _club_id := ""
var _player_text := ""
var _player_pos := ""
var _player_id := ""
var _crest_club := ""
var _out := ""                 # last text result of a database operation (validation, stats, import ...)
var _export_path := "user://exports/king_database.json"
var _import_path := "user://exports/king_database.json"
var _gen_path := "user://exports/generated_clubs.json"
var _gen_seed := 1
var _gen_count := 2
var _crest_path := ""


func build() -> void:
	add_child(UIKit.title(Loc.t("DBT_TITLE")))
	add_child(UIKit.muted(Loc.t("DBT_INTRO")))
	var tabs := TabContainer.new()
	tabs.name = "DbTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 420)
	add_child(tabs)
	for key in ["DBT_TAB_CLUBS", "DBT_TAB_PLAYERS", "DBT_TAB_CRESTS", "DBT_TAB_DATABASE"]:
		var page := UIKit.vbox(8)
		page.name = key
		tabs.add_child(page)
		tabs.set_tab_title(tabs.get_child_count() - 1, Loc.t(key))
	_build_clubs(tabs.get_child(0))
	_build_players(tabs.get_child(1))
	_build_crests(tabs.get_child(2))
	_build_database(tabs.get_child(3))
	tabs.current_tab = clampi(_tab, 0, tabs.get_tab_count() - 1)
	tabs.tab_changed.connect(func(i: int) -> void: _tab = i)


func _countries() -> Array:
	var out: Array = [""]
	for c: CountryData in db().countries.values():
		out.append(c.country_name)
	return out


func _line(placeholder: String, value: String, on_submit: Callable, width := 220.0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(width, 0)
	e.text_submitted.connect(on_submit)
	return e


# --- clubs ------------------------------------------------------------------------------------------------

func _build_clubs(page: Control) -> void:
	var bar := UIKit.hbox(8)
	var search := _line(Loc.t("DBT_SEARCH_CLUB"), _club_text, func(t: String) -> void:
		_club_text = t
		rebuild())
	search.name = "ClubSearch"
	bar.add_child(search)
	var countries := _countries()
	var co := UIKit.option(countries.map(func(c: String) -> String: return c if c != "" else Loc.t("DBT_ALL_COUNTRIES")),
			maxi(countries.find(_club_country), 0), func(i: int) -> void:
		_club_country = countries[i]
		rebuild())
	co.name = "ClubCountry"
	bar.add_child(co)
	var ty := UIKit.option(TYPE_FILTER.map(func(t: String) -> String: return t if t != "" else Loc.t("DBT_ALL_TYPES")),
			maxi(TYPE_FILTER.find(_club_type), 0), func(i: int) -> void:
		_club_type = TYPE_FILTER[i]
		rebuild())
	ty.name = "ClubType"
	bar.add_child(ty)
	var go_btn := UIKit.button(Loc.t("DBT_SEARCH"), func() -> void:
		_club_text = search.text
		rebuild(), 100)
	go_btn.name = "ClubSearchButton"
	bar.add_child(go_btn)
	page.add_child(bar)
	var found := DatabaseTools.search_clubs(db(), {"text": _club_text, "country": _club_country, "type": _club_type, "limit": 100000})
	page.add_child(UIKit.muted(Loc.f("DBT_FOUND", [found.size(), mini(found.size(), MAX_ROWS)])))
	var split := UIKit.hbox(12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	var list := UIKit.vbox(2)
	list.name = "ClubResults"
	for t in found.slice(0, MAX_ROWS):
		var row := UIKit.hbox(6)
		row.add_child(UIKit.crest(db(), t, 22))
		var b := UIKit.button("%s  ·  %s  ·  %s" % [t.display_name, t.country, t.league_id if t.league_id != "" else "-"],
				func() -> void:
			_club_id = t.id
			rebuild(), 380)
		b.name = "Club_%s" % t.id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		list.add_child(row)
	var scroll := UIKit.scroll(list)
	scroll.custom_minimum_size = Vector2(430, 0)
	split.add_child(scroll)
	var detail := UIKit.vbox(6)
	detail.name = "ClubDetail"
	var detail_scroll := UIKit.scroll(detail)
	split.add_child(detail_scroll)
	if _club_id == "" or db().get_team(_club_id) == null:
		detail.add_child(UIKit.muted(Loc.t("DBT_PICK_CLUB")))
		return
	_club_detail(detail)


func _club_detail(box: VBoxContainer) -> void:
	var pr := DatabaseTools.club_profile(db(), _club_id)
	var team: TeamData = db().get_team(_club_id)
	var head := UIKit.hbox(10)
	head.add_child(UIKit.crest(db(), team, 64, "card"))
	var names := UIKit.vbox(2)
	names.add_child(UIKit.label(str(pr["name"]), 22, UIKit.GOLD))
	names.add_child(UIKit.muted("%s · %s · %s · %s" % [pr["id"], pr["type"], pr["country"], pr["league_id"] if pr["league_id"] != "" else "-"]))
	head.add_child(names)
	box.add_child(head)
	var fin: Dictionary = pr["finance"]
	var g: Dictionary = pr["squad_groups"]
	var lines: Array = [
		Loc.f("DBT_CLUB_LINE1", [pr["city"] if pr["city"] != "" else "?", pr["founding_year"] if int(pr["founding_year"]) > 0 else "?", pr["reputation"], pr["rating"]]),
		Loc.f("DBT_CLUB_SQUAD", [pr["squad_size"], g["GK"], g["DEF"], g["MID"], g["ATT"], snappedf(float(pr["squad_average_overall"]), 0.1)]),
		Loc.f("DBT_CLUB_FINANCE", [fin["budget"], fin["transfer_budget"], fin["wage_budget"], fin["balance"], fin["status"]]),
		Loc.f("DBT_CLUB_STADIUM", [pr["stadium"]["name"] if pr["stadium"]["name"] != "" else "?", pr["stadium"]["capacity"], pr["stadium"]["level"]]),
		Loc.f("DBT_CLUB_CREST", [pr["crest_id"], pr["crest_type"]]),
	]
	for l in lines:
		var lab := UIKit.label(l, 14)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(lab)
	# change supported metadata
	box.add_child(UIKit.label(Loc.t("DBT_EDIT_CLUB"), 15, UIKit.GOLD))
	var fields: Array = DatabaseTools.EDITABLE_CLUB_FIELDS
	var edit := UIKit.hbox(6)
	var field_opt := UIKit.option(fields, 0)
	field_opt.name = "ClubField"
	edit.add_child(field_opt)
	var value := LineEdit.new()
	value.name = "ClubValue"
	value.custom_minimum_size = Vector2(200, 0)
	value.text = str(team.get(fields[0]))
	edit.add_child(value)
	field_opt.item_selected.connect(func(i: int) -> void: value.text = str(team.get(fields[i])))
	var apply := UIKit.button(Loc.t("DBT_APPLY"), func() -> void:
		var err := DatabaseTools.set_club_metadata(db(), _club_id, fields[field_opt.selected], value.text)
		say(err if err != "" else Loc.t("DBT_SAVED"), err != "")
		if err == "":
			rebuild(), 90)
	apply.name = "ClubApply"
	edit.add_child(apply)
	box.add_child(edit)
	# squad
	box.add_child(UIKit.label(Loc.t("DBT_SQUAD"), 15, UIKit.GOLD))
	for p in db().get_squad(_club_id):
		var row := UIKit.hbox(6)
		var b := UIKit.button("%s  %s %d" % [p.display_name, PlayerData.Position.keys()[p.position], p.get_overall()], func() -> void:
			_player_id = p.id
			_tab = 1
			rebuild(), 300)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		box.add_child(row)


# --- players ----------------------------------------------------------------------------------------------------

func _build_players(page: Control) -> void:
	var bar := UIKit.hbox(8)
	var search := _line(Loc.t("DBT_SEARCH_PLAYER"), _player_text, func(t: String) -> void:
		_player_text = t
		rebuild())
	search.name = "PlayerSearch"
	bar.add_child(search)
	var pos := UIKit.option(POSITION_FILTER.map(func(p: String) -> String: return p if p != "" else Loc.t("DBT_ALL_POSITIONS")),
			maxi(POSITION_FILTER.find(_player_pos), 0), func(i: int) -> void:
		_player_pos = POSITION_FILTER[i]
		rebuild())
	pos.name = "PlayerPosition"
	bar.add_child(pos)
	var go_btn := UIKit.button(Loc.t("DBT_SEARCH"), func() -> void:
		_player_text = search.text
		rebuild(), 100)
	go_btn.name = "PlayerSearchButton"
	bar.add_child(go_btn)
	page.add_child(bar)
	var found := DatabaseTools.search_players(db(), {"text": _player_text, "position": _player_pos})
	page.add_child(UIKit.muted(Loc.f("DBT_FOUND", [found.size(), mini(found.size(), MAX_ROWS)])))
	var split := UIKit.hbox(12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	var list := UIKit.vbox(2)
	list.name = "PlayerResults"
	for p in found.slice(0, MAX_ROWS):
		var club: TeamData = db().get_team(p.team_id)
		var b := UIKit.button("%s · %s %d · %s" % [p.display_name, PlayerData.Position.keys()[p.position], p.get_overall(), club.short_name if club != null else "-"],
				func() -> void:
			_player_id = p.id
			rebuild(), 400)
		b.name = "Player_%s" % p.id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	var scroll := UIKit.scroll(list)
	scroll.custom_minimum_size = Vector2(430, 0)
	split.add_child(scroll)
	var detail := UIKit.vbox(4)
	detail.name = "PlayerDetail"
	split.add_child(UIKit.scroll(detail))
	var pr := DatabaseTools.player_profile(db(), _player_id) if _player_id != "" else {}
	if pr.is_empty():
		detail.add_child(UIKit.muted(Loc.t("DBT_PICK_PLAYER")))
		return
	detail.add_child(UIKit.label(str(pr["name"]), 22, UIKit.GOLD))
	detail.add_child(UIKit.muted("%s · %s · %s · %s" % [pr["id"], pr["type"], pr["club"] if pr["club"] != "" else "-", pr["status"]]))
	var est := Loc.t("DBT_ESTIMATE") if pr["height_is_estimate"] else ""
	detail.add_child(UIKit.label(Loc.f("DBT_PLAYER_LINE", [pr["age"], pr["nationality"], pr["position"], pr["overall"], pr["potential"], pr["height_cm"], pr["weight_kg"], est]), 14))
	var attrs := UIKit.vbox(1)
	for k in pr["attributes"]:
		attrs.add_child(UIKit.stat_bar(str(k), int(pr["attributes"][k])))
	detail.add_child(attrs)
	var ap: Dictionary = pr["appearance"]
	detail.add_child(UIKit.label(Loc.f("DBT_APPEARANCE", [ap["version"], ap["seed"], ", ".join(ap["fields"].slice(0, 8))]), 13, UIKit.MUTED))
	detail.add_child(UIKit.label(Loc.t("DBT_HISTORY"), 15, UIKit.GOLD))
	var history: Array = pr["history"]
	if history.is_empty():
		detail.add_child(UIKit.muted(Loc.t("DBT_NO_HISTORY")))
	for h in history.slice(maxi(history.size() - 12, 0)):
		detail.add_child(UIKit.label(str(h), 12, UIKit.MUTED))
	var open := UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": _player_id}), 140)
	open.name = "OpenProfile"
	detail.add_child(open)


# --- crests -------------------------------------------------------------------------------------------------------

func _build_crests(page: Control) -> void:
	var bar := UIKit.hbox(8)
	var search := _line(Loc.t("DBT_SEARCH_CLUB"), _crest_club, func(t: String) -> void:
		_crest_club = t
		rebuild())
	search.name = "CrestSearch"
	bar.add_child(search)
	var go_btn := UIKit.button(Loc.t("DBT_SEARCH"), func() -> void:
		_crest_club = search.text
		rebuild(), 100)
	bar.add_child(go_btn)
	var report_btn := UIKit.button(Loc.t("DBT_CREST_REPORT"), func() -> void:
		var r := DatabaseTools.crest_report(db())
		_out = Loc.f("DBT_CREST_REPORT_TEXT", [r["stats"]["crests"], r["missing_assets"].size(), r["problems"].size(), r["orphans"]])
		_tab = 2
		rebuild(), 180)
	report_btn.name = "CrestReportButton"
	bar.add_child(report_btn)
	page.add_child(bar)
	if _out != "" and _tab == 2:
		var o := UIKit.label(_out, 14, UIKit.GOOD)
		o.name = "CrestOutput"
		page.add_child(o)
	var found := DatabaseTools.search_clubs(db(), {"text": _crest_club, "limit": 12})
	var grid := HFlowContainer.new()
	grid.name = "CrestGrid"
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for t in found:
		grid.add_child(_crest_tile(t))
	page.add_child(UIKit.scroll(grid))


func _crest_tile(t: TeamData) -> Control:
	var box := UIKit.vbox(3)
	box.name = "CrestTile_%s" % t.id
	var c := CrestService.crest_of(db(), t)
	box.add_child(UIKit.crest(db(), t, 96, "full"))
	box.add_child(UIKit.label(t.display_name, 13))
	box.add_child(UIKit.muted("%s · %s" % [c.crest_id, CrestData.AssetType.keys()[c.asset_type]] if c != null else "-"))
	# preview on the kit and a card
	var previews := UIKit.hbox(4)
	var shirt := TextureRect.new()
	shirt.texture = KitService.texture(db(), t, "home", 1)
	shirt.custom_minimum_size = Vector2(44, 56)
	shirt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shirt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	previews.add_child(shirt)
	var squad: Array = db().get_squad(t.id)
	if not squad.is_empty():
		var card := PlayerCard.new(60.0)
		card.minimal = false
		previews.add_child(card)
		card.setup(PlayerCardData.from_player(db(), squad[0].id), db())
	box.add_child(previews)
	var alt := UIKit.button(Loc.t("DBT_NEW_ALTERNATIVE"), _new_alternative.bind(t.id), 150)
	alt.name = "NewAlt_%s" % t.id
	box.add_child(alt)
	for own in db().crests.crests_of(t.id):
		if own.crest_id != t.crest_id:
			var use := UIKit.button(Loc.f("DBT_USE_CREST", own.crest_id), _assign_crest.bind(t.id, own.crest_id), 150)
			use.name = "UseCrest_%s" % own.crest_id
			box.add_child(use)
	var imp := UIKit.hbox(4)
	var path := _line(Loc.t("DBT_IMAGE_PATH"), _crest_path, func(p: String) -> void: _import_crest(t.id, p), 130)
	path.name = "ImportPath_%s" % t.id
	path.text_changed.connect(func(p: String) -> void: _crest_path = p)
	imp.add_child(path)
	var imp_btn := UIKit.button(Loc.t("DBT_IMPORT"), func() -> void: _import_crest(t.id, path.text), 70)
	imp_btn.name = "ImportCrest_%s" % t.id
	imp.add_child(imp_btn)
	box.add_child(imp)
	return UIKit.panel(box)


## Adds the next free design as an alternative crest of the club and assigns it.
func _new_alternative(club_id: String) -> void:
	var t: TeamData = db().get_team(club_id)
	var n: int = db().crests.crests_of(club_id).size()
	var used: Dictionary = db().crests._used.duplicate()
	var base := CrestGenerator.generate("%s#alt%d" % [club_id, n], t.primary_color, t.secondary_color, t.accent_color, t.is_real, used, db().crests.blocked_symbols(club_id))
	base.crest_id = "crest_%s_alt%d" % [club_id, n]
	base.club_id = club_id
	var err: String = db().crests.add_alternative(base)
	if err == "":
		err = db().crests.assign(t, base.crest_id)
	say(err if err != "" else Loc.f("DBT_ALT_CREATED", base.crest_id), err != "")
	_tab = 2
	rebuild()


func _assign_crest(club_id: String, crest_id: String) -> void:
	var err: String = db().crests.assign(db().get_team(club_id), crest_id)
	say(err if err != "" else Loc.t("DBT_SAVED"), err != "")
	_tab = 2
	rebuild()


func _import_crest(club_id: String, path: String) -> void:
	var res: Dictionary = db().crests.import_custom(db().get_team(club_id), path)
	say(Loc.t("DBT_SAVED") if res["ok"] else str(res["error"]), not res["ok"])
	_tab = 2
	rebuild()


# --- database -------------------------------------------------------------------------------------------------------------

func _build_database(page: Control) -> void:
	var row := UIKit.hbox(8)
	var validate := UIKit.button(Loc.t("DBT_VALIDATE"), func() -> void:
		var r := DatabaseTools.validate_all(db())
		var lines: Array = [Loc.f("DBT_VALIDATE_SUMMARY", [r["critical"].size(), r["warnings"].size(), r["checked"]["clubs"], r["checked"]["players"]])]
		for c in (r["critical"] as Array).slice(0, 15):
			lines.append("CRITICAL: %s" % c)
		for w in r["warnings"]:
			lines.append("WARNING: %s" % w)
		_out = "\n".join(lines)
		_tab = 3
		rebuild(), 160)
	validate.name = "ValidateButton"
	row.add_child(validate)
	var stats := UIKit.button(Loc.t("DBT_STATS"), func() -> void:
		var s := DatabaseTools.stats(db())
		_out = Loc.f("DBT_STATS_TEXT", [s["clubs"], s["national_teams"], s["players"], s["countries"], s["leagues"], s["divisions"], s["crests"]]) + "\n" \
				+ "clubs_by_type: %s\nclubs_by_country: %s\nplayers_by_type: %s" % [s["clubs_by_type"], s["clubs_by_country"], s["players_by_type"]]
		_tab = 3
		rebuild(), 160)
	stats.name = "StatsButton"
	row.add_child(stats)
	page.add_child(row)
	var output := UIKit.label(_out if _out != "" else Loc.t("DBT_NO_OUTPUT"), 13)
	output.name = "DbOutput"
	output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(UIKit.panel(output))
	# export
	var ex := UIKit.hbox(8)
	ex.add_child(UIKit.label(Loc.t("DBT_EXPORT"), 14, UIKit.MUTED))
	var ex_path := _line("", _export_path, func(p: String) -> void: _export_path = p, 360)
	ex_path.name = "ExportPath"
	ex_path.text_changed.connect(func(p: String) -> void: _export_path = p)
	ex.add_child(ex_path)
	var ex_btn := UIKit.button(Loc.t("DBT_EXPORT_BUTTON"), func() -> void:
		var err := DatabaseTools.export_snapshot(db(), ex_path.text)
		_out = Loc.f("DBT_EXPORTED", [db().teams.size(), db().players.size(), ex_path.text]) if err == "" else err
		_tab = 3
		rebuild(), 130)
	ex_btn.name = "ExportButton"
	ex.add_child(ex_btn)
	page.add_child(ex)
	# import
	var im := UIKit.hbox(8)
	im.add_child(UIKit.label(Loc.t("DBT_IMPORT_LABEL"), 14, UIKit.MUTED))
	var im_path := _line("", _import_path, func(p: String) -> void: _import_path = p, 360)
	im_path.name = "ImportPath"
	im_path.text_changed.connect(func(p: String) -> void: _import_path = p)
	im.add_child(im_path)
	var dry := CheckBox.new()
	dry.text = Loc.t("DBT_DRY_RUN")
	dry.button_pressed = true
	dry.name = "DryRun"
	im.add_child(dry)
	var im_btn := UIKit.button(Loc.t("DBT_IMPORT"), func() -> void:
		var r := DatabaseTools.import_package(db(), im_path.text, dry.button_pressed)
		if r["ok"]:
			_out = Loc.f("DBT_IMPORT_OK" if not dry.button_pressed else "DBT_IMPORT_DRY", [r["teams"], r["players"]])
		else:
			_out = "\n".join((r["errors"] as Array).slice(0, 12))
		_tab = 3
		rebuild(), 110)
	im_btn.name = "ImportButton"
	im.add_child(im_btn)
	page.add_child(im)
	# generate
	var ge := UIKit.hbox(8)
	ge.add_child(UIKit.label(Loc.t("DBT_GENERATE"), 14, UIKit.MUTED))
	var seed_edit := SpinBox.new()
	seed_edit.min_value = 1
	seed_edit.max_value = 999999999
	seed_edit.value = _gen_seed
	seed_edit.name = "GenSeed"
	ge.add_child(seed_edit)
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 20
	count.value = _gen_count
	count.name = "GenCount"
	ge.add_child(count)
	var gen_path := _line("", _gen_path, func(p: String) -> void: _gen_path = p, 300)
	gen_path.name = "GenPath"
	gen_path.text_changed.connect(func(p: String) -> void: _gen_path = p)
	ge.add_child(gen_path)
	var gen_btn := UIKit.button(Loc.t("DBT_GENERATE_BUTTON"), func() -> void:
		_gen_seed = int(seed_edit.value)
		_gen_count = int(count.value)
		var g := DatabaseTools.generate_package(db(), _gen_seed, _gen_count, gen_path.text)
		_out = Loc.f("DBT_GENERATED", [g["teams"], g["players"], gen_path.text]) if g["ok"] else str(g["error"])
		_tab = 3
		rebuild(), 130)
	gen_btn.name = "GenerateButton"
	ge.add_child(gen_btn)
	page.add_child(ge)
