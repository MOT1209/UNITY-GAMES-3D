extends HubScreen

## Career Dashboard: club status, season clock, key figures, save/load and
## shortcuts. Starts a career when none exists.


func build() -> void:
	add_child(UIKit.title("Career Dashboard"))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state("No career in progress. Pick a club and choose 'Start career'."))
		var row := UIKit.hbox(8)
		row.add_child(UIKit.button("Team Selection", go.bind("team_select"), 160))
		var load_btn := UIKit.button("Load saved career", _load, 170)
		load_btn.name = "LoadButton"
		row.add_child(load_btn)
		add_child(row)
		return
	var team: TeamData = db().get_team(career.club_id)
	var stats := UIKit.vbox(4)
	stats.add_child(UIKit.label(team.display_name, 24, UIKit.GOLD))
	stats.add_child(UIKit.label("Season %d · week %d of %d" % [career.season, career.week, CareerState.WEEKS_PER_SEASON], 16))
	stats.add_child(UIKit.label("Balance %d · transfer budget %d" % [career.ledger().balance, career.ledger().transfer_budget], 16))
	stats.add_child(UIKit.label("Squad %d · rating %d · weekly wages %d" % [team.squad_ids.size(),
			db().get_team_rating(team.id), career.market.weekly_wages(team.id)], 16))
	var expiring := career.market.expiring_contracts(team.id)
	if not expiring.is_empty():
		stats.add_child(UIKit.label("%d contract(s) expire this season" % expiring.size(), 14, UIKit.BAD))
	add_child(UIKit.panel(stats))
	var actions := UIKit.hbox(8)
	var wk := UIKit.button("Advance week", _advance, 150)
	wk.name = "AdvanceWeek"
	actions.add_child(wk)
	var end := UIKit.button("End season", _end_season, 140)
	end.name = "EndSeason"
	actions.add_child(end)
	var sv := UIKit.button("Save", _save, 90)
	sv.name = "SaveButton"
	actions.add_child(sv)
	actions.add_child(UIKit.button("Load", _load, 90))
	add_child(actions)
	var links := UIKit.hbox(8)
	for pair in [["Squad", "squad"], ["Academy", "academy"], ["Transfers", "transfers"], ["Finance", "finance"], ["Competitions", "competitions"]]:
		links.add_child(UIKit.button(pair[0], go.bind(pair[1]), 110))
	add_child(links)
	add_child(UIKit.label("Club history", 16, UIKit.GOLD))
	var seasons := career.club_history.filter(func(h: Dictionary) -> bool: return str(h.get("key", "")).begins_with("season_"))
	if seasons.is_empty():
		add_child(UIKit.muted("No completed seasons yet."))
	for h in seasons:
		add_child(UIKit.muted("Season %d — balance %d, squad %d" % [int(h["season"]), int(h["balance"]), int(h["squad_size"])]))


func _advance() -> void:
	var info: Dictionary = app().advance_week()
	say("Week %d — wages paid %d · %d prospect(s) trained · %d found%s" % [info["week"], info["wages_paid"],
			info["trained_ids"].size(), info["found_ids"].size(), " · season over" if info["season_over"] else ""])
	rebuild()


func _end_season() -> void:
	UIKit.confirm(self, "End the season? Players age, contracts run down and expired players leave.", _do_end_season)


func _do_end_season() -> void:
	var res: Dictionary = app().career.end_season(app().academies)
	say("Season %d begins — %d player(s) released" % [res["season"], res["released"].size()])
	rebuild()


func _save() -> void:
	var err: String = app().save_game()
	say(err if err != "" else "Career saved", err != "")


func _load() -> void:
	var err: String = app().load_game()
	say(err if err != "" else "Career loaded", err != "")
	rebuild()
