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
	var over := ac.over_age_ids(db())
	var kept := ac.extended_players(db())
	if not over.is_empty() or not kept.is_empty():
		_over_age_section(ac, over, kept)
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


## Over-Age Prospects: players too old for every age group. Each one needs a
## decision, so nobody becomes unreachable.
func _over_age_section(ac: Academy, over: Array[String], kept: Array[PlayerData]) -> void:
	var heading := UIKit.label("Over-Age Prospects (%d)" % over.size(), 18, UIKit.BAD)
	heading.name = "OverAgeHeading"
	add_child(heading)
	add_child(UIKit.muted("Too old for the age groups. Promote to the first team, release, or keep for further development (until age %d)." % AcademyConfig.MAX_EXTENDED_AGE))
	for pid in over:
		_over_age_row(ac, db().get_player(pid), true)
	if not kept.is_empty():
		add_child(UIKit.label("Extended development (%d)" % kept.size(), 16, UIKit.GOLD))
		for p in kept:
			_over_age_row(ac, p, false)


func _over_age_row(ac: Academy, p: PlayerData, can_keep: bool) -> void:
	var row := UIKit.hbox(10)
	row.add_child(UIKit.label("%s · %s · age %d · %s" % [p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p)], 15))
	var pro := UIKit.button("Promote", _over_age_promote.bind(p.id), 100)
	pro.name = "OverAgePromote_%s" % p.id
	pro.disabled = PromotionSystem.why_not(db(), ac, p.id) != ""
	row.add_child(pro)
	var rel := UIKit.button("Release", _over_age_release.bind(p.id), 100)
	rel.name = "OverAgeRelease_%s" % p.id
	row.add_child(rel)
	if can_keep:
		var keep := UIKit.button("Keep", _over_age_keep.bind(p.id), 80)
		keep.name = "OverAgeKeep_%s" % p.id
		keep.disabled = p.age > AcademyConfig.MAX_EXTENDED_AGE
		row.add_child(keep)
	add_child(row)


func _over_age_promote(pid: String) -> void:
	var err := PromotionSystem.promote(db(), app().academy(), pid)
	say(err if err != "" else "Promoted to the first team", err != "")
	rebuild()


func _over_age_release(pid: String) -> void:
	UIKit.confirm(self, "Release this player from the academy? He becomes a free agent.", _do_over_age_release.bind(pid))


func _do_over_age_release(pid: String) -> void:
	var err := PromotionSystem.release_youth(db(), app().academy(), pid)
	say(err if err != "" else "Player released", err != "")
	rebuild()


func _over_age_keep(pid: String) -> void:
	var err: String = app().academy().keep_extended(db(), pid)
	say(err if err != "" else "Kept in the academy for further development", err != "")
	rebuild()


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
