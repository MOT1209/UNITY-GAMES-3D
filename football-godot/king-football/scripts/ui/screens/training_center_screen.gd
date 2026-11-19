extends HubScreen

## Training center: the week's daily schedule of the managed club (rest / light / medium / intense x focus, match days fixed),
## the coach responsible for each focus, squad fitness and fatigue with a one-click workload change per player.

const FOCUS_DEPT := {"tactics": "tactical", "fitness": "fitness", "technique": "midfield", "set_pieces": "tactical"}
const DAYS: Array[String] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


func build() -> void:
	if not header(Loc.t("SCREEN_TRAINING_CENTER"), true, true):
		return
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	_schedule(c)
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
