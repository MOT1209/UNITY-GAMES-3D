class_name TransferMarket
extends RefCounted

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


# --- negotiation ----------------------------------------------------------------------------

const MAX_NEGOTIATION_ROUNDS := 3
const COUNTER_THRESHOLD := 0.85          # offers from 85 % of the asking price get a counter-offer
var _rounds: Dictionary = {}            # "buyer|player" -> {round, week} (a negotiation lasts one week)


## The seller's answer to an offer of `offer` for a player (permanent transfer):
##   {status: "accepted"}                       offer >= asking price: the club agrees to sell at the offer;
##   {status: "counter", counter: int, round}   offer >= 85 % of the price: the club asks for 95 % of the price (never less
##                                              than the offer), at most MAX_NEGOTIATION_ROUNDS counters per week;
##   {status: "rejected", reason: String}       too low, rounds used up, or the sale is impossible.
## It only answers; `buy()` still enforces every budget and squad rule when the deal is made.
func negotiate(buyer_id: String, player_id: String, offer: int, week: int) -> Dictionary:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id == "" or p.team_id == buyer_id or p.loan_parent != "" or p.status == PlayerData.Status.YOUTH:
		return {"status": "rejected", "reason": "not for sale"}
	var seller: TeamData = db.get_team(p.team_id)
	if seller == null or seller.squad_ids.size() <= MIN_SQUAD:
		return {"status": "rejected", "reason": "seller must keep a minimum squad"}
	var price := asking_price(p)
	if buyer_price_factor.is_valid():
		price = int(price * float(buyer_price_factor.call(buyer_id)))
	if offer >= price:
		_rounds.erase("%s|%s" % [buyer_id, player_id])
		return {"status": "accepted", "fee": offer}
	var key := "%s|%s" % [buyer_id, player_id]
	var st: Dictionary = _rounds.get(key, {"round": 0, "week": week})
	if int(st["week"]) != week:
		st = {"round": 0, "week": week}
	if offer < int(price * COUNTER_THRESHOLD) or int(st["round"]) >= MAX_NEGOTIATION_ROUNDS:
		return {"status": "rejected", "reason": "offer too low" if offer < int(price * COUNTER_THRESHOLD) else "negotiation broke down"}
	st["round"] = int(st["round"]) + 1
	_rounds[key] = st
	return {"status": "counter", "counter": maxi(int(price * 0.95), offer + 1), "round": int(st["round"])}


# --- transfers ----------------------------------------------------------------------------

## Permanent transfer of `player_id` to `buyer_id`. Returns "" or an error.
func buy(buyer_id: String, player_id: String, fee: int, salary: int, years: int, p_week: int,
		squads: Dictionary = {}) -> String:
	return _transfer(buyer_id, player_id, fee, salary, years, p_week, squads, true)


## The transfer itself. `check_price` = the seller must get at least its asking price (the direct `buy()`); deals agreed
## through an offer pass false: the agreed fee was already accepted by the seller.
func _transfer(buyer_id: String, player_id: String, fee: int, salary: int, years: int, week: int,
		squads: Dictionary = {}, check_price := true, deal := {}) -> String:
	var p: PlayerData = db.get_player(player_id)
	var buyer: TeamData = db.get_team(buyer_id)
	if p == null:
		return "unknown player '%s'" % player_id
	if buyer == null or buyer.category != TeamData.Category.CLUB:
		return "unknown or non-club buyer '%s'" % buyer_id
	if p.status == PlayerData.Status.YOUTH:
		return "academy youth cannot be bought (promote them first)"
	if p.loan_parent != "":
		return "player is on loan and cannot be transferred"
	if p.team_id == buyer_id:
		return "player already belongs to '%s'" % buyer_id
	var seller: TeamData = db.get_team(p.team_id) if p.team_id != "" else null
	if p.team_id != "" and seller == null:
		return "player's club '%s' does not exist" % p.team_id
	var err := _check_buyer(buyer_id, p, fee, salary, years)
	if err != "":
		return err
	var upfront := fee - (fee / maxi(1, int(deal.get("installments", 1)))) * (maxi(1, int(deal.get("installments", 1))) - 1)
	var bonus := int(deal.get("signing_bonus", 0))
	if bonus > 0 and not (ledgers[buyer_id] as FinanceLedger).can_afford(-(upfront + bonus), "signing_bonus"):
		return "insufficient funds"
	if seller != null:
		if check_price and fee < asking_price(p):
			return "offer rejected: seller asks %d" % asking_price(p)
		if seller.squad_ids.size() <= MIN_SQUAD and not bool(deal.get("free", false)):
			return "seller must keep at least %d players" % MIN_SQUAD
	elif fee != 0:
		return "free agents cost no transfer fee"
	# --- all checks passed: mutate ---
	var buyer_ledger: FinanceLedger = ledgers[buyer_id]
	if fee > 0:
		var spend_err := buyer_ledger.spend_transfer("transfer_in", upfront, "Signed %s" % p.display_name, week)
		if spend_err != "":
			return spend_err
		if seller != null and ledgers.has(seller.id):
			(ledgers[seller.id] as FinanceLedger).record("transfer_out", upfront, "Sold %s" % p.display_name, week)
			_reinvest(seller.id, upfront)
		if upfront < fee:
			_schedule_installments(buyer_id, seller.id if seller != null else "", fee - upfront,
					maxi(1, int(deal.get("installments", 1))) - 1, player_id, int(deal.get("offer_id", 0)))
		if seller != null:
			_pay_sell_on(seller.id, p, fee, week)
	if bonus > 0:
		buyer_ledger.record("signing_bonus", -bonus, "Signing bonus for %s" % p.display_name, week, "FIN_SIGNING_BONUS", [p.display_name])
	if seller != null:
		seller.squad_ids.remove_at(seller.squad_ids.find(player_id))
		_strip_from_squad(squads.get(seller.id), player_id)
	buyer.squad_ids.append(player_id)
	var from_id := p.team_id
	p.team_id = buyer_id
	if p.status != PlayerData.Status.INJURED and p.status != PlayerData.Status.SUSPENDED:
		p.status = PlayerData.Status.ACTIVE          # a move does not heal an injury or lift a ban
	p.salary = salary
	p.contract_years = years
	p.shirt_number = _free_number(buyer_id, p)
	p.development_history.append({"event": "transferred", "week": week, "from": from_id, "to": buyer_id, "fee": fee})
	_log(week, "transfer", player_id, from_id, buyer_id, fee, salary, years)
	_after_move(p, buyer_id)
	if int(deal.get("sell_on_percent", 0)) > 0 and from_id != "":
		sell_on[player_id] = {"club": from_id, "percent": int(deal["sell_on_percent"])}
	if int(deal.get("release_clause", 0)) > 0:
		release_clauses[player_id] = int(deal["release_clause"])
	if str(deal.get("squad_role", "")) != "":
		squad_roles[player_id] = str(deal["squad_role"])
	return ""


## Sells one of `seller_id`'s players to `buyer_id` (same rules as `buy`).
func sell(seller_id: String, player_id: String, buyer_id: String, fee: int, salary: int,
		years: int, week: int, squads: Dictionary = {}) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id != seller_id:
		return "player '%s' does not belong to '%s'" % [player_id, seller_id]
	return buy(buyer_id, player_id, fee, salary, years, week, squads)


func _check_buyer(buyer_id: String, p: PlayerData, fee: int, salary: int, years: int) -> String:
	if not ledgers.has(buyer_id):
		return "buyer has no finances"
	var ledger: FinanceLedger = ledgers[buyer_id]
	if fee < 0:
		return "negative fee"
	if years < 1 or years > MAX_CONTRACT_YEARS:
		return "contract length must be 1-%d years" % MAX_CONTRACT_YEARS
	if salary < minimum_wage(p):
		return "player rejects the contract: wants at least %d per week" % minimum_wage(p)
	if db.get_team(buyer_id).squad_ids.size() >= MAX_SQUAD:
		return "squad is full (%d)" % MAX_SQUAD
	if fee > 0 and fee > ledger.transfer_budget:
		return "transfer budget too small (%d available, %d needed)" % [ledger.transfer_budget, fee]
	if fee > 0 and not ledger.can_afford(-fee, "transfer_in"):
		return "insufficient funds"
	if weekly_wages(buyer_id) + salary > ledger.wage_budget:
		return "wage budget exceeded"
	return ""


# --- loans ----------------------------------------------------------------------------------

## Loans `player_id` from its owner to `to_id` for `weeks`. The borrower pays the fee and the wages.
func loan(to_id: String, player_id: String, weeks: int, fee: int, week: int,
		squads: Dictionary = {}, terms: Dictionary = {}) -> String:
	var p: PlayerData = db.get_player(player_id)
	var borrower: TeamData = db.get_team(to_id)
	if p == null:
		return "unknown player '%s'" % player_id
	if borrower == null or borrower.category != TeamData.Category.CLUB:
		return "unknown or non-club borrower '%s'" % to_id
	if p.team_id == "" or p.status == PlayerData.Status.YOUTH:
		return "only first-team players can be loaned"
	if p.loan_parent != "":
		return "player is already on loan"
	if p.team_id == to_id:
		return "player already belongs to '%s'" % to_id
	if weeks < MIN_LOAN_WEEKS or weeks > MAX_LOAN_WEEKS:
		return "loan length must be %d-%d weeks" % [MIN_LOAN_WEEKS, MAX_LOAN_WEEKS]
	if fee < 0:
		return "negative fee"
	var owner: TeamData = db.get_team(p.team_id)
	if owner == null:
		return "player's club does not exist"
	if owner.squad_ids.size() <= MIN_SQUAD:
		return "lender must keep at least %d players" % MIN_SQUAD
	if borrower.squad_ids.size() >= MAX_SQUAD:
		return "borrower's squad is full"
	if not ledgers.has(to_id):
		return "borrower has no finances"
	var ledger: FinanceLedger = ledgers[to_id]
	if fee > 0 and (fee > ledger.transfer_budget or not ledger.can_afford(-fee, "loan_in")):
		return "borrower cannot afford the loan fee"
	var split := clampi(int(terms.get("wage_split_percent", 100)), 0, 100)
	if weekly_wages(to_id) + p.salary * split / 100 > ledger.wage_budget:
		return "wage budget exceeded"
	# --- mutate ---
	if fee > 0:
		ledger.spend_transfer("loan_in", fee, "Loan fee for %s" % p.display_name, week)
		if ledgers.has(owner.id):
			(ledgers[owner.id] as FinanceLedger).record("loan_out", fee, "Loan fee for %s" % p.display_name, week)
	owner.squad_ids.remove_at(owner.squad_ids.find(player_id))
	_strip_from_squad(squads.get(owner.id), player_id)
	borrower.squad_ids.append(player_id)
	p.loan_parent = owner.id
	p.loan_weeks_left = weeks
	p.team_id = to_id
	p.shirt_number = _free_number(to_id, p)
	p.development_history.append({"event": "loaned", "week": week, "from": owner.id, "to": to_id, "weeks": weeks})
	_log(week, "loan", player_id, owner.id, to_id, fee, p.salary, 0)
	loans[player_id] = _loan_entry(owner.id, to_id, weeks, fee, terms, player_id)
	loan_seasons["%s|%s" % [to_id, player_id]] = cur_season
	return ""


## Ends one loan early or at expiry: the player returns to the owning club.
func return_from_loan(player_id: String, week: int, squads: Dictionary = {}) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.loan_parent == "":
		return "player is not on loan"
	var owner: TeamData = db.get_team(p.loan_parent)
	var borrower: TeamData = db.get_team(p.team_id)
	if borrower != null:
		var idx := borrower.squad_ids.find(player_id)
		if idx >= 0:
			borrower.squad_ids.remove_at(idx)
		_strip_from_squad(squads.get(borrower.id), player_id)
	loans.erase(player_id)
	if owner == null:   # owner vanished: player becomes a free agent instead of staying owned twice
		p.team_id = ""
		p.loan_parent = ""
		p.loan_weeks_left = 0
		return ""
	owner.squad_ids.append(player_id)
	p.team_id = owner.id
	p.loan_parent = ""
	p.loan_weeks_left = 0
	p.shirt_number = _free_number(owner.id, p)
	p.development_history.append({"event": "loan_ended", "week": week, "to": owner.id})
	_log(week, "loan_return", player_id, borrower.id if borrower != null else "", owner.id, 0, p.salary, 0)
	return ""


## Counts down all loans by one week and returns expired players to their owners.
## Loans with a purchase option end with a decision instead: the AI borrower decides at once, the user gets
## `LOAN_DECISION_WEEKS` to choose (`exercise_option` / `return_from_loan`) before the player goes back.
func advance_loans(week: int, squads: Dictionary = {}) -> Array[String]:
	var returned: Array[String] = []
	for p: PlayerData in db.players.values():            # `values()` is already a copy: a return may change the squads
		if p.loan_parent != "":
			p.loan_weeks_left -= 1
			if p.loan_weeks_left > 0:
				continue
			var entry: Dictionary = loans.get(p.id, {})
			if str(entry.get("type", "")) == TransferOffer.LOAN_WITH_OBLIGATION and int(entry.get("obligation_apps", 0)) == 0 \
					and exercise_option(p.id, week, squads, true) == "":
				continue                                          # an unconditional obligation: bought at the end of the loan
			if str(entry.get("type", TransferOffer.LOAN)) == TransferOffer.LOAN_WITH_OPTION and p.team_id == user_club \
					and p.loan_weeks_left > -LOAN_DECISION_WEEKS:
				if not bool(entry.get("decision", false)):
					entry["decision"] = true
					note("NOTE_LOAN_OPTION_DECISION", [p.id, int(entry.get("option_fee", 0))])
				continue
			if str(entry.get("type", "")) == TransferOffer.LOAN_WITH_OPTION and p.team_id != user_club \
					and _ai_takes_option(p, entry) and exercise_option(p.id, week, squads) == "":
				continue
			if return_from_loan(p.id, week, squads) == "":
				returned.append(p.id)
	return returned


# --- contracts ------------------------------------------------------------------------------

func renew_contract(team_id: String, player_id: String, salary: int, years: int, week: int) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id != team_id or p.loan_parent != "":
		return "player '%s' is not under contract with '%s'" % [player_id, team_id]
	if years < 1 or years > MAX_CONTRACT_YEARS:
		return "contract length must be 1-%d years" % MAX_CONTRACT_YEARS
	if salary < minimum_wage(p):
		return "player rejects the contract: wants at least %d per week" % minimum_wage(p)
	if not ledgers.has(team_id):
		return "club has no finances"
	var new_total := weekly_wages(team_id) - p.salary + salary
	if new_total > (ledgers[team_id] as FinanceLedger).wage_budget:
		return "wage budget exceeded"
	p.salary = salary
	p.contract_years = years
	p.development_history.append({"event": "renewed", "week": week, "salary": salary, "years": years})
	_log(week, "renewal", player_id, team_id, team_id, 0, salary, years)
	return ""


func expiring_contracts(team_id: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in db.get_squad(team_id):
		if p.contract_years <= 1 and p.loan_parent == "":
			out.append(p)
	return out


# === transfers v2 ===========================================================================================

const LOAN_DECISION_WEEKS := 2        # weeks the user has to decide about a purchase option after the loan ended


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


# --- the selling club --------------------------------------------------------------------------------------

## Rank of `p` among his club's players: {pos: better players at his position, all: better players in the squad,
## same: players at his position (him included)}. "Better" = higher overall, ties by id.
func squad_rank(p: PlayerData, team_id := "") -> Dictionary:
	var tid := team_id if team_id != "" else p.team_id
	var pos := 0
	var all := 0
	var same := 1
	var ov := p.get_overall()
	var t: TeamData = db.get_team(tid)
	if t == null:
		return {"pos": 0, "all": 0, "same": 1}
	for pid in t.squad_ids:
		if pid == p.id:
			continue
		var q: PlayerData = db.players.get(pid)
		if q == null:
			continue
		var qo := q.get_overall()
		var better := qo > ov or (qo == ov and q.id < p.id)
		if better:
			all += 1
		if q.position == p.position:
			same += 1
			if better:
				pos += 1
	return {"pos": pos, "all": all, "same": same}


## How much the owning club wants to keep the player: 1.0 (squad player) to 1.8 (one of the club's best three, first
## choice at his position, no cover behind him).
func importance(p: PlayerData) -> float:
	var r := squad_rank(p)
	var m := 1.0
	if int(r["all"]) < 3:
		m += 0.35
	if int(r["pos"]) == 0:
		m += 0.25
	elif int(r["pos"]) == 1:
		m += 0.1
	if int(r["same"]) <= 2:
		m += 0.15
	return clampf(m, 1.0, 1.8)


## The fee the owning club asks in a negotiation: the listing price when the player is on the transfer list, else the
## market value × importance (+10 % for young high-potential players), less in the last contract year and on deadline day.
func seller_price(p: PlayerData) -> int:
	if is_transfer_listed(p.id) and int(listings[p.id].get("price", 0)) > 0:
		return int(listings[p.id]["price"])
	var price := float(market_value(p)) * importance(p)
	if p.age <= 23 and p.potential - p.get_overall() >= 10:
		price *= 1.1
	if p.contract_years <= 1:
		price *= 0.85
	if bool(window_info(cur_week)["deadline"]):
		price *= 0.93
	return maxi(Valuation.round_value(price), 1000)


## Why the owner refuses to talk at all ("" = it negotiates). Translation keys OFFER_REASON_*.
func refusal(p: PlayerData, buyer_id: String, loan_deal: bool, fee: int = 0) -> String:
	if p == null or p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED or p.team_id == "":
		return "OFFER_REASON_NOT_AVAILABLE"
	if p.team_id == buyer_id:
		return "OFFER_REASON_OWN_PLAYER"
	if p.loan_parent != "":
		return "OFFER_REASON_ON_LOAN"
	var clause := release_clause(p.id)
	if not loan_deal and clause > 0 and fee >= clause:
		return ""                                        # the release clause is paid: the club cannot say no
	if listing_of(p.id) == LISTING_UNTOUCHABLE:
		return "OFFER_REASON_UNTOUCHABLE"
	var arrived := int(arrivals.get(p.id, -1000))
	if arrived > -1000 and abs_week() - arrived < RECENT_ARRIVAL_WEEKS and listing_of(p.id) == LISTING_NONE:
		return "OFFER_REASON_JUST_ARRIVED"
	var owner: TeamData = db.get_team(p.team_id)
	if owner == null or owner.squad_ids.size() <= MIN_SQUAD:
		return "OFFER_REASON_SQUAD_SIZE"
	if loan_deal:
		if loans_out(p.team_id) >= MAX_LOANS_OUT:
			return "OFFER_REASON_LOAN_LIMIT"
		if loans_in(buyer_id) >= MAX_LOANS_IN:
			return "OFFER_REASON_BORROWER_LIMIT"
		if int(loan_seasons.get("%s|%s" % [buyer_id, p.id], 0)) == cur_season:
			return "OFFER_REASON_LOANED_THIS_SEASON"
		if not is_loan_listed(p.id) and int(squad_rank(p)["pos"]) == 0 and int(squad_rank(p)["all"]) < 11:
			return "OFFER_REASON_KEY_PLAYER"
	return ""


func loans_out(team_id: String) -> int:
	var n := 0
	for pid in loans:
		if str(loans[pid]["from"]) == team_id:
			n += 1
	return n


func loans_in(team_id: String) -> int:
	var n := 0
	for pid in loans:
		if str(loans[pid]["to"]) == team_id:
			n += 1
	return n


## Lowest share of the wage the owner wants a borrower to pay: the listing's minimum, else 50 % for fringe and young
## players and 75 % for the rest; a promise of playing time lowers it by 10 points.
func min_wage_split(p: PlayerData, promised_play: int = 0) -> int:
	var split := 75
	if is_loan_listed(p.id):
		split = int(listings[p.id].get("loan_min_split", 50))
	elif p.age <= 21 or int(squad_rank(p)["pos"]) >= 2:
		split = 50
	if promised_play >= 50:
		split -= 10
	return clampi(split, 0, 100)


## Loan fee the owner expects: nothing for fringe/young players, else about 5 % of the value per cur_season.
func expected_loan_fee(p: PlayerData, weeks: int) -> int:
	if p.age <= 21 or int(squad_rank(p)["pos"]) >= 2 or is_loan_listed(p.id):
		return 0
	return Valuation.round_value(market_value(p) * 0.05 * weeks / float(WEEKS_PER_SEASON))


## Value of an offer for the seller: installments are worth a little less than cash, a sell-on share a little more.
static func effective_fee(o: TransferOffer) -> float:
	return o.fee * (1.0 - 0.03 * (o.installments - 1)) + o.fee * o.sell_on_percent / 100.0 * 0.25


## The owning club's answer to the terms on the table. Pure: nothing changes.
## {status: accepted | countered | rejected, reason: key, terms: counter terms}
func seller_answer(o: TransferOffer) -> Dictionary:
	var p: PlayerData = db.get_player(o.player_id)
	var why := refusal(p, o.from_club, o.is_loan(), o.fee)
	if why != "":
		return {"status": TransferOffer.REJECTED, "reason": why}
	if not o.is_loan():
		var clause := release_clause(p.id)
		if clause > 0 and o.fee >= clause:
			return {"status": TransferOffer.ACCEPTED, "reason": "", "release_clause": true}
		var price := float(seller_price(p))
		var ratio := effective_fee(o) / maxf(price, 1.0)
		if ratio >= 1.0:
			return {"status": TransferOffer.ACCEPTED, "reason": ""}
		if ratio < REJECT_BELOW:
			return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_TOO_LOW"}
		if o.counters() >= MAX_NEGOTIATION_ROUNDS:
			return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_BROKE_DOWN"}
		var t := o.terms()
		if ratio >= COUNTER_THRESHOLD:
			t["fee"] = maxi(o.fee + 1, Valuation.round_value((o.fee + price) / 2.0 + price * 0.02))
			if o.sell_on_percent == 0 and p.age <= 23:
				t["sell_on_percent"] = 10
		else:
			t["fee"] = int(price)
		t["fee"] = mini(int(t["fee"]), int(price))
		if effective_fee_terms(t) < price * 0.999 and int(t["fee"]) == int(price):
			t["installments"] = 1           # at the full price the club wants cash
		return {"status": TransferOffer.COUNTERED, "reason": "", "terms": t}
	# loans
	if o.loan_weeks < MIN_LOAN_WEEKS or o.loan_weeks > MAX_LOAN_WEEKS:
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_LOAN_LENGTH"}
	var want_split := min_wage_split(p, o.min_play_percent)
	var want_fee := expected_loan_fee(p, o.loan_weeks)
	var want_option := 0
	if o.type == TransferOffer.LOAN_WITH_OPTION:
		want_option = int(listings[p.id].get("loan_option_fee", 0)) if is_loan_listed(p.id) and bool(listings[p.id].get("loan_option", false)) \
				and int(listings[p.id].get("loan_option_fee", 0)) > 0 else int(seller_price(p))
	elif o.type == TransferOffer.LOAN_WITH_OBLIGATION:
		want_option = int(seller_price(p) * 0.85)
	var ok := o.wage_split_percent >= want_split and o.loan_fee >= int(want_fee * 0.7) and o.option_fee >= int(want_option * 0.97)
	if ok:
		return {"status": TransferOffer.ACCEPTED, "reason": ""}
	if o.counters() >= MAX_NEGOTIATION_ROUNDS:
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_BROKE_DOWN"}
	if o.option_fee > 0 and o.option_fee < int(want_option * REJECT_BELOW):
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_TOO_LOW"}
	var t := o.terms()
	t["wage_split_percent"] = maxi(o.wage_split_percent, want_split)
	t["loan_fee"] = maxi(o.loan_fee, want_fee)
	t["option_fee"] = maxi(o.option_fee, want_option)
	return {"status": TransferOffer.COUNTERED, "reason": "", "terms": t}


static func effective_fee_terms(t: Dictionary) -> float:
	var o := TransferOffer.new()
	o.set_terms(t)
	return effective_fee(o)


## Rough chance that the owner accepts the terms as they are: "high", "medium" or "low" (shown while negotiating).
func acceptance_chance(o: TransferOffer) -> String:
	var a := seller_answer(o)
	if a["status"] == TransferOffer.ACCEPTED:
		return "high"
	if a["status"] == TransferOffer.COUNTERED:
		return "medium"
	return "low"


# --- the player -----------------------------------------------------------------------------------------------

## Weekly wage a player of this level and age can expect.
func fair_wage(p: PlayerData) -> int:
	var ov := p.get_overall()
	var w := float(ov * ov) / 4.0
	if p.age <= 20:
		w *= 0.6
	elif p.age >= 33:
		w *= 0.8
	return maxi(100, int(w))


## Role a player would have at `team_id` once he has joined (index into ContractOffer.ROLES). His rank at his position is
## counted among the club's players WITH him, and compared with the club's level (the mean of its best 11):
## best at his position and above the club's level -> star; one of the club's starters at the position (or second in line
## but above the club's level) -> starter; next in line (not far below the level) -> rotation; otherwise backup (a prospect for a teenager).
func deserved_role(p: PlayerData, team_id: String) -> int:
	var r := squad_rank(p, team_id)
	var level := _club_level(team_id, p)
	var ov := p.get_overall()
	var slots := 2 if p.position in [PlayerData.Position.CB, PlayerData.Position.CM] else 1
	var pos := int(r["pos"])
	if pos == 0 and ov >= level + 2:
		return 0
	if pos < slots + (1 if ov >= level + 2 else 0):
		return 1                                  # a player above the club's level also starts when only second in line
	if pos < slots + 1 and ov >= level - 8:
		return 2
	if p.age <= 19 and ov < level - 8:
		return 4
	return 3


## Mean overall of the club's best 11 players, the player himself left out.
func _club_level(team_id: String, p: PlayerData) -> int:
	var t: TeamData = db.get_team(team_id)
	if t == null:
		return 60
	var all: Array = []
	for pid in t.squad_ids:
		var q: PlayerData = db.players.get(pid)
		if q != null and q != p:
			all.append(q.get_overall())
	if all.is_empty():
		return 60
	all.sort()
	all.reverse()
	var n := mini(11, all.size())
	var sum := 0
	for i in n:
		sum += int(all[i])
	return sum / n


## The player's answer to personal terms at `team_id` (renewal = his own club). Pure.
## {status: accepted | countered | rejected, reason: key, demand: ContractOffer}
func player_answer(p: PlayerData, team_id: String, c: ContractOffer, renewal := false) -> Dictionary:
	var demand := ContractOffer.make(c.salary, clampi(c.years, 1, MAX_CONTRACT_YEARS), c.squad_role, c.signing_bonus, c.release_clause, c.loyalty_bonus)
	if c.years < 1 or c.years > MAX_CONTRACT_YEARS:
		return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_YEARS", "demand": demand}
	var deserved := deserved_role(p, team_id)
	var role_wage: float = float(ContractOffer.ROLE_WAGE[ContractOffer.ROLES[deserved]])
	var expected := float(maxi(minimum_wage(p), int(fair_wage(p) * role_wage)))    # the wage follows the place he will have
	var cur_team: TeamData = db.get_team(p.team_id)
	var new_team: TeamData = db.get_team(team_id)
	var cur_rep := cur_team.reputation if cur_team != null else 40
	var new_rep := new_team.reputation if new_team != null else 50
	if renewal:
		expected = maxf(expected, p.salary * 1.05)
		if p.morale < 40:
			expected *= 1.15
	else:
		expected = maxf(expected, p.salary * 1.1)
		expected *= 1.0 + maxi(0, cur_rep - new_rep) * 0.01
		if new_rep + 30 < cur_rep and p.get_overall() >= 70 and c.salary < expected * 1.5:
			return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_AMBITION", "demand": demand}
	var promised := ContractOffer.ROLES.find(c.squad_role)
	if promised < 0:
		promised = 2
	var level := mini(promised, 3)                        # "prospect" is a youth role on the backup level
	var diff := level - mini(deserved, 3)
	if diff >= 2 and p.age <= 23 and p.potential >= 70:
		demand.squad_role = ContractOffer.ROLES[deserved]
		return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_PLAYING_TIME", "demand": demand}
	expected *= clampf(1.0 + 0.08 * diff, 0.85, 1.3)
	if p.age >= 30:
		expected *= 1.05
	if p.age <= 23 and c.years == 1:
		expected *= 1.05
	var value := maxi(market_value(p), 1)
	if c.release_clause > 0 and c.release_clause < value * 2:
		expected *= 0.97                                  # an affordable way out is worth something to the player
	var weeks := float(c.years * WEEKS_PER_SEASON)
	var effective := c.salary + (c.signing_bonus + c.loyalty_bonus) / weeks
	var want := maxi(int(ceil(expected)), minimum_wage(p))
	demand.salary = maxi(c.salary, want - int((c.signing_bonus + c.loyalty_bonus) / weeks))
	if effective >= want:
		return {"status": TransferOffer.ACCEPTED, "reason": "", "demand": demand}
	if effective >= want * 0.8:
		return {"status": TransferOffer.COUNTERED, "reason": "CONTRACT_REASON_WAGE", "demand": demand}
	return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_WAGE", "demand": demand}


## Terms the player would sign at `team_id` straight away (what an AI club offers him).
func default_contract(p: PlayerData, team_id: String, renewal := false) -> ContractOffer:
	var years := PlayerLifecycle.renewal_years(p) + (1 if p.age <= 26 else 0)
	var c := ContractOffer.make(maxi(minimum_wage(p), p.salary), clampi(years, 1, MAX_CONTRACT_YEARS),
			ContractOffer.ROLES[deserved_role(p, team_id)])
	var a := player_answer(p, team_id, c, renewal)
	if a["status"] != TransferOffer.ACCEPTED:
		c.salary = (a["demand"] as ContractOffer).salary
		if a["status"] == TransferOffer.REJECTED:
			c.salary = int(c.salary * 1.05) + 1
	return c


# --- offers ----------------------------------------------------------------------------------------------------

func get_offer(offer_id: int) -> TransferOffer:
	for o: TransferOffer in offers:
		if o.id == offer_id:
			return o
	return null


## Open offers about the user's club: "incoming" (others want the user's players) or "outgoing" (the user's offers).
func user_offers(direction: String, open_only := true) -> Array:
	var out: Array = []
	for o: TransferOffer in offers:
		if open_only and not o.is_open():
			continue
		if direction == "incoming" and o.to_club == user_club and o.from_club != user_club:
			out.append(o)
		elif direction == "outgoing" and o.from_club == user_club:
			out.append(o)
	out.reverse()
	return out


## Offers waiting for the user: incoming offers not answered yet and counter-offers to the user's offers.
func needs_user_action() -> int:
	var n := 0
	for o: TransferOffer in offers:
		if o.to_club == user_club and o.status == TransferOffer.PENDING:
			n += 1
		elif o.from_club == user_club and o.status == TransferOffer.COUNTERED:
			n += 1
		elif o.from_club == user_club and o.status == TransferOffer.ACCEPTED and o.contract.is_empty():
			n += 1
	for pid in loans:
		if bool(loans[pid].get("decision", false)) and str(loans[pid]["to"]) == user_club:
			n += 1
	return n


func unread_count() -> int:
	var n := 0
	for o: TransferOffer in offers:
		if o.unread and o.is_open() and (o.to_club == user_club or o.from_club == user_club):
			n += 1
	return n


func mark_read() -> void:
	for o: TransferOffer in offers:
		o.unread = false


## Type of a deal for a player with no club or an expiring contract.
func free_type(p: PlayerData) -> String:
	if p.team_id == "":
		return TransferOffer.FREE
	if p.contract_years <= 1 and cur_week >= WEEKS_PER_SEASON - PRE_CONTRACT_WEEKS and p.loan_parent == "":
		return TransferOffer.PRE_CONTRACT
	return ""


# --- external buyers (clubs outside the loaded leagues) ----------------------------------------------------------

static func is_external(club_id: String) -> bool:
	return club_id.begins_with(EXTERNAL_PREFIX)


## Display name of a club id: a loaded club, an external club, or the id itself.
func club_name(club_id: String) -> String:
	if is_external(club_id):
		return str((externals.get(club_id, {}) as Dictionary).get("name", club_id))
	var t: TeamData = db.get_team(club_id) if db != null and club_id != "" else null
	return t.display_name if t != null else club_id


func external_country(club_id: String) -> String:
	return str((externals.get(club_id, {}) as Dictionary).get("country", ""))


## Weeks the player has been on the transfer list (0 when he is not listed).
func weeks_listed(player_id: String) -> int:
	if not is_transfer_listed(player_id):
		return 0
	return maxi(0, abs_week() - int((listings[player_id] as Dictionary).get("since", abs_week())))


## Offers made for a player since `from_abs_week`.
func offers_for(player_id: String, from_abs_week := 0) -> int:
	var n := 0
	for o: TransferOffer in offers:
		if o.player_id == player_id and o.created_week >= from_abs_week and o.from_club != o.to_club and o.to_club == user_club:
			n += 1
	return n


## An offer from a club outside the loaded leagues for one of the user's players. The user answers it like any other
## offer (accept / counter / reject); accepting sends the player abroad (see `_sell_abroad`).
func make_external_offer(player_id: String, club_name_text: String, country: String, fee: int) -> Dictionary:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id != user_club or p.loan_parent != "" or p.status == PlayerData.Status.YOUTH:
		return {"error": "player is not available", "offer": null}
	var ext_id := "%s%d" % [EXTERNAL_PREFIX, next_external_id]
	next_external_id += 1
	externals[ext_id] = {"name": club_name_text, "country": country}
	var o := TransferOffer.new()
	o.id = next_offer_id
	next_offer_id += 1
	o.created_week = abs_week()
	o.expires_week = abs_week() + OFFER_TTL_WEEKS
	o.from_club = ext_id
	o.to_club = user_club
	o.player_id = player_id
	o.type = TransferOffer.PERMANENT
	o.set_terms({"fee": maxi(fee, 1000), "installments": 1})
	o.unread = true
	o.add_round(ext_id, abs_week())
	o.status = TransferOffer.PENDING
	offers.append(o)
	note("NOTE_OFFER_RECEIVED", [player_id, ext_id], o.id)
	_bound_offers()
	return {"error": "", "offer": o}


## The user accepts an external offer: the fee goes to the user's ledger and the player leaves the game (he plays abroad).
func _sell_abroad(o: TransferOffer, squads: Dictionary = {}) -> String:
	var p: PlayerData = db.get_player(o.player_id)
	if p == null or p.team_id != o.to_club or p.loan_parent != "":
		return _fail(o, "player is no longer at the club")
	var seller: TeamData = db.get_team(o.to_club)
	if seller == null or seller.squad_ids.size() <= MIN_SQUAD:
		return _fail(o, "seller must keep at least %d players" % MIN_SQUAD)
	var ledger: FinanceLedger = ledgers[o.to_club]
	var err := ledger.record("transfer_out", o.fee, "Sold %s" % p.display_name, cur_week)
	if err != "":
		return _fail(o, err)
	_reinvest(o.to_club, o.fee)
	_pay_sell_on(o.to_club, p, o.fee, cur_week)
	var week_now := cur_week
	_log(week_now, "transfer", p.id, o.to_club, o.from_club, o.fee, 0, 0)
	listings.erase(p.id)
	release_clauses.erase(p.id)
	squad_roles.erase(p.id)
	_strip_from_squad(squads.get(o.to_club), p.id)
	abroad[p.id] = {"club": club_name(o.from_club), "country": external_country(o.from_club), "week": abs_week()}
	PlayerLifecycle.retire(db, p, squads, cur_season)
	p.development_history[p.development_history.size() - 1] = {"event": "transferred", "week": week_now, "from": o.to_club,
			"to": o.from_club, "fee": o.fee, "abroad": true}
	o.status = TransferOffer.COMPLETED
	_notify_deal(o, "NOTE_DEAL_COMPLETED")
	for other: TransferOffer in offers:
		if other != o and other.player_id == o.player_id and other.is_open():
			other.status = TransferOffer.EXPIRED
	return ""


## The external club answers the user's counter: it pays up to 100 % of the listed price (or 110 % of the value).
func _external_responds(o: TransferOffer, previous: Dictionary) -> void:
	var p: PlayerData = db.get_player(o.player_id)
	var limit := maxi(int(previous["fee"]), mini(asking_price(p), int(market_value(p) * 1.1)))
	if o.fee <= limit:
		o.status = TransferOffer.ACCEPTED
		o.add_round(o.from_club, abs_week())
		_sell_abroad(o)
		return
	var t := o.terms()
	t["fee"] = mini(limit, Valuation.round_value((int(previous["fee"]) + o.fee) / 2.0))
	if int(t["fee"]) <= int(previous["fee"]) or o.rounds.size() > 2 * MAX_NEGOTIATION_ROUNDS:
		o.status = TransferOffer.WITHDRAWN
		o.reason = "OFFER_REASON_BUYER_WALKED_AWAY"
		note("NOTE_OFFER_WITHDRAWN", [o.player_id, o.from_club], o.id)
		return
	o.set_terms(t)
	o.add_round(o.from_club, abs_week())
	o.status = TransferOffer.PENDING
	o.unread = true
	o.expires_week = abs_week() + OFFER_TTL_WEEKS


## Makes an offer from `from_id` for `player_id`. The owning club answers at once when it is an AI club; an offer to the
## user's club waits for the user. Returns {error, offer}. `terms`: see TransferOffer.set_terms.
func make_offer(from_id: String, player_id: String, type: String, terms: Dictionary) -> Dictionary:
	var p: PlayerData = db.get_player(player_id)
	var buyer: TeamData = db.get_team(from_id)
	if p == null:
		return {"error": "unknown player '%s'" % player_id, "offer": null}
	if buyer == null or buyer.category != TeamData.Category.CLUB or not ledgers.has(from_id):
		return {"error": "unknown or non-club buyer '%s'" % from_id, "offer": null}
	if not (type in TransferOffer.TYPES):
		return {"error": "unknown offer type '%s'" % type, "offer": null}
	if p.team_id == from_id:
		return {"error": "player already belongs to '%s'" % from_id, "offer": null}
	if p.status == PlayerData.Status.YOUTH:
		return {"error": "academy youth cannot be bought (promote them first)", "offer": null}
	for o: TransferOffer in offers:
		if o.is_open() and o.from_club == from_id and o.player_id == player_id:
			return {"error": "an offer for this player is already open", "offer": null}
	if (type == TransferOffer.FREE) != (p.team_id == ""):
		return {"error": "free agents cost no transfer fee" if p.team_id == "" else "player is under contract", "offer": null}
	if type == TransferOffer.PRE_CONTRACT and free_type(p) != TransferOffer.PRE_CONTRACT:
		return {"error": "pre-contracts need a contract ending within %d weeks" % PRE_CONTRACT_WEEKS, "offer": null}
	var o := TransferOffer.new()
	o.id = next_offer_id
	next_offer_id += 1
	o.created_week = abs_week()
	o.expires_week = abs_week() + OFFER_TTL_WEEKS
	o.from_club = from_id
	o.to_club = p.team_id if type != TransferOffer.PRE_CONTRACT else p.team_id
	o.player_id = player_id
	o.type = type
	if o.is_loan() and int(terms.get("loan_weeks", 0)) <= 0:
		terms = terms.duplicate()
		terms["loan_weeks"] = weeks_to_season_end(cur_week)
	o.set_terms(terms)
	if type == TransferOffer.FREE or type == TransferOffer.PRE_CONTRACT:
		o.fee = 0
	o.unread = from_id != user_club
	o.add_round(from_id, abs_week())
	offers.append(o)
	if type == TransferOffer.FREE or type == TransferOffer.PRE_CONTRACT:
		o.status = TransferOffer.ACCEPTED                 # no club to agree with: the player decides
	elif o.to_club == user_club:
		o.status = TransferOffer.PENDING
		note("NOTE_OFFER_RECEIVED", [o.player_id, o.from_club], o.id)
	elif from_id == user_club and replies_next_week:
		_await_reply(o)
	else:
		_seller_responds(o)
	_bound_offers()
	return {"error": "", "offer": o}


func _seller_responds(o: TransferOffer) -> void:
	var a := seller_answer(o)
	o.status = a["status"]
	o.reason = str(a.get("reason", ""))
	if a.has("release_clause"):
		o.via_release_clause = true
	if o.status == TransferOffer.COUNTERED:
		o.set_terms(a["terms"])
		o.add_round(o.to_club, abs_week())
	o.expires_week = abs_week() + OFFER_TTL_WEEKS + 1
	o.unread = o.from_club == user_club
	if o.status == TransferOffer.ACCEPTED and o.is_loan():
		_finalize(o)
	elif o.status == TransferOffer.ACCEPTED and o.from_club != user_club:
		propose_contract(o.id, default_contract(db.get_player(o.player_id), o.from_club))


## The offering club changes its terms (after a counter-offer or a refusal for a low offer, while rounds remain).
func revise_offer(offer_id: int, terms: Dictionary) -> String:
	var o := get_offer(offer_id)
	if o == null or not (o.status in [TransferOffer.COUNTERED, TransferOffer.PENDING]):
		return "this offer cannot be changed"
	if o.to_club == user_club and o.from_club != user_club:
		return "this offer cannot be changed"
	o.set_terms(terms)
	o.add_round(o.from_club, abs_week())
	if o.from_club == user_club and replies_next_week:
		_await_reply(o)
	else:
		_seller_responds(o)
	return ""


## The user's offer waits for the club's answer until the next week (see `replies_next_week`).
func _await_reply(o: TransferOffer) -> void:
	o.status = TransferOffer.PENDING
	o.reason = ""
	o.unread = false
	o.expires_week = abs_week() + OFFER_TTL_WEEKS + 1


## Offers of the user that waited a week get their answer now.
func _answer_waiting_offers() -> void:
	for o: TransferOffer in offers.duplicate():
		if o.status != TransferOffer.PENDING or o.from_club != user_club or o.to_club == user_club or o.to_club == "":
			continue
		if o.rounds.is_empty() or int(o.rounds[-1]["week"]) >= abs_week():
			continue
		_seller_responds(o)
		note("NOTE_REPLY_RECEIVED", [o.player_id, o.to_club], o.id)


## The offering club accepts the owner's counter-offer.
func accept_counter(offer_id: int) -> String:
	var o := get_offer(offer_id)
	if o == null or o.status != TransferOffer.COUNTERED:
		return "there is no counter-offer to accept"
	o.status = TransferOffer.ACCEPTED
	o.add_round(o.from_club, abs_week())
	if o.is_loan():
		return _finalize(o)
	return ""


func withdraw(offer_id: int) -> String:
	var o := get_offer(offer_id)
	if o == null or not o.is_open():
		return "this offer is no longer open"
	o.status = TransferOffer.WITHDRAWN
	return ""


## The user answers an offer for one of their players. action: "accept", "reject" or "counter" (with `terms`).
func answer_incoming(offer_id: int, action: String, terms: Dictionary = {}) -> String:
	var o := get_offer(offer_id)
	if o == null or o.to_club != user_club or o.status != TransferOffer.PENDING:
		return "this offer is no longer open"
	o.unread = false
	match action:
		"reject":
			o.status = TransferOffer.REJECTED
			o.reason = "OFFER_REASON_USER_REJECTED"
			o.add_round(o.to_club, abs_week())
			return ""
		"accept":
			o.status = TransferOffer.ACCEPTED
			o.add_round(o.to_club, abs_week())
			if is_external(o.from_club):
				return _sell_abroad(o)
			if o.is_loan():
				return _finalize(o)
			return propose_contract(o.id, default_contract(db.get_player(o.player_id), o.from_club))
		"counter":
			if o.counters() >= MAX_NEGOTIATION_ROUNDS:
				return "negotiation broke down"
			var mine := o.terms()
			o.set_terms(terms)
			o.add_round(o.to_club, abs_week())
			if is_external(o.from_club):
				_external_responds(o, mine)
			else:
				_buyer_responds(o, mine)
			return ""
	return "unknown answer '%s'" % action


## Highest fee an AI club pays for a player: 125 % of his value, within its transfer budget.
func buyer_max_fee(buyer_id: String, p: PlayerData) -> int:
	var budget := (ledgers[buyer_id] as FinanceLedger).transfer_budget if ledgers.has(buyer_id) else 0
	return mini(budget, int(market_value(p) * 1.25))


## An AI club answers the user's counter to its offer: accept if within its limit, else meet halfway, else walk away.
func _buyer_responds(o: TransferOffer, previous: Dictionary) -> void:
	var p: PlayerData = db.get_player(o.player_id)
	var ok := true
	if o.is_loan():
		ok = o.loan_fee <= maxi(int(previous["loan_fee"]), expected_loan_fee(p, o.loan_weeks)) + market_value(p) / 20 \
				and o.option_fee <= maxi(int(previous["option_fee"]), int(market_value(p) * 1.1))
	else:
		ok = o.fee <= buyer_max_fee(o.from_club, p)
	if ok:
		o.status = TransferOffer.ACCEPTED
		o.add_round(o.from_club, abs_week())
		if o.is_loan():
			_finalize(o)
		else:
			propose_contract(o.id, default_contract(p, o.from_club))
		return
	var by_buyer := 0
	for r in o.rounds:
		if str(r["by"]) == o.from_club:
			by_buyer += 1
	if by_buyer > MAX_NEGOTIATION_ROUNDS or o.is_loan():
		o.status = TransferOffer.WITHDRAWN
		o.reason = "OFFER_REASON_BUYER_WALKED_AWAY"
		note("NOTE_OFFER_WITHDRAWN", [o.player_id, o.from_club], o.id)
		return
	var t := o.terms()
	t["fee"] = mini(buyer_max_fee(o.from_club, p), Valuation.round_value((int(previous["fee"]) + o.fee) / 2.0))
	if int(t["fee"]) <= int(previous["fee"]):
		o.status = TransferOffer.WITHDRAWN
		o.reason = "OFFER_REASON_BUYER_WALKED_AWAY"
		note("NOTE_OFFER_WITHDRAWN", [o.player_id, o.from_club], o.id)
		return
	o.set_terms(t)
	o.add_round(o.from_club, abs_week())
	o.status = TransferOffer.PENDING
	o.unread = true
	o.expires_week = abs_week() + OFFER_TTL_WEEKS


## Personal terms for an agreed (or free) deal. The player answers; when he accepts the deal is carried out now, or when
## the next window opens (free agents and pre-contracts at once). Returns "" or an error; the answer is in the offer
## (`reason`, and `contract` once agreed). At most MAX_CONTRACT_ROUNDS proposals.
func propose_contract(offer_id: int, c: ContractOffer) -> String:
	var o := get_offer(offer_id)
	if o == null or o.status != TransferOffer.ACCEPTED or o.is_loan():
		return "there is no agreed deal for this player"
	if not o.contract.is_empty():
		return "the player has already agreed"
	var p: PlayerData = db.get_player(o.player_id)
	if o.contract_rounds >= MAX_CONTRACT_ROUNDS:
		o.status = TransferOffer.REJECTED
		o.reason = "CONTRACT_REASON_BROKE_DOWN"
		return "the player broke off the talks"
	o.contract_rounds += 1
	var a := player_answer(p, o.from_club, c)
	if a["status"] != TransferOffer.ACCEPTED:
		o.reason = str(a["reason"])
		if a["status"] == TransferOffer.REJECTED and o.reason != "CONTRACT_REASON_WAGE":
			o.status = TransferOffer.REJECTED
			if o.to_club == user_club:
				note("NOTE_PLAYER_REFUSED", [o.player_id, o.from_club], o.id)
		elif o.contract_rounds >= MAX_CONTRACT_ROUNDS and o.from_club != user_club:
			o.status = TransferOffer.REJECTED
		elif o.from_club != user_club:
			return propose_contract(offer_id, a["demand"])     # an AI club meets the player's demand
		return "player wants %d per week" % (a["demand"] as ContractOffer).salary
	o.contract = c.to_dict()
	o.reason = ""
	return _finalize(o)


## Carries out an agreed deal now, or defers it to the next window. Returns "" or an error (the offer then fails).
func _finalize(o: TransferOffer, squads: Dictionary = {}) -> String:
	var immediate := o.type in [TransferOffer.FREE] or window_open(cur_week) or o.via_release_clause
	if o.type == TransferOffer.PRE_CONTRACT:
		o.status = TransferOffer.DEFERRED                 # carried out when the player's contract ends (cur_season end)
		_notify_deal(o, "NOTE_PRE_CONTRACT_AGREED")
		return ""
	if not immediate:
		o.status = TransferOffer.DEFERRED
		_notify_deal(o, "NOTE_DEAL_DEFERRED")
		return ""
	return execute_offer(o, squads)


func _notify_deal(o: TransferOffer, key: String) -> void:
	if o.from_club == user_club or o.to_club == user_club:
		note(key, [o.player_id, o.to_club if o.from_club == user_club else o.from_club], o.id)


## Carries out an agreed offer (transfer or loan) through the same rules as every other deal.
## C7: set by the career; true for a club banned from registering new players (financial sustainability rule).
var ban_check: Callable = Callable()
## C8: price multiplier a buyer gets in negotiations (the manager's negotiation skill); 1.0 when unset.
var buyer_price_factor: Callable = Callable()


func execute_offer(o: TransferOffer, squads: Dictionary = {}) -> String:
	if ban_check.is_valid() and not o.is_loan() and bool(ban_check.call(o.from_club)):
		return _fail(o, "club is banned from registering new players")
	var p: PlayerData = db.get_player(o.player_id)
	if p == null:
		return _fail(o, "unknown player '%s'" % o.player_id)
	var err := ""
	if o.is_loan():
		if p.team_id != o.to_club:
			return _fail(o, "player is no longer at the club")
		err = loan(o.from_club, o.player_id, o.loan_weeks, o.loan_fee, cur_week, squads, o.terms().merged({"type": o.type, "offer_id": o.id}))
	else:
		if o.type != TransferOffer.FREE and o.type != TransferOffer.PRE_CONTRACT and p.team_id != o.to_club:
			return _fail(o, "player is no longer at the club")
		var c := ContractOffer.from_dict(o.contract)
		var deal := {"installments": o.installments, "sell_on_percent": o.sell_on_percent, "signing_bonus": c.signing_bonus,
				"release_clause": c.release_clause, "squad_role": c.squad_role, "offer_id": o.id}
		err = _transfer(o.from_club, o.player_id, o.fee, c.salary, c.years, cur_week, squads, false, deal)
	if err != "":
		return _fail(o, err)
	o.status = TransferOffer.COMPLETED
	_notify_deal(o, "NOTE_DEAL_COMPLETED")
	# every other open offer for this player is over
	for other: TransferOffer in offers:
		if other != o and other.player_id == o.player_id and other.is_open():
			other.status = TransferOffer.EXPIRED
	return ""


func _fail(o: TransferOffer, err: String) -> String:
	o.status = TransferOffer.REJECTED
	o.reason = "OFFER_REASON_FAILED"
	_notify_deal(o, "NOTE_DEAL_FAILED")
	return err


# --- loans with terms ----------------------------------------------------------------------------------------------

func _loan_entry(from_id: String, to_id: String, weeks: int, fee: int, terms: Dictionary, player_id := "") -> Dictionary:
	var row: Dictionary = world_stats.get(player_id, {})
	return {"from": from_id, "to": to_id, "type": str(terms.get("type", TransferOffer.LOAN)), "weeks": weeks,
			"start": abs_week(), "fee": fee, "wage_split": clampi(int(terms.get("wage_split_percent", 100)), 0, 100),
			"option_fee": int(terms.get("option_fee", 0)), "obligation_apps": int(terms.get("obligation_apps", 0)),
			"recall_after": int(terms.get("recall_after_weeks", 0)), "min_play": int(terms.get("min_play_percent", 0)),
			"offer_id": int(terms.get("offer_id", 0)), "apps": 0, "goals": 0, "rating_sum": 0.0, "last_apps": int(row.get("apps", 0)),
			"last_goals": int(row.get("goals", 0)), "last_rating": float(row.get("rating_sum", 0.0)), "decision": false, "complained": false,
			"no_play_vs_parent": int(terms.get("no_play_vs_parent", 0)), "compensated": false}


## Weekly wages a club pays: its squad (a borrowed player only for the borrower's share) plus the lender's share of the
## wages of players it has loaned out. Over all clubs the total equals the sum of all wages.
func wage_bill(team_id: String) -> int:
	return squad_wage_bill(team_id) + lender_wage_share(team_id)


func squad_wage_bill(team_id: String) -> int:
	var sum := weekly_wages(team_id)
	for pid in loans:
		var l: Dictionary = loans[pid]
		if str(l["to"]) == team_id and int(l["wage_split"]) < 100:
			var p: PlayerData = db.players.get(pid)
			if p != null and p.team_id == team_id:
				sum -= p.salary - p.salary * int(l["wage_split"]) / 100
	return sum


func lender_wage_share(team_id: String) -> int:
	var sum := 0
	for pid in loans:
		var l: Dictionary = loans[pid]
		if str(l["from"]) == team_id and int(l["wage_split"]) < 100:
			var p: PlayerData = db.players.get(pid)
			if p != null and p.team_id == str(l["to"]):
				sum += p.salary - p.salary * int(l["wage_split"]) / 100
	return sum


## The borrower buys the player at the agreed option price (the user after the loan; the AI decides at the end).
func exercise_option(player_id: String, p_week: int, squads: Dictionary = {}, forced := false) -> String:
	var p: PlayerData = db.get_player(player_id)
	var l: Dictionary = loans.get(player_id, {})
	if p == null or l.is_empty() or p.loan_parent == "":
		return "player is not on loan"
	if str(l["type"]) == TransferOffer.LOAN:
		return "this loan has no purchase option"
	var buyer := str(l["to"])
	var seller := str(l["from"])
	var fee := int(l["option_fee"])
	var ledger: FinanceLedger = ledgers.get(buyer)
	if ledger == null:
		return "buyer has no finances"
	if not forced and fee > 0 and (fee > ledger.transfer_budget or not ledger.can_afford(-fee, "transfer_in")):
		return "transfer budget too small (%d available, %d needed)" % [ledger.transfer_budget, fee]
	# the player goes back first, then moves for good: the normal transfer keeps every record right
	var keep_split := int(l["wage_split"])
	loans.erase(player_id)
	var owner: TeamData = db.get_team(seller)
	var borrower: TeamData = db.get_team(buyer)
	if owner == null or borrower == null:
		return "club does not exist"
	borrower.squad_ids.remove_at(borrower.squad_ids.find(player_id))
	owner.squad_ids.append(player_id)
	p.team_id = seller
	p.loan_parent = ""
	p.loan_weeks_left = 0
	if forced and fee > 0:
		# an obligation is binding: paid even when the budget is short (an unavoidable installment)
		ledger.record("installment", -fee, "Obligation to buy %s" % p.display_name, p_week, "FIN_OBLIGATION", [p.display_name])
		ledger.transfer_budget = maxi(0, ledger.transfer_budget - fee)
		if ledgers.has(seller):
			(ledgers[seller] as FinanceLedger).record("installment", fee, "Obligation to buy %s" % p.display_name, p_week, "FIN_OBLIGATION", [p.display_name])
		fee = 0
	var err := _transfer(buyer, player_id, fee, maxi(p.salary, minimum_wage(p)), clampi(maxi(p.contract_years, 2), 1, MAX_CONTRACT_YEARS),
			p_week, squads, false, {"force_squad": true})
	if err != "":
		# undo: the player stays on loan where he was
		owner.squad_ids.remove_at(owner.squad_ids.find(player_id))
		borrower.squad_ids.append(player_id)
		p.team_id = buyer
		p.loan_parent = seller
		l["wage_split"] = keep_split
		loans[player_id] = l
		return err
	note("NOTE_OPTION_EXERCISED" if not forced else "NOTE_OBLIGATION_TRIGGERED", [player_id, buyer], int(l.get("offer_id", 0)))
	return ""


## The lender calls the player back early (allowed after the agreed weeks, or when the playing-time promise is broken).
func recall(player_id: String, p_week: int, squads: Dictionary = {}) -> String:
	var l: Dictionary = loans.get(player_id, {})
	if l.is_empty():
		return "player is not on loan"
	if not can_recall(player_id):
		return "the loan cannot be ended yet"
	note("NOTE_LOAN_RECALLED", [player_id, str(l["to"])], int(l.get("offer_id", 0)))
	return return_from_loan(player_id, p_week, squads)


## Compensation for a broken playing-time promise: half the loan fee, at least four weeks of the wage.
func compensation_for(player_id: String) -> int:
	var l: Dictionary = loans.get(player_id, {})
	var p: PlayerData = db.get_player(player_id)
	if l.is_empty() or p == null:
		return 0
	return maxi(int(l["fee"]) / 2, p.salary * 4)


## The lender claims the compensation once the promise was broken (once per loan). Returns "" or an error.
func claim_compensation(player_id: String) -> String:
	var l: Dictionary = loans.get(player_id, {})
	if l.is_empty() or not bool(l.get("complained", false)):
		return "the playing-time promise was kept"
	if bool(l.get("compensated", false)):
		return "compensation was already paid"
	var amount := compensation_for(player_id)
	var payer: FinanceLedger = ledgers.get(str(l["to"]))
	var payee: FinanceLedger = ledgers.get(str(l["from"]))
	if payer == null or payee == null:
		return "club has no finances"
	var p: PlayerData = db.get_player(player_id)
	var err := payer.record("loan_in", -amount, "Compensation for %s" % p.display_name, cur_week, "FIN_LOAN_COMPENSATION", [p.display_name])
	if err != "":
		return err
	payee.record("loan_out", amount, "Compensation for %s" % p.display_name, cur_week, "FIN_LOAN_COMPENSATION", [p.display_name])
	l["compensated"] = true
	if str(l["from"]) == user_club or str(l["to"]) == user_club:
		note("NOTE_LOAN_COMPENSATION", [player_id, amount], int(l.get("offer_id", 0)))
	return ""


## Players at `team_id` who may not play against `opponent_id`: loaned from it with the clause.
func blocked_against(team_id: String, opponent_id: String) -> Array:
	var out: Array = []
	for pid in loans:
		var l: Dictionary = loans[pid]
		if str(l["to"]) == team_id and str(l["from"]) == opponent_id and int(l.get("no_play_vs_parent", 0)) == 1:
			out.append(pid)
	out.sort()
	return out


func can_recall(player_id: String) -> bool:
	var l: Dictionary = loans.get(player_id, {})
	if l.is_empty():
		return false
	if bool(l.get("complained", false)):
		return true
	return int(l["recall_after"]) > 0 and abs_week() - int(l["start"]) >= int(l["recall_after"])


func _ai_takes_option(p: PlayerData, l: Dictionary) -> bool:
	var ledger: FinanceLedger = ledgers.get(str(l["to"]))
	if ledger == null or int(l["option_fee"]) > ledger.transfer_budget:
		return false
	var apps := int(l["apps"])
	return apps >= 8 and int(l["option_fee"]) <= int(market_value(p) * 1.1)


## Weekly loan bookkeeping: statistics from the cur_season table, playing-time promises and obligations to buy.
func update_loans(career: CareerState, squads: Dictionary = {}) -> void:
	var ids := loans.keys()
	ids.sort()
	for pid in ids:
		if not loans.has(pid):
			continue
		var l: Dictionary = loans[pid]
		var p: PlayerData = db.get_player(pid)
		if p == null or p.loan_parent == "":
			loans.erase(pid)
			continue
		var row: Dictionary = (career.world_stats if career != null else world_stats).get(pid, {})
		var apps := int(row.get("apps", 0))
		var goals := int(row.get("goals", 0))
		var rating := float(row.get("rating_sum", 0.0))
		if int(l["last_apps"]) >= 0:
			if apps >= int(l["last_apps"]):
				l["apps"] = int(l["apps"]) + apps - int(l["last_apps"])
				l["goals"] = int(l["goals"]) + maxi(0, goals - int(l["last_goals"]))
				l["rating_sum"] = float(l["rating_sum"]) + maxf(0.0, rating - float(l["last_rating"]))
			else:                                                   # a new cur_season started: the table was reset
				l["apps"] = int(l["apps"]) + apps
				l["goals"] = int(l["goals"]) + goals
				l["rating_sum"] = float(l["rating_sum"]) + rating
		l["last_apps"] = apps
		l["last_goals"] = goals
		l["last_rating"] = rating
		var elapsed := abs_week() - int(l["start"])
		if int(l["min_play"]) > 0 and elapsed >= 8 and not bool(l["complained"]) \
				and int(l["apps"]) * 100 < (int(l["min_play"]) - 15) * elapsed:
			l["complained"] = true
			if str(l["from"]) == user_club or str(l["to"]) == user_club:
				note("NOTE_LOAN_PLAYING_TIME", [pid, str(l["to"])], int(l.get("offer_id", 0)))
			if str(l["from"]) != user_club:
				# an AI lender takes a young player back (his development comes first), else it claims compensation;
				# a borrower that cannot pay loses the player
				if p.age <= 21 or claim_compensation(pid) != "":
					return_from_loan(pid, cur_week, squads)
					continue
		if str(l["type"]) == TransferOffer.LOAN_WITH_OBLIGATION and int(l["obligation_apps"]) > 0 and int(l["apps"]) >= int(l["obligation_apps"]):
			exercise_option(pid, cur_week, squads, true)


## Due installments are paid (binding: they may overdraw the club, like wages).
func pay_installments(p_week: int) -> void:
	var keep: Array = []
	for i in installments:
		if int(i["due"]) > abs_week():
			keep.append(i)
			continue
		var amount := int(i["amount"])
		var pl: PlayerData = db.get_player(str(i["player_id"]))
		var label := pl.display_name if pl != null else str(i["player_id"])
		if ledgers.has(str(i["payer"])):
			(ledgers[str(i["payer"])] as FinanceLedger).record("installment", -amount, "Installment for %s" % label, p_week, "FIN_INSTALLMENT", [label])
		if ledgers.has(str(i["payee"])):
			(ledgers[str(i["payee"])] as FinanceLedger).record("installment", amount, "Installment for %s" % label, p_week, "FIN_INSTALLMENT", [label])
			_reinvest(str(i["payee"]), amount)
	installments = keep


## Part of the money received for a sale goes back into the club's transfer budget.
func _reinvest(team_id: String, received: int) -> void:
	if received > 0 and ledgers.has(team_id):
		(ledgers[team_id] as FinanceLedger).transfer_budget += int(received * SALE_BUDGET_SHARE)


func _schedule_installments(payer: String, payee: String, remaining: int, count: int, player_id: String, offer_id: int) -> void:
	if count <= 0 or remaining <= 0:
		return
	var each := remaining / count
	for k in count:
		var amount := each if k < count - 1 else remaining - each * (count - 1)
		installments.append({"id": next_installment_id, "payer": payer, "payee": payee, "amount": amount,
				"due": abs_week() + INSTALLMENT_GAP_WEEKS * (k + 1), "player_id": player_id, "offer_id": offer_id})
		next_installment_id += 1
	if ledgers.has(payer):
		(ledgers[payer] as FinanceLedger).transfer_budget -= remaining    # committed money is no longer free to spend


## Installments a club still has to pay (its future commitments) and the ones it will still receive.
func commitments(team_id: String) -> Dictionary:
	var pay := 0
	var receive := 0
	for i in installments:
		if str(i["payer"]) == team_id:
			pay += int(i["amount"])
		if str(i["payee"]) == team_id:
			receive += int(i["amount"])
	var obligations := 0
	for pid in loans:
		if str(loans[pid]["to"]) == team_id and str(loans[pid]["type"]) == TransferOffer.LOAN_WITH_OBLIGATION:
			obligations += int(loans[pid]["option_fee"])
	return {"pay": pay, "receive": receive, "obligations": obligations}


func _pay_sell_on(seller_id: String, p: PlayerData, fee: int, p_week: int) -> void:
	var clause: Dictionary = sell_on.get(p.id, {})
	sell_on.erase(p.id)
	if clause.is_empty() or fee <= 0 or str(clause["club"]) == seller_id or not ledgers.has(str(clause["club"])):
		return
	var share := fee * int(clause["percent"]) / 100
	if share <= 0:
		return
	(ledgers[seller_id] as FinanceLedger).record("sell_on", -share, "Sell-on share for %s" % p.display_name, p_week, "FIN_SELL_ON", [p.display_name])
	(ledgers[str(clause["club"])] as FinanceLedger).record("sell_on", share, "Sell-on share for %s" % p.display_name, p_week, "FIN_SELL_ON", [p.display_name])


func _after_move(p: PlayerData, to_id: String) -> void:
	listings.erase(p.id)
	release_clauses.erase(p.id)
	squad_roles.erase(p.id)
	arrivals[p.id] = abs_week()


# --- renewals with personal terms ----------------------------------------------------------------------------------

## Renewal negotiated with the player (see `player_answer`). {error, status, reason, demand}.
func negotiate_renewal(team_id: String, player_id: String, c: ContractOffer, p_week: int) -> Dictionary:
	var p: PlayerData = db.get_player(player_id)
	if p == null or p.team_id != team_id or p.loan_parent != "":
		return {"error": "player '%s' is not under contract with '%s'" % [player_id, team_id]}
	var a := player_answer(p, team_id, c, true)
	if a["status"] != TransferOffer.ACCEPTED:
		return {"error": "", "status": a["status"], "reason": a["reason"], "demand": a["demand"]}
	if c.signing_bonus > 0 and not (ledgers[team_id] as FinanceLedger).can_afford(-c.signing_bonus, "signing_bonus"):
		return {"error": "insufficient funds"}
	var err := renew_contract(team_id, player_id, c.salary, c.years, p_week)
	if err != "":
		return {"error": err}
	if c.signing_bonus > 0:
		(ledgers[team_id] as FinanceLedger).record("signing_bonus", -c.signing_bonus, "Signing bonus for %s" % p.display_name, p_week, "FIN_SIGNING_BONUS", [p.display_name])
	set_release_clause(player_id, c.release_clause)
	squad_roles[player_id] = c.squad_role
	return {"error": "", "status": TransferOffer.ACCEPTED, "reason": "", "demand": c}


# --- the weekly clock ---------------------------------------------------------------------------------------------

## Once a cur_week (after wages and loans): installments, loan bookkeeping, deferred deals when a window opens, expired offers
## and the new market values.
func process_week(career: CareerState, squads: Dictionary = {}) -> void:
	pay_installments(cur_week)
	update_loans(career, squads)
	_answer_waiting_offers()
	if window_open(cur_week):
		for o: TransferOffer in offers.duplicate():
			if o.status == TransferOffer.DEFERRED and o.type != TransferOffer.PRE_CONTRACT:
				execute_offer(o, squads)
	for o: TransferOffer in offers:
		if o.status in [TransferOffer.PENDING, TransferOffer.COUNTERED] and o.expires_week < abs_week():
			o.status = TransferOffer.EXPIRED
		elif o.status == TransferOffer.ACCEPTED and o.contract.is_empty() and o.expires_week + 1 < abs_week():
			o.status = TransferOffer.EXPIRED
	if bool(window_info(cur_week)["deadline"]) and user_club != "":
		note("NOTE_DEADLINE_DAY", [])
	elif cur_week > 1 and window_open(cur_week) and not window_open(cur_week - 1):
		note("NOTE_WINDOW_OPEN", [])
	refresh_values(career)


## Pre-contracts are carried out at the end of the cur_season, before contracts run out.
func season_end_moves(squads: Dictionary = {}) -> void:
	for o: TransferOffer in offers.duplicate():
		if o.status != TransferOffer.DEFERRED or o.type != TransferOffer.PRE_CONTRACT:
			continue
		var p: PlayerData = db.get_player(o.player_id)
		if p == null or p.team_id != o.to_club or p.loan_parent != "":
			_fail(o, "player is no longer available")
			continue
		var c := ContractOffer.from_dict(o.contract)
		var err := _transfer(o.from_club, o.player_id, 0, c.salary, c.years, cur_week, squads, false,
				{"signing_bonus": c.signing_bonus, "release_clause": c.release_clause, "squad_role": c.squad_role, "free": true})
		if err != "":
			_fail(o, err)
		else:
			p.contract_years = c.years + 1                 # the season-end contract count-down follows: c.years remain
			o.status = TransferOffer.COMPLETED
			_notify_deal(o, "NOTE_DEAL_COMPLETED")


## Drops records about players that no longer exist and closed offers beyond the kept history.
func prune(p_db: Node) -> void:
	for d in [listings, release_clauses, squad_roles, arrivals, sell_on, value_history, abroad]:
		for pid in (d as Dictionary).keys():
			if not p_db.players.has(pid):
				(d as Dictionary).erase(pid)
	if externals.size() > EXTERNAL_KEEP:
		var used := {}
		for o: TransferOffer in offers:
			used[o.from_club] = true
		for h in history:
			used[str(h["to"])] = true
		for k in (externals.keys() as Array).slice(0, externals.size() - EXTERNAL_KEEP):
			if not used.has(k):
				externals.erase(k)
	shortlist = shortlist.filter(func(pid: Variant) -> bool: return p_db.players.has(pid))
	offers = offers.filter(func(o: TransferOffer) -> bool: return o.is_open() or p_db.players.has(o.player_id))
	for k in loan_seasons.keys():
		if int(loan_seasons[k]) < cur_season - 1:
			loan_seasons.erase(k)
	_bound_offers()


func _bound_offers() -> void:
	var closed := 0
	for o: TransferOffer in offers:
		if not o.is_open():
			closed += 1
	var i := 0
	while closed > CLOSED_OFFERS_KEEP and i < offers.size():
		if not (offers[i] as TransferOffer).is_open():
			offers.remove_at(i)
			closed -= 1
		else:
			i += 1


## A message for the user (news feed and the red dot of the market). Player and club ids are named when shown.
func note(key: String, args: Array, offer_id: int = 0) -> void:
	notifications.append({"season": cur_season, "week": cur_week, "key": key, "args": args.duplicate(), "offer_id": offer_id})
	while notifications.size() > NOTIFICATIONS_MAX:
		notifications.pop_front()


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
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var ka := _sort_key(a, sort)
		var kb := _sort_key(b, sort)
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


# --- save ---------------------------------------------------------------------------------------------------------

func _v2_dict() -> Dictionary:
	var o: Array = []
	for x: TransferOffer in offers:
		o.append(x.to_dict())
	return {"version": STATE_VERSION, "listings": listings.duplicate(true), "release_clauses": release_clauses.duplicate(),
			"squad_roles": squad_roles.duplicate(), "arrivals": arrivals.duplicate(), "offers": o, "next_offer_id": next_offer_id,
			"loans": loans.duplicate(true), "installments": installments.duplicate(true), "next_installment_id": next_installment_id,
			"sell_on": sell_on.duplicate(true), "shortlist": shortlist.duplicate(), "saved_searches": saved_searches.duplicate(true),
			"value_history": value_history.duplicate(true), "loan_seasons": loan_seasons.duplicate(),
			"notifications": notifications.duplicate(true), "externals": externals.duplicate(true), "abroad": abroad.duplicate(true),
			"next_external_id": next_external_id,
			"replies_next_week": replies_next_week}


## Loads the v2 block; a version-1 market (an older save) gets empty v2 state, and its running loans get terms
## (a plain loan, the borrower paying the whole wage: exactly how they worked before).
func _load_v2(d: Dictionary) -> void:
	listings = PlayerData._restore_ints((d.get("listings", {}) as Dictionary).duplicate(true))
	release_clauses = PlayerData._restore_ints((d.get("release_clauses", {}) as Dictionary).duplicate())
	squad_roles = (d.get("squad_roles", {}) as Dictionary).duplicate()
	arrivals = PlayerData._restore_ints((d.get("arrivals", {}) as Dictionary).duplicate())
	offers.clear()
	for x in d.get("offers", []):
		offers.append(TransferOffer.from_dict(x))
	next_offer_id = int(d.get("next_offer_id", offers.size() + 1))
	loans = {}
	for pid in (d.get("loans", {}) as Dictionary):
		var l: Dictionary = PlayerData._restore_ints((d["loans"][pid] as Dictionary).duplicate(true))
		for k in ["rating_sum", "last_rating"]:
			l[k] = float(l.get(k, 0.0))
		loans[pid] = l
	installments = PlayerData._restore_ints((d.get("installments", []) as Array).duplicate(true))
	next_installment_id = int(d.get("next_installment_id", installments.size() + 1))
	sell_on = PlayerData._restore_ints((d.get("sell_on", {}) as Dictionary).duplicate(true))
	shortlist = (d.get("shortlist", []) as Array).map(func(x: Variant) -> String: return str(x))
	saved_searches = PlayerData._restore_ints((d.get("saved_searches", []) as Array).duplicate(true))
	value_history = PlayerData._restore_ints((d.get("value_history", {}) as Dictionary).duplicate(true))
	loan_seasons = PlayerData._restore_ints((d.get("loan_seasons", {}) as Dictionary).duplicate())
	notifications = PlayerData._restore_ints((d.get("notifications", []) as Array).duplicate(true))
	replies_next_week = bool(d.get("replies_next_week", false))
	externals = (d.get("externals", {}) as Dictionary).duplicate(true)
	abroad = PlayerData._restore_ints((d.get("abroad", {}) as Dictionary).duplicate(true))
	next_external_id = int(d.get("next_external_id", externals.size() + 1))
	if db != null and int(d.get("version", 1)) < STATE_VERSION:
		_migrate_v1_loans()


func _migrate_v1_loans() -> void:
	var ids: Array = db.players.keys()
	ids.sort()
	for pid in ids:
		var p: PlayerData = db.players[pid]
		if p.loan_parent != "" and not loans.has(pid):
			var l := _loan_entry(p.loan_parent, p.team_id, p.loan_weeks_left, 0, {}, pid)
			l["start"] = abs_week()
			loans[pid] = l


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
	history.append({"id": next_history_id, "week": week, "kind": kind, "player_id": player_id,
			"from": from_id, "to": to_id, "fee": fee, "salary": salary, "years": years})
	next_history_id += 1
	while history.size() > HISTORY_MAX:
		history.pop_front()                    # the oldest deals leave the log; ids keep counting up


func to_dict() -> Dictionary:
	var d := _v2_dict()
	d["history"] = history.duplicate(true)
	d["next_id"] = next_history_id
	return d


func load_state(d: Dictionary) -> void:
	history = (d.get("history", []) as Array).duplicate(true)
	for h in history:
		for k in ["id", "week", "fee", "salary", "years"]:
			h[k] = int(h[k])
	next_history_id = int(d.get("next_id", history.size() + 1))
	_load_v2(d)
