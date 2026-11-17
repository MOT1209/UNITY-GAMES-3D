extends HubScreen

## Career phase C6: trophy room, hall of fame and the season summary.


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_CLUB_HISTORY")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var sm := MediaFans.season_summary(career)
	var box := UIKit.vbox(4)
	box.name = "SeasonSummary"
	box.add_child(UIKit.label(Loc.t("SUMMARY_TITLE"), 16, UIKit.GOLD))
	box.add_child(UIKit.label(Loc.f("SUMMARY_LINE", [int(sm["season"]), int(sm["rank"]), int(sm["points"]), int(sm["goals_for"]), int(sm["goals_against"])]), 15))
	if str(sm["top_scorer"]) != "":
		box.add_child(UIKit.label(Loc.f("SUMMARY_TOP_SCORER", [db().get_player(str(sm["top_scorer"])).display_name, int(sm["top_scorer_goals"])]), 15))
	box.add_child(UIKit.label(Loc.f("SUMMARY_YOUTH", int(sm["young_players_used"])), 15))
	box.add_child(UIKit.label(Loc.f("SUMMARY_FINANCE", int(sm["net_finance"])), 15))
	add_child(UIKit.panel(box))
	var room := MediaFans.trophy_room(career)
	var tbox := UIKit.vbox(4)
	tbox.name = "TrophyRoom"
	tbox.add_child(UIKit.label(Loc.t("TROPHY_ROOM"), 16, UIKit.GOLD))
	if (room["titles"] as Array).is_empty():
		tbox.add_child(UIKit.muted(Loc.t("TROPHY_NONE")))
	for t in room["titles"]:
		var name_text: String = Loc.t("TROPHY_SUPER_CUP") if t["competition"] == "super_cup" else app().competition_title(str(t["competition"]))
		tbox.add_child(UIKit.label("%s · %s" % [name_text, Loc.f("INBOX_WEEK_LINE_SEASON", int(t["season"]))], 15))
	add_child(UIKit.panel(tbox))
	var hall := MediaFans.hall_of_fame(career)
	var hbox := UIKit.vbox(4)
	hbox.name = "HallOfFame"
	hbox.add_child(UIKit.label(Loc.t("HALL_OF_FAME"), 16, UIKit.GOLD))
	hbox.add_child(UIKit.label(Loc.t("HALL_TOP_SCORERS"), 14, UIKit.MUTED))
	for r in hall["scorers"]:
		hbox.add_child(UIKit.label("%s — %s" % [_pname(str(r["player_id"])), Loc.num(int(r["value"]))], 14))
	hbox.add_child(UIKit.label(Loc.t("HALL_MOST_APPS"), 14, UIKit.MUTED))
	for r in hall["appearances"]:
		hbox.add_child(UIKit.label("%s — %s" % [_pname(str(r["player_id"])), Loc.num(int(r["value"]))], 14))
	if not (hall["legends"] as Array).is_empty():
		hbox.add_child(UIKit.label(Loc.t("HALL_LEGENDS"), 14, UIKit.MUTED))
		for r in hall["legends"]:
			hbox.add_child(UIKit.label(_pname(str(r["player_id"])), 14))
	add_child(UIKit.panel(hbox))


func _pname(id: String) -> String:
	var p: PlayerData = db().get_player(id)
	return p.display_name if p != null else id
