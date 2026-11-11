extends HubScreen

## Team Selection: browse every club / national team, open details, pick the
## team you manage, or start a Club Manager career.

var _filter := -1


func build() -> void:
	header("Team Selection")
	var bar := UIKit.hbox(8)
	bar.add_child(UIKit.label("Show:", 15, UIKit.MUTED))
	var f := UIKit.option(["All", "Clubs", "National teams"], _filter + 1, _on_filter)
	f.name = "FilterOption"
	bar.add_child(f)
	add_child(bar)
	var teams: Array = db().list_teams(_filter)
	if teams.is_empty():
		add_child(UIKit.empty_state("No teams were found. Add JSON files to data/clubs or create a club."))
		return
	var list := UIKit.vbox(4)
	for t: TeamData in teams:
		var row := UIKit.hbox(10)
		row.add_child(UIKit.kit_preview(t, "home"))
		var info := UIKit.vbox(0)
		info.custom_minimum_size = Vector2(260, 0)
		info.add_child(UIKit.label(t.display_name, 18))
		info.add_child(UIKit.muted("%s · %s · rating %d%s" % [
				"Club" if t.category == TeamData.Category.CLUB else "National", t.country,
				db().get_team_rating(t.id), "" if not t.is_real else " · real"]))
		row.add_child(info)
		row.add_child(UIKit.button("Details", go.bind("team_details", {"team_id": t.id}), 90))
		var sel := UIKit.button("Manage", _select.bind(t.id), 90)
		sel.name = "Select_%s" % t.id
		row.add_child(sel)
		if t.category == TeamData.Category.CLUB:
			var career := UIKit.button("Start career", _career.bind(t.id), 120)
			career.name = "Career_%s" % t.id
			row.add_child(career)
		list.add_child(UIKit.panel(row))
	add_child(UIKit.scroll(list))


func _on_filter(index: int) -> void:
	_filter = index - 1
	rebuild()


func _select(team_id: String) -> void:
	var err: String = app().select_team(team_id)
	say("Managing %s" % db().get_team(team_id).display_name if err == "" else err, err != "")


func _career(team_id: String) -> void:
	var err: String = app().start_career(team_id)
	if err != "":
		say(err, true)
		return
	say("Career started with %s" % db().get_team(team_id).display_name)
	go("career")
