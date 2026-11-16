## Transfers v2, phase 4: balance over five simulated seasons. A simple user policy trades every window (lists a surplus
## player, accepts fair offers, buys one player through the full negotiation); prices must neither collapse nor inflate,
## AI clubs must not go broke, AI clubs keep trading, every ledger stays audited.
##   godot --headless --path . res://tests/transfers_balance_validation.tscn
extends Node

const PACK := "real_2025"
const USER := "eng_leicester_city_fc"
const SEASONS := 5

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
	print("=== KING FOOTBALL — Transfer balance (5 seasons) ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	var c := CareerState.start(db, USER)
	var m := c.market
	var med0 := _median_value(c)
	var user_sales := 0
	var user_buys := 0
	var ai_deals: Array = []
	var incoming := 0
	var seen := {}
	for s in SEASONS:
		var deals := 0
		for w in CareerState.WEEKS_PER_SEASON:
			var info := c.advance_week()
			deals += (info["ai_transfers"] as Array).size()
			if not TransferMarket.window_open(c.week):
				continue
			if c.week == 1 or c.week == 24:
				_list_surplus(c)
			for o: TransferOffer in m.user_offers("incoming"):
				if seen.has(o.id):
					continue
				seen[o.id] = true
				incoming += 1
				if o.status != TransferOffer.PENDING:
					continue
				var p: PlayerData = db.get_player(o.player_id)
				if o.is_loan() or o.fee < int(m.market_value(p) * 0.85) or db.get_team(USER).squad_ids.size() <= TransferMarket.MIN_SQUAD + 2:
					m.answer_incoming(o.id, "reject")
				elif m.answer_incoming(o.id, "accept") == "" and o.status == TransferOffer.COMPLETED:
					user_sales += 1
			if c.week == 2 or c.week == 25:
				user_buys += _buy_one(c)
		ai_deals.append(deals)
		var res := c.end_season()
		print("season %d: AI deals %d, median value %d, user balance %d" % [s + 1, deals, _median_value(c), c.ledger().balance])
	var med5 := _median_value(c)
	_check(incoming > 0 and user_sales > 0, "the user sells through incoming offers", "%d offers, %d sales" % [incoming, user_sales])
	_check(user_buys > 0, "the user buys through negotiation", str(user_buys))
	_check(user_sales + user_buys <= SEASONS * 2 * 6, "user deals stay reasonable (not dozens a window)", str(user_sales + user_buys))
	_check(ai_deals.all(func(n: int) -> bool: return n > 0), "AI clubs trade every season", str(ai_deals))
	var ratio := float(med5) / float(maxi(med0, 1))
	_check(ratio > 0.5 and ratio < 2.0, "prices neither collapse nor inflate over five seasons", "median %d -> %d (x%.2f)" % [med0, med5, ratio])
	var broke := 0
	var clubs := 0
	var consistent := true
	for id in c.ledgers:
		var l: FinanceLedger = c.ledgers[id]
		clubs += 1
		consistent = consistent and l.is_consistent()
		if id != USER and l.balance < -5_000_000:
			broke += 1
	_check(consistent, "every ledger stays consistent over five seasons")
	_check(broke <= clubs / 20, "AI clubs do not go broke (deep debt at most 5 %)", "%d of %d" % [broke, clubs])
	_check(m.installments.all(func(i: Dictionary) -> bool: return int(i["due"]) > m.abs_week()), "no installment is overdue")
	_check((CareerValidator.validate(c, false)["errors"] as Array).is_empty(), "the career passes the integrity audit")
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _median_value(c: CareerState) -> int:
	var vals: Array = []
	for p: PlayerData in db.players.values():
		if p.team_id != "" and p.status != PlayerData.Status.YOUTH and p.status != PlayerData.Status.RETIRED:
			vals.append(p.transfer_value)
	vals.sort()
	return int(vals[vals.size() / 2]) if not vals.is_empty() else 0


## Lists the weakest non-listed outfield player for sale at his value.
func _list_surplus(c: CareerState) -> void:
	var m := c.market
	var worst: PlayerData = null
	for p: PlayerData in db.get_squad(USER):
		if p.loan_parent == "" and m.listing_of(p.id) == TransferMarket.LISTING_NONE and p.position != PlayerData.Position.GK:
			if worst == null or p.get_overall() < worst.get_overall():
				worst = p
	if worst != null:
		m.set_listing(USER, worst.id, TransferMarket.LISTING_TRANSFER, {"price": m.market_value(worst)})


## Buys the best affordable upgrade: offer 90 %, accept the counter, meet the player's demand.
func _buy_one(c: CareerState) -> int:
	var m := c.market
	var level: int = db.get_team_rating(USER)
	var budget := c.ledger().transfer_budget
	if db.get_team(USER).squad_ids.size() >= TransferMarket.MAX_SQUAD - 1:
		return 0
	for p in m.search_v2({"exclude_team": USER, "min_overall": level + 1, "max_age": 29, "sort": "overall"}):
		if p.team_id == "" or m.refusal(p, USER, false) != "" or m.seller_price(p) > budget / 2:
			continue
		var res := m.make_offer(USER, p.id, TransferOffer.PERMANENT, {"fee": int(m.seller_price(p) * 0.9)})
		if res["error"] != "":
			continue
		var o: TransferOffer = res["offer"]
		if o.status == TransferOffer.COUNTERED:
			m.accept_counter(o.id)
		if o.status != TransferOffer.ACCEPTED:
			m.withdraw(o.id)
			continue
		var demand: ContractOffer = m.player_answer(p, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
		if m.propose_contract(o.id, demand) == "" and p.team_id == USER:
			return 1
		m.withdraw(o.id)
	return 0
