extends HubScreen

## Competition Selection: list the season's competitions, create a league,
## knockout cup or group-stage tournament from the clubs, open standings/bracket.

var _type := 0
var _name := "Season Competition"
var _count := 8


func build() -> void:
	if not header(Loc.t("COMMON_COMPETITIONS"), true, true):
		return
	var career: CareerState = app().career
	add_child(UIKit.label(Loc.t("COMP_YOUR_COMPETITIONS"), 16, UIKit.GOLD))
	if career.competitions.is_empty():
		add_child(UIKit.empty_state(Loc.t("COMP_CREATE_A_LEAGUE_OR_TOURNAMENT_BELO")))
	for id in career.competitions:
		var c: Competition = career.competitions[id]
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label("%s — %s · %s%s" % [app().competition_title(c.id), Loc.enum_name("COMP_TYPE", Competition.Type.keys()[c.type]), c.stage,
				Loc.f("COMP_CHAMPION_SUFFIX", db().get_team(c.champion_id).display_name) if c.champion_id != "" else ""], 16))
		if c.type != Competition.Type.KNOCKOUT:
			row.add_child(UIKit.button(Loc.t("COMP_STANDINGS"), go.bind("standings", {"competition_id": id}), 100))
		if c.type != Competition.Type.LEAGUE:
			row.add_child(UIKit.button(Loc.t("COMP_BRACKET"), go.bind("bracket", {"competition_id": id}), 90))
		add_child(UIKit.panel(row))
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
