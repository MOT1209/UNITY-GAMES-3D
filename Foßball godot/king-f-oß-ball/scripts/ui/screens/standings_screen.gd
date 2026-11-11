extends HubScreen

## League Standings + fixtures: table(s), play or simulate matches.


func build() -> void:
	if not header("League Standings", true, true):
		return
	var cid: String = str(params.get("competition_id", ""))
	var career: CareerState = app().career
	if not career.competitions.has(cid):
		add_child(UIKit.empty_state("Open a competition from the Competitions screen."))
		add_child(UIKit.button("Competitions", go.bind("competitions"), 160))
		return
	var comp: Competition = career.competitions[cid]
	add_child(UIKit.label("%s  (%s)" % [comp.comp_name, comp.stage], 18, UIKit.GOLD))
	if comp.is_finished():
		add_child(UIKit.label("Champion: %s" % db().get_team(comp.champion_id).display_name, 20, UIKit.GOOD))
	for group in comp.tables.keys():
		if comp.tables.size() > 1:
			add_child(UIKit.label("Group %s" % group, 16, UIKit.GOLD))
		var rows: Array = []
		var pos := 1
		for r in comp.standings(group):
			rows.append([pos, db().get_team(r["team_id"]).display_name, r["played"], r["won"], r["drawn"],
					r["lost"], r["gf"], r["ga"], r["gd"], r["points"]])
			pos += 1
		add_child(UIKit.table(["#", "Team", "P", "W", "D", "L", "GF", "GA", "GD", "Pts"], rows))
	var pending := comp.pending_fixtures()
	if pending.is_empty():
		return
	add_child(UIKit.label("Next fixtures", 16, UIKit.GOLD))
	var bar := UIKit.hbox(8)
	var sim_next := UIKit.button("Simulate next round", _sim_round.bind(cid), 180)
	sim_next.name = "SimRound"
	bar.add_child(sim_next)
	var sim_all := UIKit.button("Simulate all", _sim_all.bind(cid), 130)
	sim_all.name = "SimAll"
	bar.add_child(sim_all)
	add_child(bar)
	for f in pending.slice(0, 8):
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label("%s  vs  %s" % [db().get_team(f["home"]).display_name, db().get_team(f["away"]).display_name], 15))
		var sim := UIKit.button("Simulate", _sim_one.bind(cid, f["match_id"]), 90)
		row.add_child(sim)
		var mine: bool = app().user_team_id in [f["home"], f["away"]]
		if mine:
			var play := UIKit.button("Play in 3D", _play.bind(cid, f), 110)
			play.name = "Play_%s" % f["match_id"]
			row.add_child(play)
		add_child(row)


func _sim_one(cid: String, mid: String) -> void:
	var err: String = app().simulate_fixture(cid, mid)
	say(err if err != "" else "Match simulated", err != "")
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
	say("%d match(es) simulated" % n)
	rebuild()


func _sim_all(cid: String) -> void:
	var comp: Competition = app().career.competitions[cid]
	var guard := 0
	while not comp.is_finished() and guard < 400:
		guard += 1
		var pending := comp.pending_fixtures()
		if pending.is_empty() or app().simulate_fixture(cid, pending[0]["match_id"]) != "":
			break
	say("Competition simulated")
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
