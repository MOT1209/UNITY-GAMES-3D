extends HubScreen

## Promotion: choose an academy player, inspect him, assign a squad number and
## promote him to the first team (confirmed). Uses `PromotionSystem`.

var _selected := ""


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
		rows.append([p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p), Loc.t("PROMO_READY") if why == "" else why])
	add_child(UIKit.label(Loc.t("PROMO_ACADEMY_PLAYERS"), 16, UIKit.GOLD))
	add_child(UIKit.scroll(UIKit.table([Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT"), Loc.t("PROMO_ELIGIBILITY")], rows, _pick.bind(players))))
	if _selected == "" or not (_selected in ac.roster_ids):
		add_child(UIKit.muted(Loc.t("PROMO_SELECT_A_PLAYER_WITH_OPEN_TO_REVIE")))
		return
	var p: PlayerData = db().get_player(_selected)
	var panel := UIKit.vbox(6)
	panel.add_child(UIKit.label(Loc.f("PROMO_AGE", [p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p)]), 18, UIKit.GOLD))
	for attr in PlayerData.ATTRIBUTES:
		if attr != "goalkeeping" or p.position == PlayerData.Position.GK:
			panel.add_child(UIKit.stat_bar(Loc.enum_name("ATTR", attr), p.get_attribute(attr)))
	var row := UIKit.hbox(8)
	row.add_child(UIKit.label(Loc.f("PROMO_SQUAD_NUMBER_0_AUTOMATIC_NEXT_FREE", PromotionSystem.next_free_number(db(), app().user_team_id)), 14, UIKit.MUTED))
	var num := SpinBox.new()
	num.min_value = 0
	num.max_value = 99
	num.name = "NumberSpin"
	row.add_child(num)
	var why := PromotionSystem.why_not(db(), ac, p.id)
	var btn := UIKit.button(Loc.t("COMMON_PROMOTE_TO_FIRST_TEAM"), _confirm.bind(num), 220)
	btn.name = "PromoteButton"
	btn.disabled = why != ""
	btn.tooltip_text = why
	row.add_child(btn)
	panel.add_child(row)
	add_child(UIKit.panel(panel))


func _pick(row: int, players: Array) -> void:
	_selected = (players[row] as PlayerData).id
	params["player_id"] = _selected
	rebuild()


func _confirm(num: SpinBox) -> void:
	var number := int(num.value)
	UIKit.confirm(self, Loc.t("PROMO_PROMOTE_THIS_PLAYER_TO_THE_FIRST_T"), _promote.bind(number))


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
