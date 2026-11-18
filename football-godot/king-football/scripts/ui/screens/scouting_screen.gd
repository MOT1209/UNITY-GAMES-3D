extends HubScreen

## Youth Scouting: send scouts to regions, follow missions, read reports and
## sign the prospects you like.

var _region := 0
var _position := 0                  # 0 = any, else index into PlayerData.Position.keys() + 1
var _objective := 0
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
	var regions: Array = ScoutingSystem.regions(db())          # every country in the game, plus worldwide
	var scout_ids: Array = sc.scouts.keys()
	_scout = clampi(_scout, 0, maxi(scout_ids.size() - 1, 0))
	# Flow layout: the toolbar wraps onto a second line instead of pushing "Next week" off-screen.
	var form := HFlowContainer.new()
	form.name = "ScoutToolbar"
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	form.add_child(UIKit.label(Loc.t("SCOUT_SCOUT"), 14, UIKit.MUTED))
	var so := UIKit.option(scout_ids.map(func(id: String) -> String:
			return Loc.f("SCOUT_SCOUT_OPTION", [scout_name(id, sc.scouts[id]["name"]), sc.scouts[id]["quality"] * 100.0, sc.scouts[id]["weekly_cost"]])),
			_scout, func(i: int) -> void: _scout = i)
	so.name = "ScoutOption"
	form.add_child(so)
	form.add_child(UIKit.label(Loc.t("SCOUT_REGION"), 14, UIKit.MUTED))
	var ro := UIKit.option(regions.map(func(r: String) -> String: return Loc.t("SCOUT_WORLDWIDE") if r == ScoutingSystem.WORLDWIDE else Loc.country(r)), _region, func(i: int) -> void: _region = i)
	ro.name = "RegionOption"
	form.add_child(ro)
	form.add_child(UIKit.label(Loc.t("SCOUT_POSITION"), 14, UIKit.MUTED))
	var po := UIKit.option([Loc.t("SCOUT_ANY_POSITION")] + PlayerData.Position.keys().map(func(k: String) -> String: return Loc.position_code(int(PlayerData.Position[k]))), _position, func(i: int) -> void: _position = i)
	po.name = "PositionOption"
	form.add_child(po)
	form.add_child(UIKit.label(Loc.t("SCOUT_OBJECTIVE"), 14, UIKit.MUTED))
	var oo := UIKit.option(ScoutingSystem.OBJECTIVES.map(func(o: String) -> String: return Loc.t("SCOUT_OBJ_" + o.to_upper())), _objective, func(i: int) -> void: _objective = i)
	oo.name = "ObjectiveOption"
	form.add_child(oo)
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
	_staff_section(sc, ac)
	add_child(UIKit.label(Loc.t("SCOUT_ACTIVE_MISSIONS"), 16, UIKit.GOLD))
	if sc.missions.is_empty():
		add_child(UIKit.muted(Loc.t("SCOUT_NO_SCOUT_IS_ON_A_MISSION")))
	for m in sc.missions:
		add_child(UIKit.label(Loc.f("SCOUT_WEEK_S_LEFT", [scout_name(m["scout_id"], sc.scouts[m["scout_id"]]["name"]), (Loc.t("SCOUT_WORLDWIDE") if m["region"] == ScoutingSystem.WORLDWIDE else Loc.country(m["region"])), m["weeks_left"]]), 15))
	add_child(UIKit.label(Loc.t("SCOUT_DISCOVERED_PROSPECTS"), 16, UIKit.GOLD))
	if sc.pool.is_empty():
		add_child(UIKit.empty_state(Loc.t("SCOUT_NO_PROSPECTS_FOUND_YET_SEND_A_SCOU")))
		return
	for pid in sc.pool:
		var p: PlayerData = db().get_player(pid)
		var rep: Dictionary = sc.reports.get(pid, {})
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label(Loc.f("SCOUT_AGE_NOW", [p.display_name, Loc.position_code(p.position), p.age, p.get_overall()]), 15))
		row.add_child(UIKit.label(Loc.f("SCOUT_EST_POTENTIAL", [rep.get("estimate", 0), rep.get("margin", 0)]), 15, UIKit.GOLD))
		row.add_child(UIKit.label(Loc.f("SCOUT_COST", sc.signing_cost(p)), 14, UIKit.MUTED))
		var sign_btn := UIKit.button(Loc.t("SCOUT_SIGN"), _sign.bind(pid), 70)
		sign_btn.name = "Sign_%s" % pid
		row.add_child(sign_btn)
		add_child(row)
	add_child(UIKit.label(Loc.f("SCOUT_DISCOVERY_HISTORY_PROSPECTS_FOUND", sc.history.size()), 13, UIKit.MUTED))


## Your scouts (dismiss) and the scout market (hire).
func _staff_section(sc: ScoutingSystem, ac: Academy) -> void:
	add_child(UIKit.label(Loc.f("SCOUT_STAFF", [sc.scouts.size(), ScoutingSystem.MAX_SCOUTS]), 16, UIKit.GOLD))
	for id in sc.scouts:
		var s: Dictionary = sc.scouts[id]
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label(Loc.f("SCOUT_SCOUT_OPTION", [scout_name(id, s["name"]), float(s["quality"]) * 100.0, s["weekly_cost"]]), 15))
		var b := UIKit.button(Loc.t("SCOUT_DISMISS"), _dismiss.bind(id), 110)
		b.name = "Dismiss_%s" % id
		b.disabled = sc.is_scout_busy(id) or sc.scouts.size() <= 1
		row.add_child(b)
		add_child(row)
	add_child(UIKit.label(Loc.t("SCOUT_MARKET"), 16, UIKit.GOLD))
	var list := sc.candidates()
	for i in list.size():
		var c: Dictionary = list[i]
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label(Loc.f("SCOUT_SCOUT_OPTION", [c["name"], float(c["quality"]) * 100.0, c["weekly_cost"]]), 15))
		row.add_child(UIKit.label(Loc.f("SCOUT_HIRE_FEE", sc.hire_fee(c)), 14, UIKit.MUTED))
		var b := UIKit.button(Loc.t("SCOUT_HIRE"), _hire.bind(i), 90)
		b.name = "Hire_%d" % i
		b.disabled = sc.scouts.size() >= ScoutingSystem.MAX_SCOUTS or sc.hire_fee(c) > ac.budget
		row.add_child(b)
		add_child(row)


func _hire(i: int) -> void:
	var err: String = app().scouting[app().user_team_id].hire(app().academy(), i)
	say(err if err != "" else Loc.t("SCOUT_HIRED"), err != "")
	rebuild()


func _dismiss(id: String) -> void:
	var err: String = app().scouting[app().user_team_id].dismiss(id)
	say(err if err != "" else Loc.t("SCOUT_DISMISSED"), err != "")
	rebuild()


func _start(scout_ids: Array, regions: Array) -> void:
	var err: String = app().scouting[app().user_team_id].start_mission(app().academy(), scout_ids[_scout], regions[_region], _weeks,
			"" if _position == 0 else str(PlayerData.Position.keys()[_position - 1]), ScoutingSystem.OBJECTIVES[_objective])
	say(err if err != "" else Loc.f("SCOUT_SCOUT_SENT_TO", Loc.t("SCOUT_WORLDWIDE") if regions[_region] == ScoutingSystem.WORLDWIDE else Loc.country(regions[_region])), err != "")
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


## Display name of a scout: the built-in scouts ("scout_a", "scout_b") have translated titles
## (SCOUT_NAME_SCOUT_A ...); scouts added with a custom name show that name.
static func scout_name(scout_id: String, stored: String) -> String:
	var key := "SCOUT_NAME_%s" % scout_id.to_upper()
	return Loc.t(key) if Loc.has_key(key) or Loc.has_key(key, Localization.FALLBACK_LANGUAGE) else stored
