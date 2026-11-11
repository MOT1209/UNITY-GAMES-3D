extends HubScreen

## Tournament Bracket: knockout rounds as columns with results and winners.


func build() -> void:
	if not header("Tournament Bracket", true, true):
		return
	var cid: String = str(params.get("competition_id", ""))
	var career: CareerState = app().career
	if not career.competitions.has(cid):
		add_child(UIKit.empty_state("Open a tournament from the Competitions screen."))
		return
	var comp: Competition = career.competitions[cid]
	add_child(UIKit.label("%s  (%s)" % [comp.comp_name, comp.stage], 18, UIKit.GOLD))
	if comp.is_finished():
		add_child(UIKit.label("Champion: %s" % db().get_team(comp.champion_id).display_name, 20, UIKit.GOOD))
	var rounds := comp.bracket()
	if rounds.is_empty():
		add_child(UIKit.empty_state("The knockout stage starts after the group stage."))
	var cols := UIKit.hbox(24)
	for r in rounds.size():
		var col := UIKit.vbox(10)
		col.add_child(UIKit.label(_round_name(r, rounds.size()), 15, UIKit.GOLD))
		for m in rounds[r]:
			var box := UIKit.vbox(0)
			box.add_child(UIKit.label(_line(m, m["home"]), 14, UIKit.GOOD if m["winner"] == m["home"] else UIKit.TEXT))
			box.add_child(UIKit.label(_line(m, m["away"]), 14, UIKit.GOOD if m["winner"] == m["away"] else UIKit.TEXT))
			if m["kind"] == "third":
				box.add_child(UIKit.muted("third place"))
			col.add_child(UIKit.panel(box))
		cols.add_child(col)
	add_child(UIKit.scroll(cols))
	if comp.type == Competition.Type.GROUP_KNOCKOUT:
		add_child(UIKit.button("Group standings", go.bind("standings", {"competition_id": cid}), 160))


func _round_name(index: int, total: int) -> String:
	var from_end := total - index
	return {1: "Final", 2: "Semi-finals", 3: "Quarter-finals"}.get(from_end, "Round %d" % (index + 1))


func _line(m: Dictionary, team_id: String) -> String:
	var tname: String = db().get_team(team_id).short_name if db().get_team(team_id) != null else "?"
	if not m["played"]:
		return tname
	var res := MatchResult.from_dict(app().career.competitions[params["competition_id"]].results[m["match_id"]])
	var goals := res.home_goals if team_id == m["home"] else res.away_goals
	var pens := ""
	if res.home_pens >= 0:
		pens = " (%d)" % (res.home_pens if team_id == m["home"] else res.away_pens)
	return "%s  %d%s" % [tname, goals, pens]
