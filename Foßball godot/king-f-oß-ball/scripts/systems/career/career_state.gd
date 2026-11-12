class_name CareerState
extends RefCounted

## Club-manager career (Phase T9): the managed club, season/week clock,
## finances of every club (AI clubs included), the transfer market, the
## season's competitions and club history. Everything is serialisable so a
## career survives save/load (stored in `SaveManager` extras["career"]).

const WEEKS_PER_SEASON := 46
const MATCH_REVENUE_BASE := 20000
const WAGE_BUDGET_MARGIN := 1.25
const SPONSOR_BASE := 10000
const SPONSOR_PER_REPUTATION := 250

var club_id: String = ""
var season: int = 1
var week: int = 0
var ledgers: Dictionary = {}          # team_id -> FinanceLedger
var market: TransferMarket
var competitions: Dictionary = {}     # competition_id -> Competition
var club_history: Array = []          # one entry per finished season
var released_players: Array = []      # ids released at contract expiry (audit trail)
## One league pyramid per country of the loaded data pack (empty in the default world).
var pyramids: Dictionary = {}         # league key -> LeaguePyramid
## Reports of the matches played in this career (newest last, capped) and per-player totals built from
## them. Both come ONLY from real engine reports (`MatchReport`), keyed by the match uid (idempotent).
const MATCH_LOG_MAX := 200
var match_log: Array = []
var player_stats: Dictionary = {}     # player id -> {apps, goals, assists, saves, rating_sum, motm}
## Each club's squad level at career start: the anchor for players AI clubs bring in.
var club_levels: Dictionary = {}      # team id -> int
## The user's manager: reputation, board confidence, contract and history (Phase 4).
var manager: ManagerProfile = ManagerProfile.new()
## Yellow cards collected this season per player (5 = a one-week ban) and the log of world events the news is built from.
var yellow_counts: Dictionary = {}
## Statistics of the current season for every player of the world (see SeasonStats) and the awards of past seasons.
var season_stats: Dictionary = {}     # player id -> {apps, goals, assists, clean_sheets, rating_sum}
var _xi_cache: Dictionary = {}        # SeasonStats: best XI per club for the current week
var _xi_stamp: int = -1
var award_history: Array = []         # [{season, key (country), awards}]
const EVENT_LOG_MAX := 300
var events: Array = []                # {season, week, kind, args: Array}
var db: Node


## Starts a career with `club_id`. Returns null (and sets `error`) when invalid.
static func start(p_db: Node, p_club_id: String) -> CareerState:
	var t: TeamData = p_db.get_team(p_club_id)
	if t == null or t.category != TeamData.Category.CLUB:
		return null
	var c := CareerState.new()
	c.db = p_db
	c.club_id = p_club_id
	for team: TeamData in p_db.list_teams(TeamData.Category.CLUB):
		c.ledgers[team.id] = c._new_ledger(team)
	c.market = TransferMarket.new(p_db, c.ledgers)
	for team: TeamData in p_db.list_teams(TeamData.Category.CLUB):
		c.club_levels[team.id] = p_db.get_team_rating(team.id)
	var leagues: Dictionary = p_db.get("leagues") if p_db.get("leagues") != null else {}
	for k in leagues:
		var pyr := LeaguePyramid.create(leagues[k], c.season)
		pyr.build_season(c.competitions, p_db)
		c.pyramids[k] = pyr
	c.set_objective()
	return c


## Awards of the finished season for every country's top division (all clubs in the default world), stored and logged.
func _compute_awards(league_summaries: Dictionary) -> void:
	var groups := {}
	for k in pyramids:
		groups[k] = ((pyramids[k] as LeaguePyramid).divisions[0]["team_ids"] as Array).duplicate()
	if groups.is_empty():
		groups["world"] = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	for k in groups:
		var aw := SeasonAwards.compute(db, season_stats, groups[k])
		award_history.append({"season": season, "key": k, "awards": aw})
		for kind in ["golden_boot", "player_of_the_season", "best_goalkeeper", "best_young_player"]:
			if aw[kind] != "":
				add_event("award", [kind, aw[kind], int(aw.get("golden_boot_goals", 0)) if kind == "golden_boot" else 0])
	season_stats.clear()


## Adds an event to the world log (`kind`: injury, ban, champion, promoted, relegated, sacked ...; args are ids / numbers).
func add_event(kind: String, args: Array) -> void:
	events.append({"season": season, "week": week, "kind": kind, "args": args.duplicate()})
	while events.size() > EVENT_LOG_MAX:
		events.pop_front()


## Sets this season's board objective from the managed club's division (default world: its first league).
func set_objective() -> void:
	var ud := user_division()
	if not ud.is_empty():
		manager.objective = BoardObjectives.for_club(db, club_id, ud["division"])
		return
	for cid in competitions:
		var comp: Competition = competitions[cid]
		if comp.type == Competition.Type.LEAGUE and club_id in comp.team_ids:
			manager.objective = BoardObjectives.for_club(db, club_id, {"team_ids": comp.team_ids, "relegate": 0})
			return
	manager.objective = {}


## Final league position of the managed club (1 = champion) from the season summaries; 0 when unknown.
func _user_rank(league_summaries: Dictionary) -> int:
	var ud := user_division()
	if not ud.is_empty():
		var order: Array = league_summaries.get(ud["pyramid"], {}).get("tables", {}).get(ud["division"]["id"], [])
		return order.find(club_id) + 1
	for cid in competitions:
		var comp: Competition = competitions[cid]
		if comp.type == Competition.Type.LEAGUE and club_id in comp.team_ids:
			var rows := comp.standings()
			for i in rows.size():
				if rows[i]["team_id"] == club_id:
					return i + 1
	return 0


## Evaluates the board objective, updates reputation / confidence / contract and the history, and returns the outcome
## ({} when there is no objective). A manager whose confidence falls below the limit is sacked (`unemployed`).
func _review_manager(league_summaries: Dictionary) -> Dictionary:
	if manager.unemployed:
		return {}
	if manager.objective.is_empty():
		set_objective()
	var rank := _user_rank(league_summaries)
	var ev := BoardObjectives.evaluate(manager.objective, rank)
	if ev.is_empty():
		return {}
	manager.apply_result(int(ev["confidence"]), int(ev["reputation"]))
	if ev["champion"]:
		manager.trophies += 1
	manager.contract_years -= 1
	var event := "none"
	if manager.is_sacked():
		manager.unemployed = true
		event = "sacked"
	elif manager.contract_years <= 0:
		if ev["result"] == "met":
			manager.contract_years = ManagerProfile.CONTRACT_YEARS
			event = "renewed"
		else:
			manager.unemployed = true
			event = "contract_expired"
	manager.log_entry({"season": season, "club": club_id, "objective_rank": int(manager.objective["target_rank"]), "rank": rank,
			"result": ev["result"], "reputation": manager.reputation, "confidence": manager.confidence, "event": event})
	ev["rank"] = rank
	ev["event"] = event
	return ev


func job_offers() -> Array:
	return BoardObjectives.job_offers(db, manager.reputation, club_id)


## The manager leaves the club voluntarily (small reputation cost).
func resign() -> String:
	if manager.unemployed:
		return "the manager has no club"
	manager.unemployed = true
	manager.apply_result(0, -2)
	manager.log_entry({"season": season, "club": club_id, "objective_rank": int(manager.objective.get("target_rank", 0)), "rank": 0,
			"result": "resigned", "reputation": manager.reputation, "confidence": manager.confidence, "event": "resigned"})
	return ""


## Takes a job at `new_club_id`: only while unemployed and only a club that is offering one. The caller (AppHub)
## must also switch the managed team id and squads.
func take_job(new_club_id: String) -> String:
	if not manager.unemployed:
		return "the manager already has a club"
	if not job_offers().any(func(o: Dictionary) -> bool: return o["club_id"] == new_club_id):
		return "club '%s' has not offered a job" % new_club_id
	club_id = new_club_id
	manager.unemployed = false
	manager.confidence = ManagerProfile.START_CONFIDENCE
	manager.contract_years = ManagerProfile.CONTRACT_YEARS
	set_objective()
	return ""


## Records a finished match once. Returns false for a report that was already recorded or is invalid.
func record_match(report: Dictionary) -> bool:
	var uid := str(report.get("uid", ""))
	if uid == "" or report.get("source", "") != "engine":
		return false
	if match_log.any(func(r: Dictionary) -> bool: return r.get("uid", "") == uid):
		return false
	match_log.append(report.duplicate(true))
	Availability.after_match(self, report)
	SeasonStats.record_report(self, report)
	while match_log.size() > MATCH_LOG_MAX:
		match_log.pop_front()
	for p in report.get("players", []):
		var s: Dictionary = player_stats.get(p["player_id"], {"apps": 0, "goals": 0, "assists": 0, "saves": 0, "rating_sum": 0.0, "motm": 0})
		s["apps"] += 1
		s["goals"] += int(p["goals"])
		s["assists"] += int(p["assists"])
		s["saves"] += int(p["saves"])
		s["rating_sum"] += float(p["rating"])
		if p["player_id"] == report.get("motm", ""):
			s["motm"] += 1
		player_stats[p["player_id"]] = s
	return true


## Base level of a club (recorded at career start; older saves fall back to the current rating).
func base_level(team_id: String) -> int:
	if not club_levels.has(team_id):
		club_levels[team_id] = db.get_team_rating(team_id)
	return int(club_levels[team_id])


## The pyramid and division the managed club plays in ({} outside a pyramid).
func user_division() -> Dictionary:
	for k in pyramids:
		var d: Dictionary = (pyramids[k] as LeaguePyramid).division_of(club_id)
		if not d.is_empty():
			return {"pyramid": k, "division": d}
	return {}


func _new_ledger(team: TeamData) -> FinanceLedger:
	var wages := 0
	for p in db.get_squad(team.id):
		wages += p.salary
	return FinanceLedger.new(team.id, team.budget, int(team.budget * 0.4),
			int(maxi(wages, 1000) * WAGE_BUDGET_MARGIN))


func ledger() -> FinanceLedger:
	return ledgers[club_id]


func register_competition(c: Competition) -> String:
	if competitions.has(c.id):
		return "competition '%s' already registered" % c.id
	competitions[c.id] = c
	return ""


## Calendar position across seasons; academy training/scouting key off this.
func absolute_week() -> int:
	return (season - 1) * WEEKS_PER_SEASON + week


## Plays one calendar week: pays wages, runs loans, and — when the academy
## systems are passed — runs exactly one week of youth training and scouting
## per club (the career calendar is the only clock, so training can't be
## repeated for free). Returns a summary dict.
func advance_week(squads: Dictionary = {}, academies: Dictionary = {},
		trainings: Dictionary = {}, scouting: Dictionary = {}) -> Dictionary:
	if week >= WEEKS_PER_SEASON:
		# The season is over: nothing is played and nobody is paid until `end_season()`.
		return {"week": week, "wages_paid": 0, "loans_returned": [], "season_over": true, "blocked": true,
				"trained_ids": [], "found_ids": [], "user_fixtures": [], "auto_played": [], "simulated": 0, "ai_transfers": []}
	week += 1
	var trained_ids: Array[String] = []
	var found_ids: Array[String] = []
	var now := absolute_week()
	for team_id in trainings:
		if academies.has(team_id):
			var gains: Dictionary = (trainings[team_id] as TrainingSystem).sync_to_calendar(
					db, academies[team_id], now)
			if team_id == club_id:
				trained_ids.assign(gains.keys())
	for team_id in scouting:
		if academies.has(team_id):
			var found: Array[String] = (scouting[team_id] as ScoutingSystem).sync_to_calendar(
					db, academies[team_id], now)
			if team_id == club_id:
				found_ids = found
	var wages_paid := 0
	for team_id in ledgers:
		var wages := market.weekly_wages(team_id)
		if wages > 0:
			(ledgers[team_id] as FinanceLedger).record("salary", -wages, "Weekly wages", week, "FIN_WEEKLY_WAGES")
			if team_id == club_id:
				wages_paid = wages
	for team_id in ledgers:
		(ledgers[team_id] as FinanceLedger).record("sponsorship", weekly_sponsorship(team_id), "Sponsorship", week, "FIN_SPONSORSHIP")
	var returned := market.advance_loans(week, squads)
	var deals := AITransfers.run_week(self, squads)
	Availability.weekly(self, squads)
	var user_fixtures: Array = []
	var auto_played: Array = []
	var simulated := 0
	for k in pyramids:
		var r: Dictionary = (pyramids[k] as LeaguePyramid).play_week(week, self, club_id)
		user_fixtures.append_array(r["user_fixtures"])
		auto_played.append_array(r["auto_played"])
		simulated += int(r["played"])
	return {"week": week, "wages_paid": wages_paid, "loans_returned": returned,
			"season_over": week >= WEEKS_PER_SEASON,
			"trained_ids": trained_ids, "found_ids": found_ids,
			"user_fixtures": user_fixtures, "auto_played": auto_played, "simulated": simulated, "ai_transfers": deals}


## Weekly sponsorship income of a club: a base amount plus a share that grows with the club's reputation.
func weekly_sponsorship(team_id: String) -> int:
	return SPONSOR_BASE + int(db.get_team(team_id).reputation) * SPONSOR_PER_REPUTATION


## Records match income for the home club. Returns "" or an error.
func record_match_revenue(home_team_id: String, attendance_factor: float = 1.0) -> String:
	if not ledgers.has(home_team_id):
		return "unknown club '%s'" % home_team_id
	var rep: int = db.get_team(home_team_id).reputation
	var amount := int((MATCH_REVENUE_BASE + rep * 500) * clampf(attendance_factor, 0.2, 1.5))
	return (ledgers[home_team_id] as FinanceLedger).record("match_revenue", amount, "Matchday income", week, "FIN_MATCHDAY_INCOME")


## Forwards a result to its competition and books revenue for the home club.
func submit_result(competition_id: String, r: MatchResult) -> String:
	if not competitions.has(competition_id):
		return "unknown competition '%s'" % competition_id
	var comp: Competition = competitions[competition_id]
	var err := comp.submit_result(r)
	if err != "":
		return err
	record_match_revenue(r.home_id)
	if not match_log.any(func(rep: Dictionary) -> bool: return rep.get("match_id", "") == r.match_id):
		SeasonStats.record_simulated(self, r)           # no engine report exists for this match: the statistical model fills in
	if comp.is_finished():
		_pay_competition_rewards(comp)
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


## Season rollover: league movements, everyone ages, contracts run down, expired contracts
## leave, academy players age, then `PlayerLifecycle` (retirement, development, AI squads);
## the clock resets. Returns the ids released for the
## managed club so the UI can report them.
func end_season(academies: Dictionary = {}, squads: Dictionary = {}) -> Dictionary:
	var league_summaries := {}
	for k in pyramids:
		league_summaries[k] = (pyramids[k] as LeaguePyramid).end_season(self)
	for k in league_summaries:
		var sm: Dictionary = league_summaries[k]
		for div_id in sm["champions"]:
			add_event("champion", [sm["champions"][div_id], div_id])
		for t in sm["promoted"]:
			add_event("promoted", [t])
		for t in sm["relegated"]:
			add_event("relegated", [t])
	_compute_awards(league_summaries)
	yellow_counts.clear()
	var manager_review := _review_manager(league_summaries)
	if manager_review.get("event", "") == "sacked":
		add_event("sacked", [club_id])
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
	var over_age_mine: Array[String] = []
	for team_id in academies:
		var plan := TrainingSystem.new()
		plan.age_up(db, academies[team_id])
		# Nobody vanishes: players past the group limit stay in the roster and are
		# surfaced as Over-Age Prospects; expired extensions come back for a decision.
		(academies[team_id] as Academy).expire_extensions(db)
		if team_id == club_id:
			over_age_mine = (academies[team_id] as Academy).over_age_ids(db)
	# Retirement, development outside the academy and AI squad upkeep (see PlayerLifecycle).
	var lifecycle := PlayerLifecycle.run(self, season, squads, aged)
	club_history.append({"key": "season_%d" % season, "season": season,
			"balance": ledger().balance, "squad_size": db.get_team(club_id).squad_ids.size()})
	season += 1
	week = 0
	if not manager.unemployed:
		set_objective()
	return {"manager": manager_review, "season": season, "released": released_mine, "over_age": over_age_mine, "leagues": league_summaries,
			"retired_mine": lifecycle["retired_mine"], "retired": lifecycle["retired"].size(),
			"ai_signed": lifecycle["signed"], "ai_generated": lifecycle["generated"]}


func to_dict() -> Dictionary:
	var l := {}
	for k in ledgers:
		l[k] = (ledgers[k] as FinanceLedger).to_dict()
	var c := {}
	for k in competitions:
		c[k] = (competitions[k] as Competition).to_dict()
	return {"club_id": club_id, "season": season, "week": week, "ledgers": l,
			"market": market.to_dict(), "competitions": c, "club_history": club_history.duplicate(true),
			"released": released_players.duplicate(),
			"pyramids": _pyramids_dict(), "club_levels": club_levels.duplicate(),
			"match_log": match_log.duplicate(true), "player_stats": player_stats.duplicate(true), "manager": manager.to_dict(), "yellow_counts": yellow_counts.duplicate(), "season_stats": season_stats.duplicate(true), "award_history": award_history.duplicate(true), "events": events.duplicate(true)}


func _pyramids_dict() -> Dictionary:
	var out := {}
	for k in pyramids:
		out[k] = (pyramids[k] as LeaguePyramid).to_dict()
	return out


static func from_dict(p_db: Node, d: Dictionary) -> CareerState:
	var c := CareerState.new()
	c.db = p_db
	c.club_id = str(d.get("club_id", ""))
	c.season = int(d.get("season", 1))
	c.week = int(d.get("week", 0))
	for k in (d.get("ledgers", {}) as Dictionary):
		c.ledgers[k] = FinanceLedger.from_dict(d["ledgers"][k])
	c.market = TransferMarket.new(p_db, c.ledgers)
	c.market.load_state(d.get("market", {}))
	for k in (d.get("competitions", {}) as Dictionary):
		c.competitions[k] = Competition.from_dict(d["competitions"][k])
	c.club_history = (d.get("club_history", []) as Array).duplicate(true)
	c.released_players = (d.get("released", []) as Array).duplicate()
	c.match_log = (d.get("match_log", []) as Array).duplicate(true)
	for k in (d.get("player_stats", {}) as Dictionary):
		var s: Dictionary = d["player_stats"][k]
		c.player_stats[k] = {"apps": int(s.get("apps", 0)), "goals": int(s.get("goals", 0)), "assists": int(s.get("assists", 0)),
				"saves": int(s.get("saves", 0)), "rating_sum": float(s.get("rating_sum", 0.0)), "motm": int(s.get("motm", 0))}
	c.manager = ManagerProfile.from_dict(d.get("manager", {}))
	for k in (d.get("yellow_counts", {}) as Dictionary):
		c.yellow_counts[k] = int(d["yellow_counts"][k])
	for k in (d.get("season_stats", {}) as Dictionary):
		var r: Dictionary = d["season_stats"][k]
		c.season_stats[k] = {"apps": int(r.get("apps", 0)), "goals": int(r.get("goals", 0)), "assists": int(r.get("assists", 0)),
				"clean_sheets": int(r.get("clean_sheets", 0)), "rating_sum": float(r.get("rating_sum", 0.0))}
	c.award_history = PlayerData._restore_ints((d.get("award_history", []) as Array).duplicate(true))
	for e in d.get("events", []):
		var ev: Dictionary = PlayerData._restore_ints((e as Dictionary).duplicate(true))
		c.events.append(ev)
	for k in (d.get("club_levels", {}) as Dictionary):
		c.club_levels[k] = int(d["club_levels"][k])
	for k in (d.get("pyramids", {}) as Dictionary):
		c.pyramids[k] = LeaguePyramid.from_dict(PlayerData._restore_ints(d["pyramids"][k]))
	if c.manager.objective.is_empty():
		c.set_objective()              # old saves / default world: the board sets an objective now
	return c
