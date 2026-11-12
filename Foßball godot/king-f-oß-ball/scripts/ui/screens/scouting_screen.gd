extends HubScreen

## Youth Scouting: send scouts to regions, follow missions, read reports and
## sign the prospects you like.

var _region := 0
var _weeks := 3
var _scout := 0


func build() -> void:
	if not header(Loc.t("SCOUT_YOUTH_SCOUTING"), true):
		return
	var ac: Academy = app().academy()
	var sc: ScoutingSystem = app().scouting.get(app().user_team_id)
	if ac == null or sc == null:
		add_child(UIKit.empty_state(Loc.t("SCOUT_ONLY_CLUBS_CAN_SCOUT")))
		return
	add_child(UIKit.label(Loc.f("SCOUT_ACADEMY_BUDGET", ac.budget), 16))
	var regions: Array = YouthGenerator.NAME_POOLS.keys()
	var scout_ids: Array = sc.scouts.keys()
	var form := UIKit.hbox(8)
	form.add_child(UIKit.label(Loc.t("SCOUT_SCOUT"), 14, UIKit.MUTED))
	var so := UIKit.option(scout_ids.map(func(id: String) -> String:
			return Loc.f("SCOUT_SCOUT_OPTION", [sc.scouts[id]["name"], sc.scouts[id]["quality"] * 100.0, sc.scouts[id]["weekly_cost"]])),
			_scout, func(i: int) -> void: _scout = i)
	so.name = "ScoutOption"
	form.add_child(so)
	form.add_child(UIKit.label(Loc.t("SCOUT_REGION"), 14, UIKit.MUTED))
	var ro := UIKit.option(regions, _region, func(i: int) -> void: _region = i)
	ro.name = "RegionOption"
	form.add_child(ro)
	form.add_child(UIKit.label(Loc.t("SCOUT_WEEKS"), 14, UIKit.MUTED))
	var wk := SpinBox.new()
	wk.min_value = 1
	wk.max_value = ScoutingSystem.MAX_WEEKS
	wk.value = _weeks
	wk.value_changed.connect(func(v: float) -> void: _weeks = int(v))
	wk.name = "WeeksSpin"
	form.add_child(wk)
	var go_btn := UIKit.button(Loc.t("SCOUT_SEND_SCOUT"), _start.bind(scout_ids, regions), 120)
	go_btn.name = "SendScout"
	form.add_child(go_btn)
	var adv := UIKit.button(Loc.t("COMMON_ADVANCE_WEEK"), _advance, 140)
	adv.name = "AdvanceWeek"
	form.add_child(adv)
	add_child(form)
	add_child(UIKit.label(Loc.t("SCOUT_ACTIVE_MISSIONS"), 16, UIKit.GOLD))
	if sc.missions.is_empty():
		add_child(UIKit.muted(Loc.t("SCOUT_NO_SCOUT_IS_ON_A_MISSION")))
	for m in sc.missions:
		add_child(UIKit.label(Loc.f("SCOUT_WEEK_S_LEFT", [sc.scouts[m["scout_id"]]["name"], m["region"], m["weeks_left"]]), 15))
	add_child(UIKit.label(Loc.t("SCOUT_DISCOVERED_PROSPECTS"), 16, UIKit.GOLD))
	if sc.pool.is_empty():
		add_child(UIKit.empty_state(Loc.t("SCOUT_NO_PROSPECTS_FOUND_YET_SEND_A_SCOU")))
		return
	for pid in sc.pool:
		var p: PlayerData = db().get_player(pid)
		var rep: Dictionary = sc.reports.get(pid, {})
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label(Loc.f("SCOUT_AGE_NOW", [p.display_name, PlayerData.Position.keys()[p.position], p.age, p.get_overall()]), 15))
		row.add_child(UIKit.label(Loc.f("SCOUT_EST_POTENTIAL", [rep.get("estimate", 0), rep.get("margin", 0)]), 15, UIKit.GOLD))
		row.add_child(UIKit.label(Loc.f("SCOUT_COST", sc.signing_cost(p)), 14, UIKit.MUTED))
		var sign_btn := UIKit.button(Loc.t("SCOUT_SIGN"), _sign.bind(pid), 70)
		sign_btn.name = "Sign_%s" % pid
		row.add_child(sign_btn)
		add_child(row)
	add_child(UIKit.label(Loc.f("SCOUT_DISCOVERY_HISTORY_PROSPECTS_FOUND", sc.history.size()), 13, UIKit.MUTED))


func _start(scout_ids: Array, regions: Array) -> void:
	var err: String = app().scouting[app().user_team_id].start_mission(app().academy(), scout_ids[_scout], regions[_region], _weeks)
	say(err if err != "" else Loc.f("SCOUT_SCOUT_SENT_TO", regions[_region]), err != "")
	rebuild()


func _advance() -> void:
	var info: Dictionary = app().advance_week()    # the career calendar is the only clock
	if info.is_empty():
		say(Loc.t("COMMON_START_A_CAREER_FIRST"), true)
		return
	var found: Array = info["found_ids"]
	say(Loc.f("SCOUT_PROSPECT_S_DISCOVERED", found.size()) if not found.is_empty() else Loc.t("SCOUT_WEEK_PASSED"))
	rebuild()


func _sign(pid: String) -> void:
	var err: String = app().scouting[app().user_team_id].sign_prospect(db(), app().academy(), pid)
	say(err if err != "" else Loc.t("SCOUT_PROSPECT_SIGNED_TO_THE_ACADEMY"), err != "")
	rebuild()
