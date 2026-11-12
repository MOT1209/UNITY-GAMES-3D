extends HubScreen

## Player Profile: identity, attributes, development, contract and history.


func build() -> void:
	if not header(Loc.t("PROFILE_PLAYER_PROFILE")):
		return
	var p: PlayerData = db().get_player(str(params.get("player_id", "")))
	if p == null:
		add_child(UIKit.empty_state(Loc.t("PROFILE_OPEN_A_PLAYER_FROM_A_SQUAD_OR_ACAD")))
		return
	var top := UIKit.hbox(20)
	var info := UIKit.vbox(2)
	info.add_child(UIKit.label(p.display_name, 26, UIKit.GOLD))
	info.add_child(UIKit.muted(Loc.f("PROFILE_AGE_FOOT", [PlayerData.Position.keys()[p.position], p.age,
			p.nationality, Loc.enum_name("FOOT", PlayerData.Foot.keys()[p.preferred_foot])])))
	info.add_child(UIKit.label(Loc.f("PROFILE_OVERALL_POTENTIAL", [p.get_overall(), p.potential]), 18))
	var team: TeamData = db().get_team(p.team_id)
	info.add_child(UIKit.label(Loc.f("PROFILE_CLUB", [team.display_name if team != null else Loc.t("PROFILE_FREE_AGENT"),
			Loc.f("PROFILE_ON_LOAN_FROM", p.loan_parent) if p.loan_parent != "" else ""]), 15))
	info.add_child(UIKit.label(Loc.f("PROFILE_STATUS_FITNESS_MORALE_EXPERIENCE", [
			Loc.enum_name("STATUS", PlayerData.Status.keys()[p.status]), p.fitness, p.morale, p.experience]), 14, UIKit.MUTED))
	if p.status != PlayerData.Status.YOUTH:
		info.add_child(UIKit.label(Loc.f("PROFILE_SHIRT_CONTRACT_YR_WAGE_WK_VALUE", [
				p.shirt_number, p.contract_years, p.salary, p.transfer_value]), 14, UIKit.MUTED))
	if not p.traits.is_empty():
		info.add_child(UIKit.label(Loc.f("PROFILE_TRAITS", Loc.traits_text(p.traits)), 14, UIKit.GOLD))
	top.add_child(info)
	var bars := UIKit.vbox(3)
	for attr in PlayerData.ATTRIBUTES:
		if attr == "goalkeeping" and p.position != PlayerData.Position.GK:
			continue
		bars.add_child(UIKit.stat_bar(Loc.enum_name("ATTR", attr), p.get_attribute(attr)))
	top.add_child(bars)
	add_child(UIKit.panel(top))
	if p.status == PlayerData.Status.YOUTH and app().academy() != null and p.id in app().academy().roster_ids:
		var why := PromotionSystem.why_not(db(), app().academy(), p.id)
		var btn := UIKit.button(Loc.t("COMMON_PROMOTE_TO_FIRST_TEAM"), go.bind("promotion", {"player_id": p.id}), 220)
		btn.disabled = why != ""
		btn.tooltip_text = why
		add_child(btn)
	add_child(UIKit.label(Loc.t("PROFILE_DEVELOPMENT_HISTORY"), 16, UIKit.GOLD))
	if p.development_history.is_empty():
		add_child(UIKit.muted(Loc.t("PROFILE_NO_HISTORY_YET")))
	var recent: Array = p.development_history.slice(-10)
	recent.reverse()
	for h in recent:
		add_child(UIKit.muted(_describe(h)))


func _describe(h: Dictionary) -> String:
	match str(h.get("event", "")):
		"train":
			return Loc.f("PROFILE_HIST_TRAIN", [int(h.get("week", 0)), Loc.enum_name("ATTR", str(h["attribute"])), int(h["from"]), int(h["to"])])
		"promoted":
			return Loc.f("PROFILE_HIST_PROMOTED", [int(h.get("age", 0)), int(h.get("shirt_number", 0))])
		"generated":
			return Loc.f("PROFILE_HIST_ENTERED", [int(h.get("age", 0)), int(h.get("overall", 0))])
		_:
			return str(h.get("event", "event"))
