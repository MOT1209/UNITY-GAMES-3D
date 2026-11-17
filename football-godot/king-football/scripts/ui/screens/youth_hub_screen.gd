extends HubScreen

## Youth hub: academy staff (hire), U19 league table and results, youth cup, youth loans and mentors.

func build() -> void:
	if not header(Loc.t("SCREEN_YOUTH_HUB"), true):
		return
	var ac: Academy = app().academy()
	if ac == null:
		add_child(UIKit.empty_state(Loc.t("COMMON_ONLY_CLUBS_HAVE_AN_ACADEMY")))
		return
	var d := YouthDevelopment.state(ac)
	add_child(UIKit.label(Loc.f("ACADEMY_BUDGET", ac.budget), 16))
	_staff(ac, d)
	_league(ac, d)
	_cup(d)
	_loans(ac, d)
	_mentors(ac, d)


func _section(key: String) -> void:
	add_child(UIKit.label(Loc.t(key), 18, UIKit.GOLD))


func _staff(ac: Academy, d: Dictionary) -> void:
	_section("YOUTH_STAFF")
	for role in YouthDevelopment.STAFF_ROLES:
		var s: Dictionary = d["staff"][role]
		var nm := str(s["name"])
		if nm == "" or nm in ["Academy Director", "Youth Coach"]:          # the club's original staff (older saves: English)
			nm = Loc.t("YOUTH_STAFF_ORIGINAL")
		add_child(UIKit.label(Loc.f("YOUTH_STAFF_LINE", [Loc.t("YOUTH_ROLE_" + role.to_upper()), nm, roundi(float(s["quality"]) * 100.0)]), 15))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		var list := YouthDevelopment.staff_candidates(ac, role)
		for i in list.size():
			var c: Dictionary = list[i]
			var b := UIKit.button(Loc.f("YOUTH_HIRE_CANDIDATE", [c["name"], roundi(float(c["quality"]) * 100.0), YouthDevelopment.hire_fee(c)]),
					_hire.bind(role, i), 260)
			b.name = "Hire_%s_%d" % [role, i]
			b.disabled = YouthDevelopment.hire_fee(c) > ac.budget
			row.add_child(b)
		add_child(row)


func _league(ac: Academy, d: Dictionary) -> void:
	_section("YOUTH_LEAGUE")
	var teams := YouthDevelopment.league_teams(db(), ac)
	var own_name := Loc.f("YOUTH_OWN_TEAM", db().get_team(ac.team_id).display_name)
	var rows: Array = []
	var pos := 1
	for r in YouthDevelopment.table(db(), ac):
		var nm: String = own_name if r["id"] == "own" else Loc.f("YOUTH_OWN_TEAM", teams[r["id"]]["name"])
		rows.append([pos, nm, r["p"], r["w"], r["d"], r["l"], "%d:%d" % [r["gf"], r["ga"]], r["pts"]])
		pos += 1
	add_child(UIKit.table(["#", Loc.t("COMMON_NAME"), Loc.t("YOUTH_COL_P"), Loc.t("YOUTH_COL_W"), Loc.t("YOUTH_COL_D"),
			Loc.t("YOUTH_COL_L"), "+/-", Loc.t("YOUTH_COL_PTS")], rows))
	var res: Array = d["results"]
	if res.is_empty():
		add_child(UIKit.muted(Loc.t("YOUTH_NO_RESULTS")))
	for i in range(res.size() - 1, maxi(res.size() - 6, -1), -1):
		var m: Dictionary = res[i]
		add_child(UIKit.label(Loc.f("YOUTH_RESULT", [own_name, m["for"], m["against"], Loc.f("YOUTH_OWN_TEAM", m["opp"])]), 14))


func _cup(d: Dictionary) -> void:
	_section("YOUTH_CUP")
	var cup: Dictionary = d["cup"]
	var key := "YOUTH_CUP_WON" if bool(cup["won"]) else ("YOUTH_CUP_OUT" if bool(cup["out"]) else "YOUTH_CUP_ROUND")
	add_child(UIKit.label(Loc.f(key, int(cup["round"]) + 1), 15))


func _loans(ac: Academy, d: Dictionary) -> void:
	_section("YOUTH_LOANS")
	var loans: Dictionary = d["loans"]
	for pid in loans:
		var p: PlayerData = db().get_player(pid)
		var l: Dictionary = loans[pid]
		var row := UIKit.hbox(8)
		var avg := float(l["rating_sum"]) / maxf(float(l["apps"]), 1.0)
		row.add_child(UIKit.label(Loc.f("YOUTH_LOAN_LINE", [p.display_name if p != null else pid, l["club"], l["apps"], "%.1f" % avg, l["weeks_left"]]), 14))
		row.add_child(UIKit.button(Loc.t("YOUTH_RECALL"), _recall.bind(pid), 100))
		add_child(row)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	for p in YouthDevelopment.available(db(), ac):
		if p.age < YouthDevelopment.MIN_LOAN_AGE:
			continue
		var b := UIKit.button(Loc.f("YOUTH_LOAN_OUT", [p.display_name, p.get_overall()]), _loan.bind(p.id), 220)
		b.disabled = loans.size() >= YouthDevelopment.MAX_LOANS
		flow.add_child(b)
	add_child(flow)


func _mentors(ac: Academy, d: Dictionary) -> void:
	_section("YOUTH_MENTORS")
	add_child(UIKit.muted(Loc.t("YOUTH_MENTORS_HINT")))
	var seniors: Array = []
	for p in db().get_squad(ac.team_id):
		if p.age >= 26:
			seniors.append(p)
	seniors.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	seniors = seniors.slice(0, 12)
	var names: Array = [Loc.t("YOUTH_NO_MENTOR")] + seniors.map(func(s: PlayerData) -> String:
		return "%s (%d)%s" % [s.display_name, s.get_overall(), (" · " + Loc.traits_text(s.traits)) if not s.traits.is_empty() else ""])
	var mentors: Dictionary = d["mentors"]
	var prospects := YouthDevelopment.available(db(), ac).slice(0, 8)
	for p in prospects:
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label("%s (%d)" % [p.display_name, p.get_overall()], 14))
		var cur := 0
		for i in seniors.size():
			if mentors.get(p.id, "") == (seniors[i] as PlayerData).id:
				cur = i + 1
		row.add_child(UIKit.option(names, cur, func(i: int) -> void:
			YouthDevelopment.set_mentor(ac, p.id, "" if i == 0 else (seniors[i - 1] as PlayerData).id)))
		add_child(row)


func _hire(role: String, i: int) -> void:
	var err := YouthDevelopment.hire_staff(app().academy(), role, i)
	say(err if err != "" else Loc.t("YOUTH_HIRED"), err != "")
	rebuild()


func _loan(pid: String) -> void:
	var err := YouthDevelopment.loan_out(db(), app().academy(), pid)
	say(err if err != "" else Loc.t("YOUTH_LOANED"), err != "")
	rebuild()


func _recall(pid: String) -> void:
	YouthDevelopment.recall(app().academy(), pid)
	rebuild()
