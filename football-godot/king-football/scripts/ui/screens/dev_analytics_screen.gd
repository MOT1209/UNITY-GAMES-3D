extends HubScreen

## Development analytics: team overview, two-player comparison, attribute progression chart from the history snapshots,
## monthly and seasonal reports. Everything is read from DevelopmentState (real snapshots, no invented numbers).

var _a := ""
var _b := ""
var _attr := "overall"


func build() -> void:
	if not header(Loc.t("SCREEN_DEV_ANALYTICS"), true, true):
		return
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	var dev: DevelopmentState = c.development
	var squad: Array = db().get_squad(c.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	squad.sort_custom(func(x: PlayerData, y: PlayerData) -> bool: return x.get_overall() > y.get_overall())
	_overview(c, dev, squad)
	if squad.size() >= 2:
		if _a == "" or db().get_player(_a) == null:
			_a = squad[0].id
		if _b == "" or db().get_player(_b) == null:
			_b = squad[1].id
		_compare(dev, squad)
	_reports(dev)


func _overview(c: CareerState, dev: DevelopmentState, squad: Array) -> void:
	add_child(UIKit.label(Loc.t("DEV_OVERVIEW"), 18, UIKit.GOLD))
	var avg := 0.0
	var young := 0
	var gaining := 0
	for p: PlayerData in squad:
		avg += p.get_overall()
		var hist: Array = dev.history.get(p.id, [])
		if hist.size() >= 2 and int(hist[-1]["overall"]) > int(hist[0]["overall"]):
			gaining += 1
		if p.age <= 21:
			young += 1
	avg /= maxf(float(squad.size()), 1.0)
	add_child(UIKit.label(Loc.f("DEV_AN_TEAM", [squad.size(), "%.1f" % avg, young, gaining]), 15))
	var ac: Academy = app().academy()
	if ac != null:
		add_child(UIKit.muted(Loc.f("DEV_AN_ACADEMY", [ac.roster_ids.size(), DevelopmentEngine.promotion_candidates(db(), ac, c.club_id).size()])))
	var cs := dev.coaching
	for d in DevConfig.DEPARTMENTS:
		var m := cs.dept_multiplier(d)
		add_child(ChartKit.bar_row(Loc.t("DEV_DEPT_" + d.to_upper()), "%+d%%" % roundi((m - 1.0) * 100.0), clampf((m - 0.8) / 0.4, 0.0, 1.0)))


func _compare(dev: DevelopmentState, squad: Array) -> void:
	add_child(UIKit.label(Loc.t("DEV_AN_COMPARE"), 18, UIKit.GOLD))
	var names: Array = squad.map(func(p: PlayerData) -> String: return "%s (%d)" % [p.display_name, p.get_overall()])
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	for slot in ["a", "b"]:
		var cur := _a if slot == "a" else _b
		var idx := 0
		for i in squad.size():
			if (squad[i] as PlayerData).id == cur:
				idx = i
		var o := UIKit.option(names, idx, func(i: int) -> void:
			if slot == "a":
				_a = (squad[i] as PlayerData).id
			else:
				_b = (squad[i] as PlayerData).id
			rebuild())
		o.name = "Compare_%s" % slot
		row.add_child(o)
	var attrs: Array = ["overall"] + PlayerData.ATTRIBUTES + DetailedAttributes.names()
	row.add_child(UIKit.option(attrs.map(func(a: String) -> String: return Loc.t("DEV_R_OVERALL") if a == "overall" else Loc.t("DEV_ATTR_" + a.to_upper())), attrs.find(_attr), func(i: int) -> void:
		_attr = attrs[i]
		rebuild()))
	add_child(row)
	var pa: PlayerData = db().get_player(_a)
	var pb: PlayerData = db().get_player(_b)
	var rows: Array = []
	rows.append([Loc.t("COMMON_AGE"), pa.age, pb.age])
	rows.append(["OVR", pa.get_overall(), pb.get_overall()])
	for a in PlayerData.ATTRIBUTES:
		rows.append([Loc.t("DEV_ATTR_" + a.to_upper()), pa.get_attribute(a), pb.get_attribute(a)])
	for n in DetailedAttributes.names():
		if DetailedAttributes.applicable(pa, n) or DetailedAttributes.applicable(pb, n):
			rows.append([Loc.t("DEV_ATTR_" + str(n).to_upper()), DetailedAttributes.value(pa, n) if DetailedAttributes.applicable(pa, n) else "-", DetailedAttributes.value(pb, n) if DetailedAttributes.applicable(pb, n) else "-"])
	rows.append([Loc.t("DEV_PLAN"), Loc.t("DEV_PLAN_" + str(dev.plans.plan_for(pa.id).get("type", "position")).to_upper()), Loc.t("DEV_PLAN_" + str(dev.plans.plan_for(pb.id).get("type", "position")).to_upper())])
	add_child(UIKit.table(["", pa.display_name, pb.display_name], rows))
	for p: PlayerData in [pa, pb]:
		var hist: Array = dev.history.get(p.id, [])
		add_child(UIKit.muted(p.display_name))
		if DetailedAttributes.has(_attr):          # monthly snapshots hold the broad attributes: a detailed one is charted from its recorded changes
			var changes := DetailedAttributes.recent_changes(p, 40, _attr)
			changes.reverse()
			if changes.size() >= 1:
				var series: Array = [int(changes[0]["from"])]
				for ch in changes:
					series.append(int(ch["to"]))
				add_child(ChartKit.line(series, Vector2(420, 110), UIKit.GOLD, func(v: Variant) -> String: return str(roundi(float(v)))))
			else:
				add_child(UIKit.muted(Loc.t("DEV_NO_HISTORY")))
		elif hist.size() >= 2:
			add_child(ChartKit.line(hist.map(func(h: Dictionary) -> int: return int(h["overall"]) if _attr == "overall" else int((h["attrs"] as Dictionary).get(_attr, 0))),
					Vector2(420, 110), UIKit.GOLD, func(v: Variant) -> String: return str(roundi(float(v)))))
		else:
			add_child(UIKit.muted(Loc.t("DEV_NO_HISTORY")))


func _reports(dev: DevelopmentState) -> void:
	add_child(UIKit.label(Loc.t("DEV_AN_REPORTS"), 18, UIKit.GOLD))
	if dev.reports.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_NO_REPORTS")))
	for i in range(dev.reports.size() - 1, maxi(dev.reports.size() - 10, -1), -1):
		var r: Dictionary = dev.reports[i]
		if r["kind"] == "seasonal":
			add_child(UIKit.label(Loc.f("DEV_AN_SEASONAL", [r["season"], r["players"]]), 15))
			for t in r["top"]:
				add_child(UIKit.muted("  %s  %d → %d" % [t["name"], t["from"], t["to"]]))
		else:
			add_child(UIKit.muted(Loc.f("DEV_AN_MONTHLY", [r["season"], r["week"], (r["top"] as Array).size()])))
