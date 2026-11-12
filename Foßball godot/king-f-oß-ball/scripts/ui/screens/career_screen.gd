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
	stats.add_child(UIKit.label(team.display_name, 24, UIKit.GOLD))
	stats.add_child(UIKit.label(Loc.f("CAREER_SEASON_WEEK_OF", [career.season, career.week, CareerState.WEEKS_PER_SEASON]), 16))
	stats.add_child(UIKit.label(Loc.f("CAREER_BALANCE_TRANSFER_BUDGET", [career.ledger().balance, career.ledger().transfer_budget]), 16))
	stats.add_child(UIKit.label(Loc.f("CAREER_SQUAD_RATING_WEEKLY_WAGES", [team.squad_ids.size(),
			db().get_team_rating(team.id), career.market.weekly_wages(team.id)]), 16))
	var expiring := career.market.expiring_contracts(team.id)
	if not expiring.is_empty():
		stats.add_child(UIKit.label(Loc.tn("CAREER_CONTRACTS_EXPIRE", expiring.size()), 14, UIKit.BAD))
	add_child(UIKit.panel(stats))
	var actions := UIKit.hbox(8)
	var wk := UIKit.button(Loc.t("COMMON_ADVANCE_WEEK"), _advance, 150)
	wk.name = "AdvanceWeek"
	actions.add_child(wk)
	var end := UIKit.button(Loc.t("CAREER_END_SEASON"), _end_season, 140)
	end.name = "EndSeason"
	actions.add_child(end)
	var sv := UIKit.button(Loc.t("CAREER_SAVE"), _save, 90)
	sv.name = "SaveButton"
	actions.add_child(sv)
	actions.add_child(UIKit.button(Loc.t("CAREER_LOAD"), _load, 90))
	add_child(actions)
	var links := UIKit.hbox(8)
	for pair in [["NAV_SQUAD", "squad"], ["NAV_ACADEMY", "academy"], ["NAV_TRANSFERS", "transfers"], ["NAV_FINANCE", "finance"], ["NAV_COMPETITIONS", "competitions"]]:
		links.add_child(UIKit.button(Loc.t(pair[0]), go.bind(pair[1]), 110))
	add_child(links)
	add_child(UIKit.label(Loc.t("CAREER_CLUB_HISTORY"), 16, UIKit.GOLD))
	var seasons := career.club_history.filter(func(h: Dictionary) -> bool: return str(h.get("key", "")).begins_with("season_"))
	if seasons.is_empty():
		add_child(UIKit.muted(Loc.t("CAREER_NO_COMPLETED_SEASONS_YET")))
	for h in seasons:
		add_child(UIKit.muted(Loc.f("CAREER_SEASON_BALANCE_SQUAD", [int(h["season"]), int(h["balance"]), int(h["squad_size"])])))


func _advance() -> void:
	var info: Dictionary = app().advance_week()
	say(Loc.f("CAREER_WEEK_WAGES_PAID_PROSPECT_S_TRAINED", [info["week"], info["wages_paid"],
			info["trained_ids"].size(), info["found_ids"].size(), Loc.t("CAREER_SEASON_OVER_SUFFIX") if info["season_over"] else ""]))
	rebuild()


func _end_season() -> void:
	UIKit.confirm(self, Loc.t("CAREER_END_THE_SEASON_PLAYERS_AGE_CONTRAC"), _do_end_season)


func _do_end_season() -> void:
	var res: Dictionary = app().career.end_season(app().academies)
	say(Loc.f("CAREER_SEASON_BEGINS_PLAYER_S_RELEASED_OV", [
			res["season"], res["released"].size(), res["over_age"].size()]))
	rebuild()


func _save() -> void:
	var err: String = app().save_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_SAVED"), err != "")


func _load() -> void:
	var err: String = app().load_game()
	say(err if err != "" else Loc.t("CAREER_CAREER_LOADED"), err != "")
	rebuild()
