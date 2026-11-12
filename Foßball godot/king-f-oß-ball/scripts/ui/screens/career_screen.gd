extends HubScreen

## Career Dashboard: club status, season clock, key figures, save/load and
## shortcuts. Starts a career when none exists.


func build() -> void:
	add_child(UIKit.title(Loc.t("CAREER_CAREER_DASHBOARD")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		var row := UIKit.hbox(8)
		row.add_child(UIKit.button(Loc.t("COMMON_TEAM_SELECTION"), go.bind("team_select"), 160))
		var load_btn := UIKit.button(Loc.t("CAREER_LOAD_SAVED_CAREER"), _load, 170)
		load_btn.name = "LoadButton"
		row.add_child(load_btn)
		add_child(row)
		return
	var team: TeamData = db().get_team(career.club_id)
	var stats := UIKit.vbox(4)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.crest(db(), team, 48, "card"))
	head.add_child(UIKit.label(team.display_name, 24, UIKit.GOLD))
	stats.add_child(head)
	stats.add_child(UIKit.label(Loc.f("CAREER_SEASON_WEEK_OF", [career.season, career.week, CareerState.WEEKS_PER_SEASON]), 16))
	stats.add_child(UIKit.label(Loc.f("CAREER_BALANCE_TRANSFER_BUDGET", [career.ledger().balance, career.ledger().transfer_budget]), 16))
	stats.add_child(UIKit.label(Loc.f("CAREER_SQUAD_RATING_WEEKLY_WAGES", [team.squad_ids.size(),
			db().get_team_rating(team.id), career.market.weekly_wages(team.id)]), 16))
	var expiring := career.market.expiring_contracts(team.id)
	if not expiring.is_empty():
		stats.add_child(UIKit.label(Loc.tn("CAREER_CONTRACTS_EXPIRE", expiring.size()), 14, UIKit.BAD))
	var ud := career.user_division()
	if not ud.is_empty():
		var pyr: LeaguePyramid = career.pyramids[ud["pyramid"]]
		var comp: Competition = career.competitions.get(pyr.comp.get(ud["division"]["id"], ""))
		var pos := 0
		if comp != null:
			var st := comp.standings()
			for i in st.size():
				if st[i]["team_id"] == career.club_id:
					pos = i + 1
		var line := UIKit.label(Loc.f("CAREER_DIVISION_POSITION", [ud["division"]["name"], pos]), 16, UIKit.GOLD)
		line.name = "DivisionLine"
		stats.add_child(line)
	add_child(UIKit.panel(stats))
	_my_fixtures(career)
	var actions := UIKit.hbox(8)
	var season_over := career.week >= CareerState.WEEKS_PER_SEASON
	var wk := UIKit.button(Loc.t("COMMON_ADVANCE_WEEK"), _advance, 150)
	wk.name = "AdvanceWeek"
	wk.disabled = season_over          # the calendar stops at week 46 until the season is ended
	actions.add_child(wk)
	var end := UIKit.button(Loc.t("CAREER_END_SEASON"), _end_season, 140)
	end.name = "EndSeason"
	if season_over:
		end.add_theme_color_override("font_color", UIKit.GOLD)
		end.grab_focus.call_deferred()
	actions.add_child(end)
	var sv := UIKit.button(Loc.t("CAREER_SAVE"), _save, 90)
	sv.name = "SaveButton"
	actions.add_child(sv)
	actions.add_child(UIKit.button(Loc.t("CAREER_LOAD"), _load, 90))
	add_child(actions)
	if season_over:
		var over := UIKit.label(Loc.t("CAREER_SEASON_FINISHED_HINT"), 15, UIKit.GOLD)
		over.name = "SeasonOverHint"
		add_child(over)
	var links := UIKit.hbox(8)
	var shortcuts: Array = [["NAV_SQUAD", "squad"], ["NAV_ACADEMY", "academy"], ["NAV_TRANSFERS", "transfers"], ["NAV_FINANCE", "finance"], ["NAV_COMPETITIONS", "competitions"]]
	if not career.pyramids.is_empty():
		shortcuts.insert(0, ["SCREEN_LEAGUES", "leagues"])
	for pair in shortcuts:
		links.add_child(UIKit.button(Loc.t(pair[0]), go.bind(pair[1]), 110))
	add_child(links)
	add_child(UIKit.label(Loc.t("CAREER_CLUB_HISTORY"), 16, UIKit.GOLD))
	var seasons := career.club_history.filter(func(h: Dictionary) -> bool: return str(h.get("key", "")).begins_with("season_"))
	if seasons.is_empty():
		add_child(UIKit.muted(Loc.t("CAREER_NO_COMPLETED_SEASONS_YET")))
	for h in seasons:
		add_child(UIKit.muted(Loc.f("CAREER_SEASON_BALANCE_SQUAD", [int(h["season"]), int(h["balance"]), int(h["squad_size"])])))


## The managed club's fixtures due this week (league, cup, play-off): play in 3D or quick-sim.
func _my_fixtures(career: CareerState) -> void:
	if career.pyramids.is_empty():
		return
	var mine: Array = []
	for k in career.pyramids:
		var pyr: LeaguePyramid = career.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = career.competitions.get(pyr.comp[role])
			if comp == null:
				continue
			for f in comp.pending_fixtures():
				if (f["home"] == career.club_id or f["away"] == career.club_id) and pyr.week_of(role, comp, f) <= career.week:
					mine.append([comp, f])
	var box := UIKit.vbox(4)
	box.name = "MyFixtures"
	box.add_child(UIKit.label(Loc.t("CAREER_YOUR_MATCHES"), 16, UIKit.GOLD))
	if mine.is_empty():
		box.add_child(UIKit.muted(Loc.t("CAREER_NO_MATCH_THIS_WEEK")))
	for pair in mine:
		var comp: Competition = pair[0]
		var f: Dictionary = pair[1]
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label("%s — %s" % [app().competition_title(comp.id), Loc.f("TABLE_VS", [db().get_team(f["home"]).display_name, db().get_team(f["away"]).display_name])], 15))
		var play := UIKit.button(Loc.t("TABLE_PLAY_IN_3D"), _play.bind(comp.id, f), 110)
		play.name = "PlayMine_%s" % f["match_id"]
		row.add_child(play)
		var sim := UIKit.button(Loc.t("TABLE_SIMULATE"), _quick.bind(comp.id, f["match_id"]), 90)
		sim.name = "SimMine_%s" % f["match_id"]
		row.add_child(sim)
		box.add_child(row)
	add_child(UIKit.panel(box))


func _quick(cid: String, mid: String) -> void:
	var err: String = app().simulate_fixture(cid, mid)
	say(err if err != "" else Loc.t("TABLE_MATCH_SIMULATED"), err != "")
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


func _advance() -> void:
	var info: Dictionary = app().advance_week()
	say(Loc.f("CAREER_WEEK_WAGES_PAID_PROSPECT_S_TRAINED", [info["week"], info["wages_paid"],
			info["trained_ids"].size(), info["found_ids"].size(), Loc.t("CAREER_SEASON_OVER_SUFFIX") if info["season_over"] else ""]))
	rebuild()


func _end_season() -> void:
	var text := Loc.t("CAREER_END_THE_SEASON_PLAYERS_AGE_CONTRAC")
	if app().career.week < CareerState.WEEKS_PER_SEASON:
		text = Loc.f("CAREER_END_SEASON_EARLY", CareerState.WEEKS_PER_SEASON - app().career.week) + "\n" + text
	UIKit.confirm(self, text, _do_end_season)


func _do_end_season() -> void:
	var res: Dictionary = app().career.end_season(app().academies, app().squads)
	var text := Loc.f("CAREER_SEASON_BEGINS_PLAYER_S_RELEASED_OV", [
			res["season"], res["released"].size(), res["over_age"].size()])
	for k in (res.get("leagues", {}) as Dictionary):
		var s: Dictionary = res["leagues"][k]
		if app().career.club_id in s["promoted"]:
			text += "  " + Loc.t("CAREER_YOU_WERE_PROMOTED")
		elif app().career.club_id in s["relegated"]:
			text += "  " + Loc.t("CAREER_YOU_WERE_RELEGATED")
	if not (res.get("retired_mine", []) as Array).is_empty():
		text += "  " + Loc.f("CAREER_RETIRED_MINE", (res["retired_mine"] as Array).size())
	say(text)
	rebuild()


func _save() -> void:
	var err: String = app().save_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_SAVED"), err != "")


func _load() -> void:
	var err: String = app().load_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_LOADED"), err != "")
	rebuild()
