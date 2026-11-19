extends RefCounted

## Career state, part 1 of 3 (split Nov 2026; the class is `CareerState` in career_state. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: start, add_default_league, _compute_awards, _label_award_basis, pyramid_keys, add_event,
## set_objective, _buyer_price_factor, _economy_season_end, vision, _user_rank, _review_manager, job_offers,
## resign, take_job, record_match, _report_key, _ensure_log_index, has_engine_report, _kept_clean_sheet,
## _add_season_stats, stats_for, user_division, ledger.


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
## Phase K1: day of the current week, 0 = Monday .. 6 = Sunday. The date is derived (`date()`, `CareerDate`). A week that was
## advanced as a whole ends on Sunday (6); saves from before Phase K load as "Sunday of that week".
var day: int = 6
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
## Phase S1: the same per-competition rows for matches played by the event engine (model output, labelled estimated).
var sim_comp_stats: Dictionary = {}
## Records of live-simulated matches waiting for their result to be booked (match id -> record); never saved.
var live_records: Dictionary = {}
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
var development := DevelopmentState.new()   # KING Player Development System: coaching staff, plans, history (saved under "development")
var board := BoardRelations.new()        # C2.3 / C2.4 meetings and promises
var season_extras: Array = []         # C2.2 extra objectives of the running season [{kind, target, start}]
var fan_mood: int = 60                # 0..100, moved by press answers (C4.4); the full fan system is C6
var morale := MoraleSystem.new()       # C3.2 morale reasons
var delegation := Delegation.new()     # C9.3 tasks handed to the assistant
var inbox := Inbox.new()              # C9.1 central message box
var training := TrainingPlan.new()      # K3 daily training plan of the managed club
## Microseconds spent in each phase of the last `advance_week()` (diagnostics for the performance tools; never saved).
var last_timings: Dictionary = {}
var _advancing: bool = false          # an `advance_week_async` is in progress


## The default fictional world ships no league data: a career there used to have no league at all and
## "next week" advanced an empty calendar. This adds the world's league (every club, home and away) and a
## domestic cup through the same `LeaguePyramid` machinery as the data packs (calendar, simulation of the
## other matches, the user's fixtures left to play, tables, season end). Names are translation keys.
## No-op when the world already has leagues or too few clubs. Returns true when the league was added.
const DEFAULT_LEAGUE_KEY := "fictional"

const _EMPTY_STATS := {"apps": 0, "goals": 0, "assists": 0, "saves": 0, "rating_sum": 0.0, "motm": 0,
		"yellow": 0, "red": 0, "clean_sheets": 0}


# --- Phase K2: friendlies ------------------------------------------------------------------------------------

const FRIENDLY_DAY := 2                           # Wednesday of an international-break week

# --- Phase K: days -----------------------------------------------------------------------------------

## Season rollover: league movements, everyone ages, contracts run down, expired contracts
## leave, academy players age, then `PlayerLifecycle` (retirement, development, AI squads);
## the clock resets. Returns the ids released for the
## managed club so the UI can report them.
## Per-competition rows of the model-played matches are kept for the last SIM_STATS_SEASONS seasons only
## (they would otherwise grow with every season for every player the save has ever seen).
const SIM_STATS_SEASONS := 3


var _derby_boost := 1.0
var _atmosphere := 1.0
var _atmosphere_week := -1


## Report fields that are whole numbers by definition come back from JSON as floats: restore them (ratings stay floats).
const _REPORT_INTS := ["version", "home_goals", "away_goals", "outcome_home", "home_pens", "away_pens"]
const _REPORT_PLAYER_INTS := ["goals", "assists", "shots", "shots_on_target", "passes", "passes_ok", "saves", "own_goals", "fouls", "fouled",
		"yellow", "red", "offsides"]



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


func add_default_league() -> bool:
	if not pyramids.is_empty() or db == null:
		return false
	var clubs: Array = db.list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
	if clubs.size() < 4:
		return false
	clubs.sort()
	var def := LeagueDef.from_dict(DEFAULT_LEAGUE_KEY, {"country": "fictional", "name": "LEAGUE_DEFAULT_NAME",
			"divisions": [{"id": "fic_league", "name": "LEAGUE_DEFAULT_NAME", "tier": 1, "team_ids": clubs,
					"promote": 0, "relegate": 0, "cycles": 4 if clubs.size() <= 10 else 2}],
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
	var stored := report.duplicate(true)
	stored.erase("heatmaps")          # position grids are only for the results screen; they would bloat every career save
	match_log.append(stored)
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
		s["minutes"] = int(s.get("minutes", 0)) + int(p.get("minutes", 0))
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
	s["minutes"] = int(s.get("minutes", 0)) + int(p.get("minutes", 0))
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


## The pyramid and division the managed club plays in ({} outside a pyramid).
func user_division() -> Dictionary:
	for k in pyramids:
		var d: Dictionary = (pyramids[k] as LeaguePyramid).division_of(club_id)
		if not d.is_empty():
			return {"pyramid": k, "division": d}
	return {}


func ledger() -> FinanceLedger:
	return ledgers[club_id]
