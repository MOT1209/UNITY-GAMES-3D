extends HubScreen

## Player Profile: identity, attributes, development, contract and history.


func build() -> void:
	if not header("Player Profile"):
		return
	var p: PlayerData = db().get_player(str(params.get("player_id", "")))
	if p == null:
		add_child(UIKit.empty_state("Open a player from a squad or academy list."))
		return
	var top := UIKit.hbox(20)
	var info := UIKit.vbox(2)
	info.add_child(UIKit.label(p.display_name, 26, UIKit.GOLD))
	info.add_child(UIKit.muted("%s · age %d · %s · %s foot" % [PlayerData.Position.keys()[p.position], p.age,
			p.nationality, PlayerData.Foot.keys()[p.preferred_foot].to_lower()]))
	info.add_child(UIKit.label("Overall %d · Potential %d" % [p.get_overall(), p.potential], 18))
	var team: TeamData = db().get_team(p.team_id)
	info.add_child(UIKit.label("Club: %s%s" % [team.display_name if team != null else "free agent",
			" (on loan from %s)" % p.loan_parent if p.loan_parent != "" else ""], 15))
	info.add_child(UIKit.label("Status %s · fitness %d · morale %d · experience %d" % [
			PlayerData.Status.keys()[p.status], p.fitness, p.morale, p.experience], 14, UIKit.MUTED))
	if p.status != PlayerData.Status.YOUTH:
		info.add_child(UIKit.label("Shirt %d · contract %d yr · wage %d/wk · value %d" % [
				p.shirt_number, p.contract_years, p.salary, p.transfer_value], 14, UIKit.MUTED))
	if not p.traits.is_empty():
		info.add_child(UIKit.label("Traits: %s" % ", ".join(p.traits), 14, UIKit.GOLD))
	top.add_child(info)
	var bars := UIKit.vbox(3)
	for attr in PlayerData.ATTRIBUTES:
		if attr == "goalkeeping" and p.position != PlayerData.Position.GK:
			continue
		bars.add_child(UIKit.stat_bar(attr.capitalize(), p.get_attribute(attr)))
	top.add_child(bars)
	add_child(UIKit.panel(top))
	if p.status == PlayerData.Status.YOUTH and app().academy() != null and p.id in app().academy().roster_ids:
		var why := PromotionSystem.why_not(db(), app().academy(), p.id)
		var btn := UIKit.button("Promote to first team", go.bind("promotion", {"player_id": p.id}), 220)
		btn.disabled = why != ""
		btn.tooltip_text = why
		add_child(btn)
	add_child(UIKit.label("Development history", 16, UIKit.GOLD))
	if p.development_history.is_empty():
		add_child(UIKit.muted("No history yet."))
	var recent: Array = p.development_history.slice(-10)
	recent.reverse()
	for h in recent:
		add_child(UIKit.muted(_describe(h)))


func _describe(h: Dictionary) -> String:
	match str(h.get("event", "")):
		"train":
			return "Week %d: %s %d → %d" % [int(h.get("week", 0)), str(h["attribute"]), int(h["from"]), int(h["to"])]
		"promoted":
			return "Promoted to the first team (age %d, shirt %d)" % [int(h.get("age", 0)), int(h.get("shirt_number", 0))]
		"generated":
			return "Entered the academy at age %d (overall %d)" % [int(h.get("age", 0)), int(h.get("overall", 0))]
		_:
			return str(h.get("event", "event"))
