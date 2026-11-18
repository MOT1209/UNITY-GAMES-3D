class_name CareerState
extends "res://scripts/systems/career/career_state_part2.gd"

## Career state, part 3 of 3. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: advance_week, advance_week_async, advance_day, _finish_week, _begin_week, _run_step,
## referenced_player_ids, style_mods, injury_factor_for, recovery_factor_for, due_user_fixtures, to_dict,
## _pyramids_dict, parse, _restore_report, from_dict.

## Plays one calendar week: pays wages, runs loans, and — when the academy
## systems are passed — runs exactly one week of youth training and scouting
## per club (the career calendar is the only clock, so training can't be
## repeated for free). Returns a summary dict.
func advance_week(squads: Dictionary = {}, academies: Dictionary = {},
		trainings: Dictionary = {}, scouting: Dictionary = {}) -> Dictionary:
	if day < 6 and week > 0:
		return _finish_week(squads)                 # Phase K: the rest of a week started day by day
	var run := _begin_week(squads, academies, trainings, scouting)
	if run.has("blocked"):
		return run
	for step in _week_steps():
		_run_step(step, run)
	return _end_week(run)


## Same week, same results (identical to `advance_week`, byte for byte), but it hands control back to the engine between the
## phases so a UI is not frozen for the whole week: `await career.advance_week_async(...)`. Only one week can run at a time;
## a second call while one is running returns {"blocked": true, "busy": true} and changes nothing.
func advance_week_async(squads: Dictionary = {}, academies: Dictionary = {},
		trainings: Dictionary = {}, scouting: Dictionary = {}) -> Dictionary:
	if _advancing:
		return {"week": week, "blocked": true, "busy": true, "season_over": week >= WEEKS_PER_SEASON}
	if day < 6 and week > 0:
		return _finish_week(squads)
	_advancing = true
	var run := _begin_week(squads, academies, trainings, scouting)
	if run.has("blocked"):
		_advancing = false
		return run
	var tree := Engine.get_main_loop() as SceneTree
	for step in _week_steps():
		_run_step(step, run)
		if tree != null:
			await tree.process_frame
	_advancing = false
	return _end_week(run)


## Plays ONE day. On a Monday (the first day of the next week) the weekly systems run first — wages, transfers, training,
## morale, club operations ... exactly as in `advance_week` — and then only Monday's fixtures; every other day plays that
## day's fixtures (`CareerSchedule`). Advancing day by day through a whole week gives the same fixtures, results and weekly
## bookings as `advance_week`. Returns the summary of `advance_week` plus "day" and "date".
func advance_day(squads: Dictionary = {}, academies: Dictionary = {},
		trainings: Dictionary = {}, scouting: Dictionary = {}) -> Dictionary:
	if week == 0 or day >= 6:
		var run := _begin_week(squads, academies, trainings, scouting)
		if run.has("blocked"):
			return run
		day = 0
		run["max_day"] = 0
		for step in _week_steps():
			_run_step(step, run)
		var out := _end_week(run)
		out["day"] = day
		out["date"] = date()
		return out
	day += 1
	DailyLife.day(self, CareerDate.jdn_of(season, week, day))
	var run2 := {"squads": squads, "user_fixtures": [], "auto_played": [], "simulated": 0, "max_day": day}
	for step in _match_steps():
		_run_step(step, run2)
	return {"week": week, "day": day, "date": date(), "season_over": week >= WEEKS_PER_SEASON and day >= 6,
			"user_fixtures": run2["user_fixtures"], "auto_played": run2["auto_played"], "simulated": run2["simulated"],
			"wages_paid": 0, "loans_returned": [], "trained_ids": [], "found_ids": [], "ai_transfers": []}


## The rest of a week that was entered day by day: every remaining fixture is played and the week ends on Sunday.
func _finish_week(squads: Dictionary) -> Dictionary:
	for d in range(day + 1, 7):
		DailyLife.day(self, CareerDate.jdn_of(season, week, d))
	day = 6
	var run := {"squads": squads, "user_fixtures": [], "auto_played": [], "simulated": 0, "max_day": 6}
	for step in _match_steps():
		_run_step(step, run)
	return {"week": week, "day": day, "date": date(), "season_over": week >= WEEKS_PER_SEASON,
			"user_fixtures": run["user_fixtures"], "auto_played": run["auto_played"], "simulated": run["simulated"],
			"wages_paid": 0, "loans_returned": [], "trained_ids": [], "found_ids": [], "ai_transfers": []}


func _begin_week(squads: Dictionary, academies: Dictionary, trainings: Dictionary, scouting: Dictionary) -> Dictionary:
	if week >= WEEKS_PER_SEASON:
		# The season is over: nothing is played and nobody is paid until `end_season()`.
		return {"week": week, "wages_paid": 0, "loans_returned": [], "season_over": true, "blocked": true,
				"trained_ids": [], "found_ids": [], "user_fixtures": [], "auto_played": [], "simulated": 0, "ai_transfers": []}
	week += 1
	day = 6                                         # a whole week (advance_day sets 0 itself)
	_settle_old_friendlies()
	_friendlies_for_week()
	market.sync_clock(season, week, club_id, world_stats)
	last_timings.clear()
	return {"squads": squads, "academies": academies, "trainings": trainings, "scouting": scouting,
			"trained_ids": [] as Array[String], "found_ids": [] as Array[String], "wages_paid": 0, "returned": [] as Array[String],
			"deals": [], "user_fixtures": [], "auto_played": [], "simulated": 0}


func _run_step(step: String, run: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var phase := step
	match step:
		"daily":
			# Phase K3: the days of this run (7 for a whole week, Monday only for advance_day)
			var n := 1 if int(run.get("max_day", 6)) == 0 else 7
			var start := CareerDate.jdn_of(season, week, 0)
			for i in n:
				DailyLife.day(self, start + i)
		"academy":
			var now := absolute_week()
			var trainings: Dictionary = run["trainings"]
			var academies: Dictionary = run["academies"]
			for team_id in trainings:
				if academies.has(team_id):
					(trainings[team_id] as TrainingSystem).dev_bonus = float(manager.style_effects()["youth"]) * facilities.development_factor() * staff.youth_factor() * (1.0 + progress.effect("youth")) * training.development_factor() * YouthDevelopment.coach_factor(academies[team_id]) if team_id == club_id and not manager.unemployed else 1.0
					var gains: Dictionary = (trainings[team_id] as TrainingSystem).sync_to_calendar(db, academies[team_id], now)
					if team_id == club_id:
						run["trained_ids"].assign(gains.keys())
			var scouting: Dictionary = run["scouting"]
			for team_id in scouting:
				if academies.has(team_id):
					var found: Array[String] = (scouting[team_id] as ScoutingSystem).sync_to_calendar(db, academies[team_id], now)
					if team_id == club_id:
						run["found_ids"] = found
			if academies.has(club_id) and not manager.unemployed:
				var club_team: TeamData = db.get_team(club_id)
				for e in YouthDevelopment.sync(db, academies[club_id], club_team.squad_ids if club_team != null else [], now):
					inbox.add("youth:%d:%d:%s" % [season, week, e["key"]], season, week, "board", e["key"], (e["args"] as Array).map(func(x: Variant) -> String: return str(x)), {"action": {"screen": "youth_hub", "params": {}}})
		"finance":
			for team_id in ledgers:
				var wages := market.squad_wage_bill(team_id)
				if wages > 0:
					(ledgers[team_id] as FinanceLedger).record("salary", -wages, "Weekly wages", week, "FIN_WEEKLY_WAGES")
					if team_id == club_id:
						run["wages_paid"] = wages
				var share := market.lender_wage_share(team_id)     # wages of players loaned out (the lender's share)
				if share > 0:
					(ledgers[team_id] as FinanceLedger).record("salary", -share, "Loan wage share", week, "FIN_LOAN_WAGE_SHARE")
			for team_id in ledgers:
				(ledgers[team_id] as FinanceLedger).record("sponsorship", weekly_sponsorship(team_id), "Sponsorship", week, "FIN_SPONSORSHIP")
				# C7: shirt sales for EVERY club by the same rule (the user's price and fans, defaults for the others)
				var merch := economy.merchandise_income(int(db.get_team(team_id).reputation), fan_mood) if team_id == club_id else Economy.default_merchandise(int(db.get_team(team_id).reputation))
				if merch > 0:
					(ledgers[team_id] as FinanceLedger).record("merchandise", merch, "Shirt sales", week, "FIN_MERCHANDISE")
		"loans":
			run["returned"] = market.advance_loans(week, run["squads"])
		"ai_transfers":
			run["deals"] = AITransfers.run_week(self, run["squads"])
			AITransfers.offers_to_user(self, run["squads"])
			market.process_week(self, run["squads"])
		"availability":
			Availability.weekly(self, run["squads"])
		"morale":
			var lr := _last_user_result()
			morale.weekly(self, lr)
			var last := CareerCalendar.recent_results(self, 1)
			if lr in ["win", "loss"] and not last.is_empty() and int(last[0]["week"]) >= week - 1 and WorldLife.is_derby(db, club_id, str(last[0]["opponent"])):
				for pl: PlayerData in db.get_squad(club_id).filter(func(x: PlayerData) -> bool: return x.status != PlayerData.Status.YOUTH):
					morale.apply(pl, 3 if lr == "win" else -3, "MORALE_DERBY", season, week)
				fan_mood = clampi(fan_mood + (3 if lr == "win" else -3), 0, 100)
			if lr != "":
				var lres := CareerCalendar.recent_results(self, 1)
				if not lres.is_empty():
					media.post_match(self, lr, str(lres[0]["opponent"]), str(lres[0]["score"]))
				if not lres.is_empty():
					var sc := str(lres[0]["score"]).split("-")
					if sc.size() == 2 and Matchday.press_due(int(sc[0]), int(sc[1])) and pending_press.is_empty():
						pending_press = {"opponent": str(lres[0]["opponent"]), "score": str(lres[0]["score"]), "week": week}
						inbox.add("press:%d:%d" % [season, week], season, week, "media", "INBOX_PRESS_DUE", [str(lres[0]["score"])], {"needs_decision": true, "action": {"screen": "career", "params": {}}})
				media.fan_event(self, 2 if lr == "win" else (-2 if lr == "loss" else 0), "FAN_" + lr.to_upper())
				progress.record_result(lr)
				if lr == "win":
					progress.progress_challenge("win_3", 1, self)
			if not progress.challenges.is_empty() or week == 1:
				if progress.challenges.is_empty():
					progress.challenges = ManagerProgress.new_challenges(season)
			for a in progress.check_achievements(self):
				inbox.add("ach:%s" % a, season, week, "board", "ACH_" + str(a).to_upper(), [], {})
		"club_ops":
			var done := facilities.weekly(ledger(), week)
			for k in done:
				inbox.add("fac_done:%s:%d:%d" % [k, season, week], season, week, "board", "INBOX_FACILITY_DONE", [str(k)], {})
			staff.weekly(ledger(), week)
			economy.weekly_loan(ledger(), week)
			if week == 1:
				world.play_super_cup(self)
			if week % 4 == 0:
				world.monthly_awards(self)
			national.weekly(self)
			relations.weekly_promises(self)
			relations.weekly_demands(self)
			relations.weekly_leaders(self)
			relations.weekly_position_training(self)
			relations.weekly_mentoring(self)
			media.weekly_rumour(self)
			media.deliver_rumours(self)
			if week == int(TransferMarket.WINDOWS[0][1]) + 1:
				economy.window_passed()                 # the first window of the season is over: a one-window ban ends
			delegation.quality = staff.assistant_quality()
		"assistant":
			delegation.run_week(self, run["squads"], run["academies"])
		"continental":
			if continental != null:
				var cr: Dictionary = continental.play_week(week, self, club_id, int(run.get("max_day", 6)))
				_collect(run, cr)
		_:
			phase = "leagues"
			var key: String = step.substr(7)
			if pyramids.has(key):
				_collect(run, (pyramids[key] as LeaguePyramid).play_week(week, self, club_id, int(run.get("max_day", 6))))
	last_timings[phase] = int(last_timings.get(phase, 0)) + Time.get_ticks_usec() - t0


## Every player id that some record of this career still points at (statistics, awards, transfers, reports, news events).
## Retired players in this set are never purged from the database.
func referenced_player_ids() -> Dictionary:
	var ids := {}
	for k in player_stats:
		ids[k] = true
	for k in season_stats:
		ids[k] = true
	for k in yellow_counts:
		ids[k] = true
	for k in world_stats:
		ids[k] = true
	for a in award_history:
		var aw: Dictionary = a.get("awards", {})
		for kind in ["golden_boot", "player_of_the_season", "best_goalkeeper", "best_young_player"]:
			ids[str(aw.get(kind, ""))] = true
		for pid in aw.get("team_of_the_season", []):
			ids[str(pid)] = true
	for h in market.history:
		ids[str(h.get("player_id", ""))] = true
	for rep: Dictionary in match_log:
		ids[str(rep.get("motm", ""))] = true
		for p in rep.get("players", []):
			ids[str(p.get("player_id", ""))] = true
	for e in events:
		for a in e.get("args", []):
			if a is String:
				ids[a] = true
	return ids


## The managed club's fixtures that are due (league, cup, play-off, continental): [[Competition, fixture], ...].
## The coach style's effect on simulated matches of the managed club (see ManagerProfile.STYLES).
func style_mods() -> Dictionary:
	if manager.unemployed:
		return {}
	var e := manager.style_effects()
	if _atmosphere_week != week + season * 100:
		_atmosphere = float(MoraleSystem.atmosphere(db, club_id)["factor"])
		_atmosphere_week = week + season * 100
	var f := settings.match_factors()
	return {"club": club_id, "atk": float(e["atk"]) * _atmosphere * float(f["atk"]), "def": float(e["def"]) / _atmosphere * float(f["def"])}


## C2.5 / C2.6: injury chance and recovery multipliers (facilities x staff) for the managed club; 1.0 for every other club.
func injury_factor_for(team_id: String) -> float:
	return facilities.injury_factor() * staff.injury_factor() * (1.0 - progress.effect("fitness")) if team_id == club_id else 1.0


func recovery_factor_for(team_id: String) -> float:
	return facilities.recovery_factor() * staff.recovery_factor() if team_id == club_id else 1.0


func due_user_fixtures() -> Array:
	var mine: Array = []
	for k in pyramids:
		var pyr: LeaguePyramid = pyramids[k]
		for role in pyr.comp:
			var comp: Competition = competitions.get(pyr.comp[role])
			if comp == null:
				continue
			for f in comp.pending_fixtures():
				var fw := pyr.week_of(role, comp, f)
				if (f["home"] == club_id or f["away"] == club_id) and (fw < week or (fw == week and pyr.day_of(role, comp, f) <= day)):
					mine.append([comp, f])                 # Phase K: due once its day has come
	for pair in friendly_comps():
		for f in (pair[0] as Competition).pending_fixtures():
			if int(pair[1]) < week or (int(pair[1]) == week and FRIENDLY_DAY <= day):
				mine.append([pair[0], f])
	if continental != null:
		var cc: Competition = continental.competition(self)
		if cc != null:
			for f in cc.pending_fixtures():
				var cw := continental.week_of(f)
				if (f["home"] == club_id or f["away"] == club_id) and (cw < week or (cw == week and CareerSchedule.continental_day(str(f["match_id"])) <= day)):
					mine.append([cc, f])
	return mine


func to_dict() -> Dictionary:
	var l := {}
	for k in ledgers:
		l[k] = (ledgers[k] as FinanceLedger).to_dict()
	var c := {}
	for k in competitions:
		c[k] = (competitions[k] as Competition).to_dict()
	return {"club_id": club_id, "season": season, "week": week, "day": day, "ledgers": l,
			"market": market.to_dict(), "competitions": c, "club_history": club_history.duplicate(true),
			"released": released_players.duplicate(),
			"pyramids": _pyramids_dict(), "club_levels": club_levels.duplicate(),
			"match_log": match_log.duplicate(true), "player_stats": player_stats.duplicate(true),
			"season_stats": season_stats.duplicate(true), "sim_comp_stats": sim_comp_stats.duplicate(true), "manager": manager.to_dict(), "yellow_counts": yellow_counts.duplicate(),
			"world_stats": world_stats.duplicate(true), "world_stats_legacy": world_stats_legacy, "continental": continental.to_dict() if continental != null else {}, "award_history": award_history.duplicate(true), "events": events.duplicate(true), "inbox": inbox.to_dict(), "training": training.to_dict(), "delegation": delegation.to_dict(), "morale": morale.to_dict(), "fan_mood": fan_mood, "board": board.to_dict(), "facilities": facilities.to_dict(), "economy": economy.to_dict(), "progress": progress.to_dict(), "world": world.to_dict(), "media": media.to_dict(), "relations": relations.to_dict(), "settings": settings.to_dict(), "pending_press": pending_press.duplicate(), "national": national.to_dict(), "staff": staff.to_dict(), "season_extras": season_extras.duplicate(true)}


func _pyramids_dict() -> Dictionary:
	var out := {}
	for k in pyramids:
		out[k] = (pyramids[k] as LeaguePyramid).to_dict()
	return out


## Safe loader for data that may be damaged: shape check, build, then the integrity audit. Returns
## {"ok", "career" (null unless ok), "errors", "warnings"}; nothing is modified on failure. `deep` also validates every player.
static func parse(p_db: Node, d: Variant, deep: bool = false) -> Dictionary:
	var errors := CareerValidator.check_shape(d)
	if not errors.is_empty():
		return {"ok": false, "career": null, "errors": errors, "warnings": []}
	var c := from_dict(p_db, d)
	var audit := CareerValidator.validate(c, deep)
	var ok: bool = (audit["errors"] as Array).is_empty()
	return {"ok": ok, "career": c if ok else null, "errors": audit["errors"], "warnings": audit["warnings"]}


static func _restore_report(r: Dictionary) -> Dictionary:
	var out := r.duplicate(true)
	for k in _REPORT_INTS:
		if out.has(k):
			out[k] = int(out[k])
	if out.has("team_stats"):
		out["team_stats"] = PlayerData._restore_ints(out["team_stats"])
	if out.has("scorers"):
		out["scorers"] = PlayerData._restore_ints(out["scorers"])
	for p in out.get("players", []):
		for k in _REPORT_PLAYER_INTS:
			if p.has(k):
				p[k] = int(p[k])
	return out


static func from_dict(p_db: Node, d: Dictionary) -> CareerState:
	var c := CareerState.new()
	c.db = p_db
	c.club_id = str(d.get("club_id", ""))
	c.season = int(d.get("season", 1))
	c.week = int(d.get("week", 0))
	for pid in (d.get("sim_comp_stats", {}) as Dictionary):
		var by_key2: Dictionary = {}
		for key in d["sim_comp_stats"][pid]:
			var s2: Dictionary = d["sim_comp_stats"][pid][key]
			by_key2[key] = {"apps": int(s2.get("apps", 0)), "goals": int(s2.get("goals", 0)), "assists": int(s2.get("assists", 0)),
					"saves": int(s2.get("saves", 0)), "rating_sum": float(s2.get("rating_sum", 0.0)), "motm": int(s2.get("motm", 0)),
					"yellow": int(s2.get("yellow", 0)), "red": int(s2.get("red", 0)), "clean_sheets": int(s2.get("clean_sheets", 0))}
		c.sim_comp_stats[pid] = by_key2
	c.training = TrainingPlan.from_dict(d.get("training", {}))
	c.day = clampi(int(d.get("day", 6)), 0, 6)       # Phase K migration: a week-based save is at the end of its week
	for k in (d.get("ledgers", {}) as Dictionary):
		c.ledgers[k] = FinanceLedger.from_dict(d["ledgers"][k])
	c.market = TransferMarket.new(p_db, c.ledgers)
	c.market.sync_clock(c.season, c.week, c.club_id, c.world_stats)
	c.market.load_state(d.get("market", {}))
	for k in (d.get("competitions", {}) as Dictionary):
		c.competitions[k] = Competition.from_dict(d["competitions"][k])
	c.club_history = PlayerData._restore_ints((d.get("club_history", []) as Array).duplicate(true))
	c.released_players = (d.get("released", []) as Array).map(func(x: Variant) -> String: return str(x))
	for rep in d.get("match_log", []):
		c.match_log.append(_restore_report(rep))
	for k in (d.get("player_stats", {}) as Dictionary):
		var s: Dictionary = d["player_stats"][k]
		c.player_stats[k] = {"apps": int(s.get("apps", 0)), "goals": int(s.get("goals", 0)), "assists": int(s.get("assists", 0)),
				"saves": int(s.get("saves", 0)), "rating_sum": float(s.get("rating_sum", 0.0)), "motm": int(s.get("motm", 0))}
	c.manager = ManagerProfile.from_dict(d.get("manager", {}))
	for k in (d.get("yellow_counts", {}) as Dictionary):
		c.yellow_counts[k] = int(d["yellow_counts"][k])
	if not (d.get("continental", {}) as Dictionary).is_empty():
		c.continental = ContinentalCup.from_dict(d["continental"])
	var any_split := false
	for k in (d.get("world_stats", {}) as Dictionary):
		c.world_stats[k] = SeasonStats.restore_row(d["world_stats"][k])
		any_split = any_split or d["world_stats"][k].has("est_apps")
	c.world_stats_legacy = bool(d.get("world_stats_legacy", false)) or (not c.world_stats.is_empty() and not any_split)
	c.award_history = PlayerData._restore_ints((d.get("award_history", []) as Array).duplicate(true))
	for e in d.get("events", []):
		var ev: Dictionary = PlayerData._restore_ints((e as Dictionary).duplicate(true))
		c.events.append(ev)
	for pid in (d.get("season_stats", {}) as Dictionary):
		var by_key: Dictionary = {}
		for key in d["season_stats"][pid]:
			var s: Dictionary = d["season_stats"][pid][key]
			by_key[key] = {"apps": int(s.get("apps", 0)), "goals": int(s.get("goals", 0)), "assists": int(s.get("assists", 0)),
					"saves": int(s.get("saves", 0)), "rating_sum": float(s.get("rating_sum", 0.0)), "motm": int(s.get("motm", 0)),
					"yellow": int(s.get("yellow", 0)), "red": int(s.get("red", 0)), "clean_sheets": int(s.get("clean_sheets", 0))}
		c.season_stats[pid] = by_key
	for k in (d.get("club_levels", {}) as Dictionary):
		c.club_levels[k] = int(d["club_levels"][k])
	for k in (d.get("pyramids", {}) as Dictionary):
		c.pyramids[k] = LeaguePyramid.from_dict(PlayerData._restore_ints(d["pyramids"][k]))
	c.national = NationalBreaks.from_dict(d.get("national", {}) as Dictionary)
	c.pending_press = (d.get("pending_press", {}) as Dictionary).duplicate()
	c.settings = CareerSettings.from_dict(d.get("settings", {}) as Dictionary)
	c.relations = PlayerRelations.from_dict(d.get("relations", {}) as Dictionary)
	c.media = MediaFans.from_dict(d.get("media", {}) as Dictionary)
	c.world = WorldLife.from_dict(d.get("world", {}) as Dictionary)
	c.progress = ManagerProgress.from_dict(d.get("progress", {}) as Dictionary)
	c.economy = Economy.from_dict(d.get("economy", {}) as Dictionary)
	c.market.ban_check = Callable(c.economy, "is_banned")
	c.market.buyer_price_factor = Callable(c, "_buyer_price_factor")
	c.facilities = Facilities.from_dict(d.get("facilities", {}) as Dictionary)
	c.staff = StaffTeam.from_dict(d.get("staff", {}) as Dictionary)
	c.board = BoardRelations.from_dict(d.get("board", {}) as Dictionary)
	c.season_extras = PlayerData._restore_ints((d.get("season_extras", []) as Array).duplicate(true))
	c.fan_mood = clampi(int(d.get("fan_mood", 60)), 0, 100)
	c.morale = MoraleSystem.from_dict(d.get("morale", {}) as Dictionary)
	c.delegation = Delegation.from_dict(d.get("delegation", {}) as Dictionary)
	c.inbox = Inbox.from_dict(d.get("inbox", {}) as Dictionary)
	if c.manager.objective.is_empty():
		c.set_objective()              # old saves / default world: the board sets an objective now
	return c
