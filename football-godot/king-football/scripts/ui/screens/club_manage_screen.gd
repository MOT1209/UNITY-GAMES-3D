extends HubScreen

## Screen for the club-management systems of the career program: facilities (C2.5), staff (C2.6), prices / sponsors / loan (C7),
## board meetings (C2.3) and the manager's skill tree (C8). Every button calls the same logic the tests exercise.

var tab := "facilities"
const TABS: Array[String] = ["facilities", "staff", "finance", "board", "skills"]


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_CLUB_MANAGE")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var tabs := HFlowContainer.new()
	tabs.name = "ManageTabs"
	for t in TABS:
		var b := UIKit.button(Loc.t("MANAGE_TAB_" + t.to_upper()), _set_tab.bind(t), 100)
		b.name = "Tab_%s" % t
		b.disabled = t == tab
		tabs.add_child(b)
	add_child(tabs)
	match tab:
		"facilities":
			_facilities(career)
		"staff":
			_staff(career)
		"finance":
			_finance(career)
		"board":
			_board(career)
		_:
			_skills(career)


func _set_tab(t: String) -> void:
	tab = t
	rebuild()


func _row(title_text: String, detail: String, button_text: String, callback: Callable, button_name: String, disabled := false) -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	var col := UIKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label(title_text, 16, UIKit.GOLD))
	var d := UIKit.label(detail, 13, UIKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	row.add_child(col)
	if button_text != "":
		var b := UIKit.button(button_text, callback, 130)
		b.name = button_name
		b.disabled = disabled
		row.add_child(b)
	return UIKit.panel(row)


func _result(err: String, ok_key: String = "MANAGE_DONE") -> void:
	say(Loc.t(ok_key) if err == "" else Loc.t(err), err != "")
	app().state_changed.emit()
	rebuild()


# --- facilities ----------------------------------------------------------------------------------------------

func _facilities(career: CareerState) -> void:
	for k in Facilities.KINDS:
		var lvl := career.facilities.level(k)
		var building := career.facilities.is_building(k)
		var detail := Loc.f("MANAGE_FAC_DETAIL", [lvl, Facilities.MAX_LEVEL, Loc.money(Facilities.cost_of(lvl + 1)) if lvl < Facilities.MAX_LEVEL else "-",
				Facilities.build_weeks(lvl + 1) if lvl < Facilities.MAX_LEVEL else 0])
		if building:
			for q in career.facilities.queue:
				if q["kind"] == k:
					detail = Loc.f("MANAGE_FAC_BUILDING", int(q["weeks_left"]))
		add_child(_row(Loc.t("FAC_" + k.to_upper()), detail, Loc.t("MANAGE_UPGRADE"), _upgrade.bind(k), "Upgrade_%s" % k, building or lvl >= Facilities.MAX_LEVEL))
		add_child(ChartKit.bar_row("", "%d/%d" % [lvl, Facilities.MAX_LEVEL], float(lvl) / Facilities.MAX_LEVEL,
				UIKit.WARN if building else UIKit.GOLD, 0.0))


func _upgrade(kind: String) -> void:
	var career: CareerState = app().career
	_result(career.facilities.upgrade(career.ledger(), kind, career.week, career.manager.confidence))


# --- staff ---------------------------------------------------------------------------------------------------

func _staff(career: CareerState) -> void:
	add_child(UIKit.muted(Loc.f("MANAGE_STAFF_SLOTS", [career.staff.members.size(), career.staff.slots(career.facilities.level("training"))])))
	add_child(UIKit.muted(Loc.t("DEV_MANAGE_NOTE")))
	var to_coaches := UIKit.button(Loc.t("SCREEN_COACHING_STAFF"), go.bind("coaching_staff"), 200)
	to_coaches.name = "OpenCoachingStaff"
	add_child(to_coaches)
	for role in StaffTeam.UI_ROLES:
		var m := career.staff.member_for(role)
		if not m.is_empty():
			add_child(_row("%s: %s" % [Loc.t("STAFF_" + role.to_upper()), Loc.iso(str(m["name"]))],
					Loc.f("MANAGE_STAFF_DETAIL", [int(m["skill"]), Loc.money(int(m["wage"])), int(m["years"])]), Loc.t("MANAGE_FIRE"), _fire.bind(role), "Fire_%s" % role))
		else:
			var cands := StaffTeam.market(role, career.season, hash(career.club_id) & 0x7fffffff, 3)
			var best: Dictionary = cands[0]
			for c in cands:
				if int(c["skill"]) > int(best["skill"]):
					best = c
			add_child(_row("%s: %s" % [Loc.t("STAFF_" + role.to_upper()), Loc.t("MANAGE_VACANT")],
					Loc.f("MANAGE_STAFF_CANDIDATE", [Loc.iso(str(best["name"])), int(best["skill"]), Loc.money(int(best["wage"]))]), Loc.t("MANAGE_HIRE"), _hire.bind(best), "Hire_%s" % role))


func _hire(candidate: Dictionary) -> void:
	var career: CareerState = app().career
	_result(career.staff.hire(candidate, career.facilities.level("training"), career.ledger(), career.week, career.market.wage_budget_of(career.club_id)))


func _fire(role: String) -> void:
	var career: CareerState = app().career
	_result(career.staff.fire(role, career.ledger(), career.week))


# --- finance: prices, sponsor, loan -------------------------------------------------------------------------

func _finance(career: CareerState) -> void:
	var box := UIKit.vbox(6)
	box.name = "PricesPanel"
	box.add_child(UIKit.label(Loc.t("MANAGE_TICKETS"), 16, UIKit.GOLD))
	var row := UIKit.hbox(UIKit.SPACE_S)
	for lvl in Economy.TICKET_LEVELS:
		var b := UIKit.button(Loc.t("MANAGE_TICKET_" + str(lvl).to_upper()), _ticket.bind(str(lvl)), 100)
		b.name = "Ticket_%s" % lvl
		b.disabled = career.economy.ticket_level == lvl
		row.add_child(b)
	box.add_child(row)
	box.add_child(UIKit.label(Loc.f("MANAGE_SHIRT_PRICE", career.economy.shirt_price), 15))
	var shirt_row := UIKit.hbox(UIKit.SPACE_S)
	var down := UIKit.button("-10", _shirt.bind(-10), 70)
	down.name = "ShirtDown"
	var up := UIKit.button("+10", _shirt.bind(10), 70)
	up.name = "ShirtUp"
	shirt_row.add_child(down)
	shirt_row.add_child(up)
	box.add_child(shirt_row)
	add_child(UIKit.panel(box))
	var offers := Economy.sponsor_offers(career.season, hash(career.club_id) & 0x7fffffff, int(db().get_team(career.club_id).reputation))
	for o in offers:
		var chosen: bool = career.economy.sponsor.get("kind", "") == o["kind"]
		add_child(_row(Loc.t("MANAGE_SPONSOR_" + str(o["kind"]).to_upper()), Loc.f("MANAGE_SPONSOR_DETAIL", [Loc.money(int(o["fixed_weekly"])), Loc.money(int(o["rank_bonus"])), Loc.money(int(o["goal_bonus"]))]),
				Loc.t("MANAGE_CHOOSE"), _sponsor.bind(o), "Sponsor_%s" % o["kind"], chosen))
	var weekly_income := career.weekly_sponsorship(career.club_id) + 25000
	var loan_text := Loc.t("MANAGE_NO_LOAN") if career.economy.loan.is_empty() else Loc.f("MANAGE_LOAN_ACTIVE", [Loc.money(int(career.economy.loan["weekly"])), int(career.economy.loan["weeks_left"])])
	add_child(_row(Loc.t("MANAGE_LOAN"), "%s · %s" % [loan_text, Loc.f("MANAGE_LOAN_LIMIT", Loc.money(Economy.loan_limit(weekly_income)))],
			Loc.t("MANAGE_TAKE_LOAN"), _loan.bind(Economy.loan_limit(weekly_income) / 4, weekly_income), "TakeLoan", not career.economy.loan.is_empty()))


func _ticket(level: String) -> void:
	(app().career as CareerState).economy.set_ticket_level(level)
	rebuild()


func _shirt(delta: int) -> void:
	var e: Economy = (app().career as CareerState).economy
	e.set_shirt_price(e.shirt_price + delta)
	rebuild()


func _sponsor(offer: Dictionary) -> void:
	(app().career as CareerState).economy.choose_sponsor(offer)
	_result("")


func _loan(amount: int, weekly_income: int) -> void:
	var career: CareerState = app().career
	_result(career.economy.take_loan(career.ledger(), amount, weekly_income, career.week))


# --- board -------------------------------------------------------------------------------------------------------

func _board(career: CareerState) -> void:
	var vision := career.vision()
	add_child(UIKit.label(Loc.f("MANAGE_VISION", Loc.t("VISION_" + vision.to_upper())), 16, UIKit.GOLD))
	for kind in BoardRelations.REQUESTS:
		add_child(_row(Loc.t("MANAGE_REQ_" + str(kind).to_upper()), Loc.t("MANAGE_REQ_HINT"), Loc.t("MANAGE_ASK"), _request.bind(str(kind), vision), "Request_%s" % kind, not career.board.can_meet(career)))
	for p in career.board.promises:
		add_child(UIKit.label("%s · %s" % [Loc.t("PROMISE_" + str(p["kind"]).to_upper()), Loc.t("PROMISE_STATUS_" + str(p["status"]).to_upper())], 14))
	for kind in BoardRelations.PROMISE_KINDS:
		var b := UIKit.button(Loc.f("MANAGE_PROMISE", Loc.t("PROMISE_" + str(kind).to_upper())), _promise.bind(str(kind)), 220)
		b.name = "Promise_%s" % kind
		add_child(b)


func _request(kind: String, vision: String) -> void:
	var career: CareerState = app().career
	var r := career.board.request(career, kind, vision)
	say(Loc.t(str(r["reason"])), not bool(r["accepted"]))
	app().state_changed.emit()
	rebuild()


func _promise(kind: String) -> void:
	var career: CareerState = app().career
	_result(career.board.promise(career, kind, 2 if kind == "youth_players" else 0))


# --- skills ------------------------------------------------------------------------------------------------------

func _skills(career: CareerState) -> void:
	var p := career.progress
	add_child(UIKit.label(Loc.f("MANAGE_LEVEL", [p.level(), p.xp, p.points_available()]), 16, UIKit.GOLD))
	for b in ManagerProgress.BRANCHES:
		add_child(_row(Loc.t("SKILL_" + b.to_upper()), Loc.f("MANAGE_BRANCH", [int(p.branch_levels[b]), ManagerProgress.BRANCH_MAX]), Loc.t("MANAGE_LEARN"), _learn.bind(b), "Learn_%s" % b))
	add_child(UIKit.label(Loc.f("MANAGE_ACHIEVEMENTS", p.unlocked.size()), 15))
	for a in p.unlocked:
		add_child(UIKit.label("• " + Loc.t("ACH_" + str(a).to_upper()), 14))


func _learn(branch: String) -> void:
	_result((app().career as CareerState).progress.spend(branch))
