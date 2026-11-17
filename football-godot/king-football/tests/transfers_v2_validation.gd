## Transfers v2 (phase 1: data and rules): market value, seller and player answers, offers and counter-offers,
## installments, sell-on shares, loans with wage split / option / obligation, windows, pre-contracts, save + migration.
##   godot --headless --path . res://tests/transfers_v2_validation.tscn
extends Node

const PACK := "real_2025"
const USER := "eng_leicester_city_fc"

var _passed := 0
var _failed := 0
var db: TeamDatabase


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Transfers v2 validation ===")
	db = get_node("/root/TeamDB")
	for t in [_test_valuation, _test_windows, _test_seller_answers, _test_player_answers, _test_permanent_flow,
			_test_installments_and_sell_on, _test_loan_wage_split, _test_loan_option, _test_loan_obligation, _test_loan_rules,
			_test_window_rule_for_user, _test_free_and_pre_contract, _test_incoming_offers, _test_renewal, _test_search,
			_test_save_load, _test_v1_migration, _test_replies_next_week, _test_compensation_for_user, _test_parent_clause]:
		db.load_world(PACK)
		t.call()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _career(week := 3) -> CareerState:
	var c := CareerState.start(db, USER)
	c.week = week
	c.market.sync_clock(c.season, week, USER)
	var l := c.ledger()
	l.opening_balance += 900_000_000 - l.balance        # keeps the audit (opening + entries == balance) intact
	l.balance = 900_000_000
	l.transfer_budget = 600_000_000
	l.wage_budget = 50_000_000
	return c


## A first-team player of an AI club that is not among his club's best three, at a club with spare players.
func _target(c: CareerState, min_ov := 60, max_age := 40) -> PlayerData:
	var ids: Array = db.players.keys()
	ids.sort()
	for id in ids:
		var p: PlayerData = db.players[id]
		if p.team_id == "" or p.team_id == USER or p.loan_parent != "" or p.status == PlayerData.Status.YOUTH:
			continue
		if p.get_overall() < min_ov or p.age > max_age or p.contract_years < 2:
			continue
		var t: TeamData = db.get_team(p.team_id)
		if t.squad_ids.size() < TransferMarket.MIN_SQUAD + 3:
			continue
		var r := c.market.squad_rank(p)
		if int(r["all"]) >= 3 and int(r["pos"]) >= 1:
			return p
	return null


func _star(c: CareerState, club: String) -> PlayerData:
	var best: PlayerData = null
	for p in db.get_squad(club):
		if best == null or p.get_overall() > best.get_overall():
			best = p
	return best


func _ledgers_ok(c: CareerState) -> bool:
	for id in c.ledgers:
		if not (c.ledgers[id] as FinanceLedger).is_consistent():
			return false
	return true


# --- 2.1 market value ------------------------------------------------------------------------------------------------

func _test_valuation() -> void:
	var p := PlayerData.new()
	p.id = "val_test"
	p.position = PlayerData.Position.CM
	for a in ["pace", "shooting", "passing", "dribbling", "defending", "physical"]:
		p.set(a, 75)
	p.age = 26
	p.potential = 76
	p.contract_years = 3
	p.team_id = USER
	var v26 := Valuation.value(p, db)
	p.age = 33
	var v33 := Valuation.value(p, db)
	p.age = 26
	p.contract_years = 1
	var v_last := Valuation.value(p, db)
	p.contract_years = 0
	var v_out := Valuation.value(p, db)
	p.contract_years = 3
	for a in ["pace", "shooting", "passing", "dribbling", "defending", "physical"]:
		p.set(a, 85)
	var v85 := Valuation.value(p, db)
	_check(v26 > 0 and v85 > v26 * 1.5, "value grows faster than linearly with the overall", "%d vs %d" % [v26, v85])
	_check(v33 < v26 * 0.6, "veterans are worth much less than players in their prime")
	_check(absf(float(v_last) / v26 - 0.7) < 0.02, "last contract year: -30 %", "%d / %d" % [v_last, v26])
	_check(v_out == 0, "an expired contract is worth no fee")
	p.age = 19
	p.potential = 90
	for a in ["pace", "shooting", "passing", "dribbling", "defending", "physical"]:
		p.set(a, 70)
	var young_hi := Valuation.value(p, db)
	p.potential = 70
	_check(young_hi > Valuation.value(p, db) * 1.2, "a young player's potential raises his value")
	var c := _career()
	var any := _target(c)
	_check(any != null and any.transfer_value == Valuation.value(any, db, c), "a career keeps every player's market value up to date")
	c.advance_week()
	var mine: PlayerData = db.get_squad(USER)[0]
	_check((c.market.value_history.get(mine.id, []) as Array).size() >= 1, "the values of the user's players are recorded weekly")


# --- 2.5 windows ------------------------------------------------------------------------------------------------------

func _test_windows() -> void:
	# Phase K2: the windows follow the dates — summer 1 Jul - 1 Sep (weeks 1-5), winter 1-31 Jan (weeks 22-26)
	_check(TransferMarket.window_open(1) and TransferMarket.window_open(5) and not TransferMarket.window_open(6) and TransferMarket.window_open(22) and not TransferMarket.window_open(27),
			"windows: weeks 1-5 and 22-26")
	var w3 := TransferMarket.window_info(3)
	_check(w3["open"] and int(w3["weeks_left"]) == 3 and not w3["deadline"], "window info: weeks left", str(w3))
	_check(TransferMarket.window_info(5)["deadline"], "the last week of a window is deadline day")
	var w10 := TransferMarket.window_info(10)
	_check(not w10["open"] and int(w10["next_open"]) == 22, "closed window: names the week it opens", str(w10))
	_check(int(TransferMarket.window_info(40)["next_open"]) == 1, "after the winter window the next one is next season's week 1")
	_check(TransferMarket.weeks_to_next_window(3) == 19 and TransferMarket.weeks_to_season_end(3) == 43, "half-season and season loan lengths")


# --- 2.2 the selling club ----------------------------------------------------------------------------------------------

func _test_seller_answers() -> void:
	var c := _career()
	var m := c.market
	var p := _target(c)
	var price := m.seller_price(p)
	var low := m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": int(price * 0.6)})
	_check(low["error"] == "" and (low["offer"] as TransferOffer).status == TransferOffer.REJECTED
			and (low["offer"] as TransferOffer).reason == "OFFER_REASON_TOO_LOW", "an offer below 70 % of the price is rejected")
	var mid: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": int(price * 0.9)})["offer"]
	_check(mid.status == TransferOffer.COUNTERED and mid.fee > int(price * 0.9) and mid.fee <= price,
			"an offer at 85-100 % gets a counter-offer between the offer and the price", "%d (price %d)" % [mid.fee, price])
	_check(mid.rounds.size() == 2 and str(mid.rounds[1]["by"]) == p.team_id, "the rounds of the negotiation are recorded")
	m.revise_offer(mid.id, {"fee": int(price * 0.9)})
	m.revise_offer(mid.id, {"fee": int(price * 0.9)})
	m.revise_offer(mid.id, {"fee": int(price * 0.9)})
	_check(mid.status == TransferOffer.REJECTED and mid.reason == "OFFER_REASON_BROKE_DOWN", "after three counter-offers the talks break down", mid.status)
	var full: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": price})["offer"]
	_check(full.status == TransferOffer.ACCEPTED, "an offer at the asking price is accepted")
	m.withdraw(full.id)
	var star := _star(c, p.team_id)
	_check(m.seller_price(star) > m.market_value(star), "a club asks more than the value for one of its best three players",
			"%d vs %d" % [m.seller_price(star), m.market_value(star)])
	_check(m.importance(star) > m.importance(p), "importance: a star matters more than a squad player")
	m.set_listing(star.team_id, star.id, TransferMarket.LISTING_UNTOUCHABLE)
	var un: TransferOffer = m.make_offer(USER, star.id, TransferOffer.PERMANENT, {"fee": m.market_value(star) * 3})["offer"]
	_check(un.status == TransferOffer.REJECTED and un.reason == "OFFER_REASON_UNTOUCHABLE", "an untouchable player is not for sale")
	m.set_release_clause(star.id, m.market_value(star) * 2)
	var cl: TransferOffer = m.make_offer(USER, star.id, TransferOffer.PERMANENT, {"fee": m.release_clause(star.id)})["offer"]
	_check(cl.status == TransferOffer.ACCEPTED and cl.via_release_clause, "paying the release clause cannot be refused")
	m.withdraw(cl.id)
	m.arrivals[p.id] = m.abs_week() - 5
	var fresh: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": price * 2})["offer"]
	_check(fresh.status == TransferOffer.REJECTED and fresh.reason == "OFFER_REASON_JUST_ARRIVED", "a player who joined less than 20 weeks ago is not sold")
	m.arrivals.erase(p.id)
	m.sync_clock(1, 5, USER)
	var deadline := m.seller_price(p)
	m.sync_clock(1, 3, USER)
	_check(deadline < m.seller_price(p), "on deadline day the clubs ask less")
	m.set_listing(p.team_id, p.id, TransferMarket.LISTING_TRANSFER, {"price": 1_234_000})
	_check(m.seller_price(p) == 1_234_000 and m.asking_price(p) == 1_234_000, "a listed player's price is the listing price")
	var chance := m.acceptance_chance(_offer_stub(p, 1_234_000))
	_check(chance == "high" and m.acceptance_chance(_offer_stub(p, 1_100_000)) == "medium" and m.acceptance_chance(_offer_stub(p, 100_000)) == "low",
			"the acceptance indicator follows the club's answer")
	_check(_ledgers_ok(c), "ledgers stay consistent")


func _offer_stub(p: PlayerData, fee: int) -> TransferOffer:
	var o := TransferOffer.new()
	o.from_club = USER
	o.to_club = p.team_id
	o.player_id = p.id
	o.fee = fee
	return o


# --- 2.3 the player ----------------------------------------------------------------------------------------------------

func _test_player_answers() -> void:
	var c := _career()
	var m := c.market
	var p := _target(c, 65)
	var fair := m.fair_wage(p)
	var cheap := m.player_answer(p, USER, ContractOffer.make(100, 3, "starter"))
	_check(cheap["status"] == TransferOffer.REJECTED and cheap["reason"] == "CONTRACT_REASON_WAGE", "a far too low wage is refused")
	var demand: ContractOffer = cheap["demand"]
	_check(demand.salary >= m.minimum_wage(p), "the refusal names the wage he wants", str(demand.salary))
	var ok := m.player_answer(p, USER, ContractOffer.make(demand.salary, 3, "starter"))
	_check(ok["status"] == TransferOffer.ACCEPTED, "his demand is accepted")
	var near := m.player_answer(p, USER, ContractOffer.make(int(demand.salary * 0.9), 3, "starter"))
	_check(near["status"] == TransferOffer.COUNTERED, "close to his demand: he counters")
	var bonus := m.player_answer(p, USER, ContractOffer.make(int(demand.salary * 0.9), 3, "starter", demand.salary * 20 * 3))
	_check(bonus["status"] == TransferOffer.ACCEPTED, "a signing bonus makes up for a lower wage")
	_check(m.player_answer(p, USER, ContractOffer.make(demand.salary, 9, "starter"))["status"] == TransferOffer.REJECTED, "1-5 year contracts only")
	var young: PlayerData = null
	for q: PlayerData in db.players.values():
		if q.team_id != "" and q.team_id != USER and q.age <= 21 and q.potential >= 80 and q.get_overall() >= 72:
			young = q
			break
	if young != null:
		var a := m.player_answer(young, USER, ContractOffer.make(young.salary * 3, 3, "backup"))
		_check(a["status"] == TransferOffer.REJECTED and a["reason"] == "CONTRACT_REASON_PLAYING_TIME" or m.deserved_role(young, USER) >= 2,
				"a young talent refuses a backup role", str(a))
	_check(fair > 0, "fair wage is positive")


# --- full permanent deal -------------------------------------------------------------------------------------------------

func _test_permanent_flow() -> void:
	var c := _career()
	var m := c.market
	var p := _target(c)
	var seller := p.team_id
	var price := m.seller_price(p)
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": int(price * 0.9)})["offer"]
	_check(m.accept_counter(o.id) == "" and o.status == TransferOffer.ACCEPTED and o.contract.is_empty(),
			"accepting the counter-offer: clubs agree, the contract is still open")
	_check(m.needs_user_action() >= 1, "an agreed deal waiting for personal terms needs the user")
	var bal := c.ledger().balance
	var seller_bal: int = (c.ledgers[seller] as FinanceLedger).balance
	var err := m.propose_contract(o.id, ContractOffer.make(100, 3, "rotation"))
	_check(err != "" and o.status == TransferOffer.ACCEPTED and p.team_id == seller, "a refused contract changes nothing", err)
	var d: ContractOffer = m.player_answer(p, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
	d.release_clause = price * 3
	err = m.propose_contract(o.id, d)
	_check(err == "" and o.status == TransferOffer.COMPLETED and p.team_id == USER, "personal terms agreed: the player joins", err)
	_check(c.ledger().balance == bal - o.fee and (c.ledgers[seller] as FinanceLedger).balance == seller_bal + o.fee,
			"the agreed fee moves between the clubs", "%d" % o.fee)
	_check(p.salary == d.salary and p.contract_years == 3 and m.release_clause(p.id) == price * 3 and m.squad_role(p.id) == "rotation",
			"contract, release clause and role are applied")
	_check(m.history[-1]["kind"] == "transfer" and int(m.history[-1]["fee"]) == o.fee, "the deal is in the transfer history")
	_check(int(m.arrivals.get(p.id, -1)) == m.abs_week(), "the arrival week is recorded")
	_check(_ledgers_ok(c), "ledgers consistent after the deal")


# --- installments and sell-on ---------------------------------------------------------------------------------------------

func _test_installments_and_sell_on() -> void:
	var c := _career()
	var m := c.market
	var p := _target(c)
	var seller := p.team_id
	var price := m.seller_price(p)
	var fee := int(price * 1.1)
	var budget_before := c.ledger().transfer_budget
	var bal_before := c.ledger().balance
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": fee, "installments": 3, "sell_on_percent": 20})["offer"]
	_check(o.status == TransferOffer.ACCEPTED, "an offer above the price with installments is accepted", o.status + " " + o.reason)
	var d: ContractOffer = m.player_answer(p, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
	_check(m.propose_contract(o.id, d) == "" and p.team_id == USER, "the deal with installments completes")
	var first := fee - (fee / 3) * 2
	_check(c.ledger().balance == bal_before - first, "only the first installment is paid now", "%d vs %d" % [bal_before - c.ledger().balance, first])
	_check(c.ledger().transfer_budget == budget_before - fee, "the transfer budget counts the whole fee (future commitments)")
	_check(m.installments.size() == 2 and int(m.commitments(USER)["pay"]) == fee - first, "two installments are scheduled")
	_check(int(m.installments[0]["due"]) == m.abs_week() + TransferMarket.INSTALLMENT_GAP_WEEKS, "the next one is due in half a season")
	_check(m.sell_on.has(p.id) and str(m.sell_on[p.id]["club"]) == seller and int(m.sell_on[p.id]["percent"]) == 20, "the sell-on share is recorded")
	var seller_bal: int = (c.ledgers[seller] as FinanceLedger).balance
	m.sync_clock(1, 3 + TransferMarket.INSTALLMENT_GAP_WEEKS - 1, USER)
	m.pay_installments(m.cur_week)
	_check(m.installments.size() == 2, "nothing is paid before the due week")
	m.sync_clock(1, 3 + TransferMarket.INSTALLMENT_GAP_WEEKS, USER)
	var bal2 := c.ledger().balance
	m.pay_installments(m.cur_week)
	_check(m.installments.size() == 1 and c.ledger().balance == bal2 - fee / 3 and (c.ledgers[seller] as FinanceLedger).balance == seller_bal + fee / 3,
			"the second installment is paid in its week, to the seller")
	_check(c.ledger().entries[-1]["category"] == "installment", "installments are their own ledger category")
	# sell the player on: the former club gets its share
	var buyer := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.id != seller and t.squad_ids.size() < TransferMarket.MAX_SQUAD - 1:
			buyer = t.id
			break
	(c.ledgers[buyer] as FinanceLedger).opening_balance += 900_000_000 - (c.ledgers[buyer] as FinanceLedger).balance
	(c.ledgers[buyer] as FinanceLedger).balance = 900_000_000
	(c.ledgers[buyer] as FinanceLedger).transfer_budget = 900_000_000
	(c.ledgers[buyer] as FinanceLedger).wage_budget = 90_000_000
	m.arrivals.erase(p.id)
	var sale := 10_000_000
	var seller_bal2: int = (c.ledgers[seller] as FinanceLedger).balance
	var user_bal: int = c.ledger().balance
	var err := m._transfer(buyer, p.id, sale, p.salary + 10, 3, m.cur_week, {}, false)
	_check(err == "" and (c.ledgers[seller] as FinanceLedger).balance == seller_bal2 + sale * 20 / 100
			and c.ledger().balance == user_bal + sale - sale * 20 / 100, "on the next sale 20 % goes to the former club", err)
	_check(not m.sell_on.has(p.id), "the sell-on share is paid once")
	_check(_ledgers_ok(c), "ledgers consistent with installments and sell-on")


# --- 2.4 loans ----------------------------------------------------------------------------------------------------------

func _loanable(c: CareerState) -> PlayerData:
	var ids: Array = db.players.keys()
	ids.sort()
	for id in ids:
		var p: PlayerData = db.players[id]
		if p.team_id == "" or p.team_id == USER or p.loan_parent != "" or p.status == PlayerData.Status.YOUTH or p.salary < 500:
			continue
		if db.get_team(p.team_id).squad_ids.size() < TransferMarket.MIN_SQUAD + 3:
			continue
		if int(c.market.squad_rank(p)["pos"]) >= 2:
			return p
	return null


func _test_loan_wage_split() -> void:
	var c := _career()
	var m := c.market
	var p := _loanable(c)
	var lender := p.team_id
	var user_bill := m.wage_bill(USER)
	var lender_bill := m.wage_bill(lender)
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.LOAN, {"loan_weeks": 26, "wage_split_percent": 60})["offer"]
	_check(o.status == TransferOffer.COMPLETED and p.team_id == USER and p.loan_parent == lender, "a 26-week loan at 60/40 is agreed and done",
			o.status + " " + o.reason)
	var borrower_part := p.salary * 60 / 100
	_check(m.wage_bill(USER) == user_bill + borrower_part, "the borrower pays 60 % of the wage", "%d vs %d" % [m.wage_bill(USER) - user_bill, borrower_part])
	_check(m.wage_bill(lender) == lender_bill - p.salary + (p.salary - borrower_part), "the lender keeps paying 40 %")
	_check(m.lender_wage_share(lender) + (m.squad_wage_bill(USER) - (user_bill)) == p.salary, "together they pay exactly the wage")
	var before_user := c.ledger().total("salary")
	var before_lender := (c.ledgers[lender] as FinanceLedger).total("salary")
	var squad_part := m.squad_wage_bill(USER)
	var share := m.lender_wage_share(lender)
	var lender_squad := m.squad_wage_bill(lender)
	c.advance_week()
	_check(c.ledger().total("salary") - before_user == -squad_part, "week: the borrower's ledger pays its share")
	_check((c.ledgers[lender] as FinanceLedger).total("salary") - before_lender == -(lender_squad + share), "week: the lender's ledger pays 40 %")
	_check(m.loans.has(p.id) and int(m.loans[p.id]["wage_split"]) == 60, "the loan terms are stored")
	_check(_ledgers_ok(c), "ledgers consistent with a split wage")


func _test_loan_option() -> void:
	var c := _career()
	var m := c.market
	var p := _loanable(c)
	var lender := p.team_id
	var option := m.seller_price(p)
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.LOAN_WITH_OPTION, {"loan_weeks": 4, "wage_split_percent": 100, "option_fee": option})["offer"]
	_check(o.status == TransferOffer.COMPLETED and p.loan_parent == lender, "a loan with a purchase option is agreed", o.status + " " + o.reason)
	for i in 4:
		m.advance_loans(m.cur_week)
	_check(p.team_id == USER and bool(m.loans[p.id]["decision"]), "at the end of the loan the user decides (the player waits)")
	_check(m.needs_user_action() >= 1, "the decision is shown as an action for the user")
	var bal := c.ledger().balance
	_check(m.exercise_option(p.id, m.cur_week) == "", "exercising the option")
	_check(p.team_id == USER and p.loan_parent == "" and not m.loans.has(p.id), "the player now belongs to the user")
	_check(c.ledger().balance == bal - option, "the option price is paid", "%d" % (bal - c.ledger().balance))
	_check(_ledgers_ok(c), "ledgers consistent after the option")
	# declined: the player goes back after the decision weeks
	var q := _loanable(c)
	var lender2 := q.team_id
	m.make_offer(USER, q.id, TransferOffer.LOAN_WITH_OPTION, {"loan_weeks": 4, "option_fee": m.seller_price(q)})
	for i in 4 + TransferMarket.LOAN_DECISION_WEEKS:
		m.advance_loans(m.cur_week)
	_check(q.team_id == lender2 and q.loan_parent == "", "without a decision the player returns to his club")


func _test_loan_obligation() -> void:
	var c := _career()
	var m := c.market
	var p := _loanable(c)
	var fee := int(m.seller_price(p) * 0.9)
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.LOAN_WITH_OBLIGATION, {"loan_weeks": 30, "option_fee": fee, "obligation_apps": 15})["offer"]
	_check(o.status == TransferOffer.COMPLETED, "a loan with an obligation to buy (15 appearances) is agreed", o.status + " " + o.reason)
	_check(int(m.commitments(USER)["obligations"]) == fee, "the obligation is shown as a future commitment")
	c.world_stats[p.id] = {"apps": 10, "goals": 1, "rating_sum": 68.0}
	m.update_loans(c)
	_check(p.loan_parent != "" and int(m.loans[p.id]["apps"]) == 10, "10 appearances: still on loan")
	var bal := c.ledger().balance
	c.world_stats[p.id] = {"apps": 15, "goals": 2, "rating_sum": 103.0}
	m.update_loans(c)
	_check(p.team_id == USER and p.loan_parent == "" and c.ledger().balance == bal - fee, "15 appearances: the player is bought automatically")
	_check(_ledgers_ok(c), "ledgers consistent after the obligation")


func _test_loan_rules() -> void:
	var c := _career()
	var m := c.market
	var p := _loanable(c)
	var low: TransferOffer = m.make_offer(USER, p.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 10})["offer"]
	_check(low.status == TransferOffer.COUNTERED and low.wage_split_percent >= m.min_wage_split(p), "a low wage share gets a counter-offer", low.status)
	m.withdraw(low.id)
	var star := _star(c, p.team_id)
	var key: TransferOffer = m.make_offer(USER, star.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100})["offer"]
	_check(key.status == TransferOffer.REJECTED and key.reason == "OFFER_REASON_KEY_PLAYER", "clubs do not loan out their key players")
	# loans in: at most 4
	var n := 0
	var ids: Array = db.players.keys()
	ids.sort()
	for id in ids:
		var q: PlayerData = db.players[id]
		if n >= TransferMarket.MAX_LOANS_IN or q.team_id == "" or q.team_id == USER or q.loan_parent != "" or q.status == PlayerData.Status.YOUTH:
			continue
		if db.get_team(q.team_id).squad_ids.size() < TransferMarket.MIN_SQUAD + 3 or int(m.squad_rank(q)["pos"]) < 2:
			continue
		var r: TransferOffer = m.make_offer(USER, q.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100})["offer"]
		if r.status == TransferOffer.COMPLETED:
			n += 1
	_check(m.loans_in(USER) == TransferMarket.MAX_LOANS_IN, "four loans in", str(m.loans_in(USER)))
	var fifth := _loanable(c)
	var r5: TransferOffer = m.make_offer(USER, fifth.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100})["offer"]
	_check(r5.status == TransferOffer.REJECTED and r5.reason == "OFFER_REASON_BORROWER_LIMIT", "a fifth loan in is refused")
	# recall
	var loaned: String = m.loans.keys()[0]
	_check(not m.can_recall(loaned) and m.recall(loaned, m.cur_week) != "", "no early recall without the clause")
	m.loans[loaned]["recall_after"] = 2
	m.sync_clock(1, m.cur_week + 2, USER)
	var owner := str(m.loans[loaned]["from"])
	_check(m.recall(loaned, m.cur_week) == "" and db.get_player(loaned).team_id == owner, "recall after the agreed weeks")
	var again: TransferOffer = m.make_offer(USER, loaned, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100})["offer"]
	_check(again.status == TransferOffer.REJECTED and again.reason == "OFFER_REASON_LOANED_THIS_SEASON", "no second loan of a player to the same club in a season")
	# playing-time promise broken: an AI lender takes the player back
	for pid in m.loans.keys():                     # make room: at most four loans in
		if str(m.loans[pid]["to"]) == USER:
			m.return_from_loan(pid, m.cur_week)
	var q2: PlayerData = null
	for q: PlayerData in db.players.values():
		if q.team_id != "" and q.team_id != USER and q.loan_parent == "" and q.status != PlayerData.Status.YOUTH and q.age > 21 \
				and int(m.squad_rank(q)["pos"]) >= 2 and m.refusal(q, USER, true) == "":
			q2 = q
			break
	var lender := q2.team_id
	var lo: TransferOffer = m.make_offer(USER, q2.id, TransferOffer.LOAN, {"loan_weeks": 30, "wage_split_percent": 100, "min_play_percent": 80})["offer"]
	_check(lo.status == TransferOffer.COMPLETED, "(setup) a loan with an 80 % playing-time promise", lo.status + " " + lo.reason)
	m.sync_clock(1, m.cur_week + 10, USER)
	c.world_stats[q2.id] = {"apps": 1, "goals": 0, "rating_sum": 6.0}
	var user_bal := c.ledger().balance
	var comp := m.compensation_for(q2.id)
	var young := q2.age <= 21
	m.update_loans(c)
	if young:
		_check(q2.team_id == lender and q2.loan_parent == "", "a broken promise: the AI lender takes a young player back")
	else:
		_check(q2.loan_parent == lender and bool(m.loans[q2.id]["compensated"]) and c.ledger().balance == user_bal - comp,
				"a broken promise: the AI lender claims compensation from the borrower", "%d" % (user_bal - c.ledger().balance))
	_check(_ledgers_ok(c), "ledgers consistent")


# --- the window applies to the user ---------------------------------------------------------------------------------------

func _test_window_rule_for_user() -> void:
	var c := _career(10)
	var m := c.market
	var p := _target(c)
	var seller := p.team_id
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": m.seller_price(p)})["offer"]
	var d: ContractOffer = m.player_answer(p, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
	_check(m.propose_contract(o.id, d) == "" and o.status == TransferOffer.DEFERRED and p.team_id == seller,
			"agreed outside the window: the deal waits", o.status)
	for w in range(11, 22):
		c.week = w
		m.sync_clock(1, w, USER)
		m.process_week(c)
	_check(p.team_id == seller and o.status == TransferOffer.DEFERRED, "nothing moves while the window is closed")
	c.week = 24
	m.sync_clock(1, 24, USER)
	m.process_week(c)
	_check(p.team_id == USER and o.status == TransferOffer.COMPLETED, "the deal is carried out when the window opens")
	var notes: Array = m.notifications.map(func(n: Dictionary) -> String: return str(n["key"]))
	_check("NOTE_DEAL_DEFERRED" in notes and "NOTE_DEAL_COMPLETED" in notes, "the user is told about both steps")
	var q := _loanable(c)
	c.week = 12
	m.sync_clock(1, 12, USER)
	var lo: TransferOffer = m.make_offer(USER, q.id, TransferOffer.LOAN, {"loan_weeks": 10, "wage_split_percent": 100})["offer"]
	_check(lo.status == TransferOffer.DEFERRED and q.loan_parent == "", "a loan agreed outside the window waits as well")


func _test_free_and_pre_contract() -> void:
	var c := _career(12)
	var m := c.market
	var free: PlayerData = null
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.squad_ids.size() > TransferMarket.MIN_SQUAD + 2:
			free = db.get_player(t.squad_ids[t.squad_ids.size() - 1])
			PromotionSystem.release_from_squad(db, t.id, free.id)
			break
	_check(free != null and free.team_id == "", "(setup) a free agent")
	var o: TransferOffer = m.make_offer(USER, free.id, TransferOffer.FREE, {})["offer"]
	_check(o.status == TransferOffer.ACCEPTED, "a free agent needs no club agreement")
	var d: ContractOffer = m.player_answer(free, USER, ContractOffer.make(100, 2, "backup"))["demand"]
	_check(m.propose_contract(o.id, d) == "" and free.team_id == USER, "free agents sign outside the window too")
	var p := _target(c)
	p.contract_years = 1
	c.week = 30
	m.sync_clock(1, 30, USER)
	_check(m.free_type(p) == TransferOffer.PRE_CONTRACT, "a contract ending within 26 weeks allows a pre-contract")
	var pc: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PRE_CONTRACT, {})["offer"]
	var d2: ContractOffer = m.player_answer(p, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
	var old_club := p.team_id
	_check(m.propose_contract(pc.id, d2) == "" and pc.status == TransferOffer.DEFERRED and p.team_id == old_club, "pre-contract agreed: he stays until the season ends")
	c.week = CareerState.WEEKS_PER_SEASON
	c.end_season()
	_check(p.team_id == USER and p.contract_years == d2.years and pc.status == TransferOffer.COMPLETED, "at the season end he joins for free",
			"%s %d" % [p.team_id, p.contract_years])
	_check(_ledgers_ok(c), "ledgers consistent")


# --- 2.6 AI offers for the user's players --------------------------------------------------------------------------------

func _test_incoming_offers() -> void:
	var c := _career(1)
	c.week = 0
	var m := c.market
	var mine := db.get_squad(USER)
	mine.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() < b.get_overall())
	var listed: PlayerData = mine[mine.size() / 2]
	var price := Valuation.round_value(m.market_value(listed) * 0.8)
	_check(m.set_listing(USER, listed.id, TransferMarket.LISTING_TRANSFER, {"price": price}) == "", "list a player for sale")
	var star: PlayerData = mine[-1]
	m.set_listing(USER, star.id, TransferMarket.LISTING_UNTOUCHABLE)
	var squad_before := db.get_team(USER).squad_ids.duplicate()
	var incoming: Array = []
	for w in 5:                                 # the summer window is weeks 1-5 (Phase K2)
		c.advance_week()
		incoming.append_array(m.user_offers("incoming", false).filter(func(o: TransferOffer) -> bool: return not (o in incoming)))
	var for_listed := incoming.filter(func(o: TransferOffer) -> bool: return o.player_id == listed.id and not o.is_loan())
	_check(not for_listed.is_empty(), "offers arrive for the listed player during the window", str(incoming.size()))
	_check(for_listed.all(func(o: TransferOffer) -> bool: return o.fee >= int(price * 0.85) and o.fee <= price),
			"they are close to the listing price", str(for_listed.map(func(o: TransferOffer) -> int: return o.fee)))
	_check(not incoming.any(func(o: TransferOffer) -> bool: return o.player_id == star.id), "no offers for an untouchable player")
	var per_week := {}
	for o: TransferOffer in incoming:
		per_week[o.created_week] = int(per_week.get(o.created_week, 0)) + 1
	_check(per_week.values().all(func(n: int) -> bool: return n <= TransferMarket.MAX_INCOMING_PER_WEEK), "at most three offers a week", str(per_week))
	_check(db.get_team(USER).squad_ids == squad_before, "the squad only changes when the user accepts")
	var open: Array = m.user_offers("incoming").filter(func(o: TransferOffer) -> bool: return o.status == TransferOffer.PENDING and not o.is_loan())
	if not open.is_empty():
		open.sort_custom(func(x: TransferOffer, y: TransferOffer) -> bool: return x.fee < y.fee)       # the cheapest: its buyer can pay it
		var o: TransferOffer = open[0]
		var pl: PlayerData = db.get_player(o.player_id)
		var bal := c.ledger().balance
		_check(m.answer_incoming(o.id, "accept") == "" and pl.team_id == o.from_club and o.status == TransferOffer.COMPLETED,
				"accepting an incoming offer sells the player", o.status)
		_check(c.ledger().balance == bal + o.upfront(), "the fee is received")
	_check(_ledgers_ok(c), "ledgers consistent")
	# counter an AI offer
	var p2: PlayerData = null
	for q in db.get_squad(USER):
		if q.loan_parent == "" and m.listing_of(q.id) == TransferMarket.LISTING_NONE:
			p2 = q
			break
	var buyer := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and (c.ledgers[t.id] as FinanceLedger).transfer_budget > m.market_value(p2) * 2:
			buyer = t.id
			break
	if buyer != "":
		m.arrivals.erase(p2.id)
		var o2: TransferOffer = m.make_offer(buyer, p2.id, TransferOffer.PERMANENT, {"fee": m.market_value(p2)})["offer"]
		_check(o2.status == TransferOffer.PENDING and o2.unread, "an AI offer waits for the user's answer")
		m.answer_incoming(o2.id, "counter", {"fee": m.market_value(p2) * 5})
		_check(o2.status in [TransferOffer.PENDING, TransferOffer.WITHDRAWN] and o2.fee <= m.buyer_max_fee(buyer, p2),
				"a greedy counter: the AI meets halfway within its limit or walks away", "%s %d" % [o2.status, o2.fee])


func _test_renewal() -> void:
	var c := _career()
	var m := c.market
	var p: PlayerData = db.get_squad(USER)[3]
	var low := m.negotiate_renewal(USER, p.id, ContractOffer.make(100, 3, "starter"), c.week)
	_check(low["error"] == "" and low["status"] != TransferOffer.ACCEPTED, "a renewal at a low wage is not accepted")
	var demand: ContractOffer = low["demand"]
	demand.release_clause = 50_000_000
	var ok := m.negotiate_renewal(USER, p.id, demand, c.week)
	_check(ok["status"] == TransferOffer.ACCEPTED and p.salary == demand.salary and p.contract_years == demand.years
			and m.release_clause(p.id) == 50_000_000, "a renewal at his demand: new wage, length and release clause", str(ok))


func _test_search() -> void:
	var c := _career()
	var m := c.market
	var all := m.search_v2({"exclude_team": USER})
	_check(all.size() > 1000, "the search lists the world")
	var f := m.search_v2({"positions": [PlayerData.Position.ST, PlayerData.Position.LW], "min_age": 20, "max_age": 25, "min_overall": 70, "max_overall": 80})
	_check(not f.is_empty() and f.all(func(p: PlayerData) -> bool:
		return p.position in [PlayerData.Position.ST, PlayerData.Position.LW] and p.age >= 20 and p.age <= 25 and p.get_overall() >= 70 and p.get_overall() <= 80),
		"multi-position, age and rating ranges")
	var some: PlayerData = f[0]
	var by_nat := m.search_v2({"nationality": some.nationality})
	_check(by_nat.all(func(p: PlayerData) -> bool: return p.nationality == some.nationality), "nationality filter")
	var league := db.get_team(some.team_id).league_id
	_check(m.search_v2({"league": league}).all(func(p: PlayerData) -> bool: return db.get_team(p.team_id).league_id == league), "league filter")
	_check(m.search_v2({"club": some.team_id}).size() == db.get_squad(some.team_id).filter(func(p: PlayerData) -> bool: return p.loan_parent == "").size(), "club filter")
	var exp := m.search_v2({"expiring": true})
	_check(exp.all(func(p: PlayerData) -> bool: return p.contract_years <= 1), "expiring contracts filter")
	m.set_listing(some.team_id, some.id, TransferMarket.LISTING_BOTH, {"price": 5_000_000})
	_check(m.search_v2({"listed_only": true}).has(some) and m.search_v2({"loan_available": true}).has(some), "listed / loan-available filters")
	var by_price := m.search_v2({"sort": "price", "max_price": 3_000_000})
	_check(by_price.size() > 2 and m.asking_price(by_price[0]) <= m.asking_price(by_price[1]), "sort by price (cheapest first)")
	var by_pot := m.search_v2({"sort": "potential"})
	_check(by_pot[0].potential >= by_pot[1].potential, "sort by potential")
	_check(m.toggle_shortlist(some.id) and some.id in m.shortlist and not m.toggle_shortlist(some.id), "shortlist toggles")
	for i in TransferMarket.SAVED_SEARCHES_MAX:
		m.save_search("s%d" % i, {"min_overall": 70})
	_check(m.save_search("too many", {}) != "", "at most five saved searches")


# --- save / load -----------------------------------------------------------------------------------------------------------

func _save_reload(c: CareerState) -> CareerState:
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(), "user_team_id": c.club_id})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	var res := SaveManager.restore(db, parsed)
	if not res["ok"]:
		print(res["errors"])
		return null
	return CareerState.from_dict(db, res["extras"]["career"])


func _test_save_load() -> void:
	var c := _career()
	var m := c.market
	var a := _target(c)
	var talks: TransferOffer = m.make_offer(USER, a.id, TransferOffer.PERMANENT, {"fee": int(m.seller_price(a) * 0.9)})["offer"]
	var b := _loanable(c)
	m.make_offer(USER, b.id, TransferOffer.LOAN_WITH_OPTION, {"loan_weeks": 26, "wage_split_percent": 70, "option_fee": m.seller_price(b), "recall_after_weeks": 10})
	var d: PlayerData = null
	for p: PlayerData in db.players.values():
		if p != a and p != b and p.team_id != "" and p.team_id != USER and p.loan_parent == "" and p.status != PlayerData.Status.YOUTH \
				and db.get_team(p.team_id).squad_ids.size() > TransferMarket.MIN_SQUAD + 2 and int(m.squad_rank(p)["all"]) >= 3:
			d = p
			break
	var io: TransferOffer = m.make_offer(USER, d.id, TransferOffer.PERMANENT, {"fee": m.seller_price(d) * 2, "installments": 4, "sell_on_percent": 15})["offer"]
	m.propose_contract(io.id, m.player_answer(d, USER, ContractOffer.make(100, 3, "rotation"))["demand"])
	m.set_listing(USER, db.get_squad(USER)[2].id, TransferMarket.LISTING_BOTH, {"price": 3_000_000, "loan_min_split": 40})
	m.toggle_shortlist(a.id)
	m.save_search("wingers", {"positions": [PlayerData.Position.LW]})
	c.advance_week()
	var before := JSON.stringify(c.to_dict(), "", true)
	_check(talks.status == TransferOffer.COUNTERED and m.loans.has(b.id) and m.installments.size() == 3, "(setup) negotiation, loan and installments under way",
			"%s %s %d" % [talks.status, m.loans.has(b.id), m.installments.size()])
	var c2 := _save_reload(c)
	_check(c2 != null and JSON.stringify(c2.to_dict(), "", true) == before, "save + load in the middle of talks, a loan and installments: identical state")
	if c2 == null:
		return
	var m2 := c2.market
	var t2 := m2.get_offer(talks.id)
	_check(t2 != null and t2.status == TransferOffer.COUNTERED and t2.rounds.size() == talks.rounds.size(), "the negotiation continues after loading")
	_check(int(m2.loans[b.id]["wage_split"]) == 70 and str(m2.loans[b.id]["type"]) == TransferOffer.LOAN_WITH_OPTION, "loan terms survive")
	_check(m2.accept_counter(t2.id) == "" and t2.status == TransferOffer.ACCEPTED, "the counter-offer can be accepted after loading")
	c2.advance_week()
	_check(_ledgers_ok(c2) and CareerValidator.validate(c2, false)["errors"].is_empty(), "the loaded career plays on cleanly")


func _test_v1_migration() -> void:
	var c := _career()
	var p := _loanable(c)
	c.market.loan(USER, p.id, 12, 0, c.week)
	var d := c.to_dict()
	var md: Dictionary = d["market"]
	for k in md.keys():
		if not (k in ["history", "next_id"]):
			md.erase(k)                         # a market block as saved before transfers v2
	var c2 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(d)))
	_check(c2.market.loans.has(p.id) and int(c2.market.loans[p.id]["wage_split"]) == 100, "an old save's running loan gets plain terms (borrower pays all)")
	_check(c2.market.offers.is_empty() and c2.market.history.size() == c.market.history.size(), "an old save loads with an empty offer list and its history")
	_check(int(c2.market.to_dict()["version"]) == TransferMarket.STATE_VERSION, "it is saved again as version 2")
	var bill := c2.market.wage_bill(USER)
	_check(bill == c2.market.weekly_wages(USER), "old loans cost the borrower exactly what they did before")



# --- plan items added after the first merge -------------------------------------------------------------------------------

func _test_replies_next_week() -> void:
	var c := _career()
	var m := c.market
	m.replies_next_week = true
	var p := _target(c)
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": m.seller_price(p)})["offer"]
	_check(o.status == TransferOffer.PENDING, "replies next week: the offer waits for the answer")
	m.process_week(c)
	_check(o.status == TransferOffer.PENDING, "no answer in the same week")
	c.week += 1
	m.sync_clock(1, c.week, USER)
	m.process_week(c)
	_check(o.status == TransferOffer.ACCEPTED, "the club answers in the following week", o.status)
	_check(m.notifications.any(func(n: Dictionary) -> bool: return n["key"] == "NOTE_REPLY_RECEIVED"), "the answer is announced")
	var d := c.to_dict()
	_check(CareerState.from_dict(db, JSON.parse_string(JSON.stringify(d))).market.replies_next_week, "the setting is saved")
	m.replies_next_week = false
	m.withdraw(o.id)
	var q := p
	var now: TransferOffer = m.make_offer(USER, q.id, TransferOffer.PERMANENT, {"fee": m.seller_price(q)})["offer"]
	_check(now.status != TransferOffer.PENDING, "switched off: the answer comes at once")


func _test_compensation_for_user() -> void:
	var c := _career()
	var m := c.market
	var mine: PlayerData = null
	for p in db.get_squad(USER):
		if p.position != PlayerData.Position.GK and p.loan_parent == "":
			mine = p
	var borrower := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.squad_ids.size() < TransferMarket.MAX_SQUAD - 2:
			borrower = t.id
			break
	_check(m.loan(borrower, mine.id, 30, 400_000, c.week, {}, {"min_play_percent": 80}) == "", "(setup) the user loans a player out with a playing-time promise")
	_check(m.claim_compensation(mine.id) != "", "no compensation while the promise is kept")
	m.sync_clock(1, c.week + 10, USER)
	c.world_stats[mine.id] = {"apps": 1, "goals": 0, "rating_sum": 6.0}
	m.update_loans(c)
	_check(bool(m.loans[mine.id]["complained"]) and m.can_recall(mine.id), "promise broken: the user may recall")
	var bal := c.ledger().balance
	var bbal: int = (c.ledgers[borrower] as FinanceLedger).balance
	var comp := m.compensation_for(mine.id)
	_check(comp == maxi(200_000, mine.salary * 4), "compensation: half the loan fee, at least four weeks of wages", str(comp))
	_check(m.claim_compensation(mine.id) == "" and c.ledger().balance == bal + comp and (c.ledgers[borrower] as FinanceLedger).balance == bbal - comp,
			"the borrower pays the compensation to the user")
	_check(m.claim_compensation(mine.id) != "", "compensation is paid once")
	_check(mine.loan_parent == USER, "the loan goes on after the compensation")
	_check(_ledgers_ok(c), "ledgers consistent")


func _test_parent_clause() -> void:
	var c := _career()
	var m := c.market
	var p := _loanable(c)
	var lender := p.team_id
	var o: TransferOffer = m.make_offer(USER, p.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100, "no_play_vs_parent": 1})["offer"]
	_check(o.status == TransferOffer.COMPLETED and int(m.loans[p.id]["no_play_vs_parent"]) == 1, "a loan with the clause 'not against his own club'")
	_check(m.blocked_against(USER, lender) == [p.id] and m.blocked_against(USER, "nobody").is_empty(), "he is blocked only against his own club")
	var sq := Squad.new(USER)
	sq.auto_pick(db)
	if not (p.id in sq.starting):
		sq.starting[3] = p.id
	var setup := MatchSetup.new()
	setup.home_id = USER
	setup.away_id = lender
	setup.home_squad = sq
	setup.excluded = m.blocked_against(USER, lender)
	var side := setup.build_side(db, "home")
	var ids: Array = side["starters"].map(func(s: Dictionary) -> String: return str(s["player_id"]))
	_check(not (p.id in ids) and not (p.id in side["bench"]) and not ids.has(""), "the match lineup leaves him out and fills his place", str(ids))
	_check(p.id in sq.starting, "the club's own lineup is not changed")
	var back := MatchSetup.from_dict(setup.to_dict())
	_check(back.excluded == setup.excluded, "the exclusion is kept in a match save")
	# simulated matches: the user's side is rated without him against his own club
	var best: PlayerData = null
	for x in db.get_squad(USER):
		if best == null or x.get_overall() > best.get_overall():
			best = x
	_check(MatchSimulator.rating_without(db, USER, [best.id]) <= db.get_team_rating(USER)
			and MatchSimulator.rating_without(db, USER, []) == db.get_team_rating(USER), "a simulated side is rated without an excluded player")
	var f := {"match_id": "clause_test", "home": USER, "away": lender, "stage": "league"}
	var with_clause := MatchSimulator.career_result(c, f, 7)
	var plain := MatchSimulator.result(db, f, 7, {}, [p.id])
	_check(with_clause.home_goals == plain.home_goals and with_clause.away_goals == plain.away_goals,
			"a simulated match against his own club leaves the loanee out")
	var other_club := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.id != lender:
			other_club = t.id
			break
	var f2 := {"match_id": "clause_test2", "home": USER, "away": other_club, "stage": "league"}
	var r1 := MatchSimulator.career_result(c, f2, 7)
	var r2 := MatchSimulator.result(db, f2, 7)
	_check(r1.home_goals == r2.home_goals and r1.away_goals == r2.away_goals, "against other clubs nothing changes")
	var crest := UIKit.crest(db, TransferMarket.EXTERNAL_PREFIX + "test_club", 22)
	_check(crest is TextureRect and (crest as TextureRect).texture != null, "clubs outside the loaded leagues get a drawn crest")
	crest.free()
	var q := _loanable(c)
	m.make_offer(USER, q.id, TransferOffer.LOAN, {"loan_weeks": 20, "wage_split_percent": 100})
	_check(not (q.id in m.blocked_against(USER, str(m.loans[q.id]["from"]))), "without the clause he may play")
