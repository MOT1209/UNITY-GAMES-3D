extends HubScreen

## Team Details: info, kits, rating, squad overview and a side-by-side comparison.

var _compare_index := 0


func build() -> void:
	var team_id: String = params.get("team_id", app().user_team_id)
	var team: TeamData = db().get_team(team_id)
	if not header(Loc.t("TEAM_TEAM_DETAILS")):
		return
	if team == null:
		add_child(UIKit.empty_state(Loc.t("TEAM_PICK_A_TEAM_IN_TEAM_SELECTION_TO_S")))
		return
	params["team_id"] = team_id
	var top := UIKit.hbox(16)
	var info := UIKit.vbox(2)
	info.add_child(UIKit.label(team.display_name, 24, UIKit.GOLD))
	info.add_child(UIKit.muted("%s (%s) · %s · %s" % [team.short_name, team.country,
			Loc.t("TEAM_KIND_CLUB") if team.category == TeamData.Category.CLUB else Loc.t("TEAM_KIND_NATIONAL"),
			"real" if team.is_real else "fictional"]))
	info.add_child(UIKit.label(Loc.f("TEAM_RATING_REPUTATION_SQUAD", [
			db().get_team_rating(team_id), team.reputation, team.squad_ids.size()]), 16))
	if team.category == TeamData.Category.CLUB:
		info.add_child(UIKit.label(Loc.f("TEAM_BUDGET", _money(team.budget)), 16))
	top.add_child(info)
	for slot in KitEditor.SLOTS:
		top.add_child(UIKit.kit_preview(team, slot))
	add_child(UIKit.panel(top))
	# Comparison
	var cmp_row := UIKit.hbox(8)
	cmp_row.add_child(UIKit.label(Loc.t("TEAM_COMPARE_WITH"), 15, UIKit.MUTED))
	var other := UIKit.option(team_names(), _compare_index, _on_compare)
	other.name = "CompareOption"
	cmp_row.add_child(other)
	add_child(cmp_row)
	var other_id := team_id_at(_compare_index)
	if other_id != "" and other_id != team_id:
		add_child(_comparison(team, db().get_team(other_id)))
	# Squad overview
	var players: Array = db().get_squad(team_id)
	if players.is_empty():
		add_child(UIKit.empty_state(Loc.t("TEAM_THIS_TEAM_HAS_NO_PLAYERS")))
		return
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var rows: Array = []
	for p: PlayerData in players:
		rows.append([p.shirt_number, p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p)])
	var table := UIKit.table(["#", Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT")], rows, _open_player.bind(players))
	add_child(UIKit.scroll(table))


func _comparison(a: TeamData, b: TeamData) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	for h in ["", a.short_name, b.short_name]:
		grid.add_child(UIKit.label(h, 14, UIKit.GOLD))
	var stats := {Loc.t("TEAM_STAT_RATING"): [db().get_team_rating(a.id), db().get_team_rating(b.id)],
			Loc.t("TEAM_STAT_REPUTATION"): [a.reputation, b.reputation],
			Loc.t("TEAM_STAT_AVG_AGE"): [_avg_age(a.id), _avg_age(b.id)],
			Loc.t("TEAM_STAT_TOP_PLAYER"): [_top(a.id), _top(b.id)]}
	for k in stats:
		grid.add_child(UIKit.label(k, 14, UIKit.MUTED))
		grid.add_child(UIKit.label(str(stats[k][0]), 15))
		grid.add_child(UIKit.label(str(stats[k][1]), 15))
	return UIKit.panel(grid)


func _avg_age(team_id: String) -> String:
	var squad: Array = db().get_squad(team_id)
	if squad.is_empty():
		return "-"
	var sum := 0
	for p: PlayerData in squad:
		sum += p.age
	return Loc.decimal(float(sum) / squad.size(), 1)


func _top(team_id: String) -> int:
	var best := 0
	for p: PlayerData in db().get_squad(team_id):
		best = maxi(best, p.get_overall())
	return best


func _on_compare(index: int) -> void:
	_compare_index = index
	rebuild()


func _open_player(row: int, players: Array) -> void:
	go("player_profile", {"player_id": (players[row] as PlayerData).id})


func _money(v: int) -> String:
	return Loc.f("COMMON_MILLIONS", Loc.decimal(v / 1000000.0, 1)) if absi(v) >= 1000000 else Loc.num(v)
