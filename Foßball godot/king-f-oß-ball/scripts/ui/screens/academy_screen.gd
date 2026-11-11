extends HubScreen

## Youth Academy dashboard: roster per age group, budget, facilities, intake,
## and a confirmed release action.

const FACILITY_COST := 250000
const MAX_QUALITY := 0.95


func build() -> void:
	if not header("Youth Academy", true):
		return
	var ac: Academy = app().academy()
	if ac == null:
		add_child(UIKit.empty_state("National teams have no academy. Manage a club."))
		return
	var top := UIKit.hbox(24)
	top.add_child(UIKit.label("Budget: %d" % ac.budget, 18))
	top.add_child(UIKit.label("Facilities: %d%%" % roundi(ac.quality * 100.0), 18))
	top.add_child(UIKit.label("Prospects: %d" % ac.roster_ids.size(), 18))
	add_child(UIKit.panel(top))
	var actions := UIKit.hbox(8)
	var intake := UIKit.button("Generate intake (5)", _intake, 190)
	intake.name = "IntakeButton"
	actions.add_child(intake)
	var up := UIKit.button("Upgrade facilities (%d)" % FACILITY_COST, _upgrade, 230)
	up.name = "UpgradeButton"
	up.disabled = ac.quality >= MAX_QUALITY
	actions.add_child(up)
	add_child(actions)
	add_child(UIKit.muted("Better facilities raise scouting reliability, training speed and prospect potential."))
	if ac.roster_ids.is_empty():
		add_child(UIKit.empty_state("The academy is empty. Generate an intake or scout prospects."))
		return
	for group in AcademyConfig.group_ids():
		var players := ac.group_players(db(), group)
		add_child(UIKit.label("%s  (%d/%d)" % [group, players.size(), AcademyConfig.capacity(group)], 18, UIKit.GOLD))
		if players.is_empty():
			add_child(UIKit.muted("No players in this group."))
			continue
		players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.potential > b.potential)
		var rows: Array = []
		for p in players:
			rows.append([p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p), ", ".join(p.traits)])
		add_child(UIKit.table(["Name", "Pos", "Age", "OVR/POT", "Traits"], rows, _open.bind(players)))


func _open(row: int, players: Array) -> void:
	go("player_profile", {"player_id": (players[row] as PlayerData).id})


func _intake() -> void:
	var made: Array = app().academy().generate_intake(db(), 5)
	say("%d new prospects joined" % made.size() if not made.is_empty() else "Age groups are full — no new prospects", made.is_empty())
	rebuild()


func _upgrade() -> void:
	var ac: Academy = app().academy()
	if ac.budget < FACILITY_COST:
		say("Not enough academy budget (%d needed)" % FACILITY_COST, true)
		return
	ac.budget -= FACILITY_COST
	ac.quality = minf(ac.quality + 0.05, MAX_QUALITY)
	say("Facilities upgraded")
	rebuild()
