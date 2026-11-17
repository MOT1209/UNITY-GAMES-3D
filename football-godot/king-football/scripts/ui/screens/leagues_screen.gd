extends HubScreen

## Leagues: every country of the loaded data pack, its divisions, the live table with
## promotion / play-off / relegation zones, this week's results of the division, the domestic
## cup and last season's movements. Without a career the initial memberships are shown.

const ZONE_UP := Color(0.35, 0.8, 0.5)
const ZONE_PLAYOFF := Color(0.93, 0.75, 0.3)
const ZONE_DOWN := Color(0.9, 0.35, 0.35)

var _country := 0
var _division := 0
var _focused := false     # first build jumps to the managed club's country and division


func _init() -> void:
	super()
	own_scroll = true       # lays out its own ScrollContainer


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_LEAGUES")))
	var keys: Array = db().leagues.keys()
	if keys.is_empty() and app().career != null:
		keys = app().career.pyramids.keys()          # fictional world: the career's built-in league
	keys.sort()
	if keys.is_empty():
		add_child(UIKit.empty_state(Loc.t("LEAGUES_NO_PACK")))
		add_child(UIKit.button(Loc.t("SCREEN_SETTINGS"), go.bind("settings"), 160))
		return
	var career: CareerState = app().career
	if not _focused and career != null:
		_focused = true
		var ud := career.user_division()
		if not ud.is_empty():
			_country = maxi(keys.find(ud["pyramid"]), 0)
			var pyr0: LeaguePyramid = career.pyramids[ud["pyramid"]]
			_division = maxi(pyr0.divisions.find(ud["division"]), 0)
	_country = clampi(_country, 0, keys.size() - 1)
	var key: String = keys[_country]
	var pyr: LeaguePyramid = career.pyramids.get(key) if career != null else null
	var divisions: Array = pyr.divisions if pyr != null else (db().leagues[key] as LeagueDef).divisions
	_division = clampi(_division, 0, divisions.size() - 1)
	var d: Dictionary = divisions[_division]
	var bar := UIKit.hbox(8)
	var countries: Array = keys.map(func(k: String) -> String:
		if db().leagues.has(k):
			return Loc.country((db().leagues[k] as LeagueDef).country)
		return LeaguePyramid.label((career.pyramids[k] as LeaguePyramid).display_name))
	var co := UIKit.option(countries, _country, func(i: int) -> void:
		_country = i
		_division = 0
		rebuild())
	co.name = "CountryOption"
	bar.add_child(co)
	var dv := UIKit.option(divisions.map(func(x: Dictionary) -> String: return "%d · %s" % [x["tier"], LeaguePyramid.label(x["name"])]), _division, func(i: int) -> void:
		_division = i
		rebuild())
	dv.name = "DivisionOption"
	bar.add_child(dv)
	if pyr != null and pyr.comp.has("cup"):
		var cup := UIKit.button(LeaguePyramid.label(str(pyr.cup_def.get("name", "Cup"))), go.bind("bracket", {"competition_id": pyr.comp["cup"]}), 150)
		cup.name = "CupButton"
		bar.add_child(cup)
	add_child(bar)
	add_child(UIKit.muted(Loc.f("LEAGUES_RULES", [int(d["promote"]), _playoff_text(d), int(d["relegate"])])))
	if pyr == null:
		add_child(UIKit.muted(Loc.t("LEAGUES_START_CAREER_HINT")))
		add_child(_members(d))
		return
	var comp: Competition = career.competitions.get(pyr.comp.get(d["id"], ""))
	if comp != null:
		add_child(UIKit.label(Loc.f("LEAGUES_SEASON_WEEK", [pyr.season, career.week]), 15, UIKit.MUTED))
		var row := UIKit.hbox(16)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var table_scroll := UIKit.scroll(_table(d, comp))
		table_scroll.custom_minimum_size = Vector2(420, 300)
		row.add_child(table_scroll)
		var week_panel := _week_results(pyr, d, comp, career.week)
		week_panel.custom_minimum_size = Vector2(380, 0)
		week_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(week_panel)
		add_child(row)
	if not pyr.history.is_empty():
		add_child(_last_season(pyr.history[pyr.history.size() - 1]))


func _playoff_text(d: Dictionary) -> String:
	var po: Dictionary = d["playoff"]
	if po.is_empty():
		return Loc.t("LEAGUES_NO_PLAYOFF")
	if int(po.get("vs_upper", 0)) > 0:
		return Loc.f("LEAGUES_RELEGATION_PLAYOFF", [int(po["from"]), int(po["to"]), int(po["vs_upper"])])
	return Loc.f("LEAGUES_PLAYOFF", [int(po["from"]), int(po["to"])])


func _members(d: Dictionary) -> Control:
	var rows: Array = []
	var ids: Array = (d["team_ids"] as Array).duplicate()
	ids.sort_custom(func(a: String, b: String) -> bool: return db().get_team_rating(a) > db().get_team_rating(b))
	for t in ids:
		var team: TeamData = db().get_team(t)
		rows.append([team.display_name, db().get_team_rating(t)])
	return UIKit.scroll(UIKit.table([Loc.t("TABLE_TEAM"), Loc.t("LEAGUES_RATING")], rows))


func _zone(d: Dictionary, pos: int, size: int) -> Color:
	var po: Dictionary = d["playoff"]
	if pos <= int(d["promote"]):
		return ZONE_UP
	if not po.is_empty() and pos >= int(po["from"]) and pos <= int(po["to"]):
		return ZONE_PLAYOFF
	if pos > size - int(d["relegate"]):
		return ZONE_DOWN
	return UIKit.TEXT


func _table(d: Dictionary, comp: Competition) -> Control:
	var grid := GridContainer.new()
	grid.name = "LeagueTable"
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 16)
	for h in ["#", Loc.t("TABLE_TEAM"), Loc.t("TABLE_P"), Loc.t("TABLE_W"), Loc.t("TABLE_D"), Loc.t("TABLE_L"), Loc.t("TABLE_GD"), Loc.t("TABLE_PTS"), ""]:
		grid.add_child(UIKit.label(h, 14, UIKit.GOLD))
	var rows := comp.standings()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var col := _zone(d, i + 1, rows.size())
		var mine: bool = r["team_id"] == app().user_team_id
		grid.add_child(UIKit.label(str(i + 1), 15, col))
		grid.add_child(UIKit.team_cell(db(), r["team_id"], 20, UIKit.GOLD if mine else UIKit.TEXT))
		for k in ["played", "won", "drawn", "lost", "gd", "points"]:
			# Numbers are always laid out left-to-right: "-9" must not become "9-" in Arabic
			# (bidi isolate characters are not enough for text without strong characters).
			var num := UIKit.label(str(r[k]), 15)
			num.text_direction = Control.TEXT_DIRECTION_LTR
			num.language = "en"
			grid.add_child(num)
		grid.add_child(UIKit.label("●" if mine else "", 15, UIKit.GOLD))
	return grid


## Results / fixtures of the rounds due this week in this division.
func _week_results(pyr: LeaguePyramid, d: Dictionary, comp: Competition, week: int) -> Control:
	var box := UIKit.vbox(2)
	box.add_child(UIKit.label(Loc.f("LEAGUES_THIS_WEEK", maxi(week, 1)), 16, UIKit.GOLD))
	var shown := 0
	var items: Array = []
	for role in [d["id"], "po:" + d["id"], "rb:" + d["id"]]:
		var c: Competition = app().career.competitions.get(pyr.comp.get(role, ""))
		if c == null:
			continue
		for f in c.fixtures:
			if pyr.week_of(role, c, f) == maxi(week, 1):
				items.append([c, f])
	for item in items:
		comp = item[0]
		var f: Dictionary = item[1]
		var score := ""
		if f["played"]:
			var res := MatchResult.from_dict(comp.results[f["match_id"]])
			score = "%d - %d" % [res.home_goals, res.away_goals]
			if res.home_pens >= 0:
				score += " (%d-%d)" % [res.home_pens, res.away_pens]
		if comp.id != pyr.comp.get(d["id"], ""):
			box.add_child(UIKit.label(app().competition_title(comp.id), 12, UIKit.MUTED))       # play-off / relegation play-off
		var line := UIKit.fixture_row(db(), f["home"], f["away"], score, 14, not f["played"], app().user_team_id)
		line.name = "WeekResult_%s" % f["match_id"]
		box.add_child(line)
		shown += 1
	if shown == 0:
		box.add_child(UIKit.muted(Loc.t("LEAGUES_NO_MATCHES_THIS_WEEK")))
	return UIKit.panel(box)


func _last_season(s: Dictionary) -> Control:
	var box := UIKit.vbox(2)
	box.name = "LastSeason"
	box.add_child(UIKit.label(Loc.f("LEAGUES_LAST_SEASON", int(s["season"])), 16, UIKit.GOLD))
	for div_id in (s["champions"] as Dictionary):
		var t: TeamData = db().get_team(s["champions"][div_id])
		if t != null:
			box.add_child(UIKit.label(Loc.f("LEAGUES_CHAMPION_OF", [_division_name(div_id), t.display_name]), 14))
	var names := func(ids: Array) -> String:
		return ", ".join(ids.map(func(x: String) -> String: return db().get_team(x).display_name if db().get_team(x) != null else x))
	box.add_child(UIKit.label(Loc.f("LEAGUES_PROMOTED", names.call(s["promoted"])), 14, ZONE_UP))
	box.add_child(UIKit.label(Loc.f("LEAGUES_RELEGATED", names.call(s["relegated"])), 14, ZONE_DOWN))
	var cup: TeamData = db().get_team(str(s.get("cup_winner", "")))
	if cup != null:
		box.add_child(UIKit.label(Loc.f("LEAGUES_CUP_WINNER", cup.display_name), 14, UIKit.GOLD))
	return UIKit.panel(box)


func _division_name(div_id: String) -> String:
	for k in db().leagues:
		var d: Dictionary = (db().leagues[k] as LeagueDef).division(div_id)
		if not d.is_empty():
			return LeaguePyramid.label(d["name"])
	if app().career != null:
		for k in app().career.pyramids:
			for d in (app().career.pyramids[k] as LeaguePyramid).divisions:
				if d["id"] == div_id:
					return LeaguePyramid.label(d["name"])
	return div_id
