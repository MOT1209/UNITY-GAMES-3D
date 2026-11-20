extends RefCounted

## Transfer market, part 1 of 3 (split Nov 2026; the class is `TransferMarket` in transfer_market.gd):
## state, pricing and search, the window calendar, values / listings / roles, advanced search and helpers.
## transfer_market_valuation.gd extends this file, transfer_market.gd extends that one. A part only calls
## functions of its own part or an earlier one.


## Transfers, loans and contracts (Phase T9). Every operation validates
## first and mutates afterwards. Ownership is single-valued: a player is in
## exactly one squad_ids list (the borrower's while on loan; `loan_parent`
## remembers the owner). Money moves only through `FinanceLedger`.

const MAX_SQUAD := 30
## Longest transfer log kept (about 20 seasons of AI and user deals).
const HISTORY_MAX := 2000
const MIN_SQUAD := 18          # a selling/loaning club must keep at least this many
const MAX_CONTRACT_YEARS := 5
const MIN_LOAN_WEEKS := 4
const MAX_LOAN_WEEKS := 52

var db: Node
var ledgers: Dictionary = {}       # team_id -> FinanceLedger
var history: Array = []            # {id, week, kind, player_id, from, to, fee, salary, years}
var next_history_id: int = 1

# --- transfers v2 (offers, negotiation, loans with terms, installments) -------------------------
## Version of the saved market block: 1 = history only (before transfers v2), 2 = everything below.
const STATE_VERSION := 2
const WEEKS_PER_SEASON := 46
## Transfer windows (weeks of the season, inclusive). The same windows apply to the user and to the AI.
## Phase K2: summer window 1 July - 1 September (pre-season + weeks 1-5: 1 Sep falls in week 5), winter window
## 1 - 31 January (weeks 22-26). `window_days_left` counts the exact days from the career date.
const WINDOWS: Array = [[1, 5], [22, 26]]
const WINDOW_DATES: Array = [[[7, 1], [9, 1]], [[1, 1], [1, 31]]]
const LISTING_NONE := "none"
const LISTING_TRANSFER := "transfer"
const LISTING_LOAN := "loan"
const LISTING_BOTH := "both"
const LISTING_UNTOUCHABLE := "untouchable"
const LISTINGS: Array[String] = [LISTING_NONE, LISTING_TRANSFER, LISTING_LOAN, LISTING_BOTH, LISTING_UNTOUCHABLE]
const MAX_LOANS_OUT := 6
const MAX_LOANS_IN := 4
const RECENT_ARRIVAL_WEEKS := 20      # a club does not sell a player it signed less than 20 weeks ago
const REJECT_BELOW := 0.70            # offers below 70 % of the asking price are rejected outright
const OFFER_TTL_WEEKS := 1            # an offer waiting for an answer expires after one week
const MAX_INCOMING_PER_WEEK := 3      # AI offers to the user per week
const PRE_CONTRACT_WEEKS := 26        # a player whose contract ends within 26 weeks may agree a free move
const INSTALLMENT_GAP_WEEKS := 23     # installments are due every half season
const MAX_CONTRACT_ROUNDS := 3
const NOTIFICATIONS_MAX := 150
const EXTERNAL_PREFIX := "ext:"       # id prefix of an external buyer (a club outside the loaded leagues)
const EXTERNAL_KEEP := 40             # external clubs kept (the oldest unreferenced ones are dropped)
const CLOSED_OFFERS_KEEP := 200
const SAVED_SEARCHES_MAX := 5
const SHORTLIST_MAX := 60
## Share of the money received for a sale that goes back into the seller's transfer budget (the same rule for every club).
## Without it a closed world (the 8-club fictional one) spends its budgets once and the market freezes.
const SALE_BUDGET_SHARE := 0.5

var cur_season: int = 1               # kept in step with the career (see `sync_clock`)
var cur_week: int = 0
var user_club: String = ""            # the managed club: AI offers and notifications are about it
var listings: Dictionary = {}         # player id -> {mode, price, loan_weeks, loan_min_split, loan_option, loan_option_fee}
var release_clauses: Dictionary = {}  # player id -> fee that the owner cannot refuse
var squad_roles: Dictionary = {}      # player id -> ContractOffer role promised in his contract
var arrivals: Dictionary = {}         # player id -> absolute week he joined his club
var offers: Array = []                # TransferOffer
var next_offer_id: int = 1
var loans: Dictionary = {}            # player id -> loan terms and statistics (see `_loan_entry`)
var installments: Array = []          # {id, payer, payee, amount, due, player_id, offer_id}
var next_installment_id: int = 1
var sell_on: Dictionary = {}          # player id -> {club, percent}: share of his next sale owed to a former club
var shortlist: Array = []             # player ids (the user's)
var saved_searches: Array = []        # [{name, filters}]
var value_history: Dictionary = {}    # player id -> last values (tracked players only)
var loan_seasons: Dictionary = {}     # "club|player" -> season of the last loan (no second loan to a club in a season)
var externals: Dictionary = {}        # "ext:N" -> {name, country}: clubs outside the loaded leagues that bid for listed players
var abroad: Dictionary = {}           # player id -> {club, country, week}: players sold to an external club (they leave the game)
var next_external_id: int = 1
var notifications: Array = []         # {season, week, key, args, offer_id}
## The career's season statistics (shared, never saved here): loan reports and the obligation conditions read them.
var world_stats: Dictionary = {}
## The user's choice: AI clubs answer the user's offers at once (false) or in the following week (true).
var replies_next_week: bool = false


## Free agents (Nov 2026): they ask this share of a fair wage and accept from FREE_AGENT_ACCEPT of their ask.
const FREE_AGENT_WAGE_FACTOR := 0.85
const FREE_AGENT_ACCEPT := 0.9

# --- declarations of the later parts (constants and state used across the parts) ---
const MAX_NEGOTIATION_ROUNDS := 3
const COUNTER_THRESHOLD := 0.85          # offers from 85 % of the asking price get a counter-offer
var _rounds: Dictionary = {}            # "buyer|player" -> {round, week} (a negotiation lasts one week)
const LOAN_DECISION_WEEKS := 2        # weeks the user has to decide about a purchase option after the loan ended
## Carries out an agreed offer (transfer or loan) through the same rules as every other deal.
## C7: set by the career; true for a club banned from registering new players (financial sustainability rule).
var ban_check: Callable = Callable()
## C8: price multiplier a buyer gets in negotiations (the manager's negotiation skill); 1.0 when unset.
var buyer_price_factor: Callable = Callable()

func _init(p_db: Node = null, p_ledgers: Dictionary = {}) -> void:
	db = p_db
	ledgers = p_ledgers


# --- pricing / search -------------------------------------------------------------------

## Price the owning club asks for a player (value, +10 % for young high-potential players).
func asking_price(p: PlayerData) -> int:
	var listing: Dictionary = listings.get(p.id, {})
	if int(listing.get("price", 0)) > 0 and str(listing.get("mode", "")) in [LISTING_TRANSFER, LISTING_BOTH]:
		return int(listing["price"])
	var price := p.transfer_value
	if p.age <= 23 and p.potential - p.get_overall() >= 10:
		price = int(price * 1.1)
	return price


## Lowest weekly wage the player accepts: 90 % of the current wage (min 100).
func minimum_wage(p: PlayerData) -> int:
	return maxi(100, int(p.salary * 0.9))


func weekly_wages(team_id: String) -> int:
	var t: TeamData = db.get_team(team_id)
	if t == null:
		return 0
	var sum := 0
	for pid in t.squad_ids:                    # same players as `get_squad`, without building the array
		var p: PlayerData = db.players.get(pid)
		if p != null:
			sum += p.salary
	return sum


## filters: name (substring), position (enum int), min_overall, max_age, max_price,
## exclude_team. Only first-team players of other clubs and free agents appear.
func search(filters: Dictionary = {}) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p: PlayerData in db.players.values():
		if p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED:
			continue
		if p.loan_parent != "":
			continue
		if filters.has("exclude_team") and p.team_id == filters["exclude_team"]:
			continue
		if filters.has("name") and str(filters["name"]) != "" \
				and p.display_name.to_lower().find(str(filters["name"]).to_lower()) < 0:
			continue
		if filters.has("position") and int(p.position) != int(filters["position"]):
			continue
		if filters.has("min_overall") and p.get_overall() < int(filters["min_overall"]):
			continue
		if filters.has("max_age") and p.age > int(filters["max_age"]):
			continue
		if filters.has("max_price") and asking_price(p) > int(filters["max_price"]):
			continue
		out.append(p)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		if a.get_overall() != b.get_overall():
			return a.get_overall() > b.get_overall()
		return a.id < b.id)
	return out


## The career keeps the market's clock in step (windows, offer deadlines, "recently arrived").
func sync_clock(p_season: int, p_week: int, p_user_club: String, p_stats: Variant = null) -> void:
	cur_season = p_season
	cur_week = p_week
	user_club = p_user_club
	if p_stats is Dictionary:
		world_stats = p_stats


func abs_week() -> int:
	return (cur_season - 1) * WEEKS_PER_SEASON + cur_week


## Days until the open window closes (its last day included), or -1 when no window is open on (season, week, day).
static func window_days_left(season: int, week: int, day: int) -> int:
	var today := CareerDate.jdn_of(season, week, day)
	var y := CareerDate.season_year(season)
	for win in WINDOW_DATES:
		var yy := y if int(win[0][0]) >= 7 else y + 1
		var a := CareerDate.jdn(yy, int(win[0][0]), int(win[0][1]))
		var b := CareerDate.jdn(yy, int(win[1][0]), int(win[1][1]))
		if today >= a and today <= b:
			return b - today + 1
	return -1


static func window_open(w: int) -> bool:
	for win in WINDOWS:
		if w >= int(win[0]) and w <= int(win[1]):
			return true
	return false


## {open, weeks_left (this cur_week included, 0 when closed), deadline (last cur_week of an open window), next_open (cur_week)}.
static func window_info(w: int) -> Dictionary:
	for win in WINDOWS:
		if w >= int(win[0]) and w <= int(win[1]):
			return {"open": true, "weeks_left": int(win[1]) - w + 1, "deadline": w == int(win[1]), "next_open": w}
	var next := int(WINDOWS[0][0])
	for win in WINDOWS:
		if int(win[0]) > w:
			next = int(win[0])
			break
	return {"open": false, "weeks_left": 0, "deadline": false, "next_open": next}


## Weeks from cur_week `w` until the next window opens (a "half season" loan), at least MIN_LOAN_WEEKS.
static func weeks_to_next_window(w: int) -> int:
	var next := -1
	for win in WINDOWS:
		if int(win[0]) > w:
			next = int(win[0])
			break
	var weeks := next - w if next > w else WEEKS_PER_SEASON - w + int(WINDOWS[0][0])
	return clampi(weeks, MIN_LOAN_WEEKS, MAX_LOAN_WEEKS)


static func weeks_to_season_end(w: int) -> int:
	return clampi(WEEKS_PER_SEASON - w, MIN_LOAN_WEEKS, MAX_LOAN_WEEKS)


# --- values, listings, roles ----------------------------------------------------------------------------------

func market_value(p: PlayerData) -> int:
	return p.transfer_value


## Recomputes every player's market value (see `Valuation`) and keeps a short history for the players the user follows.
func refresh_values(career: CareerState = null) -> void:
	for p: PlayerData in db.players.values():
		if p.status == PlayerData.Status.RETIRED or p.status == PlayerData.Status.YOUTH:
			continue
		p.transfer_value = Valuation.value(p, db, career)
	var tracked := {}
	if user_club != "" and db.get_team(user_club) != null:
		for pid in db.get_team(user_club).squad_ids:
			tracked[pid] = true
	for pid in shortlist:
		tracked[pid] = true
	for o: TransferOffer in offers:
		if o.is_open():
			tracked[o.player_id] = true
	for pid in value_history.keys():
		if not tracked.has(pid):
			value_history.erase(pid)
	var ids := tracked.keys()
	ids.sort()
	for pid in ids:
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		var h: Array = value_history.get(pid, [])
		h.append(p.transfer_value)
		while h.size() > Valuation.HISTORY_LEN:
			h.pop_front()
		value_history[pid] = h


func listing_of(player_id: String) -> String:
	return str((listings.get(player_id, {}) as Dictionary).get("mode", LISTING_NONE))


func is_transfer_listed(player_id: String) -> bool:
	return listing_of(player_id) in [LISTING_TRANSFER, LISTING_BOTH]


func is_loan_listed(player_id: String) -> bool:
	return listing_of(player_id) in [LISTING_LOAN, LISTING_BOTH]


## Puts one of `team_id`'s players on the market (or takes him off with LISTING_NONE). `opts`: price, loan_weeks,
## loan_min_split (lowest wage share a borrower must pay), loan_option (allow a purchase option), loan_option_fee.
func set_listing(team_id: String, player_id: String, mode: String, opts: Dictionary = {}) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id != team_id or p.loan_parent != "":
		return "player '%s' is not under contract with '%s'" % [player_id, team_id]
	if not (mode in LISTINGS):
		return "unknown listing '%s'" % mode
	if mode == LISTING_NONE:
		listings.erase(player_id)
		return ""
	var price := int(opts.get("price", 0))
	if mode in [LISTING_TRANSFER, LISTING_BOTH] and price <= 0:
		price = market_value(p)
	var since := int((listings.get(player_id, {}) as Dictionary).get("since", abs_week()))
	listings[player_id] = {"mode": mode, "price": maxi(0, price), "since": since,
			"loan_weeks": clampi(int(opts.get("loan_weeks", weeks_to_season_end(cur_week))), MIN_LOAN_WEEKS, MAX_LOAN_WEEKS),
			"loan_min_split": clampi(int(opts.get("loan_min_split", 50)), 0, 100),
			"loan_option": bool(opts.get("loan_option", false)), "loan_option_fee": maxi(0, int(opts.get("loan_option_fee", 0)))}
	return ""


func set_release_clause(player_id: String, fee: int) -> void:
	if fee > 0:
		release_clauses[player_id] = fee
	else:
		release_clauses.erase(player_id)


func release_clause(player_id: String) -> int:
	return int(release_clauses.get(player_id, 0))


func squad_role(player_id: String) -> String:
	return str(squad_roles.get(player_id, ""))


func toggle_shortlist(player_id: String) -> bool:
	var i := shortlist.find(player_id)
	if i >= 0:
		shortlist.remove_at(i)
		return false
	if shortlist.size() >= SHORTLIST_MAX:
		return false
	shortlist.append(player_id)
	return true


func save_search(search_name: String, filters: Dictionary) -> String:
	if saved_searches.size() >= SAVED_SEARCHES_MAX:
		return "at most %d saved searches" % SAVED_SEARCHES_MAX
	saved_searches.append({"name": search_name, "filters": filters.duplicate(true)})
	return ""


# --- advanced search -------------------------------------------------------------------------------------------------

## Search with the filters of the market screen (all optional): name, position / positions (enum ints; `secondary` also
## matches secondary positions), min_age, max_age, min_overall, max_overall, min_potential, max_potential, min_price,
## max_price, max_wage, nationality, league (division id), club, foot, min_height, max_height, expiring, listed_only,
## loan_available, free_only, exclude_team; sort: overall (default), potential, price, age, value_ratio.
func search_v2(f: Dictionary) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var positions: Array = f.get("positions", [])
	if f.has("position"):
		positions = [int(f["position"])]
	var name_q := str(f.get("name", "")).to_lower()
	for p: PlayerData in db.players.values():
		if p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED or p.loan_parent != "":
			continue
		if f.has("exclude_team") and p.team_id == f["exclude_team"]:
			continue
		if name_q != "" and p.display_name.to_lower().find(name_q) < 0:
			continue
		if not positions.is_empty() and not (int(p.position) in positions):
			if not bool(f.get("secondary", false)) or not p.secondary_positions.any(func(s: Variant) -> bool:
					return PlayerData.Position.keys().find(str(s)) in positions):
				continue
		var ov := p.get_overall()
		if ov < int(f.get("min_overall", 0)) or ov > int(f.get("max_overall", 99)):
			continue
		if p.potential < int(f.get("min_potential", 0)) or p.potential > int(f.get("max_potential", 99)):
			continue
		if p.age < int(f.get("min_age", 0)) or p.age > int(f.get("max_age", 99)):
			continue
		if bool(f.get("free_only", false)) and p.team_id != "":
			continue
		if bool(f.get("listed_only", false)) and not is_transfer_listed(p.id):
			continue
		if bool(f.get("loan_available", false)) and not is_loan_listed(p.id):
			continue
		if bool(f.get("expiring", false)) and (p.team_id == "" or p.contract_years > 1):
			continue
		if str(f.get("nationality", "")) != "" and p.nationality != str(f["nationality"]) and p.nationality_id != str(f["nationality"]):
			continue
		if str(f.get("club", "")) != "" and p.team_id != str(f["club"]):
			continue
		if str(f.get("league", "")) != "":
			var t: TeamData = db.get_team(p.team_id)
			if t == null or t.league_id != str(f["league"]):
				continue
		if f.has("foot") and int(f["foot"]) >= 0 and int(p.preferred_foot) != int(f["foot"]):
			continue
		if f.has("min_height") or f.has("max_height"):
			var h := p.get_height_cm()
			if h < int(f.get("min_height", 0)) or h > int(f.get("max_height", 300)):
				continue
		if int(f.get("max_wage", 0)) > 0 and p.salary > int(f["max_wage"]):
			continue
		var price := asking_price(p) if p.team_id != "" else 0
		if int(f.get("max_price", 0)) > 0 and price > int(f["max_price"]):
			continue
		if price < int(f.get("min_price", 0)):
			continue
		out.append(p)
	var sort := str(f.get("sort", "overall"))
	# Keys computed once per player: the comparator runs ~n·log n times (≈100k for 8,000 players) and
	# `_sort_key` (overall, asking price) is not cheap.
	var keys := {}
	for p in out:
		keys[p] = _sort_key(p, sort)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var ka: float = keys[a]
		var kb: float = keys[b]
		if ka != kb:
			return ka > kb
		return a.id < b.id)
	return out


func _sort_key(p: PlayerData, sort: String) -> float:
	match sort:
		"potential":
			return p.potential
		"price":
			return -float(asking_price(p) if p.team_id != "" else 0)
		"age":
			return -p.age
		"value_ratio":
			return float(p.get_overall() * p.get_overall()) / float(maxi(asking_price(p), 1000)) if p.team_id != "" else 1.0e9
	return p.get_overall()


# --- helpers ---------------------------------------------------------------------------------

func _free_number(team_id: String, p: PlayerData) -> int:
	var used := PromotionSystem.used_numbers(db, team_id)
	var wanted := p.shirt_number
	if wanted >= 1 and wanted <= 99 and not (wanted in used):
		return wanted
	var n := PromotionSystem.next_free_number(db, team_id)
	return n if n != -1 else 0


func _strip_from_squad(squad: Variant, player_id: String) -> void:
	if squad == null:
		return
	var s: Squad = squad
	for i in s.starting.size():
		if s.starting[i] == player_id:
			s.starting[i] = ""
	s.bench.erase(player_id)
	s.reserves.erase(player_id)
	if s.captain_id == player_id:
		s.captain_id = ""
	for k in s.set_pieces:
		if s.set_pieces[k] == player_id:
			s.set_pieces[k] = ""


func _log(week: int, kind: String, player_id: String, from_id: String, to_id: String,
		fee: int, salary: int, years: int) -> void:
	history.append({"id": next_history_id, "season": cur_season, "week": week, "kind": kind, "player_id": player_id,
			"from": from_id, "to": to_id, "fee": fee, "salary": salary, "years": years})
	next_history_id += 1
	while history.size() > HISTORY_MAX:
		history.pop_front()                    # the oldest deals leave the log; ids keep counting up
