extends HubScreen

## League Standings + fixtures: table(s), play or simulate matches.


func build() -> void:
	if not header(Loc.t("TABLE_LEAGUE_STANDINGS"), true, true):
		return
	var cid: String = str(params.get("competition_id", ""))
	var career: CareerState = app().career
	if not career.competitions.has(cid):
		add_child(UIKit.empty_state(Loc.t("TABLE_OPEN_A_COMPETITION_FROM_THE_COMPET")))
		add_child(UIKit.button(Loc.t("COMMON_COMPETITIONS"), go.bind("competitions"), 160))
		return
	var comp: Competition = career.competitions[cid]
	add_child(UIKit.label("%s  (%s)" % [app().competition_title(comp.id), comp.stage], 18, UIKit.GOLD))
	if comp.is_finished():
		add_child(UIKit.label(Loc.f("COMMON_CHAMPION", db().get_team(comp.champion_id).display_name), 20, UIKit.GOOD))
	for group in comp.tables.keys():
		if comp.tables.size() > 1:
			add_child(UIKit.label(Loc.f("TABLE_GROUP", group), 16, UIKit.GOLD))
		var rows: Array = []
		var pos := 1
		for r in comp.standings(group):
			rows.append([pos, UIKit.team_cell(db(), r["team_id"]), r["played"], r["won"], r["drawn"],
					r["lost"], r["gf"], r["ga"], r["gd"], r["points"]])
			pos += 1
		add_child(UIKit.table(["#", Loc.t("TABLE_TEAM"), "P", "W", "D", "L", Loc.t("TABLE_GF"), Loc.t("TABLE_GA"), Loc.t("TABLE_GD"), Loc.t("TABLE_PTS")], rows))
	var pending := comp.pending_fixtures()
	if pending.is_empty():
		return
	var pyr: LeaguePyramid = app().pyramid_of(cid)
	if pyr != null:
		_pyramid_fixtures(pyr, cid, comp, pending)
		return
	add_child(UIKit.label(Loc.t("TABLE_NEXT_FIXTURES"), 16, UIKit.GOLD))
	var bar := UIKit.hbox(8)
	var sim_next := UIKit.button(Loc.t("TABLE_SIMULATE_NEXT_ROUND"), _sim_round.bind(cid), 180)
	sim_next.name = "SimRound"
	bar.add_child(sim_next)
	var sim_all := UIKit.button(Loc.t("TABLE_SIMULATE_ALL"), _sim_all.bind(cid), 130)
	sim_all.name = "SimAll"
	bar.add_child(sim_all)
	add_child(bar)
	for f in pending.slice(0, 8):
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(Loc.f("TABLE_VS", [db().get_team(f["home"]).display_name, db().get_team(f["away"]).display_name]), 15))
		var sim := UIKit.button(Loc.t("TABLE_SIMULATE"), _sim_one.bind(cid, f["match_id"]), 90)
		row.add_child(sim)
		var mine: bool = app().user_team_id in [f["home"], f["away"]]
		if mine:
			var play := UIKit.button(Loc.t("TABLE_PLAY_IN_3D"), _play.bind(cid, f), 110)
			play.name = "Play_%s" % f["match_id"]
			row.add_child(play)
		add_child(row)


## League-pyramid competitions run on the career calendar: no bulk simulation here (it would
## put rounds and weeks out of step). Only the user's fixtures that are due can be played.
func _pyramid_fixtures(pyr: LeaguePyramid, cid: String, comp: Competition, pending: Array) -> void:
	var hint := UIKit.muted(Loc.t("TABLE_CALENDAR_HINT"))
	hint.name = "CalendarHint"
	add_child(hint)
	add_child(UIKit.button(Loc.t("SCREEN_CAREER"), go.bind("career"), 160))
	var role := pyr.role_of(cid)
	for f in pending:
		var mine: bool = app().user_team_id in [f["home"], f["away"]]
		if not mine or pyr.week_of(role, comp, f) > app().career.week:
			continue
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(Loc.f("TABLE_VS", [db().get_team(f["home"]).display_name, db().get_team(f["away"]).display_name]), 15))
		row.add_child(UIKit.button(Loc.t("TABLE_SIMULATE"), _sim_one.bind(cid, f["match_id"]), 90))
		var play := UIKit.button(Loc.t("TABLE_PLAY_IN_3D"), _play.bind(cid, f), 110)
		play.name = "Play_%s" % f["match_id"]
		row.add_child(play)
		add_child(row)


func _sim_one(cid: String, mid: String) -> void:
	var err: String = app().simulate_fixture(cid, mid)
	say(err if err != "" else Loc.t("TABLE_MATCH_SIMULATED"), err != "")
	rebuild()


func _sim_round(cid: String) -> void:
	var comp: Competition = app().career.competitions[cid]
	var pending := comp.pending_fixtures()
	if pending.is_empty():
		return
	var round_no: int = pending[0]["round"]
	var stage: String = pending[0]["stage"]
	var n := 0
	for f in pending.duplicate():
		if f["round"] == round_no and f["stage"] == stage and app().simulate_fixture(cid, f["match_id"]) == "":
			n += 1
	app().career.advance_week()
	say(Loc.f("TABLE_MATCH_ES_SIMULATED", n))
	rebuild()


func _sim_all(cid: String) -> void:
	var comp: Competition = app().career.competitions[cid]
	var guard := 0
	while not comp.is_finished() and guard < 400:
		guard += 1
		var pending := comp.pending_fixtures()
		if pending.is_empty() or app().simulate_fixture(cid, pending[0]["match_id"]) != "":
			break
	say(Loc.t("TABLE_COMPETITION_SIMULATED"))
	rebuild()


func _play(cid: String, f: Dictionary) -> void:
	var setup := MatchSetup.new()
	setup.home_id = f["home"]
	setup.away_id = f["away"]
	setup.competition_id = cid
	setup.match_id = f["match_id"]
	setup.knockout = f["stage"] == "ko" or f["stage"] == "third"
	setup.human_side = "home" if f["home"] == app().user_team_id else "away"
	var err: String = app().play_match(setup, {"competition_id": cid, "match_id": f["match_id"]})
	if err != "":
		say(err, true)
