extends HubScreen

## Training center: the week's daily schedule of the managed club (rest / light / medium / intense x focus, match days fixed),
## the coach responsible for each focus, squad fitness and fatigue with a one-click workload change per player.

const FOCUS_DEPT := {"tactics": "tactical", "fitness": "fitness", "technique": "midfield", "set_pieces": "tactical"}
var _stype := 0
var _sday := 0
var _sint := 2
var _sgroup := 0
const DAYS: Array[String] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


func build() -> void:
	if not header(Loc.t("SCREEN_TRAINING_CENTER"), true, true):
		return
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	_schedule(c)
	_sessions(c)
	_squad(c)


func _schedule(c: CareerState) -> void:
	add_child(UIKit.label(Loc.t("DEV_TC_SCHEDULE"), 18, UIKit.GOLD))
	add_child(UIKit.muted(Loc.t("DEV_TC_HINT")))
	var start := CareerDate.jdn_of(c.season, c.week, 0)
	var matches := TrainingPlan.match_days(c)
	for i in 7:
		var jdn := start + i
		var plan := c.training.day_plan(c, jdn, matches)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_child(UIKit.label(Loc.t("DEV_DAY_" + DAYS[i]), 15, UIKit.MUTED))
		if bool(plan["match"]):
			row.add_child(UIKit.label(Loc.t("DEV_TC_MATCH_DAY"), 15))
		else:
			var iv := UIKit.option(TrainingPlan.INTENSITIES.map(func(x: String) -> String: return Loc.t("DEV_INT_" + x.to_upper())), TrainingPlan.INTENSITIES.find(plan["intensity"]), _set_day.bind(jdn, "intensity"))
			iv.name = "Day%d_intensity" % i
			row.add_child(iv)
			var fo := UIKit.option(TrainingPlan.FOCUSES.map(func(x: String) -> String: return Loc.t("DEV_FOCUS_" + x.to_upper())), TrainingPlan.FOCUSES.find(plan["focus"]), _set_day.bind(jdn, "focus"))
			fo.name = "Day%d_focus" % i
			row.add_child(fo)
			row.add_child(UIKit.muted(_coach_text(c, str(plan["focus"]))))
			if not bool(plan["auto"]):
				var b := UIKit.button(Loc.t("DEV_TC_AUTO"), _clear_day.bind(jdn), 110)
				b.name = "Auto_%d" % i
				row.add_child(b)
		add_child(row)


func _coach_text(c: CareerState, focus: String) -> String:
	var dept: String = FOCUS_DEPT.get(focus, "tactical")
	var list := c.development.coaching.in_department(dept)
	if list.is_empty():
		return Loc.f("DEV_TC_NO_COACH", Loc.t("DEV_DEPT_" + dept.to_upper()))
	return Loc.f("DEV_TC_COACH", [list[0]["name"], DevConfig.stars_text(int(list[0]["overall"]))])


func _squad(c: CareerState) -> void:
	add_child(UIKit.label(Loc.t("DEV_TC_SQUAD"), 18, UIKit.GOLD))
	var players: Array = db().get_squad(c.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.fitness < b.fitness)
	for p: PlayerData in players.slice(0, 25):
		var plan := c.development.plans.ensure(p, c.absolute_week())
		var row := UIKit.hbox(8)
		var l := UIKit.label("%s %s" % [p.display_name, Loc.f("DEV_TC_FIT", p.fitness)], 14, UIKit.GOLD if p.fitness < DevConfig.FATIGUE_WARN_FITNESS else UIKit.TEXT)
		l.custom_minimum_size = Vector2(260, 0)
		row.add_child(l)
		row.add_child(UIKit.muted(Loc.f("DEV_TC_LOAD", roundi(float(plan["intensity"]) * 100.0))))
		for spec in [["DEV_TC_LIGHTER", -0.2], ["DEV_TC_HARDER", 0.2]]:
			var b := UIKit.button(Loc.t(spec[0]), _shift.bind(p.id, float(spec[1])), 100)
			b.name = "%s_%s" % [str(spec[0]).trim_prefix("DEV_TC_").capitalize(), p.id]
			row.add_child(b)
		add_child(row)


func _set_day(i: int, jdn: int, what: String) -> void:
	var c: CareerState = app().career
	var cur := c.training.day_plan(c, jdn)
	var iv: String = cur["intensity"]
	var fo: String = cur["focus"]
	if what == "intensity":
		iv = TrainingPlan.INTENSITIES[i]
	else:
		fo = TrainingPlan.FOCUSES[i]
	var err := c.training.set_day(jdn, iv, fo)
	if err != "":
		say(err, true)
	rebuild()


func _clear_day(jdn: int) -> void:
	app().career.training.set_day(jdn, "")
	rebuild()


func _shift(pid: String, delta: float) -> void:
	var c: CareerState = app().career
	c.development.plans.set_intensity(pid, float(c.development.plans.plan_for(pid).get("intensity", DevConfig.INTENSITY_DEFAULT)) + delta)
	rebuild()


# --- sessions ------------------------------------------------------------------------------------------------------

const GROUPS: Array[String] = ["all", "gk", "def", "mid", "att"]


func _sessions(c: CareerState) -> void:
	add_child(UIKit.label(Loc.t("DEV_SES_TITLE"), 18, UIKit.GOLD))
	add_child(UIKit.muted(Loc.t("DEV_SES_HINT")))
	var ids: Array = DevConfig.SESSIONS.keys()
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var to := UIKit.option(ids.map(func(k: String) -> String: return "%s - %s" % [Loc.t("DEV_CAT_" + str(DevConfig.SESSIONS[k][0]).to_upper()), Loc.t("DEV_SES_" + k.to_upper())]), _stype, func(i: int) -> void: _stype = i)
	to.name = "SessionType"
	row.add_child(to)
	var dopt := UIKit.option(DAYS.map(func(d: String) -> String: return Loc.t("DEV_DAY_" + d)), _sday, func(i: int) -> void: _sday = i)
	dopt.name = "SessionDay"
	row.add_child(dopt)
	var iopt := UIKit.option(["25%", "50%", "75%", "100%"], _sint, func(i: int) -> void: _sint = i)
	iopt.name = "SessionIntensity"
	row.add_child(iopt)
	var gopt := UIKit.option(GROUPS.map(func(g: String) -> String: return Loc.t("DEV_SESG_" + g.to_upper())), _sgroup, func(i: int) -> void: _sgroup = i)
	gopt.name = "SessionPlayers"
	row.add_child(gopt)
	var add := UIKit.button(Loc.t("DEV_SES_ADD"), _add_session.bind(ids), 150)
	add.name = "AddSession"
	row.add_child(add)
	add_child(row)
	var dev: DevelopmentState = c.development
	if dev.sessions.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_SES_NONE")))
	for ss in dev.sessions:
		var r := UIKit.hbox(8)
		r.add_child(UIKit.label("%s · %s · %d%% · %s" % [Loc.t("DEV_DAY_" + DAYS[int(ss["day"])]), Loc.t("DEV_SES_" + str(ss["session"]).to_upper()), roundi(float(ss["intensity"]) * 100.0), Loc.f("DEV_SES_PLAYERS", (ss["player_ids"] as Array).size())], 14))
		var b := UIKit.button(Loc.t("DEV_SES_REMOVE"), _remove_session.bind(str(ss["id"])), 110)
		b.name = "RemoveSession_%s" % ss["id"]
		r.add_child(b)
		add_child(r)


func _line_of(p: PlayerData) -> String:
	return YouthDevelopment._line(p)


func _add_session(ids: Array) -> void:
	var c: CareerState = app().career
	var g: String = GROUPS[_sgroup]
	var players: Array = []
	for p: PlayerData in db().get_squad(c.club_id):
		if p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED:
			continue
		if g == "all" or _line_of(p) == g:
			players.append(p.id)
	var matches := TrainingPlan.match_days(c)
	var start := CareerDate.jdn_of(c.season, c.week, 0)
	var match_idx := {}
	for i in 7:
		if matches.has(start + i):
			match_idx[i] = true
	var err := c.development.add_session(ids[_stype], _sday, float(_sint + 1) * 0.25, players, match_idx)
	say(Loc.t(err) if err != "" else Loc.t("DEV_SES_ADDED"), err != "")
	rebuild()


func _remove_session(id: String) -> void:
	app().career.development.remove_session(id)
	rebuild()
