extends HubScreen

## Tournament Bracket: knockout rounds as columns with results and winners.


func _init() -> void:
	super()
	own_scroll = true       # lays out its own ScrollContainer


func build() -> void:
	if not header(Loc.t("BRACKET_TOURNAMENT_BRACKET"), true, true):
		return
	var cid: String = str(params.get("competition_id", ""))
	var career: CareerState = app().career
	if not career.competitions.has(cid):
		add_child(UIKit.empty_state(Loc.t("BRACKET_OPEN_A_TOURNAMENT_FROM_THE_COMPETI")))
		return
	var comp: Competition = career.competitions[cid]
	add_child(UIKit.label("%s  (%s)" % [app().competition_title(comp.id), Loc.enum_name("STAGE", comp.stage)], 18, UIKit.GOLD))
	if comp.is_finished():
		add_child(UIKit.label(Loc.f("COMMON_CHAMPION", db().get_team(comp.champion_id).display_name), 20, UIKit.GOOD))
	var rounds := comp.bracket()
	if rounds.is_empty():
		add_child(UIKit.empty_state(Loc.t("BRACKET_THE_KNOCKOUT_STAGE_STARTS_AFTER_TH")))
	var cols := UIKit.hbox(24)
	for r in rounds.size():
		var col := UIKit.vbox(10)
		col.add_child(UIKit.label(_round_name(r, rounds[r]), 15, UIKit.GOLD))
		for m in rounds[r]:
			var box := UIKit.vbox(2)
			box.add_child(_team_line(m, m["home"]))
			box.add_child(_team_line(m, m["away"]))
			if m["kind"] == "third":
				box.add_child(UIKit.muted(Loc.t("BRACKET_THIRD_PLACE")))
			col.add_child(UIKit.panel(box))
		cols.add_child(col)
	add_child(UIKit.scroll(cols))
	if comp.type == Competition.Type.GROUP_KNOCKOUT:
		add_child(UIKit.button(Loc.t("BRACKET_GROUP_STANDINGS"), go.bind("standings", {"competition_id": cid}), 160))


## Named by how many ties the round holds (final 1, semi-finals 2, quarter-finals 4): later rounds do not exist yet while the
## cup is running, so counting columns from the end would call the semi-finals "the final".
func _round_name(index: int, ties: Array) -> String:
	var n := ties.filter(func(m: Dictionary) -> bool: return m["kind"] != "third").size()
	return {1: Loc.t("BRACKET_FINAL"), 2: Loc.t("BRACKET_SEMI_FINALS"), 4: Loc.t("BRACKET_QUARTER_FINALS")}.get(n, Loc.f("BRACKET_ROUND", index + 1))


## Crest, full name and goals of one side of a tie; the winner in green.
func _team_line(m: Dictionary, team_id: String) -> Control:
	var tm: TeamData = db().get_team(team_id)
	var row := UIKit.hbox(6)
	row.add_child(UIKit.crest(db(), tm, 20))
	var lab := UIKit.label(_line(m, team_id), 14, UIKit.GOOD if m["winner"] == team_id else UIKit.TEXT)
	lab.custom_minimum_size.x = 150
	row.add_child(lab)
	return row


func _line(m: Dictionary, team_id: String) -> String:
	var tname: String = db().get_team(team_id).display_name if db().get_team(team_id) != null else "?"
	if not m["played"]:
		return tname
	var res := MatchResult.from_dict(app().career.competitions[params["competition_id"]].results[m["match_id"]])
	var goals := res.home_goals if team_id == m["home"] else res.away_goals
	var pens := ""
	if res.home_pens >= 0:
		pens = " (%d)" % (res.home_pens if team_id == m["home"] else res.away_pens)
	return "%s  %d%s" % [tname, goals, pens]
