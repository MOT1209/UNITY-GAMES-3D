extends HubScreen

## Youth Scouting (Phase 4 redesign): an overview, a mission form with a searchable country picker, your scouts, the scout
## market (new candidates every week), the running missions (with progress and recall) and the discovered prospects as
## cards with separate View / Sign / Reject actions. Everything acts on the club's ScoutingSystem; nothing is display-only.

var _region := 0
var _position := 0                  # 0 = any, else index into PlayerData.Position.keys() + 1
var _objective := 0
var _weeks := 3
var _scout := 0
var _market_sort := 0               # 0 newest, 1 rating, 2 salary
var _talent_sort := 0               # 0 newest, 1 potential, 2 age
var _talent_pos := 0                # 0 all, else PlayerData.Position index + 1

const MARKET_SORTS := ["SCOUT_SORT_NEWEST", "SCOUT_SORT_RATING", "SCOUT_SORT_SALARY"]
const TALENT_SORTS := ["SCOUT_SORT_NEWEST", "SCOUT_SORT_POTENTIAL", "SCOUT_SORT_AGE"]


func sc() -> ScoutingSystem:
	return app().scouting.get(app().user_team_id)


func build() -> void:
	if not header(Loc.t("SCOUT_YOUTH_SCOUTING"), true):
		return
	var ac: Academy = app().academy()
	var s := sc()
	if ac == null or s == null:
		add_child(UIKit.empty_state(Loc.t("SCOUT_ONLY_CLUBS_CAN_SCOUT")))
		return
	s.candidates()                                        # an old save fills its market here
	_overview(s, ac)
	_mission_form(s, ac)
	_section(Loc.f("SCOUT_STAFF", [s.scouts.size(), ScoutingSystem.MAX_SCOUTS]))
	_staff_cards(s)
	_section(Loc.t("SCOUT_MARKET"))
	_market_cards(s, ac)
	_section(Loc.t("SCOUT_ACTIVE_MISSIONS"))
	_mission_cards(s)
	_section(Loc.f("SCOUT_TALENTS_TITLE", [s.pool.size(), ScoutingSystem.MAX_POOL]))
	_talent_cards(s)
	add_child(UIKit.label(Loc.f("SCOUT_HISTORY_LINE", [s.history.size(), s.rejected.size()]), 13, UIKit.MUTED))


func _section(text: String) -> void:
	add_child(UIKit.label(text, 17, UIKit.GOLD))


func _card(node_name: String, min_w := 300.0) -> Array:
	var p := PanelContainer.new()
	p.name = node_name
	p.custom_minimum_size = Vector2(min_w, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UIKit.box(UIKit.PANEL, UIKit.PANEL.lightened(0.15), 1, 10, 12))
	var v := UIKit.vbox(4)
	p.add_child(v)
	return [p, v]


func _flow(node_name: String) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.name = node_name
	f.add_theme_constant_override("h_separation", UIKit.SPACE_S)
	f.add_theme_constant_override("v_separation", UIKit.SPACE_S)
	add_child(f)
	return f


static func region_name(r: String) -> String:
	return Loc.t("SCOUT_WORLDWIDE") if r == ScoutingSystem.WORLDWIDE else Loc.country(r)


# ------------------------------------------------------------------------------------------------- A: overview

func _overview(s: ScoutingSystem, ac: Academy) -> void:
	var f := _flow("ScoutOverview")
	var new_count := s.market.filter(func(c: Dictionary) -> bool: return int(c.get("listed_week", -1)) == s.week).size()
	for item in [["SCOUT_OV_BUDGET", Loc.money(ac.budget)], ["SCOUT_OV_SCOUTS", "%d / %d" % [s.scouts.size(), ScoutingSystem.MAX_SCOUTS]],
			["SCOUT_OV_AVAILABLE", "%d (+%d)" % [s.market.size(), new_count]], ["SCOUT_OV_MISSIONS", str(s.missions.size())],
			["SCOUT_OV_TALENTS", "%d / %d" % [s.pool.size(), ScoutingSystem.MAX_POOL]]]:
		var c := _card("Ov_%s" % item[0], 150.0)
		(c[1] as VBoxContainer).add_child(UIKit.label(Loc.t(item[0]), 12, UIKit.MUTED))
		(c[1] as VBoxContainer).add_child(UIKit.label(str(item[1]), 20, UIKit.TEXT))
		f.add_child(c[0])
	for d in s.departures:
		if int(d.get("week", -1)) == s.week:
			add_child(UIKit.label(Loc.f("SCOUT_CONTRACT_ENDED", str(d["name"])), 14, UIKit.WARN))


# ------------------------------------------------------------------------------------------------- mission form

func _mission_form(s: ScoutingSystem, ac: Academy) -> void:
	var c := _card("MissionForm")
	var v: VBoxContainer = c[1]
	v.add_child(UIKit.label(Loc.t("SCOUT_NEW_MISSION"), 16, UIKit.GOLD))
	var regions: Array = ScoutingSystem.regions(db())
	var scout_ids: Array = s.scouts.keys()
	_scout = clampi(_scout, 0, maxi(scout_ids.size() - 1, 0))
	_region = clampi(_region, 0, regions.size() - 1)
	var form := HFlowContainer.new()
	form.name = "ScoutToolbar"
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	form.add_child(UIKit.label(Loc.t("SCOUT_SCOUT"), 14, UIKit.MUTED))
	var so := UIKit.option(scout_ids.map(func(id: String) -> String:
			var sd: Dictionary = s.scouts[id]
			return Loc.f("SCOUT_SCOUT_OPTION", [scout_name(id, sd["name"]), float(sd["quality"]) * 100.0, sd["weekly_cost"]]) \
					+ ("  · " + Loc.t("SCOUT_BUSY") if s.is_scout_busy(id) else "")), _scout, func(i: int) -> void: _scout = i)
	so.name = "ScoutOption"
	form.add_child(so)
	form.add_child(UIKit.label(Loc.t("SCOUT_REGION"), 14, UIKit.MUTED))
	var picker := CountryPicker.make(regions.map(func(r: String) -> String: return region_name(r)), _region,
			func(i: int) -> void: _region = i, "RegionOption")
	form.add_child(picker)
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
	wk.value_changed.connect(func(val: float) -> void: _weeks = int(val))
	wk.name = "WeeksSpin"
	form.add_child(wk)
	v.add_child(form)
	var cost := 0
	if not scout_ids.is_empty():
		cost = int(s.scouts[scout_ids[_scout]]["weekly_cost"]) * _weeks
	v.add_child(UIKit.muted(Loc.f("SCOUT_MISSION_COST_HINT", [Loc.money(cost), Loc.money(ac.budget)])))
	var actions := UIKit.hbox(UIKit.SPACE_S)
	var go_btn := UIKit.button(Loc.t("SCOUT_SEND_SCOUT"), _start.bind(scout_ids, regions), 160)
	go_btn.name = "SendScout"
	go_btn.disabled = scout_ids.is_empty()
	actions.add_child(go_btn)
	var adv := UIKit.button(Loc.t("COMMON_ADVANCE_WEEK"), _advance, 160)
	adv.name = "AdvanceWeek"
	actions.add_child(adv)
	v.add_child(actions)
	add_child(c[0])


# ------------------------------------------------------------------------------------------------- your scouts

static func stars(q: float) -> String:
	var n := clampi(roundi(q * 5.0), 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _profile_lines(v: VBoxContainer, d: Dictionary) -> void:
	v.add_child(UIKit.label("%s  %d%%" % [stars(float(d["quality"])), roundi(float(d["quality"]) * 100.0)], 15, UIKit.GOLD))
	var nat := str(d.get("nationality", ""))
	v.add_child(UIKit.muted(Loc.f("SCOUT_NATIONALITY_EXP", [Loc.country(nat) if nat != "" else Loc.t("SCOUT_UNKNOWN"),
			Loc.f("SCOUT_YEARS", int(d["experience"])) if d.has("experience") else Loc.t("SCOUT_UNKNOWN")])))
	var reg := str(d.get("region", ""))
	v.add_child(UIKit.label(Loc.f("SCOUT_SPECIALTY_REGION", [Loc.t("SCOUT_SPEC_" + str(d.get("specialty", "all_round")).to_upper()),
			Loc.country(reg) if reg != "" else Loc.t("SCOUT_NO_REGION")]), 13))


func _staff_cards(s: ScoutingSystem) -> void:
	var f := _flow("ScoutStaff")
	for id in s.scouts:
		var d: Dictionary = s.scouts[id]
		var c := _card("Staff_%s" % id)
		var v: VBoxContainer = c[1]
		v.add_child(UIKit.label(scout_name(id, d["name"]), 17))
		_profile_lines(v, d)
		var until := int(d.get("contract_until", 0))
		v.add_child(UIKit.muted(Loc.f("SCOUT_SALARY_CONTRACT", [Loc.money(int(d["weekly_cost"])),
				Loc.f("SCOUT_CONTRACT_WEEKS_LEFT", maxi(until - s.week, 0)) if until > 0 else Loc.t("SCOUT_CONTRACT_OPEN")])))
		var busy := s.is_scout_busy(id)
		var mission_region := ""
		for m in s.missions:
			if m["scout_id"] == id:
				mission_region = region_name(str(m["region"]))
		v.add_child(UIKit.label(Loc.f("SCOUT_STATUS_MISSION", mission_region) if busy else Loc.t("SCOUT_STATUS_IDLE"), 13, UIKit.MUTED if busy else UIKit.GOOD))
		var b := UIKit.button(Loc.t("SCOUT_END_CONTRACT"), _ask_dismiss.bind(id), 150)
		b.name = "Dismiss_%s" % id
		b.disabled = busy or s.scouts.size() <= 1
		b.tooltip_text = Loc.t("SCOUT_END_CONTRACT_HINT")
		v.add_child(b)
		f.add_child(c[0])


# ------------------------------------------------------------------------------------------------- market

func _market_cards(s: ScoutingSystem, ac: Academy) -> void:
	var bar := UIKit.hbox(UIKit.SPACE_S)
	var hint := UIKit.muted(Loc.f("SCOUT_MARKET_HINT", ScoutingSystem.MARKET_STAY_WEEKS))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	var so := UIKit.option(MARKET_SORTS.map(func(k: String) -> String: return Loc.t(k)), _market_sort, func(i: int) -> void:
		_market_sort = i
		rebuild())
	so.name = "MarketSort"
	bar.add_child(so)
	add_child(bar)
	var order: Array = range(s.market.size())
	match _market_sort:
		1:
			order.sort_custom(func(a: int, b: int) -> bool: return float(s.market[a]["quality"]) > float(s.market[b]["quality"]))
		2:
			order.sort_custom(func(a: int, b: int) -> bool: return int(s.market[a]["weekly_cost"]) < int(s.market[b]["weekly_cost"]))
		_:
			order.sort_custom(func(a: int, b: int) -> bool: return int(s.market[a]["listed_week"]) > int(s.market[b]["listed_week"]))
	if order.is_empty():
		add_child(UIKit.empty_state(Loc.t("SCOUT_MARKET_EMPTY")))
		return
	var f := _flow("ScoutMarket")
	for i: int in order:
		var d: Dictionary = s.market[i]
		var c := _card("Cand_%s" % str(d.get("cid", i)))
		var v: VBoxContainer = c[1]
		var top := UIKit.hbox(6)
		top.add_child(UIKit.label(str(d["name"]), 17))
		if int(d.get("listed_week", -1)) == s.week:
			top.add_child(UIKit.label(Loc.t("SCOUT_NEW_BADGE"), 12, UIKit.GOOD))
		v.add_child(top)
		_profile_lines(v, d)
		v.add_child(UIKit.muted(Loc.f("SCOUT_SALARY_CONTRACT", [Loc.money(int(d["weekly_cost"])), Loc.f("SCOUT_CONTRACT_OFFER", int(d.get("contract_weeks", 52)))])))
		v.add_child(UIKit.label(Loc.f("SCOUT_HIRE_FEE", Loc.money(s.hire_fee(d))), 13, UIKit.MUTED))
		var b := UIKit.button(Loc.t("SCOUT_HIRE"), _hire.bind(i), 150)
		b.name = "Hire_%d" % i
		b.disabled = s.scouts.size() >= ScoutingSystem.MAX_SCOUTS or s.hire_fee(d) > ac.budget
		v.add_child(b)
		f.add_child(c[0])


# ------------------------------------------------------------------------------------------------- missions

func _mission_cards(s: ScoutingSystem) -> void:
	if s.missions.is_empty():
		add_child(UIKit.muted(Loc.t("SCOUT_NO_SCOUT_IS_ON_A_MISSION")))
		return
	var f := _flow("ScoutMissions")
	for m in s.missions:
		var c := _card("Mission_%d" % int(m["id"]))
		var v: VBoxContainer = c[1]
		var sd: Dictionary = s.scouts.get(m["scout_id"], {"name": str(m["scout_id"])})
		v.add_child(UIKit.label("%s → %s" % [scout_name(str(m["scout_id"]), str(sd["name"])), region_name(str(m["region"]))], 16))
		var pos := str(m.get("position", ""))
		v.add_child(UIKit.muted(Loc.f("SCOUT_MISSION_FOCUS", [Loc.position_code(int(PlayerData.Position[pos])) if pos != "" else Loc.t("SCOUT_ANY_POSITION"),
				Loc.t("SCOUT_OBJ_" + str(m.get("objective", "balanced")).to_upper())])))
		var done := int(m["weeks_total"]) - int(m["weeks_left"])
		var pb := ProgressBar.new()
		pb.name = "Progress"
		pb.min_value = 0
		pb.max_value = int(m["weeks_total"])
		pb.value = done
		pb.custom_minimum_size = Vector2(0, 14)
		pb.show_percentage = false
		v.add_child(pb)
		v.add_child(UIKit.label(Loc.f("SCOUT_MISSION_PROGRESS", [done, int(m["weeks_total"]), int(m["weeks_left"])]), 13))
		var b := UIKit.button(Loc.t("SCOUT_RECALL"), _ask_recall.bind(int(m["id"])), 150)
		b.name = "Recall_%d" % int(m["id"])
		v.add_child(b)
		f.add_child(c[0])


# ------------------------------------------------------------------------------------------------- talents

func _talent_cards(s: ScoutingSystem) -> void:
	if s.pool.is_empty():
		add_child(UIKit.empty_state(Loc.t("SCOUT_NO_PROSPECTS_FOUND_YET_SEND_A_SCOU")))
		return
	var bar := UIKit.hbox(UIKit.SPACE_S)
	bar.add_child(UIKit.label(Loc.t("SCOUT_FILTER"), 14, UIKit.MUTED))
	var pf := UIKit.option([Loc.t("SCOUT_ANY_POSITION")] + PlayerData.Position.keys().map(func(k: String) -> String: return Loc.position_code(int(PlayerData.Position[k]))),
			_talent_pos, func(i: int) -> void:
				_talent_pos = i
				rebuild())
	pf.name = "TalentFilter"
	bar.add_child(pf)
	bar.add_child(UIKit.label(Loc.t("SCOUT_SORT"), 14, UIKit.MUTED))
	var ts := UIKit.option(TALENT_SORTS.map(func(k: String) -> String: return Loc.t(k)), _talent_sort, func(i: int) -> void:
		_talent_sort = i
		rebuild())
	ts.name = "TalentSort"
	bar.add_child(ts)
	add_child(bar)
	var ids: Array = []
	for pid in s.pool:
		var p: PlayerData = db().get_player(pid)
		if p != null and (_talent_pos == 0 or p.position == _talent_pos - 1):
			ids.append(pid)
	match _talent_sort:
		1:
			ids.sort_custom(func(a: String, b: String) -> bool: return int(s.reports.get(a, {}).get("estimate", 0)) > int(s.reports.get(b, {}).get("estimate", 0)))
		2:
			ids.sort_custom(func(a: String, b: String) -> bool: return (db().get_player(a) as PlayerData).age < (db().get_player(b) as PlayerData).age)
		_:
			ids.reverse()
	if ids.is_empty():
		add_child(UIKit.muted(Loc.t("SCOUT_FILTER_NONE")))
		return
	var f := _flow("TalentCards")
	for pid in ids:
		f.add_child(_talent_card(s, pid))


## The source of a prospect: scout, region and week of the discovery (from the discovery history).
static func source_of(s: ScoutingSystem, pid: String) -> Dictionary:
	for h in s.history:
		if str(h.get("player_id", "")) == pid:
			return h
	return {}


## The three best of the seven broad attributes (the values the game stores; nothing estimated).
static func main_attributes(p: PlayerData) -> Array:
	var rows: Array = []
	for a in PlayerData.ATTRIBUTES:
		if a == "goalkeeping" and p.position != PlayerData.Position.GK:
			continue
		rows.append([a, p.get_attribute(a)])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]))
	return rows.slice(0, 3)


func _talent_card(s: ScoutingSystem, pid: String) -> Control:
	var p: PlayerData = db().get_player(pid)
	var rep: Dictionary = s.reports.get(pid, {})
	var c := _card("Talent_%s" % pid, 320.0)
	var v: VBoxContainer = c[1]
	var top := UIKit.hbox(8)
	top.add_child(UIKit.label(Loc.position_code(p.position), 15, UIKit.GOLD))
	top.add_child(UIKit.label(p.display_name, 17))
	v.add_child(top)
	v.add_child(UIKit.muted(Loc.f("SCOUT_TALENT_IDENTITY", [p.age, Loc.country(p.nationality_id) if p.nationality_id != "" else Loc.country(p.nationality), p.get_overall()])))
	v.add_child(UIKit.label(Loc.f("SCOUT_EST_POTENTIAL", [int(rep.get("estimate", 0)), int(rep.get("margin", 0))]), 16, UIKit.GOLD))
	v.add_child(UIKit.muted(Loc.f("SCOUT_REPORT_RELIABILITY", roundi(float(rep.get("reliability", 0.0)) * 100.0))))
	var attrs: PackedStringArray = []
	for row in main_attributes(p):
		attrs.append("%s %d" % [Loc.enum_name("ATTR", str(row[0])), int(row[1])])
	v.add_child(UIKit.label(", ".join(attrs), 13))
	var src := source_of(s, pid)
	if not src.is_empty():
		var sid := str(src.get("scout_id", ""))
		var sd: Dictionary = s.scouts.get(sid, {"name": sid})
		v.add_child(UIKit.muted(Loc.f("SCOUT_FOUND_BY", [scout_name(sid, str(sd["name"])), region_name(str(src.get("region", ""))), int(src.get("week", 0))])))
	v.add_child(UIKit.muted(Loc.f("SCOUT_SIGNING_COST", Loc.money(s.signing_cost(p)))))
	var actions := UIKit.hbox(6)
	var view := UIKit.button(Loc.t("SCOUT_VIEW"), go.bind("player_profile", {"player_id": pid}), 90)
	view.name = "View_%s" % pid
	actions.add_child(view)
	var sign := UIKit.button(Loc.t("SCOUT_SIGN"), _sign.bind(pid), 90)
	sign.name = "Sign_%s" % pid
	actions.add_child(sign)
	var rej := UIKit.button(Loc.t("SCOUT_REJECT"), _ask_reject.bind(pid), 90)
	rej.name = "Reject_%s" % pid
	actions.add_child(rej)
	v.add_child(actions)
	return c[0]


# ------------------------------------------------------------------------------------------------- actions

func _hire(i: int) -> void:
	var err: String = sc().hire(app().academy(), i)
	say(err if err != "" else Loc.t("SCOUT_HIRED"), err != "")
	rebuild()


func _ask_dismiss(id: String) -> void:
	UIKit.confirm(self, Loc.f("SCOUT_END_CONTRACT_CONFIRM", scout_name(id, str(sc().scouts[id]["name"]))), _dismiss.bind(id))


func _dismiss(id: String) -> void:
	var err: String = sc().dismiss(id)
	say(err if err != "" else Loc.t("SCOUT_DISMISSED"), err != "")
	rebuild()


func _ask_recall(mission_id: int) -> void:
	UIKit.confirm(self, Loc.t("SCOUT_RECALL_CONFIRM"), _recall.bind(mission_id))


func _recall(mission_id: int) -> void:
	var err: String = sc().recall(app().academy(), mission_id)
	say(err if err != "" else Loc.t("SCOUT_RECALLED"), err != "")
	rebuild()


func _start(scout_ids: Array, regions: Array) -> void:
	if scout_ids.is_empty():
		return
	var err: String = sc().start_mission(app().academy(), scout_ids[_scout], regions[_region], _weeks,
			"" if _position == 0 else str(PlayerData.Position.keys()[_position - 1]), ScoutingSystem.OBJECTIVES[_objective])
	say(err if err != "" else Loc.f("SCOUT_SCOUT_SENT_TO", region_name(regions[_region])), err != "")
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
	var err: String = sc().sign_prospect(db(), app().academy(), pid)
	say(err if err != "" else Loc.t("SCOUT_PROSPECT_SIGNED_TO_THE_ACADEMY"), err != "")
	rebuild()


func _ask_reject(pid: String) -> void:
	var p: PlayerData = db().get_player(pid)
	UIKit.confirm(self, Loc.f("SCOUT_REJECT_CONFIRM", p.display_name if p != null else pid), _reject.bind(pid))


func _reject(pid: String) -> void:
	var p: PlayerData = db().get_player(pid)
	var nm := p.display_name if p != null else pid
	var err: String = sc().reject_prospect(db(), pid)
	say(err if err != "" else Loc.f("SCOUT_REJECTED", nm), err != "")
	rebuild()


## Display name of a scout: the built-in scouts ("scout_a", "scout_b") have translated titles
## (SCOUT_NAME_SCOUT_A ...); scouts added with a custom name show that name.
static func scout_name(scout_id: String, stored: String) -> String:
	var key := "SCOUT_NAME_%s" % scout_id.to_upper()
	return Loc.t(key) if Loc.has_key(key) or Loc.has_key(key, Localization.FALLBACK_LANGUAGE) else stored
