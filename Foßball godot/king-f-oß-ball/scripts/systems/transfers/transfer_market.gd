class_name TransferMarket
extends RefCounted

## Transfers, loans and contracts (Phase T9). Every operation validates
## first and mutates afterwards. Ownership is single-valued: a player is in
## exactly one squad_ids list (the borrower's while on loan; `loan_parent`
## remembers the owner). Money moves only through `FinanceLedger`.

const MAX_SQUAD := 30
const MIN_SQUAD := 18          # a selling/loaning club must keep at least this many
const MAX_CONTRACT_YEARS := 5
const MIN_LOAN_WEEKS := 4
const MAX_LOAN_WEEKS := 52

var db: Node
var ledgers: Dictionary = {}       # team_id -> FinanceLedger
var history: Array = []            # {id, week, kind, player_id, from, to, fee, salary, years}
var next_history_id: int = 1


func _init(p_db: Node = null, p_ledgers: Dictionary = {}) -> void:
	db = p_db
	ledgers = p_ledgers


# --- pricing / search -------------------------------------------------------------------

## Price the owning club asks for a player (value, +10 % for young high-potential players).
func asking_price(p: PlayerData) -> int:
	var price := p.transfer_value
	if p.age <= 23 and p.potential - p.get_overall() >= 10:
		price = int(price * 1.1)
	return price


## Lowest weekly wage the player accepts: 90 % of the current wage (min 100).
func minimum_wage(p: PlayerData) -> int:
	return maxi(100, int(p.salary * 0.9))


func weekly_wages(team_id: String) -> int:
	var sum := 0
	for p in db.get_squad(team_id):
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
func buy(buyer_id: String, player_id: String, fee: int, salary: int, years: int, week: int,
		squads: Dictionary = {}) -> String:
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
	if seller != null:
		if fee < asking_price(p):
			return "offer rejected: seller asks %d" % asking_price(p)
		if seller.squad_ids.size() <= MIN_SQUAD:
			return "seller must keep at least %d players" % MIN_SQUAD
	elif fee != 0:
		return "free agents cost no transfer fee"
	# --- all checks passed: mutate ---
	var buyer_ledger: FinanceLedger = ledgers[buyer_id]
	if fee > 0:
		var spend_err := buyer_ledger.spend_transfer("transfer_in", fee, "Signed %s" % p.display_name, week)
		if spend_err != "":
			return spend_err
		if seller != null and ledgers.has(seller.id):
			(ledgers[seller.id] as FinanceLedger).record("transfer_out", fee, "Sold %s" % p.display_name, week)
	if seller != null:
		seller.squad_ids.remove_at(seller.squad_ids.find(player_id))
		_strip_from_squad(squads.get(seller.id), player_id)
	buyer.squad_ids.append(player_id)
	var from_id := p.team_id
	p.team_id = buyer_id
	p.status = PlayerData.Status.ACTIVE
	p.salary = salary
	p.contract_years = years
	p.shirt_number = _free_number(buyer_id, p)
	p.development_history.append({"event": "transferred", "week": week, "from": from_id, "to": buyer_id, "fee": fee})
	_log(week, "transfer", player_id, from_id, buyer_id, fee, salary, years)
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
		squads: Dictionary = {}) -> String:
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
	if weekly_wages(to_id) + p.salary > ledger.wage_budget:
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
func advance_loans(week: int, squads: Dictionary = {}) -> Array[String]:
	var returned: Array[String] = []
	for p: PlayerData in db.players.values().duplicate():
		if p.loan_parent != "":
			p.loan_weeks_left -= 1
			if p.loan_weeks_left <= 0 and return_from_loan(p.id, week, squads) == "":
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


func to_dict() -> Dictionary:
	return {"history": history.duplicate(true), "next_id": next_history_id}


func load_state(d: Dictionary) -> void:
	history = (d.get("history", []) as Array).duplicate(true)
	for h in history:
		for k in ["id", "week", "fee", "salary", "years"]:
			h[k] = int(h[k])
	next_history_id = int(d.get("next_id", history.size() + 1))
