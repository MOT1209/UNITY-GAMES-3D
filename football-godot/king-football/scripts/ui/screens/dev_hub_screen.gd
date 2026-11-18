extends HubScreen

## Player Development Hub: first-team and academy players with plan, progress and warnings; the selected player's development
## screen (plan switching, target attributes, coach influence, history chart); team overview, notifications and reports.

var _selected := ""
var _group := "first"            # "first" | "youth"


func build() -> void:
	if not header(Loc.t("SCREEN_DEV_HUB"), true, true):
		return
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	var dev: DevelopmentState = c.development
	var tabs := UIKit.hbox(8)
	for g in ["first", "youth"]:
		var b := UIKit.button(Loc.t("DEV_GROUP_" + g.to_upper()), _set_group.bind(g), 150)
		b.name = "Group_%s" % g
		b.disabled = _group == g
		tabs.add_child(b)
	tabs.add_child(UIKit.button(Loc.t("SCREEN_COACHING_STAFF"), go.bind("coaching_staff"), 170))
	tabs.add_child(UIKit.button(Loc.t("SCREEN_TRAINING"), go.bind("training"), 150))
	add_child(tabs)
	var players := _players(c)
	var rows: Array = []
	for p in players:
		var plan := dev.plans.plan_for(p.id)
		rows.append([p.display_name, Loc.position_code(p.position), p.age, p.get_overall(), Loc.t("DEV_PLAN_" + str(plan.get("type", "position")).to_upper()),
				_warnings(c, dev, p), p.fitness])
	add_child(UIKit.table([Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), "OVR", Loc.t("DEV_PLAN"), Loc.t("DEV_WARNINGS"), Loc.t("DEV_FITNESS")], rows,
			func(i: int) -> void:
				_selected = players[i].id
				rebuild()))
	var sel: PlayerData = db().get_player(_selected)
	if sel != null:
		_detail(c, dev, sel)
	_overview(dev)


func _players(c: CareerState) -> Array:
	var out: Array = []
	if _group == "youth":
		var ac: Academy = app().academy()
		if ac != null:
			for pid in ac.roster_ids:
				var p: PlayerData = db().get_player(pid)
				if p != null:
					out.append(p)
	else:
		out = db().get_squad(c.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	return out.slice(0, 40)


func _warnings(c: CareerState, dev: DevelopmentState, p: PlayerData) -> String:
	var w: Array = []
	if p.status == PlayerData.Status.INJURED:
		w.append(Loc.t("DEV_W_INJURED"))
	if p.fitness < DevConfig.FATIGUE_WARN_FITNESS:
		w.append(Loc.t("DEV_W_TIRED"))
	if p.age <= 21 and int(dev.idle_weeks.get(p.id, 0)) >= DevConfig.LOW_PLAYTIME_WEEKS:
		w.append(Loc.t("DEV_W_NO_GAMES"))
	var ac: Academy = app().academy()
	if ac != null and p.id in ac.roster_ids and p in DevelopmentEngine.promotion_candidates(db(), ac, c.club_id):
		w.append(Loc.t("DEV_W_READY"))
	return ", ".join(w) if not w.is_empty() else "-"


func _detail(c: CareerState, dev: DevelopmentState, p: PlayerData) -> void:
	var plan := dev.plans.ensure(p, c.absolute_week())
	var ac: Academy = app().academy()
	add_child(UIKit.label("%s  %s  %s" % [p.display_name, Loc.position_code(p.position), Loc.f("DEV_AGE_OVR_POT", [p.age, p.get_overall(), Loc.t("DEV_POT_HIDDEN") if (ac != null and p.id in ac.roster_ids) else str(p.potential)])], 18, UIKit.GOLD))
	if ac != null and p.id in ac.roster_ids:
		add_child(UIKit.muted(Loc.f("DEV_POT_RANGE", YouthDevelopment.potential_text(ac, p))))
	for a in PlayerData.ATTRIBUTES:
		add_child(UIKit.stat_bar(Loc.t("DEV_ATTR_" + a.to_upper()), p.get_attribute(a)))
	# plan controls
	add_child(UIKit.label(Loc.t("DEV_PLAN_CONTROLS"), 16, UIKit.GOLD))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var types := DevelopmentPlans.TYPES.filter(func(t: String) -> bool: return t != "custom")
	var ptype := UIKit.option(types.map(func(t: String) -> String: return Loc.t("DEV_PLAN_" + t.to_upper())), maxi(types.find(plan["type"]), 0), _set_plan.bind(p.id, types))
	ptype.name = "PlanType"
	row.add_child(ptype)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = float(plan["intensity"]) * 100.0
	sl.custom_minimum_size = Vector2(180, 20)
	sl.name = "PlanIntensity"
	sl.value_changed.connect(func(v: float) -> void: dev.plans.set_intensity(p.id, v / 100.0))
	row.add_child(UIKit.label(Loc.t("DEV_INTENSITY"), 14, UIKit.MUTED))
	row.add_child(sl)
	add_child(row)
	var pr := dev.plans.progress(p, DevelopmentEngine.facility_quality(c))
	var wk := float(pr.get("weeks_per_point", -1.0))
	add_child(UIKit.muted(Loc.f("DEV_PLAN_STATUS", [pr.get("weeks", 0), pr.get("overall_change", 0), Loc.t("DEV_DEPT_" + str(pr.get("department", "tactical")).to_upper()),
			(Loc.f("DEV_EST_WEEKS", roundi(wk)) if wk > 0.0 else Loc.t("DEV_EST_NONE"))])))
	for t in pr.get("targets", []):
		add_child(UIKit.stat_bar("%s (+%d)" % [Loc.t("DEV_ATTR_" + str(t["attr"]).to_upper()), int(t["gain"])], int(t["current"])))
	add_child(UIKit.muted(Loc.f("DEV_FOCUS_ITEMS", ", ".join((plan["items"] as Array).map(func(it: Array) -> String: return Loc.t(str(it[0])))))))
	if plan["type"] == "attribute" or plan["type"] == "role" or plan["type"] == "conversion":
		add_child(UIKit.muted(Loc.t("DEV_PLAN_PARAM_HINT")))
	# coach influence
	var kind := DevelopmentEngine.kind_of(p)
	var lead: String = DevConfig.ATTRIBUTE_LEAD.get(str((pr.get("targets", [{"attr": "passing"}]) as Array)[0]["attr"]) if not (pr.get("targets", []) as Array).is_empty() else "passing", "tactical")
	add_child(UIKit.muted(Loc.f("DEV_COACH_INFLUENCE", [Loc.t("DEV_DEPT_" + lead.to_upper()), "%+d%%" % roundi((dev.coaching.dept_multiplier(lead, kind) - 1.0) * 100.0)])))
	var hist: Array = dev.history.get(p.id, [])
	if hist.size() >= 2:
		add_child(UIKit.label(Loc.t("DEV_HISTORY"), 16, UIKit.GOLD))
		add_child(ChartKit.line(hist.map(func(h: Dictionary) -> int: return int(h["overall"])), Vector2(420, 130), UIKit.GOLD, func(v: Variant) -> String: return str(roundi(float(v)))))
	else:
		add_child(UIKit.muted(Loc.t("DEV_NO_HISTORY")))
	add_child(UIKit.button(Loc.t("DEV_OPEN_PROFILE"), go.bind("player_profile", {"player_id": p.id}), 200))


func _overview(dev: DevelopmentState) -> void:
	add_child(UIKit.label(Loc.t("DEV_OVERVIEW"), 18, UIKit.GOLD))
	var last_month := {}
	for i in range(dev.reports.size() - 1, -1, -1):
		if dev.reports[i]["kind"] == "monthly":
			last_month = dev.reports[i]
			break
	if last_month.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_NO_REPORTS")))
	else:
		add_child(UIKit.muted(Loc.f("DEV_MONTHLY_LINE", [last_month["week"], last_month["players"]])))
		for t in last_month["top"]:
			add_child(UIKit.muted("  %s  %d (%+d)" % [t["name"], t["overall"], t["delta"]]))
	add_child(UIKit.label(Loc.t("DEV_NOTIFICATIONS"), 16, UIKit.GOLD))
	if dev.notifications.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_NO_NOTIFICATIONS")))
	for i in range(dev.notifications.size() - 1, maxi(dev.notifications.size() - 12, -1), -1):
		var n: Dictionary = dev.notifications[i]
		var args: Array = (n["args"] as Array).duplicate()
		if n["key"] == "INBOX_DEV_ATTR_UP" and args.size() > 1:
			args[1] = Loc.t("DEV_ATTR_" + str(args[1]).to_upper())
		add_child(UIKit.muted(Loc.f(str(n["key"]), args.map(func(x: Variant) -> String: return str(x)))))


func _set_group(g: String) -> void:
	_group = g
	_selected = ""
	rebuild()


func _set_plan(i: int, pid: String, types: Array) -> void:
	var c: CareerState = app().career
	var p: PlayerData = db().get_player(pid)
	var type: String = types[i]
	var params := {}
	var group := DevelopmentPlans.group_of(p.position)
	match type:
		"role":
			var roles := DevelopmentPlans.roles_for(group)
			if roles.is_empty():
				say(Loc.t("DEV_ERR_NO_ROLE"), true)
				rebuild()
				return
			params["role"] = roles[0]
		"attribute":
			params["attribute"] = _lead_attribute(p)
		"conversion":
			params["target_position"] = _conversion_target(p)
	var cur: Dictionary = c.development.plans.plan_for(pid)
	params["intensity"] = float(cur.get("intensity", DevConfig.INTENSITY_DEFAULT))
	var err := c.development.plans.assign(p, type, c.absolute_week(), params)
	say(err if err != "" else Loc.t("DEV_PLAN_CHANGED"), err != "")
	rebuild()


## The attribute of a single-attribute plan: the player's weakest one among the ones his position's overall uses.
func _lead_attribute(p: PlayerData) -> String:
	var weights: Dictionary = PlayerData.OVERALL_WEIGHTS[p.position]
	var best := ""
	var low := 1000
	for a in weights:
		if p.get_attribute(a) < low:
			low = p.get_attribute(a)
			best = a
	return best


## The nearest position the player does not play yet (same family: keeper stays keeper).
func _conversion_target(p: PlayerData) -> String:
	var order := ["LB", "RB", "CB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"]
	if p.position == PlayerData.Position.GK:
		return "GK"
	var names := PlayerData.Position.keys()
	var idx := order.find(names[p.position])
	for step in order.size():
		var cand: String = order[posmod(idx + 1 + step, order.size())]
		if cand != names[p.position] and not p.secondary_positions.has(cand):
			return cand
	return "ST"
