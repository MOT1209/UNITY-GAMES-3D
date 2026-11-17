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
## Ledger entries kept in full detail after a season ends (older ones are folded into per-category summaries, see
## `FinanceLedger.compact`): the managed club's recent history for the finance screen, a short tail for AI clubs.
const LEDGER_KEEP_USER := 400
const LEDGER_KEEP_AI := 60
## Audit-trail lists that would otherwise grow for ever in a long career (oldest entries drop out first).
const RELEASED_MAX := 1500
const CLUB_HISTORY_MAX := 200
const AWARD_HISTORY_MAX := 100

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
## Lookup over `match_log` (report uids and match ids), derived and never saved; see `_ensure_log_index`.
var _log_uids: Dictionary = {}
var _log_match_ids: Dictionary = {}
var _log_indexed: int = -1
var player_stats: Dictionary = {}     # player id -> {apps, goals, assists, saves, rating_sum, motm}  (all-time)
## Season- and competition-aware copy of the same counters:
## player id -> {"<season>:<competition id>": {apps, goals, assists, saves, rating_sum, motm}}.
## Matches without a competition (friendlies) use the id "friendly".
var season_stats: Dictionary = {}
## Each club's squad level at career start: the anchor for players AI clubs bring in.
var club_levels: Dictionary = {}      # team id -> int
## The user's manager: reputation, board confidence, contract and history (Phase 4).
var manager: ManagerProfile = ManagerProfile.new()
## Yellow cards collected this season per player (5 = a one-week ban) and the log of world events the news is built from.
var yellow_counts: Dictionary = {}
## Statistics of the current season for every player of the world (see SeasonStats) and the awards of past seasons.
var world_stats: Dictionary = {}      # player id -> {apps, goals, assists, clean_sheets, rating_sum, est_*} (SeasonStats, all clubs)
## True for a season that was started by a game version that did not record which numbers are model estimates: its rows
## cannot be split into measured and estimated, so its awards are labelled "unknown_mixed". Cleared with the season.
var world_stats_legacy: bool = false
var _xi_cache: Dictionary = {}        # SeasonStats: best XI per club for the current week
var _xi_stamp: int = -1
var award_history: Array = []         # [{season, key (country), awards}]
const EVENT_LOG_MAX := 300
var events: Array = []                # {season, week, kind, args: Array}
## The continental club cup of the data pack (null in a world without leagues).
var continental: ContinentalCup
var db: Node
var national := NationalBreaks.new()   # C5.1 international breaks
var pending_press: Dictionary = {}     # C4.4 a press conference waiting {opponent, score, week}
var settings := CareerSettings.new()    # C1.2 wizard options
var relations := PlayerRelations.new()  # C3.3-C3.6
var media := MediaFans.new()            # C6
var world := WorldLife.new()            # C5
var progress := ManagerProgress.new()    # C8
var economy := Economy.new()            # C7
var facilities := Facilities.new()      # C2.5
var staff := StaffTeam.new()            # C2.6
var board := BoardRelations.new()        # C2.3 / C2.4 meetings and promises
var season_extras: Array = []         # C2.2 extra objectives of the running season [{kind, target, start}]
var fan_mood: int = 60                # 0..100, moved by press answers (C4.4); the full fan system is C6
var morale := MoraleSystem.new()       # C3.2 morale reasons
var delegation := Delegation.new()     # C9.3 tasks handed to the assistant
var inbox := Inbox.new()              # C9.1 central message box
## Microseconds spent in each phase of the last `advance_week()` (diagnostics for the performance tools; never saved).
var last_timings: Dictionary = {}
var _advancing: bool = false          # an `advance_week_async` is in progress


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
	c.market.ban_check = Callable(c.economy, "is_banned")
	c.market.buyer_price_factor = Callable(c, "_buyer_price_factor")
	c.market.buyer_price_factor = Callable(c, "_buyer_price_factor")
	c.market.sync_clock(c.season, c.week, c.club_id, c.world_stats)
	c.market.refresh_values(c)
	for team: TeamData in p_db.list_teams(TeamData.Category.CLUB):
		c.club_levels[team.id] = p_db.get_team_rating(team.id)
	var leagues: Dictionary = p_db.get("leagues") if p_db.get("leagues") != null else {}
	for k in leagues:
		var pyr := LeaguePyramid.create(leagues[k], c.season)
		pyr.build_season(c.competitions, p_db)
		c.pyramids[k] = pyr
	c.continental = ContinentalCup.new()
	if not c.continental.build(c):
		c.continental = null
	c.set_objective()
	return c


## The default fictional world ships no league data: a career there used to have no league at all and
## "next week" advanced an empty calendar. This adds the world's league (every club, home and away) and a
## domestic cup through the same `LeaguePyramid` machinery as the data packs (calendar, simulation of the
## other matches, the user's fixtures left to play, tables, season end). Names are translation keys.
## No-op when the world already has leagues or too few clubs. Returns true when the league was added.
const DEFAULT_LEAGUE_KEY := "fictional"

func add_default_league() -> bool:
	if not pyramids.is_empty() or db == null:
		return false
	var clubs: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	if clubs.size() < 4:
		return false
	clubs.sort()
	var def := LeagueDef.from_dict(DEFAULT_LEAGUE_KEY, {"country": "fictional", "name": "LEAGUE_DEFAULT_NAME",
			"divisions": [{"id": "fic_league", "name": "LEAGUE_DEFAULT_NAME", "tier": 1, "team_ids": clubs,
					"promote": 0, "relegate": 0}],
			"cup": {"id": "fic_cup", "name": "LEAGUE_DEFAULT_CUP"}})
	var pyr := LeaguePyramid.create(def, season)
	pyr.build_season(competitions, db)
	pyramids[DEFAULT_LEAGUE_KEY] = pyr
	set_objective()
	return true


## Awards of the finished season for every country's top division (all clubs in the default world), stored and logged.
func _compute_awards(league_summaries: Dictionary) -> void:
	var groups := {}
	for k in pyramid_keys():
		groups[k] = ((pyramids[k] as LeaguePyramid).divisions[0]["team_ids"] as Array).duplicate()
	if groups.is_empty():
		groups["world"] = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	for k in groups:
		var aw := SeasonAwards.compute(db, world_stats, groups[k])
		_label_award_basis(aw, groups[k])
		award_history.append({"season": season, "key": k, "awards": aw})
		for kind in ["golden_boot", "player_of_the_season", "best_goalkeeper", "best_young_player"]:
			if aw[kind] != "":
				add_event("award", [kind, aw[kind], int(aw.get("golden_boot_goals", 0)) if kind == "golden_boot" else 0])
	world_stats.clear()
	world_stats_legacy = false


## Says what the awards of one group were ranked on: "engine" (only real match events), "model" (only the statistical model of
## simulated matches), "mixed" (both, `estimated_percent` = estimated share of the appearances, 0..100) or "unknown_mixed" (legacy season).
func _label_award_basis(aw: Dictionary, club_ids: Array) -> void:
	var apps := 0
	var est := 0
	for pid in world_stats:
		var p: PlayerData = db.get_player(pid)
		if p != null and p.team_id in club_ids:
			apps += int(world_stats[pid].get("apps", 0))
			est += int(world_stats[pid].get("est_apps", 0))
	aw["estimated_percent"] = roundi(100.0 * float(est) / float(apps)) if apps > 0 else 0
	if world_stats_legacy:
		aw["basis"] = "unknown_mixed"
	else:
		aw["basis"] = "engine" if est == 0 else ("model" if est == apps else "mixed")


## League-system keys in a fixed (alphabetical) order: saves sort their keys, so the order of `pyramids` is not stable across a
## save / load, and the order of ledger entries and events must not depend on it.
func pyramid_keys() -> Array:
	var keys := pyramids.keys()
	keys.sort()
	return keys


## Adds an event to the world log (`kind`: injury, ban, champion, promoted, relegated, sacked ...; args are ids / numbers).
func add_event(kind: String, args: Array) -> void:
	events.append({"season": season, "week": week, "kind": kind, "args": args.duplicate()})
	while events.size() > EVENT_LOG_MAX:
		events.pop_front()


## Sets this season's board objective from the managed club's division (default world: its first league).
func set_objective() -> void:
	season_extras = ClubVision.extras_for(vision(), ledger().balance) if ledgers.has(club_id) else []
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


## The price factor the negotiation skill gives the managed club when it buys (1.0 for every other club).
func _buyer_price_factor(buyer_id: String) -> float:
	return (1.0 - progress.effect("negotiation")) * settings.market_price_factor() if buyer_id == club_id else 1.0


## C7: variable sponsor pay, broadcast rights for the managed club, and the sustainability rule for every club.
func _economy_season_end(review: Dictionary, _league_summaries: Dictionary) -> void:
	if not manager.unemployed or not review.is_empty():
		var rank := int(review.get("rank", 0))
		var size := int(manager.objective.get("division_size", 0))
		var ud := user_division()
		var tier := int(ud["division"].get("tier", 1)) if not ud.is_empty() else 1
		if rank > 0 and size > 0:
			var pay := economy.sponsor_season_payment(rank, size, 0)
			if pay > 0:
				ledger().record("sponsorship", pay, "Sponsor bonus", week, "FIN_SPONSORSHIP")
			var bc := Economy.broadcast_income(tier, rank, size)
			ledger().record("broadcast", bc, "Broadcast rights", week, "FIN_BROADCAST")
	var results := economy.settle_season(self)
	if results.get(club_id, "") == "fined":
		inbox.add("fine:%d" % season, season, week, "board", "INBOX_FINE", [], {})
	market.ban_check = Callable(economy, "is_banned")


## The managed club's vision (C2.1), derived from its division.
func vision(for_club: String = "") -> String:
	var id := club_id if for_club == "" else for_club
	var ud := user_division() if id == club_id else {}
	if ud.is_empty():
		for cid in competitions:
			var comp: Competition = competitions[cid]
			if comp.type == Competition.Type.LEAGUE and id in comp.team_ids:
				return ClubVision.for_club(db, id, {"team_ids": comp.team_ids})
		return "stability"
	return ClubVision.for_club(db, id, ud["division"], int(ud["division"].get("tier", 1)))


## Final league position of the managed club (1 = champion) from the season summaries; 0 when unknown.
func _user_rank(league_summaries: Dictionary) -> int:
	var ud := user_division()
	if not ud.is_empty():
		var tables: Dictionary = league_summaries.get(ud["pyramid"], {}).get("tables", {})
		var order: Array = tables.get(ud["division"]["id"], [])
		if order.has(club_id):
			return order.find(club_id) + 1
		# promoted / relegated at this season end: the club's final position is in the table of the division it played in
		for div_id in tables:
			if (tables[div_id] as Array).has(club_id):
				return (tables[div_id] as Array).find(club_id) + 1
		return 0
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
	var dc := int(ev["confidence"])
	if dc < 0:
		dc = int(round(float(dc) * (1.0 - progress.effect("management"))))
	manager.apply_result(dc, int(ev["reputation"]))
	var extra_results := ClubVision.evaluate_extras(self, season_extras)
	if not extra_results.is_empty():
		manager.apply_result(ClubVision.sum_delta(extra_results), 0)
	ev["extras"] = extra_results
	var was_promoted: bool = league_summaries.values().any(func(sm: Dictionary) -> bool: return (sm.get("promoted", []) as Array).has(club_id))
	ev["promises"] = board.settle(self, rank, was_promoted)
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
	market.sync_clock(season, week, club_id, world_stats)
	manager.unemployed = false
	manager.confidence = ManagerProfile.START_CONFIDENCE
	manager.contract_years = ManagerProfile.CONTRACT_YEARS
	set_objective()
	return ""


## Records a finished match once. Returns false for a report that was already recorded or is invalid.
func record_match(report: Dictionary, competition_id: String = "") -> bool:
	if report.get("source", "") != "engine":
		return false
	var uid := _report_key(report)
	if uid == "":
		return false
	_ensure_log_index()
	if _log_uids.has(uid):
		return false
	match_log.append(report.duplicate(true))
	_log_uids[uid] = true
	_log_match_ids[str(report.get("match_id", ""))] = true
	Availability.after_match(self, report)
	SeasonStats.record_report(self, report)
	while match_log.size() > MATCH_LOG_MAX:
		var old: Dictionary = match_log.pop_front()
		_log_uids.erase(_report_key(old))
		_log_match_ids.erase(str(old.get("match_id", "")))
	_log_indexed = match_log.size()
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
		_add_season_stats(str(p["player_id"]), p, p["player_id"] == report.get("motm", ""), competition_id, _kept_clean_sheet(report, p))
	return true


## Identity of an engine report: its uid, or - for a report that carries none - its match id.
static func _report_key(report: Dictionary) -> String:
	var uid := str(report.get("uid", ""))
	if uid != "":
		return uid
	var mid := str(report.get("match_id", ""))
	return "match:" + mid if mid != "" else ""


func _ensure_log_index() -> void:
	if _log_indexed == match_log.size():
		return
	_log_uids.clear()
	_log_match_ids.clear()
	for r: Dictionary in match_log:
		_log_uids[_report_key(r)] = true
		_log_match_ids[str(r.get("match_id", ""))] = true
	_log_indexed = match_log.size()


## True when an engine report for this match id is in the log (its statistics are real, so the model must not add any).
func has_engine_report(match_id: String) -> bool:
	_ensure_log_index()
	return _log_match_ids.has(match_id)


const _EMPTY_STATS := {"apps": 0, "goals": 0, "assists": 0, "saves": 0, "rating_sum": 0.0, "motm": 0,
		"yellow": 0, "red": 0, "clean_sheets": 0}


## Per-competition counters (`season_stats`): a goalkeeper or defender whose side conceded nothing (and who played) keeps a clean
## sheet. NOTE the deliberate difference to `world_stats` (`SeasonStats.record_report`), which counts goalkeepers only because
## its only consumer is the goalkeeper award.
func _kept_clean_sheet(report: Dictionary, p: Dictionary) -> bool:
	var side := str(p.get("side", ""))
	if side not in ["home", "away"]:
		return false
	var conceded := int(report.get("away_goals", 0)) if side == "home" else int(report.get("home_goals", 0))
	if conceded != 0:
		return false
	var pl: PlayerData = db.get_player(str(p["player_id"]))
	return pl != null and pl.position in [PlayerData.Position.GK, PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB]


func _add_season_stats(player_id: String, p: Dictionary, was_motm: bool, competition_id: String, clean_sheet: bool = false) -> void:
	var by_key: Dictionary = season_stats.get(player_id, {})
	var key := "%d:%s" % [season, competition_id if competition_id != "" else "friendly"]
	var s: Dictionary = by_key.get(key, _EMPTY_STATS.duplicate())
	s["apps"] += 1
	s["goals"] += int(p["goals"])
	s["assists"] += int(p["assists"])
	s["saves"] += int(p["saves"])
	s["rating_sum"] += float(p["rating"])
	if was_motm:
		s["motm"] += 1
	s["yellow"] = int(s.get("yellow", 0)) + int(p.get("yellow", 0))
	s["red"] = int(s.get("red", 0)) + int(p.get("red", 0))
	s["clean_sheets"] = int(s.get("clean_sheets", 0)) + (1 if clean_sheet else 0)
	by_key[key] = s
	season_stats[player_id] = by_key


## Counters of one player for a season (all competitions summed, or one competition).
func stats_for(player_id: String, p_season: int, competition_id: String = "") -> Dictionary:
	var total := _EMPTY_STATS.duplicate()
	var by_key: Dictionary = season_stats.get(player_id, {})
	for key: String in by_key:
		var parts := key.split(":", true, 1)
		if int(parts[0]) != p_season or (competition_id != "" and parts[1] != competition_id):
			continue
		for k in total:
			total[k] += by_key[key].get(k, 0)
	return total


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


## Phases of a week, in order. Each league system is its own phase (the biggest piece of work).
func _week_steps() -> Array:
	var steps: Array = ["academy", "finance", "loans", "ai_transfers", "availability", "morale", "club_ops", "assistant"]
	for k in pyramid_keys():
		steps.append("league:" + str(k))
	steps.append("continental")
	return steps


func _begin_week(squads: Dictionary, academies: Dictionary, trainings: Dictionary, scouting: Dictionary) -> Dictionary:
	if week >= WEEKS_PER_SEASON:
		# The season is over: nothing is played and nobody is paid until `end_season()`.
		return {"week": week, "wages_paid": 0, "loans_returned": [], "season_over": true, "blocked": true,
				"trained_ids": [], "found_ids": [], "user_fixtures": [], "auto_played": [], "simulated": 0, "ai_transfers": []}
	week += 1
	market.sync_clock(season, week, club_id, world_stats)
	last_timings.clear()
	return {"squads": squads, "academies": academies, "trainings": trainings, "scouting": scouting,
			"trained_ids": [] as Array[String], "found_ids": [] as Array[String], "wages_paid": 0, "returned": [] as Array[String],
			"deals": [], "user_fixtures": [], "auto_played": [], "simulated": 0}


func _run_step(step: String, run: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var phase := step
	match step:
		"academy":
			var now := absolute_week()
			var trainings: Dictionary = run["trainings"]
			var academies: Dictionary = run["academies"]
			for team_id in trainings:
				if academies.has(team_id):
					(trainings[team_id] as TrainingSystem).dev_bonus = float(manager.style_effects()["youth"]) * facilities.development_factor() * staff.youth_factor() * (1.0 + progress.effect("youth")) if team_id == club_id and not manager.unemployed else 1.0
					var gains: Dictionary = (trainings[team_id] as TrainingSystem).sync_to_calendar(db, academies[team_id], now)
					if team_id == club_id:
						run["trained_ids"].assign(gains.keys())
			var scouting: Dictionary = run["scouting"]
			for team_id in scouting:
				if academies.has(team_id):
					var found: Array[String] = (scouting[team_id] as ScoutingSystem).sync_to_calendar(db, academies[team_id], now)
					if team_id == club_id:
						run["found_ids"] = found
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
				var cr: Dictionary = continental.play_week(week, self, club_id)
				_collect(run, cr)
		_:
			phase = "leagues"
			var key: String = step.substr(7)
			if pyramids.has(key):
				_collect(run, (pyramids[key] as LeaguePyramid).play_week(week, self, club_id))
	last_timings[phase] = int(last_timings.get(phase, 0)) + Time.get_ticks_usec() - t0


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
		(academies[team_id] as Academy).expire_extensions(db)
		if team_id == club_id:
			over_age_mine = (academies[team_id] as Academy).over_age_ids(db)
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
	season += 1
	week = 0
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


var _derby_boost := 1.0
var _atmosphere := 1.0
var _atmosphere_week := -1


## "win" / "draw" / "loss" of the user's last played match of THIS week ("" when none).
func _last_user_result() -> String:
	var res := CareerCalendar.recent_results(self, 1)
	if res.is_empty() or int(res[0]["week"]) < week - 1 or int(res[0]["week"]) > week:
		return ""                          # the match of the week that just ended (the calendar has already moved on)
	var parts := str(res[0]["score"]).split("-")
	if parts.size() != 2:
		return ""
	return "win" if int(parts[0]) > int(parts[1]) else ("loss" if int(parts[0]) < int(parts[1]) else "draw")


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
				if (f["home"] == club_id or f["away"] == club_id) and pyr.week_of(role, comp, f) <= week:
					mine.append([comp, f])
	if continental != null:
		var cc: Competition = continental.competition(self)
		if cc != null:
			for f in cc.pending_fixtures():
				if (f["home"] == club_id or f["away"] == club_id) and continental.week_of(f) <= week:
					mine.append([cc, f])
	return mine


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
			"match_log": match_log.duplicate(true), "player_stats": player_stats.duplicate(true),
			"season_stats": season_stats.duplicate(true), "manager": manager.to_dict(), "yellow_counts": yellow_counts.duplicate(),
			"world_stats": world_stats.duplicate(true), "world_stats_legacy": world_stats_legacy, "continental": continental.to_dict() if continental != null else {}, "award_history": award_history.duplicate(true), "events": events.duplicate(true), "inbox": inbox.to_dict(), "delegation": delegation.to_dict(), "morale": morale.to_dict(), "fan_mood": fan_mood, "board": board.to_dict(), "facilities": facilities.to_dict(), "economy": economy.to_dict(), "progress": progress.to_dict(), "world": world.to_dict(), "media": media.to_dict(), "relations": relations.to_dict(), "settings": settings.to_dict(), "pending_press": pending_press.duplicate(), "national": national.to_dict(), "staff": staff.to_dict(), "season_extras": season_extras.duplicate(true)}


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


## Report fields that are whole numbers by definition come back from JSON as floats: restore them (ratings stay floats).
const _REPORT_INTS := ["version", "home_goals", "away_goals", "outcome_home", "home_pens", "away_pens"]
const _REPORT_PLAYER_INTS := ["goals", "assists", "shots", "shots_on_target", "passes", "passes_ok", "saves", "own_goals", "fouls", "fouled",
		"yellow", "red", "offsides"]


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
