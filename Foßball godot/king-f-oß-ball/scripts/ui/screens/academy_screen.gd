extends HubScreen

## Youth Academy dashboard: roster per age group, budget, facilities, intake,
## and a confirmed release action.

const FACILITY_COST := 250000
const MAX_QUALITY := 0.95


func build() -> void:
	if not header(Loc.t("ACADEMY_YOUTH_ACADEMY"), true):
		return
	var ac: Academy = app().academy()
	if ac == null:
		add_child(UIKit.empty_state(Loc.t("ACADEMY_NATIONAL_TEAMS_HAVE_NO_ACADEMY_MAN")))
		return
	var top := UIKit.hbox(24)
	top.add_child(UIKit.label(Loc.f("ACADEMY_BUDGET", ac.budget), 18))
	top.add_child(UIKit.label(Loc.f("ACADEMY_FACILITIES", roundi(ac.quality * 100.0)), 18))
	top.add_child(UIKit.label(Loc.f("ACADEMY_PROSPECTS", ac.roster_ids.size()), 18))
	add_child(UIKit.panel(top))
	var actions := UIKit.hbox(8)
	var intake := UIKit.button(Loc.t("ACADEMY_GENERATE_INTAKE_5"), _intake, 190)
	intake.name = "IntakeButton"
	actions.add_child(intake)
	var up := UIKit.button(Loc.f("ACADEMY_UPGRADE_FACILITIES", FACILITY_COST), _upgrade, 230)
	up.name = "UpgradeButton"
	up.disabled = ac.quality >= MAX_QUALITY
	actions.add_child(up)
	add_child(actions)
	add_child(UIKit.muted(Loc.t("ACADEMY_BETTER_FACILITIES_RAISE_SCOUTING_R")))
	if ac.roster_ids.is_empty():
		add_child(UIKit.empty_state(Loc.t("ACADEMY_THE_ACADEMY_IS_EMPTY_GENERATE_AN_I")))
		return
	var over := ac.over_age_ids(db())
	var kept := ac.extended_players(db())
	if not over.is_empty() or not kept.is_empty():
		_over_age_section(ac, over, kept)
	for group in AcademyConfig.group_ids():
		var players := ac.group_players(db(), group)
		add_child(UIKit.label("%s  (%d/%d)" % [group, players.size(), AcademyConfig.capacity(group)], 18, UIKit.GOLD))
		if players.is_empty():
			add_child(UIKit.muted(Loc.t("ACADEMY_NO_PLAYERS_IN_THIS_GROUP")))
			continue
		players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.potential > b.potential)
		var rows: Array = []
		for p in players:
			rows.append([p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p), Loc.traits_text(p.traits)])
		add_child(_group_cards(players))
		add_child(UIKit.table([Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT"), Loc.t("ACADEMY_TRAITS")], rows, _open.bind(players)))


## Over-Age Prospects: players too old for every age group. Each one needs a
## decision, so nobody becomes unreachable.
func _over_age_section(ac: Academy, over: Array[String], kept: Array[PlayerData]) -> void:
	var heading := UIKit.label(Loc.f("ACADEMY_OVER_AGE_PROSPECTS", over.size()), 18, UIKit.BAD)
	heading.name = "OverAgeHeading"
	add_child(heading)
	add_child(UIKit.muted(Loc.f("ACADEMY_TOO_OLD_FOR_THE_AGE_GROUPS_PROMOTE", AcademyConfig.MAX_EXTENDED_AGE)))
	for pid in over:
		_over_age_row(ac, db().get_player(pid), true)
	if not kept.is_empty():
		add_child(UIKit.label(Loc.f("ACADEMY_EXTENDED_DEVELOPMENT", kept.size()), 16, UIKit.GOLD))
		for p in kept:
			_over_age_row(ac, p, false)


func _over_age_row(ac: Academy, p: PlayerData, can_keep: bool) -> void:
	var row := UIKit.hbox(10)
	row.add_child(UIKit.label(Loc.f("ACADEMY_AGE", [p.display_name, PlayerData.Position.keys()[p.position], p.age, overall_text(p)]), 15))
	var pro := UIKit.button(Loc.t("ACADEMY_PROMOTE"), _over_age_promote.bind(p.id), 100)
	pro.name = "OverAgePromote_%s" % p.id
	pro.disabled = PromotionSystem.why_not(db(), ac, p.id) != ""
	row.add_child(pro)
	var rel := UIKit.button(Loc.t("ACADEMY_RELEASE"), _over_age_release.bind(p.id), 100)
	rel.name = "OverAgeRelease_%s" % p.id
	row.add_child(rel)
	if can_keep:
		var keep := UIKit.button(Loc.t("ACADEMY_KEEP"), _over_age_keep.bind(p.id), 80)
		keep.name = "OverAgeKeep_%s" % p.id
		keep.disabled = p.age > AcademyConfig.MAX_EXTENDED_AGE
		row.add_child(keep)
	add_child(row)


func _over_age_promote(pid: String) -> void:
	var err := PromotionSystem.promote(db(), app().academy(), pid)
	say(err if err != "" else Loc.t("ACADEMY_PROMOTED_TO_THE_FIRST_TEAM"), err != "")
	rebuild()


func _over_age_release(pid: String) -> void:
	UIKit.confirm(self, Loc.t("ACADEMY_RELEASE_THIS_PLAYER_FROM_THE_ACADE"), _do_over_age_release.bind(pid))


func _do_over_age_release(pid: String) -> void:
	var err := PromotionSystem.release_youth(db(), app().academy(), pid)
	say(err if err != "" else Loc.t("ACADEMY_PLAYER_RELEASED"), err != "")
	rebuild()


func _over_age_keep(pid: String) -> void:
	var err: String = app().academy().keep_extended(db(), pid)
	say(err if err != "" else Loc.t("ACADEMY_KEPT_IN_THE_ACADEMY_FOR_FURTHER_DE"), err != "")
	rebuild()


func _open(row: int, players: Array) -> void:
	go("player_profile", {"player_id": (players[row] as PlayerData).id})


func _intake() -> void:
	var made: Array = app().academy().generate_intake(db(), 5)
	say(Loc.f("ACADEMY_NEW_PROSPECTS_JOINED", made.size()) if not made.is_empty() else Loc.t("ACADEMY_AGE_GROUPS_ARE_FULL_NO_NEW_PROSPEC"), made.is_empty())
	rebuild()


func _upgrade() -> void:
	var ac: Academy = app().academy()
	if ac.budget < FACILITY_COST:
		say(Loc.f("ACADEMY_NOT_ENOUGH_ACADEMY_BUDGET_NEEDED", FACILITY_COST), true)
		return
	ac.budget -= FACILITY_COST
	ac.quality = minf(ac.quality + 0.05, MAX_QUALITY)
	say(Loc.t("ACADEMY_FACILITIES_UPGRADED"))
	rebuild()


## Cards of one age group: portrait, real attributes and class of each prospect.
## Promotion keeps the same PlayerData (id, appearance, history), so the card
## looks identical after the player joins the first team.
func _group_cards(players: Array[PlayerData]) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "ProspectCards"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for p in players:
		var card := PlayerCard.new(110.0)
		card.name = "Card_%s" % p.id
		card.setup(PlayerCardData.from_data(db(), p), db())
		card.pressed.connect(func(id: String) -> void: go("player_profile", {"player_id": id}))
		flow.add_child(card)
	return flow
