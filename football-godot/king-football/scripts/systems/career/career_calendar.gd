class_name CareerCalendar
extends RefCounted

## Career phases C9.4 / C9.6: read-only views of the season for the calendar screen and the career dashboard. Everything is
## derived from the real competitions, so it can never disagree with the game.


## One entry per week 1..46: {week, matches: [{comp_id, comp_name_key, opponent, home, played, score}], window, is_now}.
static func season_weeks(career: CareerState) -> Array:
	var out: Array = []
	for w in range(1, CareerState.WEEKS_PER_SEASON + 1):
		out.append({"week": w, "matches": [], "window": TransferMarket.window_open(w), "is_now": w == career.week})
	for pair in _user_competitions(career):
		var comp: Competition = pair[0]
		var week_of: Callable = pair[1]
		for f in comp.fixtures:
			if f["home"] != career.club_id and f["away"] != career.club_id:
				continue
			var w: int = int(week_of.call(f))
			if w < 1 or w > CareerState.WEEKS_PER_SEASON:
				continue
			var home: bool = f["home"] == career.club_id
			var entry := {"comp_id": comp.id, "opponent": f["away"] if home else f["home"], "home": home, "played": bool(f["played"]), "score": ""}
			if entry["played"] and comp.results.has(f["match_id"]):
				var r := MatchResult.from_dict(comp.results[f["match_id"]])
				entry["score"] = "%d-%d" % [r.home_goals, r.away_goals] if home else "%d-%d" % [r.away_goals, r.home_goals]
			(out[w - 1]["matches"] as Array).append(entry)
	return out


# --- Phase K: days -------------------------------------------------------------------------------------------

## Every match of the user's club this season with its exact day, oldest first:
## [{jdn, week, day, comp_id, kind ("league"/"cup"/"continental"/"playoff"), opponent, home, played, score, result ("W"/"D"/"L"/"")}].
static func season_days(career: CareerState) -> Array:
	var out: Array = []
	for k in career.pyramids:
		var pyr: LeaguePyramid = career.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = career.competitions.get(pyr.comp[role])
			if comp == null:
				continue
			var kind := "cup" if role == "cup" else ("playoff" if (str(role).begins_with("po:") or str(role).begins_with("rb:")) else "league")
			for f in comp.fixtures:
				if f["home"] != career.club_id and f["away"] != career.club_id:
					continue
				var w := pyr.week_of(role, comp, f)
				out.append(_day_entry(career, comp, f, w, pyr.day_of(role, comp, f), kind))
	if career.continental != null:
		var cc: Competition = career.continental.competition(career)
		if cc != null:
			for f in cc.fixtures:
				if f["home"] != career.club_id and f["away"] != career.club_id:
					continue
				out.append(_day_entry(career, cc, f, career.continental.week_of(f), CareerSchedule.continental_day(str(f["match_id"])), "continental"))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["jdn"]) < int(b["jdn"]))
	return out


static func _day_entry(career: CareerState, comp: Competition, f: Dictionary, w: int, d: int, kind: String) -> Dictionary:
	var home: bool = f["home"] == career.club_id
	var e := {"jdn": CareerDate.jdn_of(career.season, w, d), "week": w, "day": d, "comp_id": comp.id, "kind": kind,
			"match_id": f["match_id"], "opponent": f["away"] if home else f["home"], "home": home, "played": bool(f["played"]), "score": "", "result": ""}
	if e["played"] and comp.results.has(f["match_id"]):
		var r := MatchResult.from_dict(comp.results[f["match_id"]])
		var mine := r.home_goals if home else r.away_goals
		var theirs := r.away_goals if home else r.home_goals
		e["score"] = "%d-%d" % [mine, theirs]
		e["result"] = "W" if mine > theirs else ("L" if mine < theirs else "D")
	return e


## Everything the month view needs for `month` of `year`: {year, month, first_weekday (0 = Monday), days: [{jdn, day,
## past, today, match (entry or {}), training (plan), break (international), window (transfer window open)}]}.
static func month_view(career: CareerState, year: int, month: int) -> Dictionary:
	var first := CareerDate.jdn(year, month, 1)
	var next_first := CareerDate.jdn(year + (1 if month == 12 else 0), 1 if month == 12 else month + 1, 1)
	var today := CareerDate.jdn_of(career.season, career.week, career.day)
	var by_jdn := {}
	for e in season_days(career):
		by_jdn[int(e["jdn"])] = e
	var matches := {}
	for j in by_jdn:
		matches[j] = true
	var days: Array = []
	for j in range(first, next_first):
		var wd := CareerDate.week_day_of(career.season, j)
		var info := {"jdn": j, "day": CareerDate.from_jdn(j)["day"], "past": j < today, "today": j == today,
				"match": by_jdn.get(j, {}), "training": career.training.day_plan(career, j, matches),
				"break": NationalBreaks.is_break(int(wd["week"])) and int(wd["week"]) > 0,
				"window": TransferMarket.window_days_left(career.season, int(wd["week"]), int(wd["day"])) > 0}
		days.append(info)
	return {"year": year, "month": month, "first_weekday": CareerDate.from_jdn(first)["weekday"], "days": days}


## The months of the season in order (July .. June): [[year, month], ...].
static func season_months(career: CareerState) -> Array:
	var y := CareerDate.season_year(career.season)
	var out: Array = []
	for m in range(7, 13):
		out.append([y, m])
	for m in range(1, 7):
		out.append([y + 1, m])
	return out


## [[Competition, week_of Callable], ...] of every competition the user's club plays this season.
static func _user_competitions(career: CareerState) -> Array:
	var out: Array = []
	for k in career.pyramids:
		var pyr: LeaguePyramid = career.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = career.competitions.get(pyr.comp[role])
			if comp != null:
				out.append([comp, func(f: Dictionary) -> int: return pyr.week_of(role, comp, f)])
	if career.continental != null:
		var cc: Competition = career.continental.competition(career)
		if cc != null:
			out.append([cc, func(f: Dictionary) -> int: return career.continental.week_of(f)])
	return out


## The next unplayed match of the user (this week or later): {week, comp_id, opponent, home} or {}.
static func next_match(career: CareerState) -> Dictionary:
	for e in season_weeks(career):
		if int(e["week"]) < career.week:
			continue
		for m in e["matches"]:
			if not bool(m["played"]):
				var out: Dictionary = (m as Dictionary).duplicate()
				out["week"] = int(e["week"])
				return out
	return {}


## The user's last `n` results, newest first: [{week, comp_id, opponent, home, score}].
static func recent_results(career: CareerState, n: int = 5) -> Array:
	var played: Array = []
	for e in season_weeks(career):
		for m in e["matches"]:
			if bool(m["played"]) and str(m["score"]) != "":
				var item: Dictionary = (m as Dictionary).duplicate()
				item["week"] = int(e["week"])
				played.append(item)
	played.reverse()
	return played.slice(0, n)


## Position and points of the user's club in its league: {rank, points, played, size} or {}.
static func league_line(career: CareerState) -> Dictionary:
	var ud := career.user_division()
	if ud.is_empty():
		return {}
	var pyr: LeaguePyramid = career.pyramids[ud["pyramid"]]
	var comp: Competition = career.competitions.get(pyr.comp.get(ud["division"]["id"], ""))
	if comp == null:
		return {}
	var st := comp.standings()
	for i in st.size():
		if st[i]["team_id"] == career.club_id:
			return {"rank": i + 1, "points": int(st[i].get("points", 0)), "played": int(st[i].get("played", 0)), "size": st.size()}
	return {}
