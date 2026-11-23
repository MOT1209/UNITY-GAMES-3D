extends "res://scripts/systems/career/career_state_part1.gd"

## Career state, part 2 of 3 (split Nov 2026; the class is `CareerState` in career_state. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: base_level, _new_ledger, register_competition, absolute_week, _friendlies_for_week, friendly_comps,
## _settle_old_friendlies, date, _match_steps, _week_steps, _collect, _end_week, _lap, weekly_sponsorship,
## record_match_revenue, submit_result, _pay_competition_rewards, _prune_sim_stats, end_season, _bound_histories,
## _last_user_result.

## Base level of a club (recorded at career start; older saves fall back to the current rating).
func base_level(team_id: String) -> int:
	if not club_levels.has(team_id):
		club_levels[team_id] = db.get_team_rating(team_id)
	return int(club_levels[team_id])


func _new_ledger(team: TeamData) -> FinanceLedger:
	var wages := 0
	for p in db.get_squad(team.id):
		wages += p.salary
	return FinanceLedger.new(team.id, team.budget, int(team.budget * 0.4),
			int(maxi(wages, 1000) * WAGE_BUDGET_MARGIN))


func register_competition(c: Competition) -> String:
	if competitions.has(c.id):
		return "competition '%s' already registered" % c.id
	competitions[c.id] = c
	return ""


## Calendar position across seasons; academy training/scouting key off this.
func absolute_week() -> int:
	return (season - 1) * WEEKS_PER_SEASON + week


## Friendly of the managed club in each international-break week (the club has no league match then): a one-match
## competition "friendly_s<season>_w<week>" against a club picked by the season and week. Created when the week starts;
## it behaves like any fixture of the club (due on its day, play in 3D / live / quick-sim) and does not touch the table.
func _friendlies_for_week() -> void:
	if not NationalBreaks.is_break(week) or club_id == "" or manager.unemployed:
		return
	var cid := "friendly_s%d_w%d" % [season, week]
	if competitions.has(cid):
		return
	var clubs: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id).filter(func(i: String) -> bool: return i != club_id)
	if clubs.is_empty():
		return
	clubs.sort()
	var opp: String = clubs[absi(hash([season, week, club_id])) % clubs.size()]
	var home := (week + season) % 2 == 0
	var teams: Array = [club_id, opp] if home else [opp, club_id]
	var c := Competition.create_league(cid, "FRIENDLY_NAME", teams, false)
	c.season = season
	competitions[cid] = c


## Friendly competitions of this season: [[Competition, fixture week]] (the week is parsed from the id).
func friendly_comps() -> Array:
	var out: Array = []
	for cid in competitions:
		if str(cid).begins_with("friendly_s%d_w" % season):
			out.append([competitions[cid], int(str(cid).get_slice("_w", 1))])
	return out


## Friendlies whose week has passed are simulated (the season must never stall on an unplayed friendly).
func _settle_old_friendlies() -> void:
	for pair in friendly_comps():
		var comp: Competition = pair[0]
		if int(pair[1]) < week:
			for f in comp.pending_fixtures():
				submit_result(comp.id, MatchSimulator.career_result(self, f, hash([season, "friendly"])))


## The date of the current day ({year, month, day, weekday}).
func date() -> Dictionary:
	return CareerDate.of(season, week, day)


## The steps that play fixtures (one per league system, then the continental cup).
func _match_steps() -> Array:
	var steps: Array = []
	for k in pyramid_keys():
		steps.append("league:" + str(k))
	steps.append("continental")
	return steps


## Phases of a week, in order. Each league system is its own phase (the biggest piece of work).
func _week_steps() -> Array:
	var steps: Array = ["daily", "academy", "finance", "loans", "ai_transfers", "availability", "morale", "club_ops", "assistant"]
	for k in pyramid_keys():
		steps.append("league:" + str(k))
	steps.append("continental")
	return steps


static func _collect(run: Dictionary, r: Dictionary) -> void:
	(run["user_fixtures"] as Array).append_array(r["user_fixtures"])
	(run["auto_played"] as Array).append_array(r["auto_played"])
	run["simulated"] += int(r["played"])


func _end_week(run: Dictionary) -> Dictionary:
	return {"week": week, "wages_paid": run["wages_paid"], "loans_returned": run["returned"],
			"season_over": week >= WEEKS_PER_SEASON,
			"trained_ids": run["trained_ids"], "found_ids": run["found_ids"],
			"user_fixtures": run["user_fixtures"], "auto_played": run["auto_played"], "simulated": run["simulated"],
			"ai_transfers": run["deals"]}


## Stores the time since `since` (usec) under `phase` in `last_timings` and returns the new mark.
func _lap(phase: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	last_timings[phase] = now - since
	return now


## Weekly sponsorship income of a club: a base amount plus a share that grows with the club's reputation.
func weekly_sponsorship(team_id: String) -> int:
	if team_id == club_id and not economy.sponsor.is_empty():
		return int(economy.sponsor["fixed_weekly"])
	return SPONSOR_BASE + int(db.get_team(team_id).reputation) * SPONSOR_PER_REPUTATION


## Records match income for the home club. Returns "" or an error.
func record_match_revenue(home_team_id: String, attendance_factor: float = 1.0) -> String:
	if not ledgers.has(home_team_id):
		return "unknown club '%s'" % home_team_id
	var rep: int = db.get_team(home_team_id).reputation
	var amount := int((MATCH_REVENUE_BASE + rep * 500) * clampf(attendance_factor, 0.2, 1.5) * ((facilities.matchday_factor() * economy.matchday_multiplier(fan_mood)) if home_team_id == club_id else 1.0) * (_derby_boost if home_team_id == club_id else 1.0))
	if home_team_id == club_id:
		fan_mood = clampi(fan_mood + int(Economy.TICKET_FAN_EFFECT[economy.ticket_level]), 0, 100)
	return (ledgers[home_team_id] as FinanceLedger).record("match_revenue", amount, "Matchday income", week, "FIN_MATCHDAY_INCOME")


## Forwards a result to its competition and books revenue for the home club.
func submit_result(competition_id: String, r: MatchResult) -> String:
	_derby_boost = 1.25 if WorldLife.is_derby(db, r.home_id, r.away_id) else 1.0
	if not competitions.has(competition_id):
		return "unknown competition '%s'" % competition_id
	var comp: Competition = competitions[competition_id]
	var err := comp.submit_result(r)
	if err != "":
		return err
	record_match_revenue(r.home_id)
	if not has_engine_report(r.match_id):
		SeasonStats.record_simulated(self, r, competition_id)           # no engine report exists for this match: the statistical model fills in
	if comp.is_finished() and not comp.id.begins_with("friendly_"):
		_pay_competition_rewards(comp)             # a friendly has no prize
	return ""


func _pay_competition_rewards(comp: Competition) -> void:
	var prizes := {"champion": 1_000_000, "runner_up": 500_000, "third": 250_000}
	var reward_key := "rewards_paid_" + comp.id
	if club_history.any(func(h: Dictionary) -> bool: return h.get("key", "") == reward_key):
		return
	for award in prizes:
		var team_id: String = comp.awards().get(award, "")
		if team_id != "" and ledgers.has(team_id):
			(ledgers[team_id] as FinanceLedger).record("competition_reward", prizes[award],
					"%s – %s" % [comp.comp_name, award], week)
	club_history.append({"key": reward_key, "season": season, "competition": comp.id,
			"champion": comp.champion_id, "runner_up": comp.runner_up_id})


func _prune_sim_stats() -> void:
	for pid in sim_comp_stats.keys():
		var rows: Dictionary = sim_comp_stats[pid]
		for key in rows.keys():
			if int(str(key).get_slice(":", 0)) <= season - 1 - SIM_STATS_SEASONS:
				rows.erase(key)
		if rows.is_empty():
			sim_comp_stats.erase(pid)


func end_season(academies: Dictionary = {}, squads: Dictionary = {}) -> Dictionary:
	last_timings.clear()
	var t_mark := Time.get_ticks_usec()
	if db.teams.size() <= 12:                  # a small (fictional) world: AI transfer budgets are topped up every season,
		for tid in ledgers:                    # else they run dry after the first window and the market freezes
			if tid != club_id:
				var l: FinanceLedger = ledgers[tid]
				l.transfer_budget = maxi(l.transfer_budget, int(maxi(l.balance, 0) * 0.05))
	var league_summaries := {}
	for k in pyramid_keys():
		league_summaries[k] = (pyramids[k] as LeaguePyramid).end_season(self)
	for k in league_summaries:
		var sm: Dictionary = league_summaries[k]
		for div_id in sm["champions"]:
			add_event("champion", [sm["champions"][div_id], div_id])
		for t in sm["promoted"]:
			add_event("promoted", [t])
		for t in sm["relegated"]:
			add_event("relegated", [t])
	var cup_champion := ""
	if continental != null:
		cup_champion = continental.finish(self)
		if cup_champion != "":
			add_event("continental_champion", [cup_champion])
	t_mark = _lap("end:leagues", t_mark)
	_compute_awards(league_summaries)
	yellow_counts.clear()
	t_mark = _lap("end:awards", t_mark)
	var manager_review := _review_manager(league_summaries)
	_economy_season_end(manager_review, league_summaries)
	world.move_reputation(db, league_summaries)
	world.review_managers(self, league_summaries)
	world.manager_of_season(self, league_summaries)
	world.schedule_super_cup(self, league_summaries)
	if not manager_review.is_empty():
		var was_up: bool = league_summaries.values().any(func(sm: Dictionary) -> bool: return (sm.get("promoted", []) as Array).has(club_id))
		if was_up:
			progress.promotions += 1
		progress.add_xp(ManagerProgress.xp_for_season(bool(manager_review.get("champion", false)), manager_review.get("result", "") == "met", was_up))
		progress.challenges = ManagerProgress.new_challenges(season + 1)
		progress.check_achievements(self)
	if manager_review.get("event", "") == "sacked":
		add_event("sacked", [club_id])
	market.season_end_moves(squads)               # pre-contracts move before contracts run out
	var released_mine: Array[String] = []
	var aged := {}                        # players aged here; PlayerLifecycle must not age them again
	for team: TeamData in db.list_teams(TeamData.Category.CLUB):
		var level: int = db.get_team_rating(team.id)
		for p in db.get_squad(team.id):
			p.age += 1
			aged[p.id] = true
			if p.loan_parent != "":
				continue
			p.contract_years -= 1
			if p.contract_years <= 0 and team.id != club_id and PlayerLifecycle.ai_renews(p, level):
				p.contract_years = PlayerLifecycle.renewal_years(p)    # AI clubs keep their useful players
				continue
			if p.contract_years <= 0:
				if team.squad_ids.size() > TransferMarket.MIN_SQUAD:
					PromotionSystem.release_from_squad(db, team.id, p.id)
					released_players.append(p.id)
					if team.id == club_id:
						released_mine.append(p.id)
				else:
					p.contract_years = 1     # small squads get an automatic one-year extension
	t_mark = _lap("end:contracts", t_mark)
	var over_age_mine: Array[String] = []
	for team_id in academies:
		var plan := TrainingSystem.new()
		plan.age_up(db, academies[team_id])
		# Nobody vanishes: players past the group limit stay in the roster and are
		# surfaced as Over-Age Prospects; expired extensions come back for a decision.
		var ac := academies[team_id] as Academy
		ac.expire_extensions(db)
		# Youth economy (Nov 2026): one intake per season instead of a free button, and a yearly grant paid
		# from the club's ledger into the academy budget (nothing when the club cannot afford it).
		var intake := ac.generate_intake(db, Academy.annual_intake_size(ac.quality) + YouthDevelopment.intake_bonus(ac))
		if team_id == club_id:
			var grant := Academy.annual_grant(db.get_team(team_id))
			if ledgers.has(club_id) and grant > 0 and ledger().record("academy", -grant, "Academy grant", week, "FIN_ACADEMY_GRANT") != "":
				grant = 0
			ac.budget += grant
			if ac.pay_upkeep() > 0.0:
				inbox.add("academy_decay:%d" % season, season, week, "board", "INBOX_ACADEMY_DECAY", [], {"action": {"screen": "academy", "params": {}}})
			inbox.add("academy_intake:%d" % season, season, week, "board", "INBOX_ACADEMY_INTAKE",
					[str(intake.size()), str(grant)], {"action": {"screen": "academy", "params": {}}})
			for e in YouthDevelopment.season_end(db, ac, intake, season):
				inbox.add("youth_end:%d:%s" % [season, e["key"]], season, week, "board", e["key"], (e["args"] as Array).map(func(x: Variant) -> String: return str(x)), {"action": {"screen": "academy", "params": {}}})
			over_age_mine = ac.over_age_ids(db)
	if not manager.unemployed:
		var dev_success := 0.5
		if not manager_review.is_empty():
			dev_success = 1.0 if bool(manager_review.get("champion", false)) else (0.75 if manager_review.get("result", "") == "met" else (0.5 if manager_review.get("result", "") == "partial" else 0.25))
		for e in DevelopmentEngine.season_end(self, development, dev_success, academies.get(club_id)):
			inbox.add("dev:%s" % e["id"], season, week, "board", e["key"], (e["args"] as Array).map(func(x: Variant) -> String: return str(x)), {"action": {"screen": "coaching_staff", "params": {}}})
	# Retirement, development outside the academy and AI squad upkeep (see PlayerLifecycle).
	t_mark = _lap("end:academies", t_mark)
	var lifecycle := PlayerLifecycle.run(self, season, squads, aged)
	t_mark = _lap("end:lifecycle", t_mark)
	var purged := PlayerLifecycle.purge_retired(self, season)
	t_mark = _lap("end:purge", t_mark)
	for team_id in ledgers:
		(ledgers[team_id] as FinanceLedger).compact(LEDGER_KEEP_USER if team_id == club_id else LEDGER_KEEP_AI)
	t_mark = _lap("end:ledgers", t_mark)
	_bound_histories()
	club_history.append({"key": "season_%d" % season, "season": season,
			"balance": ledger().balance, "squad_size": db.get_team(club_id).squad_ids.size()})
	for pair in friendly_comps():
		competitions.erase((pair[0] as Competition).id)          # Phase K2: friendlies are not kept
	season += 1
	# Season points belong to one season. DevelopmentEngine.season_end clears them too, but it is skipped while the
	# manager is unemployed (also right after a sacking in this call), so the boundary clears them itself.
	development.season_gain.clear()
	development.plans.mark_season_start(db.get_player)       # "this season" growth starts from here (cumulative keeps start_overall)
	_prune_sim_stats()
	week = 0
	day = 6
	market.sync_clock(season, week, club_id, world_stats)
	market.prune(db)
	if continental != null:
		var last_tables := {}
		for k in league_summaries:
			last_tables[k] = (league_summaries[k] as Dictionary).get("tables", {})
		competitions.erase(continental.comp_id)          # last season's cup is over; it used to stay in the career for ever
		continental = ContinentalCup.new()
		if not continental.build(self, last_tables):
			continental = null
	t_mark = _lap("end:continental", t_mark)
	if not manager.unemployed:
		set_objective()
	return {"continental_champion": cup_champion, "manager": manager_review, "season": season, "released": released_mine, "over_age": over_age_mine, "leagues": league_summaries,
			"retired_mine": lifecycle["retired_mine"], "retired": lifecycle["retired"].size(), "purged_players": purged,
			"ai_signed": lifecycle["signed"], "ai_generated": lifecycle["generated"]}


## Keeps the audit-trail lists within their limits (called once per season).
func _bound_histories() -> void:
	# "rewards_paid_<competition>" markers only stop a finished competition from paying twice: once it is gone they are noise
	club_history = club_history.filter(func(h: Dictionary) -> bool:
		return not (str(h.get("key", "")).begins_with("rewards_paid_") and not competitions.has(str(h.get("competition", ""))))
	)
	while released_players.size() > RELEASED_MAX:
		released_players.pop_front()
	while club_history.size() > CLUB_HISTORY_MAX:
		club_history.pop_front()
	while award_history.size() > AWARD_HISTORY_MAX:
		award_history.pop_front()


## "win" / "draw" / "loss" of the user's last played match of THIS week ("" when none).
func _last_user_result() -> String:
	var res := CareerCalendar.recent_results(self, 1)
	if res.is_empty() or int(res[0]["week"]) < week - 1 or int(res[0]["week"]) > week:
		return ""                          # the match of the week that just ended (the calendar has already moved on)
	var parts := str(res[0]["score"]).split("-")
	if parts.size() != 2:
		return ""
	return "win" if int(parts[0]) > int(parts[1]) else ("loss" if int(parts[0]) < int(parts[1]) else "draw")
