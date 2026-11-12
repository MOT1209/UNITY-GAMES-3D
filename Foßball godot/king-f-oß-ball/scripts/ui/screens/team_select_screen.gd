extends HubScreen

## Team Selection: browse every club / national team, open details, pick the
## team you manage, or start a Club Manager career.

var _filter := -1


func build() -> void:
	header(Loc.t("COMMON_TEAM_SELECTION"))
	var bar := UIKit.hbox(8)
	bar.add_child(UIKit.label(Loc.t("SELECT_SHOW"), 15, UIKit.MUTED))
	var f := UIKit.option([Loc.t("SELECT_ALL"), Loc.t("SELECT_CLUBS"), Loc.t("SELECT_NATIONAL_TEAMS")], _filter + 1, _on_filter)
	f.name = "FilterOption"
	bar.add_child(f)
	add_child(bar)
	var teams: Array = db().list_teams(_filter)
	if teams.is_empty():
		add_child(UIKit.empty_state(Loc.t("SELECT_NO_TEAMS_WERE_FOUND_ADD_JSON_FILES")))
		return
	var list := UIKit.vbox(4)
	for t: TeamData in teams:
		var row := UIKit.hbox(10)
		row.add_child(UIKit.kit_preview(t, "home"))
		var info := UIKit.vbox(0)
		info.custom_minimum_size = Vector2(260, 0)
		info.add_child(UIKit.label(t.display_name, 18))
		info.add_child(UIKit.muted(Loc.f("SELECT_RATING", [
				Loc.t("TEAM_KIND_CLUB") if t.category == TeamData.Category.CLUB else Loc.t("TEAM_KIND_NATIONAL_SHORT"), t.country,
				db().get_team_rating(t.id), "" if not t.is_real else Loc.t("SELECT_REAL_SUFFIX")])))
		row.add_child(info)
		row.add_child(UIKit.button(Loc.t("SELECT_DETAILS"), go.bind("team_details", {"team_id": t.id}), 90))
		var sel := UIKit.button(Loc.t("SELECT_MANAGE"), _select.bind(t.id), 90)
		sel.name = "Select_%s" % t.id
		row.add_child(sel)
		if t.category == TeamData.Category.CLUB:
			var career := UIKit.button(Loc.t("SELECT_START_CAREER"), _career.bind(t.id), 120)
			career.name = "Career_%s" % t.id
			row.add_child(career)
		list.add_child(UIKit.panel(row))
	add_child(UIKit.scroll(list))


func _on_filter(index: int) -> void:
	_filter = index - 1
	rebuild()


func _select(team_id: String) -> void:
	var err: String = app().select_team(team_id)
	say(Loc.f("SELECT_MANAGING", db().get_team(team_id).display_name) if err == "" else err, err != "")


func _career(team_id: String) -> void:
	var err: String = app().start_career(team_id)
	if err != "":
		say(err, true)
		return
	say(Loc.f("SELECT_CAREER_STARTED_WITH", db().get_team(team_id).display_name))
	go("career")
