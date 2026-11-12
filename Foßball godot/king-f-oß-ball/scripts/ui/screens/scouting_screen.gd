extends HubScreen

## Youth Scouting: send scouts to regions, follow missions, read reports and
## sign the prospects you like.

var _region := 0
var _weeks := 3
var _scout := 0


func build() -> void:
	if not header("Youth Scouting", true):
		return
	var ac: Academy = app().academy()
	var sc: ScoutingSystem = app().scouting.get(app().user_team_id)
	if ac == null or sc == null:
		add_child(UIKit.empty_state("Only clubs can scout."))
		return
	add_child(UIKit.label("Academy budget: %d" % ac.budget, 16))
	var regions: Array = YouthGenerator.NAME_POOLS.keys()
	var scout_ids: Array = sc.scouts.keys()
	var form := UIKit.hbox(8)
	form.add_child(UIKit.label("Scout", 14, UIKit.MUTED))
	var so := UIKit.option(scout_ids.map(func(id: String) -> String:
			return "%s (q%.0f%%, %d/wk)" % [sc.scouts[id]["name"], sc.scouts[id]["quality"] * 100.0, sc.scouts[id]["weekly_cost"]]),
			_scout, func(i: int) -> void: _scout = i)
	so.name = "ScoutOption"
	form.add_child(so)
	form.add_child(UIKit.label("Region", 14, UIKit.MUTED))
	var ro := UIKit.option(regions, _region, func(i: int) -> void: _region = i)
	ro.name = "RegionOption"
	form.add_child(ro)
	form.add_child(UIKit.label("Weeks", 14, UIKit.MUTED))
	var wk := SpinBox.new()
	wk.min_value = 1
	wk.max_value = ScoutingSystem.MAX_WEEKS
	wk.value = _weeks
	wk.value_changed.connect(func(v: float) -> void: _weeks = int(v))
	wk.name = "WeeksSpin"
	form.add_child(wk)
	var go_btn := UIKit.button("Send scout", _start.bind(scout_ids, regions), 120)
	go_btn.name = "SendScout"
	form.add_child(go_btn)
	var adv := UIKit.button("Advance week", _advance, 140)
	adv.name = "AdvanceWeek"
	form.add_child(adv)
	add_child(form)
	add_child(UIKit.label("Active missions", 16, UIKit.GOLD))
	if sc.missions.is_empty():
		add_child(UIKit.muted("No scout is on a mission."))
	for m in sc.missions:
		add_child(UIKit.label("%s → %s: %d week(s) left" % [sc.scouts[m["scout_id"]]["name"], m["region"], m["weeks_left"]], 15))
	add_child(UIKit.label("Discovered prospects", 16, UIKit.GOLD))
	if sc.pool.is_empty():
		add_child(UIKit.empty_state("No prospects found yet. Send a scout and advance weeks."))
		return
	for pid in sc.pool:
		var p: PlayerData = db().get_player(pid)
		var rep: Dictionary = sc.reports.get(pid, {})
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label("%s · %s · age %d · now %d" % [p.display_name, PlayerData.Position.keys()[p.position], p.age, p.get_overall()], 15))
		row.add_child(UIKit.label("Est. potential %d ±%d" % [rep.get("estimate", 0), rep.get("margin", 0)], 15, UIKit.GOLD))
		row.add_child(UIKit.label("cost %d" % sc.signing_cost(p), 14, UIKit.MUTED))
		var sign_btn := UIKit.button("Sign", _sign.bind(pid), 70)
		sign_btn.name = "Sign_%s" % pid
		row.add_child(sign_btn)
		add_child(row)
	add_child(UIKit.label("Discovery history: %d prospects found" % sc.history.size(), 13, UIKit.MUTED))


func _start(scout_ids: Array, regions: Array) -> void:
	var err: String = app().scouting[app().user_team_id].start_mission(app().academy(), scout_ids[_scout], regions[_region], _weeks)
	say(err if err != "" else "Scout sent to %s" % regions[_region], err != "")
	rebuild()


func _advance() -> void:
	var info: Dictionary = app().advance_week()    # the career calendar is the only clock
	if info.is_empty():
		say("Start a career first", true)
		return
	var found: Array = info["found_ids"]
	say("%d prospect(s) discovered" % found.size() if not found.is_empty() else "Week passed")
	rebuild()


func _sign(pid: String) -> void:
	var err: String = app().scouting[app().user_team_id].sign_prospect(db(), app().academy(), pid)
	say(err if err != "" else "Prospect signed to the academy", err != "")
	rebuild()
