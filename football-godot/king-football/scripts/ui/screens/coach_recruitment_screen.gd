extends HubScreen

## Coach recruitment market: department filter, name search, candidate profiles, comparison, salary / contract negotiation,
## hire and reject. The market refreshes with the career calendar.

var _dept := ""
var _query := ""
var _offers: Dictionary = {}          # candidate id -> {salary, years}
var _compare: Array = []              # up to two candidate ids
var _reply := ""


func build() -> void:
	if not header(Loc.t("SCREEN_COACH_RECRUITMENT"), true, true):
		return
	if params.has("department"):
		_dept = str(params["department"])
		params.erase("department")
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	var cs: CoachingStaff = c.development.coaching
	cs.fill_market(c.absolute_week())
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	var names: Array = [Loc.t("DEV_ALL_DEPARTMENTS")] + DevConfig.DEPARTMENTS.map(func(d: String) -> String: return Loc.t("DEV_DEPT_" + d.to_upper()))
	var o := UIKit.option(names, DevConfig.DEPARTMENTS.find(_dept) + 1, func(i: int) -> void:
		_dept = "" if i == 0 else DevConfig.DEPARTMENTS[i - 1]
		rebuild())
	o.name = "DeptFilter"
	bar.add_child(o)
	var search := LineEdit.new()
	search.placeholder_text = Loc.t("DEV_SEARCH")
	search.text = _query
	search.custom_minimum_size = Vector2(220, 0)
	search.name = "Search"
	search.text_changed.connect(func(t: String) -> void: _query = t)
	search.text_submitted.connect(func(_t: String) -> void: rebuild())
	bar.add_child(search)
	bar.add_child(UIKit.button(Loc.t("DEV_SEARCH_GO"), rebuild, 100))
	add_child(bar)
	add_child(UIKit.label(Loc.f("DEV_BUDGET_LINE", [c.ledger().balance, cs.weekly_wages(), c.ledger().wage_budget]), 15))
	if _reply != "":
		add_child(UIKit.label(_reply, 15, UIKit.GOLD))
	if _compare.size() == 2:
		_comparison(cs)
	var list := cs.browse(_dept, _query)
	if list.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_NO_CANDIDATES")))
	for cand in list:
		_candidate(c, cs, cand)


func _offer(cand: Dictionary) -> Dictionary:
	if not _offers.has(cand["id"]):
		_offers[cand["id"]] = {"salary": int(cand["salary"]), "years": int(cand.get("pref_years", 3))}
	return _offers[cand["id"]]


func _candidate(c: CareerState, cs: CoachingStaff, cand: Dictionary) -> void:
	var id := str(cand["id"])
	var off := _offer(cand)
	var box := UIKit.vbox(3)
	box.add_child(UIKit.label("%s  %s  - %s" % [cand["name"], DevConfig.stars_text(int(cand["overall"])), Loc.t("DEV_DEPT_" + str(cand["department"]).to_upper())], 16))
	box.add_child(UIKit.muted(Loc.f("DEV_COACH_RATINGS", [cand["overall"], cand["technical"], cand["tactical"], cand["youth"], cand["pro"], Loc.t("DEV_SPEC_" + str(cand["specialization"]).to_upper())])))
	box.add_child(UIKit.muted(Loc.f("DEV_CAND_INFO", [cand["age"], Loc.country(str(cand["nationality"])), cand["experience"], cand["reputation"], cand["salary"], cand["pref_years"]])))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var sal := SpinBox.new()
	sal.min_value = 100
	sal.max_value = 20000
	sal.step = 50
	sal.value = int(off["salary"])
	sal.name = "Salary_%s" % id
	sal.value_changed.connect(func(v: float) -> void: off["salary"] = int(v))
	row.add_child(sal)
	var years := UIKit.option(["1", "2", "3", "4", "5"], int(off["years"]) - 1, func(i: int) -> void: off["years"] = i + 1)
	years.name = "Years_%s" % id
	row.add_child(years)
	for spec in [["DEV_NEGOTIATE", _negotiate], ["DEV_HIRE", _hire], ["DEV_REJECT", _reject], ["DEV_COMPARE", _add_compare]]:
		var b := UIKit.button(Loc.t(spec[0]), (spec[1] as Callable).bind(id), 120)
		b.name = "%s_%s" % [str(spec[0]).trim_prefix("DEV_").capitalize(), id]
		row.add_child(b)
	box.add_child(row)
	add_child(UIKit.panel(box))


func _comparison(cs: CoachingStaff) -> void:
	var rows: Array = []
	var cands: Array = []
	for id in _compare:
		cands.append(cs.candidate(id))
	if cands.any(func(x: Dictionary) -> bool: return x.is_empty()):
		_compare.clear()
		return
	for k in [["DEV_R_OVERALL", "overall"], ["DEV_R_TECHNICAL", "technical"], ["DEV_R_TACTICAL", "tactical"], ["DEV_R_YOUTH", "youth"], ["DEV_R_PRO", "pro"], ["DEV_R_REPUTATION", "reputation"], ["DEV_R_SALARY", "salary"]]:
		rows.append([Loc.t(k[0]), cands[0][k[1]], cands[1][k[1]]])
	add_child(UIKit.table(["", str(cands[0]["name"]), str(cands[1]["name"])], rows))
	add_child(UIKit.button(Loc.t("DEV_CLEAR_COMPARE"), func() -> void:
		_compare.clear()
		rebuild(), 160))


func _add_compare(id: String) -> void:
	if id in _compare:
		return
	if _compare.size() >= 2:
		_compare.pop_front()
	_compare.append(id)
	rebuild()


func _negotiate(id: String) -> void:
	var cs: CoachingStaff = app().career.development.coaching
	var off: Dictionary = _offers.get(id, {"salary": 0, "years": 3})
	var r := cs.negotiate(id, int(off["salary"]), int(off["years"]))
	_reply = Loc.t(str(r["reply"])) + ("" if r["accepted"] else " " + Loc.f("DEV_COUNTER", r["counter_salary"]))
	if not r["accepted"] and r["counter_salary"] > 0:
		off["salary"] = int(r["counter_salary"])
	rebuild()


func _hire(id: String) -> void:
	var c: CareerState = app().career
	var off: Dictionary = _offers.get(id, {"salary": 0, "years": 3})
	var r := c.development.coaching.hire(id, int(off["salary"]), int(off["years"]), c.facilities.level("training"), c.ledger(), c.absolute_week(), c.season, c.staff.weekly_wages())
	_reply = Loc.t("DEV_HIRED") if r["ok"] else Loc.t(str(r["error"]))
	say(_reply, not r["ok"])
	rebuild()


func _reject(id: String) -> void:
	var c: CareerState = app().career
	c.development.coaching.reject(id, c.absolute_week())
	_reply = Loc.t("DEV_REJECTED")
	rebuild()
