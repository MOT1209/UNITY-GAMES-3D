extends HubScreen

## Career Dashboard: club status, season clock, key figures, save/load and
## shortcuts. Starts a career when none exists.


func build() -> void:
	add_child(UIKit.title(Loc.t("CAREER_CAREER_DASHBOARD")))
	var career: CareerState = app().career
	if career != null:
		sub_links("career")
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		var row := UIKit.hbox(8)
		var wiz := UIKit.button(Loc.t("SCREEN_CAREER_WIZARD"), go.bind("career_wizard"), 180)
		wiz.name = "NewCareerButton"
		row.add_child(wiz)
		row.add_child(UIKit.button(Loc.t("COMMON_TEAM_SELECTION"), go.bind("team_select"), 160))
		var load_btn := UIKit.button(Loc.t("CAREER_LOAD_SAVED_CAREER"), _load, 170)
		load_btn.name = "LoadButton"
		row.add_child(load_btn)
		add_child(row)
		return
	add_child(_dashboard(career))
	add_child(_prep_panel(career))
	if not career.pending_press.is_empty():
		add_child(_press_panel(career))
	var team: TeamData = db().get_team(career.club_id)
	var stats := UIKit.vbox(4)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.crest(db(), team, 48, "card"))
	head.add_child(UIKit.label(team.display_name, 24, UIKit.GOLD))
	stats.add_child(head)
	stats.add_child(UIKit.label(CareerDate.format(career.date()) + "  ·  " + Loc.f("CAREER_SEASON_WEEK_OF", [career.season, career.week, CareerState.WEEKS_PER_SEASON]), 16))
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
		var line := UIKit.label(Loc.f("CAREER_DIVISION_POSITION", [LeaguePyramid.label(ud["division"]["name"]), pos]), 16, UIKit.GOLD)
		line.name = "DivisionLine"
		stats.add_child(line)
	add_child(UIKit.panel(stats))
	add_child(_manager_panel(career))
	add_child(_delegation_panel(career))
	add_child(_news_panel(career))
	_my_fixtures(career)
	var actions := UIKit.hbox(8)
	var season_over := career.week >= CareerState.WEEKS_PER_SEASON
	var cont := UIKit.button(Loc.t("CAREER_CONTINUE"), _continue, 170)
	cont.name = "ContinueButton"
	cont.add_theme_color_override("font_color", UIKit.GOLD)
	actions.add_child(cont)
	var oneday := UIKit.button(Loc.t("CAL2_ONE_DAY"), _one_day, 120)       # Phase K5
	oneday.name = "OneDayButton"
	oneday.disabled = season_over and career.day >= 6
	actions.add_child(oneday)
	var cal := UIKit.button(Loc.t("SCREEN_CALENDAR"), func() -> void: go("calendar"), 120)
	cal.name = "CalendarButton"
	actions.add_child(cal)
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
	var mine: Array = app().due_user_fixtures()
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
		var live_b := UIKit.button(Loc.t("LIVE_PLAY"), func() -> void: go("live_match", {"competition_id": comp.id, "match_id": f["match_id"]}), 110)
		live_b.name = "LiveMine_%s" % f["match_id"]
		row.add_child(live_b)
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
	var err: String = app().play_fixture(cid, f)
	if err != "":
		say(err, true)


## The week is simulated in phases with a frame in between (`AppHub.advance_week_async`), so the window never freezes; the
## screen is refreshed when `week_advanced` arrives. The button stays disabled meanwhile.
func _advance() -> void:
	if app().is_advancing():
		return
	var btn := find_child("AdvanceWeek", true, false) as Button
	if btn != null:
		btn.disabled = true
	if not app().week_advanced.is_connected(_on_week_advanced):
		app().week_advanced.connect(_on_week_advanced, CONNECT_ONE_SHOT)
	app().advance_week_async()


## C9.2: advances week by week until something needs a decision (a match, an offer, the end of the season), then shows it.
func _continue() -> void:
	if app().is_advancing() or app().career == null:
		return
	var career: CareerState = app().career
	# Phase K5: day by day until the first event that needs the manager (his match, an offer, a demand, a meeting ...)
	var res: Dictionary = await CareerFlow.continue_days(career, app().advance_day_async)
	if app().career != career:
		return
	app().state_changed.emit()
	var stop: Dictionary = res["stop"]
	if stop.is_empty():
		say(Loc.t("CAREER_CONTINUE_NOTHING"))
	else:
		say("%s — %s" % [CareerDate.format(career.date()), Loc.f(str(stop["key"]), stop["args"])])
	rebuild()


## Phase K5: exactly one day.
func _one_day() -> void:
	if app().is_advancing() or app().career == null:
		return
	app().advance_day()
	say(CareerDate.format(app().career.date()))
	rebuild()


func _on_week_advanced(info: Dictionary) -> void:
	say(Loc.f("CAREER_WEEK_WAGES_PAID_PROSPECT_S_TRAINED", [info["week"], info["wages_paid"],
			info["trained_ids"].size(), info["found_ids"].size(), Loc.t("CAREER_SEASON_OVER_SUFFIX") if info["season_over"] else ""]))
	rebuild()


## C9.6: next match, last results, league position, waiting decisions, board confidence and finances at a glance.
func _dashboard(career: CareerState) -> Control:
	CareerFlow.sync(career)
	var box := UIKit.vbox(4)
	box.name = "Dashboard"
	box.add_child(UIKit.label(Loc.t("DASH_TITLE"), 16, UIKit.GOLD))
	var nm := CareerCalendar.next_match(career)
	var next_line := Loc.t("DASH_NO_MATCH")
	if not nm.is_empty():
		var opp: TeamData = db().get_team(str(nm["opponent"]))
		next_line = Loc.f("DASH_NEXT_LINE", [int(nm["week"]), app().competition_title(str(nm["comp_id"])), Loc.iso(opp.display_name if opp != null else str(nm["opponent"])),
				Loc.t("CAL_HOME") if nm["home"] else Loc.t("CAL_AWAY")])
	var nl := UIKit.label("%s: %s" % [Loc.t("DASH_NEXT_MATCH"), next_line], 15)
	nl.name = "DashNext"
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nl)
	var form: Array = CareerCalendar.recent_results(career, 5)
	var form_text := Loc.t("DASH_NO_RESULTS") if form.is_empty() else "  ".join(form.map(func(r: Dictionary) -> String: return Loc.ltr(str(r["score"]))))
	var fl := UIKit.label("%s: %s" % [Loc.t("DASH_RESULTS"), form_text], 15)
	fl.name = "DashResults"
	box.add_child(fl)
	var ll := CareerCalendar.league_line(career)
	if not ll.is_empty():
		var l := UIKit.label(Loc.f("DASH_LEAGUE", [int(ll["rank"]), int(ll["size"]), int(ll["points"])]), 15)
		l.name = "DashLeague"
		box.add_child(l)
	var pending := career.inbox.pending_decisions().size()
	var dl := UIKit.label(Loc.f("DASH_DECISIONS", pending), 15, UIKit.BAD if pending > 0 else UIKit.MUTED)
	dl.name = "DashDecisions"
	box.add_child(dl)
	var atm := MoraleSystem.atmosphere(db(), career.club_id)
	var al := UIKit.label(Loc.f("DASH_ATMOSPHERE", Loc.t(str(atm["key"]))), 15)
	al.name = "DashAtmosphere"
	box.add_child(al)
	box.add_child(UIKit.label(Loc.f("DASH_BOARD", career.manager.confidence), 15))
	box.add_child(UIKit.label(Loc.f("DASH_FINANCE", [career.ledger().balance, career.ledger().transfer_budget]), 15))
	return UIKit.panel(box)


## C4.1: opponent report and team talk before the next match.
func _prep_panel(career: CareerState) -> Control:
	var box := UIKit.vbox(4)
	box.name = "MatchPrep"
	box.add_child(UIKit.label(Loc.t("PREP_TITLE"), 16, UIKit.GOLD))
	var nm := CareerCalendar.next_match(career)
	if nm.is_empty():
		box.add_child(UIKit.muted(Loc.t("DASH_NO_MATCH")))
		return UIKit.panel(box)
	var rep := Matchday.opponent_report(career, str(nm["opponent"]))
	var form: Array = rep["form"]
	var fl := UIKit.label("%s: %s" % [Loc.t("PREP_FORM"), " ".join(form.map(func(x: String) -> String: return Loc.t("PREP_RESULT_" + x))) if not form.is_empty() else "-"], 14)
	fl.name = "PrepForm"
	box.add_child(fl)
	if str(rep["danger"]) != "":
		var dl := UIKit.label("%s: %s" % [Loc.t("PREP_DANGER"), db().get_player(str(rep["danger"])).display_name], 14)
		dl.name = "PrepDanger"
		box.add_child(dl)
	if str(rep["strongest"]) != "":
		box.add_child(UIKit.label("%s: %s · %s: %s" % [Loc.t("PREP_STRONG"), Loc.t("PREP_LINE_" + str(rep["strongest"]).to_upper()), Loc.t("PREP_WEAK"), Loc.t("PREP_LINE_" + str(rep["weakest"]).to_upper())], 14))
	if str(rep["style"]) != "":
		box.add_child(UIKit.label("%s: %s" % [Loc.t("PREP_STYLE"), Loc.t("PREP_STYLE_" + str(rep["style"]).to_upper())], 14))
	var row := HFlowContainer.new()
	for kind in Matchday.TALKS:
		var b := UIKit.button(Loc.t("TALK_" + kind.to_upper()), _talk.bind(kind, float(nm.get("week", 0)) >= 40), 110)
		b.name = "Talk_%s" % kind
		row.add_child(b)
	box.add_child(row)
	return UIKit.panel(box)


func _talk(kind: String, big: bool) -> void:
	var career: CareerState = app().career
	var r := Matchday.team_talk(career, kind, 1.0 if big else 0.5)
	say(Loc.f("TALK_RESULT", [Loc.t("TALK_" + kind.to_upper()), int(r["total"])]))
	app().state_changed.emit()
	rebuild()


## C4.4: the press conference after a big result: one question, four tones (or "the assistant answers").
func _press_panel(career: CareerState) -> Control:
	var box := UIKit.vbox(4)
	box.name = "PressConference"
	box.add_child(UIKit.label(Loc.t("PRESS_TITLE"), 16, UIKit.GOLD))
	box.add_child(UIKit.label(Loc.f("PRESS_QUESTION", Loc.ltr(str(career.pending_press["score"]))), 15))
	var row := HFlowContainer.new()
	for tone in Matchday.TONES:
		var b := UIKit.button(Loc.t("PRESS_TONE_" + str(tone).to_upper()), _answer_press.bind(str(tone)), 110)
		b.name = "Press_%s" % tone
		row.add_child(b)
	var skip := UIKit.button(Loc.t("PRESS_SKIP"), _answer_press.bind("calm"), 170)
	skip.name = "Press_skip"
	row.add_child(skip)
	box.add_child(row)
	return UIKit.panel(box)


func _answer_press(tone: String) -> void:
	var career: CareerState = app().career
	var r := Matchday.press_answer(career, tone)
	say(Loc.t(str(r["key"])))
	app().state_changed.emit()
	rebuild()


## C9.3: who handles each task, me or the assistant.
func _delegation_panel(career: CareerState) -> Control:
	var box := UIKit.vbox(4)
	box.name = "DelegationPanel"
	box.add_child(UIKit.label(Loc.t("DELEGATE_TITLE"), 16, UIKit.GOLD))
	box.add_child(UIKit.muted(Loc.t("DELEGATE_HINT")))
	var lv := UIKit.hbox(8)
	var lvl := UIKit.label(Loc.f("DELEGATE_LEVEL", [career.delegation.level, Delegation.MAX_LEVEL, roundi(career.delegation.effective_quality() * 100.0)]), 15, UIKit.GOLD)
	lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(lvl)
	if career.delegation.level < Delegation.MAX_LEVEL:
		var up := UIKit.button(Loc.f("DELEGATE_UPGRADE", career.delegation.upgrade_cost()), func() -> void:
			var err := career.delegation.upgrade(career)
			say(err if err != "" else Loc.f("DELEGATE_UPGRADED", career.delegation.level), err != "")
			rebuild(), 220)
		up.name = "AssistantUpgrade"
		lv.add_child(up)
	box.add_child(lv)
	for domain in Delegation.DOMAINS:
		var row := UIKit.hbox(8)
		var name_label := UIKit.label(Loc.t("DELEGATE_" + domain.to_upper()), 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var opt := UIKit.option([Loc.t("DELEGATE_ME"), Loc.t("DELEGATE_ASSISTANT")], 1 if career.delegation.is_delegated(domain) else 0,
				func(i: int) -> void: career.delegation.set_domain(domain, Delegation.ASSISTANT if i == 1 else Delegation.ME))
		opt.name = "Delegate_%s" % domain
		opt.custom_minimum_size.y = 48.0
		opt.disabled = not career.delegation.unlocked(domain)
		if opt.disabled:
			opt.tooltip_text = Loc.f("DELEGATE_LOCKED", int(Delegation.DOMAIN_LEVEL.get(domain, 1)))
			name_label.text += "  🔒 " + Loc.f("DELEGATE_LOCKED", int(Delegation.DOMAIN_LEVEL.get(domain, 1)))
		row.add_child(opt)
		box.add_child(row)
	return UIKit.panel(box)


func _manager_panel(career: CareerState) -> Control:
	var m := career.manager
	var box := UIKit.vbox(4)
	box.name = "ManagerPanel"
	box.add_child(UIKit.label(Loc.t("CAREER_MANAGER"), 16, UIKit.GOLD))
	box.add_child(UIKit.label(Loc.f("CAREER_MANAGER_LINE", [m.reputation, m.confidence, m.contract_years, m.trophies]), 15))
	if m.unemployed:
		var out := UIKit.label(Loc.t("CAREER_MANAGER_UNEMPLOYED"), 15, UIKit.BAD)
		out.name = "UnemployedLine"
		box.add_child(out)
		for o in career.job_offers():
			var team: TeamData = db().get_team(o["club_id"])
			var b := UIKit.button(Loc.f("CAREER_JOB_OFFER", [team.display_name, o["rating"]]), _take_job.bind(o["club_id"]), 320)
			b.name = "Job_%s" % o["club_id"]
			box.add_child(b)
	else:
		if not m.objective.is_empty():
			var obj := UIKit.label(Loc.f("CAREER_BOARD_OBJECTIVE", [int(m.objective["target_rank"])]), 15)
			obj.name = "BoardObjective"
			box.add_child(obj)
		var rs := UIKit.button(Loc.t("CAREER_RESIGN"), _resign_confirm, 140)
		rs.name = "ResignButton"
		box.add_child(rs)
	return UIKit.panel(box)


func _news_panel(career: CareerState) -> Control:
	var box := UIKit.vbox(2)
	box.name = "NewsPanel"
	box.add_child(UIKit.label(Loc.t("CAREER_NEWS"), 16, UIKit.GOLD))
	var items := NewsFeed.build(career, 5, true)
	if items.is_empty():
		box.add_child(UIKit.muted(Loc.t("CAREER_NO_NEWS")))
	for n in items:
		var line := UIKit.label(Loc.f(n["key"], n["args"]), 14)
		line.text_direction = Control.TEXT_DIRECTION_AUTO
		box.add_child(line)
	return UIKit.panel(box)


func _resign_confirm() -> void:
	UIKit.confirm(self, Loc.t("CAREER_RESIGN_CONFIRM"), _resign)


func _resign() -> void:
	var err: String = app().career.resign()
	say(err if err != "" else Loc.t("CAREER_RESIGNED"), err != "")
	rebuild()


func _take_job(club_id: String) -> void:
	var err: String = app().take_job(club_id)
	say(err if err != "" else Loc.t("CAREER_JOB_TAKEN"), err != "")
	rebuild()


func _end_season() -> void:
	var text := Loc.t("CAREER_END_THE_SEASON_PLAYERS_AGE_CONTRAC")
	if app().career.week < CareerState.WEEKS_PER_SEASON:
		text = Loc.f("CAREER_END_SEASON_EARLY", CareerState.WEEKS_PER_SEASON - app().career.week) + "\n" + text
	UIKit.confirm(self, text, _do_end_season)


func _do_end_season() -> void:
	if app().is_advancing():
		return
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
	var rv: Dictionary = res.get("manager", {})
	if not rv.is_empty():
		text += "  " + Loc.f("CAREER_BOARD_REVIEW", [Loc.t("CAREER_RESULT_" + str(rv["result"]).to_upper()), int(rv["rank"])])
		if rv["event"] == "sacked":
			text += "  " + Loc.t("CAREER_MANAGER_SACKED")
		elif rv["event"] == "contract_expired":
			text += "  " + Loc.t("CAREER_CONTRACT_EXPIRED")
	say(text)
	rebuild()


func _save() -> void:
	var err: String = app().save_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_SAVED"), err != "")


func _load() -> void:
	var err: String = app().load_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_LOADED"), err != "")
	rebuild()
