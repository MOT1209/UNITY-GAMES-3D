extends HubScreen

## Competition Selection: list the season's competitions, create a league,
## knockout cup or group-stage tournament from the clubs, open standings/bracket.

var _type := 0
var _name := ""
var _count := 8
var _creator_open := false
var _others_open := false


func build() -> void:
	if not header(Loc.t("COMMON_COMPETITIONS"), true, true):
		return
	var career: CareerState = app().career
	if _name == "":
		_name = Loc.t("COMP_DEFAULT_NAME")
	add_child(UIKit.label(Loc.t("COMP_YOUR_COMPETITIONS"), 16, UIKit.GOLD))
	if career.competitions.is_empty():
		add_child(UIKit.empty_state(Loc.t("COMP_CREATE_A_LEAGUE_OR_TOURNAMENT_BELO")))
	# The club's own competitions first; every other league / cup of the world folds away under one button.
	var mine: Array = []
	var others: Array = []
	for id in career.competitions:
		var c: Competition = career.competitions[id]
		if str(id).begins_with("friendly_") or app().user_team_id in c.team_ids:
			mine.append(id)
		else:
			others.append(id)
	for id in mine:
		_competition_row(career, id)
	if not others.is_empty():
		var label := Loc.f("COMP_OTHER_COMPETITIONS", others.size())
		var toggle := UIKit.button(("▾ " if _others_open else "▸ ") + label, func() -> void:
			_others_open = not _others_open
			rebuild(), 260)
		toggle.name = "ToggleOthers"
		add_child(toggle)
		if _others_open:
			for id in others:
				_competition_row(career, id)
	_creator(career)


func _competition_row(career: CareerState, id: Variant) -> void:
	var c: Competition = career.competitions[id]
	if str(id).begins_with("friendly_"):          # a friendly is one match: its score, no table and no "champion"
		add_child(UIKit.panel(_friendly_line(c)))
		return
	var row := UIKit.hbox(10)
	row.add_child(UIKit.label("%s — %s · %s%s" % [app().competition_title(c.id), Loc.enum_name("COMP_TYPE", Competition.Type.keys()[c.type]), Loc.enum_name("STAGE", c.stage),
			Loc.f("COMP_CHAMPION_SUFFIX", db().get_team(c.champion_id).display_name) if c.champion_id != "" else ""], 16))
	if c.type != Competition.Type.KNOCKOUT:
		row.add_child(UIKit.button(Loc.t("COMP_STANDINGS"), go.bind("standings", {"competition_id": id}), 100))
	if c.type != Competition.Type.LEAGUE:
		row.add_child(UIKit.button(Loc.t("COMP_BRACKET"), go.bind("bracket", {"competition_id": id}), 90))
	add_child(UIKit.panel(row))


func _creator(career: CareerState) -> void:
	if not career.pyramids.is_empty() and not _creator_open:
		# a career already has its leagues and cups: the free-play creator stays folded away until asked for
		var show := UIKit.button(Loc.t("COMP_CREATE_COMPETITION"), func() -> void:
			_creator_open = true
			rebuild(), 220)
		show.name = "ShowCreator"
		add_child(show)
		return
	add_child(UIKit.label(Loc.t("COMP_CREATE_COMPETITION"), 16, UIKit.GOLD))
	var form := UIKit.hbox(8)
	var to := UIKit.option([Loc.t("COMP_LEAGUE_HOME_AWAY"), Loc.t("COMP_KNOCKOUT_CUP"), Loc.t("COMP_GROUPS_KNOCKOUT")], _type, func(i: int) -> void: _type = i)
	to.name = "TypeOption"
	form.add_child(to)
	var ne := LineEdit.new()
	ne.text = _name
	ne.custom_minimum_size = Vector2(200, 0)
	ne.name = "NameEdit"
	ne.text_changed.connect(func(t: String) -> void: _name = t)
	form.add_child(ne)
	form.add_child(UIKit.label(Loc.t("COMP_TEAMS"), 14, UIKit.MUTED))
	var sp := SpinBox.new()
	sp.min_value = 2
	sp.max_value = 16
	sp.value = _count
	sp.name = "TeamCount"
	sp.value_changed.connect(func(v: float) -> void: _count = int(v))
	form.add_child(sp)
	var create := UIKit.button(Loc.t("COMP_CREATE"), _create, 100)
	create.name = "CreateButton"
	form.add_child(create)
	add_child(form)
	add_child(UIKit.muted(Loc.t("COMP_YOUR_CLUB_IS_ALWAYS_INCLUDED_OTHER")))


func _friendly_line(c: Competition) -> Control:
	var row := UIKit.hbox(10)
	row.name = "Friendly_%s" % c.id
	row.add_child(UIKit.label(app().competition_title(c.id), 15, UIKit.MUTED))
	if c.fixtures.is_empty():
		return row
	var f: Dictionary = c.fixtures[0]
	row.add_child(UIKit.crest(db(), str(f["home"]), 22))
	var score := Loc.t("COMP_FRIENDLY_PENDING")
	if bool(f["played"]) and c.results.has(f["match_id"]):
		var r := MatchResult.from_dict(c.results[f["match_id"]])
		score = Loc.score(r.home_goals, r.away_goals)
	row.add_child(UIKit.label("%s  %s  %s" % [db().get_team(str(f["home"])).display_name, score, db().get_team(str(f["away"])).display_name], 15))
	row.add_child(UIKit.crest(db(), str(f["away"]), 22))
	return row


func _create() -> void:
	var career: CareerState = app().career
	var clubs: Array = db().list_teams(TeamData.Category.CLUB)
	clubs.sort_custom(func(a: TeamData, b: TeamData) -> bool: return db().get_team_rating(a.id) > db().get_team_rating(b.id))
	var ids: Array = [app().user_team_id]
	for t: TeamData in clubs:
		if ids.size() >= _count:
			break
		if t.id != app().user_team_id:
			ids.append(t.id)
	var type_enum: Competition.Type = [Competition.Type.LEAGUE, Competition.Type.KNOCKOUT, Competition.Type.GROUP_KNOCKOUT][_type]
	var groups := 2 if _type == 2 else 0
	if _type == 2 and ids.size() >= 16:
		groups = 4
	var problem := Competition.validate_setup(type_enum, ids, groups)
	if problem != "":
		say(problem, true)
		return
	var cid := "%s_s%d_%d" % [ClubCreator.slugify(_name), career.season, career.competitions.size() + 1]
	var comp: Competition
	match _type:
		0:
			comp = Competition.create_league(cid, _name, ids, true)
		1:
			comp = Competition.create_knockout(cid, _name, ids, true)
		_:
			comp = Competition.create_group_knockout(cid, _name, ids, groups, true)
	comp.season = career.season
	var err := career.register_competition(comp)
	say(err if err != "" else Loc.f("COMP_CREATED", _name), err != "")
	rebuild()
