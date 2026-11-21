extends HubScreen

## Coaching staff: the six development departments, their coaches (stars, ratings, contract), vacancies, weekly wages,
## renew / dismiss, and the way to the recruitment market.

func build() -> void:
	if not header(Loc.t("SCREEN_COACHING_STAFF"), true, true):
		return
	var c: CareerState = app().career
	DevelopmentEngine.ensure_staff(c, c.development)
	var cs: CoachingStaff = c.development.coaching
	var lvl := c.facilities.level("training")
	add_child(UIKit.label(Loc.f("DEV_STAFF_SUMMARY", [Loc.money(int(cs.weekly_wages())), cs.coaches.size(), DevConfig.total_slots(lvl), DevConfig.dept_cap(lvl)]), 16))
	add_child(UIKit.muted(Loc.t("DEV_STAFF_HINT")))
	for dept in DevConfig.DEPARTMENTS:
		add_child(UIKit.label(Loc.t("DEV_DEPT_" + dept.to_upper()), 18, UIKit.GOLD))
		var list := cs.in_department(dept)
		if list.is_empty():
			add_child(UIKit.label(Loc.f("DEV_VACANCY", Loc.t("DEV_DEPT_" + dept.to_upper())), 15, UIKit.MUTED))
		for co in list:
			_coach_row(c, cs, co)
		var b := UIKit.button(Loc.t("DEV_RECRUIT"), go.bind("coach_recruitment", {"department": dept}), 160)
		b.name = "Recruit_%s" % dept
		add_child(b)
	add_child(UIKit.label(Loc.t("DEV_ACTIVITY"), 18, UIKit.GOLD))
	if cs.activity.is_empty():
		add_child(UIKit.muted(Loc.t("DEV_NO_ACTIVITY")))
	for i in range(cs.activity.size() - 1, maxi(cs.activity.size() - 8, -1), -1):
		var a: Dictionary = cs.activity[i]
		add_child(UIKit.muted(Loc.f("DEV_ACTIVITY_LINE", [Loc.t("DEV_ACT_" + str(a["kind"]).to_upper()), a["name"], a["week"]])))


func _coach_row(c: CareerState, cs: CoachingStaff, co: Dictionary) -> void:
	var box := UIKit.vbox(2)
	box.add_child(UIKit.label("%s  %s  (%s)" % [co["name"], DevConfig.stars_text(int(co["overall"])), Loc.t(DevConfig.star_key(int(co["overall"])))], 16))
	box.add_child(UIKit.muted(Loc.f("DEV_COACH_RATINGS", [co["overall"], co["technical"], co["tactical"], co["youth"], co["pro"], Loc.t("DEV_SPEC_" + str(co["specialization"]).to_upper())])))
	box.add_child(UIKit.muted(Loc.f("DEV_COACH_CONTRACT", [Loc.money(int(co["salary"])), CoachingStaff.years_left(co, c.season), co["expiry_season"], co["age"], co["experience"], co["reputation"]])))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var renew := UIKit.button(Loc.t("DEV_RENEW"), _renew.bind(str(co["id"])), 140)
	renew.name = "Renew_%s" % co["id"]
	row.add_child(renew)
	var fire := UIKit.button(Loc.f("DEV_DISMISS", Loc.money(int(CoachingStaff.dismiss_cost(co, c.season)))), _dismiss.bind(str(co["id"])), 200)
	fire.name = "Dismiss_%s" % co["id"]
	row.add_child(fire)
	var groups: Array = [""] + AcademyConfig.group_ids()
	var go_ := UIKit.option(groups.map(func(g: String) -> String: return Loc.t("DEV_GROUP_ALL") if g == "" else Loc.enum_name("AGEGROUP", g)), groups.find(str(co.get("youth_group", ""))), func(i: int) -> void:
		cs.assign_group(str(co["id"]), groups[i])
		rebuild())
	go_.name = "Group_%s" % co["id"]
	row.add_child(UIKit.label(Loc.t("DEV_ACADEMY_GROUP"), 14, UIKit.MUTED))
	row.add_child(go_)
	box.add_child(row)
	add_child(UIKit.panel(box))


func _renew(id: String) -> void:
	var c: CareerState = app().career
	var co := c.development.coaching.coach(id)
	var r := c.development.coaching.renew(id, int(CoachingStaff.salary_demand(co) * 1.1), 2, c.ledger(), c.absolute_week(), c.season, c.staff.weekly_wages(), c.market.wage_budget_of(c.club_id))
	say(Loc.t("DEV_RENEWED") if r["ok"] else Loc.t(str(r["error"])), not r["ok"])
	rebuild()


func _dismiss(id: String) -> void:
	var c: CareerState = app().career
	var co := c.development.coaching.coach(id)
	UIKit.confirm(self, Loc.f("DEV_CONFIRM_DISMISS", [co["name"], CoachingStaff.dismiss_cost(co, c.season)]), func() -> void:
		c.development.coaching.dismiss(id, c.ledger(), c.absolute_week(), c.season)
		say(Loc.t("DEV_DISMISSED"))
		rebuild())
