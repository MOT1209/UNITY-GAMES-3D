extends HubScreen

## Promotion: choose an academy player, inspect him, assign a squad number and
## promote him to the first team (confirmed). Uses `PromotionSystem`.

var _selected := ""


func _init() -> void:
	super()
	own_scroll = true       # lays out its own ScrollContainer


func build() -> void:
	if not header(Loc.t("PROMO_PROMOTION"), true):
		return
	var ac: Academy = app().academy()
	if ac == null:
		add_child(UIKit.empty_state(Loc.t("COMMON_ONLY_CLUBS_HAVE_AN_ACADEMY")))
		return
	_selected = str(params.get("player_id", _selected))
	if ac.roster_ids.is_empty():
		add_child(UIKit.empty_state(Loc.t("PROMO_THERE_ARE_NO_ACADEMY_PLAYERS_TO_PR")))
		return
	var players: Array = ac.roster_ids.map(func(id: String) -> PlayerData: return db().get_player(id))
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var rows: Array = []
	for p: PlayerData in players:
		var why := PromotionSystem.why_not(db(), ac, p.id)
		rows.append([p.display_name, Loc.position_code(p.position), p.age, overall_text(p), Loc.t("PROMO_READY") if why == "" else ErrorText.localize(why, db())])
	add_child(UIKit.label(Loc.t("PROMO_ACADEMY_PLAYERS"), 16, UIKit.GOLD))
	# Two columns: the list, and the selected player's details next to it (the right half used to be empty).
	var columns := UIKit.hbox(14)
	columns.name = "PromotionColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var list := UIKit.scroll(UIKit.table([Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT"), Loc.t("PROMO_ELIGIBILITY")], rows, _pick.bind(players)))
	columns.add_child(list)
	if _selected == "" or not (_selected in ac.roster_ids):
		_selected = (players[0] as PlayerData).id          # best prospect preselected
	var p: PlayerData = db().get_player(_selected)
	var panel := UIKit.vbox(6)
	panel.name = "PromotionDetails"
	var card := PlayerCard.new(150.0)
	card.setup(PlayerCardData.from_data(db(), p), db())
	panel.add_child(card)
	panel.add_child(UIKit.label(Loc.f("PROMO_AGE", [p.display_name, Loc.position_code(p.position), p.age, "%d / %s" % [p.get_overall(), YouthDevelopment.potential_text(ac, p)]]), 18, UIKit.GOLD))
	var ready := p.get_overall() >= _first_team_benchmark(p) - 3
	panel.add_child(UIKit.label(Loc.t("YOUTH_READY") if ready else Loc.t("YOUTH_NOT_READY"), 15, UIKit.GOLD if ready else UIKit.MUTED))
	var rival := _best_at_position(p)
	if rival != null:
		panel.add_child(UIKit.muted(Loc.f("YOUTH_COMPARE", [rival.display_name, rival.get_overall(), rival.age, p.get_overall() - rival.get_overall()])))
	var prog: Array = (YouthDevelopment.state(ac)["progress"] as Dictionary).get(p.id, [])
	if prog.size() >= 2:
		panel.add_child(UIKit.muted(Loc.t("YOUTH_PROGRESS_CHART")))
		panel.add_child(SparkChart.new(prog))
	for attr in PlayerData.ATTRIBUTES:
		if attr != "goalkeeping" or p.position == PlayerData.Position.GK:
			panel.add_child(UIKit.stat_bar(Loc.enum_name("ATTR", attr), p.get_attribute(attr)))
	panel.add_child(UIKit.muted(Loc.f("PROMO_SQUAD_NUMBER_0_AUTOMATIC_NEXT_FREE", PromotionSystem.next_free_number(db(), app().user_team_id))))
	var row := UIKit.hbox(8)
	var num := SpinBox.new()
	num.min_value = 0
	num.max_value = 99
	num.name = "NumberSpin"
	row.add_child(num)
	var why := PromotionSystem.why_not(db(), ac, p.id)
	var btn := UIKit.button(Loc.t("COMMON_PROMOTE_TO_FIRST_TEAM"), _confirm.bind(num), 220)
	btn.name = "PromoteButton"
	btn.disabled = why != ""
	btn.tooltip_text = ErrorText.localize(why, db()) if why != "" else ""
	row.add_child(btn)
	panel.add_child(row)
	var details := UIKit.panel(panel)
	details.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(details)


func _pick(row: int, players: Array) -> void:
	_selected = (players[row] as PlayerData).id
	params["player_id"] = _selected
	rebuild()


func _confirm(num: SpinBox) -> void:
	var number := int(num.value)
	UIKit.confirm(self, Loc.t("PROMO_PROMOTE_THIS_PLAYER_TO_THE_FIRST_T"), _promote.bind(number))


## Best first-team player in the prospect's position (null when none).
func _best_at_position(p: PlayerData) -> PlayerData:
	var best: PlayerData = null
	for s in db().get_squad(app().user_team_id):
		if s.position == p.position and (best == null or s.get_overall() > best.get_overall()):
			best = s
	return best


## Rating of a regular starter in this position (the best player there, else the squad average).
func _first_team_benchmark(p: PlayerData) -> int:
	var best := _best_at_position(p)
	if best != null:
		return best.get_overall()
	var sq: Array = db().get_squad(app().user_team_id)
	var s := 0
	for x in sq:
		s += (x as PlayerData).get_overall()
	return s / maxi(sq.size(), 1)


func promote_selected(number: int = 0) -> String:
	## Direct (non-dialog) entry point, also used by tests.
	return _promote(number)


func _promote(number: int) -> String:
	var pid := _selected
	var err := PromotionSystem.promote(db(), app().academy(), pid, -1 if number == 0 else number)
	if err == "":
		say(Loc.f("PROMO_JOINED_THE_FIRST_TEAM", db().get_player(pid).display_name))
		_selected = ""
		params.erase("player_id")
	else:
		say(err, true)
	rebuild()
	return err
