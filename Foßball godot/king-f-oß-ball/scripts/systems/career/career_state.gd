class_name CareerState
extends RefCounted

## Club-manager career (Phase T9): the managed club, season/week clock,
## finances of every club (AI clubs included), the transfer market, the
## season's competitions and club history. Everything is serialisable so a
## career survives save/load (stored in `SaveManager` extras["career"]).

const WEEKS_PER_SEASON := 46
const MATCH_REVENUE_BASE := 20000
const WAGE_BUDGET_MARGIN := 1.25

var club_id: String = ""
var season: int = 1
var week: int = 0
var ledgers: Dictionary = {}          # team_id -> FinanceLedger
var market: TransferMarket
var competitions: Dictionary = {}     # competition_id -> Competition
var club_history: Array = []          # one entry per finished season
var released_players: Array = []      # ids released at contract expiry (audit trail)
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
	return c


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
			(ledgers[team_id] as FinanceLedger).record("salary", -wages, "Weekly wages", week)
			if team_id == club_id:
				wages_paid = wages
	var returned := market.advance_loans(week, squads)
	return {"week": week, "wages_paid": wages_paid, "loans_returned": returned,
			"season_over": week >= WEEKS_PER_SEASON,
			"trained_ids": trained_ids, "found_ids": found_ids}


## Records match income for the home club. Returns "" or an error.
func record_match_revenue(home_team_id: String, attendance_factor: float = 1.0) -> String:
	if not ledgers.has(home_team_id):
		return "unknown club '%s'" % home_team_id
	var rep: int = db.get_team(home_team_id).reputation
	var amount := int((MATCH_REVENUE_BASE + rep * 500) * clampf(attendance_factor, 0.2, 1.5))
	return (ledgers[home_team_id] as FinanceLedger).record("match_revenue", amount, "Matchday income", week)


## Forwards a result to its competition and books revenue for the home club.
func submit_result(competition_id: String, r: MatchResult) -> String:
	if not competitions.has(competition_id):
		return "unknown competition '%s'" % competition_id
	var comp: Competition = competitions[competition_id]
	var err := comp.submit_result(r)
	if err != "":
		return err
	record_match_revenue(r.home_id)
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


## Season rollover: everyone ages, contracts run down, expired contracts leave,
## academy players age, the clock resets. Returns the ids released for the
## managed club so the UI can report them.
func end_season(academies: Dictionary = {}) -> Dictionary:
	var released_mine: Array[String] = []
	for team: TeamData in db.list_teams(TeamData.Category.CLUB):
		for p in db.get_squad(team.id):
			p.age += 1
			if p.loan_parent != "":
				continue
			p.contract_years -= 1
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
	club_history.append({"key": "season_%d" % season, "season": season,
			"balance": ledger().balance, "squad_size": db.get_team(club_id).squad_ids.size()})
	season += 1
	week = 0
	return {"season": season, "released": released_mine, "over_age": over_age_mine}


func to_dict() -> Dictionary:
	var l := {}
	for k in ledgers:
		l[k] = (ledgers[k] as FinanceLedger).to_dict()
	var c := {}
	for k in competitions:
		c[k] = (competitions[k] as Competition).to_dict()
	return {"club_id": club_id, "season": season, "week": week, "ledgers": l,
			"market": market.to_dict(), "competitions": c, "club_history": club_history.duplicate(true),
			"released": released_players.duplicate()}


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
	return c
