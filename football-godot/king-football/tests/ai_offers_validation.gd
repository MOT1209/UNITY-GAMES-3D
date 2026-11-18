## Transfers v2, phase 2: the AI on the market over a whole simulated season — offers for the user's players (listed first,
## close to the price), loan requests, never an untouchable player, at most three a week, only in the windows; AI listings;
## AI answers to the user's offers through the same rules; every ledger stays audited.
##   godot --headless --path . res://tests/ai_offers_validation.tscn
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
	print("=== KING FOOTBALL — AI transfer offers validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	var first := _test_season()
	db.load_world(PACK)
	_test_determinism(first)
	db.load_world(PACK)
	_test_user_offers_to_ai()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _setup(c: CareerState) -> Dictionary:
	var m := c.market
	var mine: Array = db.get_squad(USER)
	mine.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return a.get_overall() > b.get_overall() or (a.get_overall() == b.get_overall() and a.id < b.id))
	var star: PlayerData = mine[0]
	var listed: PlayerData = mine[mine.size() / 2]
	var young: PlayerData = null
	for p: PlayerData in mine:
		if p.age <= 23 and p != listed and p != star:
			young = p
	if young == null:
		young = mine[-1]
	m.set_listing(USER, star.id, TransferMarket.LISTING_UNTOUCHABLE)
	var price := Valuation.round_value(m.market_value(listed) * 0.9)
	m.set_listing(USER, listed.id, TransferMarket.LISTING_TRANSFER, {"price": price})
	m.set_listing(USER, young.id, TransferMarket.LISTING_LOAN, {"loan_min_split": 50})
	return {"star": star, "listed": listed, "price": price, "young": young}


func _test_season() -> Array:
	var c := CareerState.start(db, USER)
	var m := c.market
	var s := _setup(c)
	var squad_before := db.get_team(USER).squad_ids.duplicate()
	var seen := {}
	var all: Array = []
	var first_window: Array = []
	var ai_deals := 0
	var listed_ai := false
	for w in CareerState.WEEKS_PER_SEASON:
		var info := c.advance_week()
		ai_deals += (info["ai_transfers"] as Array).size()
		for o: TransferOffer in m.offers:
			if o.to_club == USER and o.from_club != USER and not seen.has(o.id):
				seen[o.id] = true
				all.append(o)
				if c.week <= 6:
					first_window.append(o.to_dict())
		if c.week == 1:
			for pid in m.listings:
				var p: PlayerData = db.get_player(pid)
				if p != null and p.team_id != USER and m.is_loan_listed(pid):
					listed_ai = true
	_check(all.size() > 0, "AI clubs make offers for the user's players during the season", str(all.size()))
	_check(listed_ai, "at the start of the window AI clubs list players for loan")
	_check(not all.any(func(o: TransferOffer) -> bool: return o.player_id == (s["star"] as PlayerData).id), "no offer for the untouchable player")
	var weeks := {}
	for o: TransferOffer in all:
		weeks[o.created_week] = int(weeks.get(o.created_week, 0)) + 1
	_check(weeks.values().all(func(n: int) -> bool: return n <= TransferMarket.MAX_INCOMING_PER_WEEK), "at most three incoming offers a week", str(weeks))
	_check(weeks.keys().all(func(wk: int) -> bool: return TransferMarket.window_open(wk)), "offers only come while a window is open", str(weeks.keys()))
	var for_listed: Array = all.filter(func(o: TransferOffer) -> bool: return o.player_id == (s["listed"] as PlayerData).id and not o.is_loan())
	_check(not for_listed.is_empty(), "the listed player gets offers")
	_check(for_listed.all(func(o: TransferOffer) -> bool: return o.rounds.size() >= 1 and int(o.rounds[0]["terms"]["fee"]) >= int(s["price"]) * 0.85 \
			and int(o.rounds[0]["terms"]["fee"]) <= int(s["price"])), "offers for a listed player are close to his price")
	var loans: Array = all.filter(func(o: TransferOffer) -> bool: return o.is_loan())
	_check(not loans.is_empty(), "AI clubs ask to borrow the user's young players", str(loans.size()))
	_check(all.all(func(o: TransferOffer) -> bool: return not o.is_open()), "after the season no incoming offer is left open (they expire)")
	_check(db.get_team(USER).squad_ids == squad_before, "nothing leaves the user's squad without the user's consent")
	_check(ai_deals > 0, "AI clubs still trade among themselves", str(ai_deals))
	var ok := true
	for id in c.ledgers:
		ok = ok and (c.ledgers[id] as FinanceLedger).is_consistent()
	_check(ok, "every ledger stays consistent over the season")
	var audit := CareerValidator.validate(c, false)
	_check((audit["errors"] as Array).is_empty(), "the career passes the integrity audit", str((audit["errors"] as Array).slice(0, 3)))
	_check(m.notifications.any(func(n: Dictionary) -> bool: return n["key"] == "NOTE_OFFER_RECEIVED"), "incoming offers are announced in the news")
	_check(NewsFeed.build(c, 400, true).any(func(n: Dictionary) -> bool: return n["key"] == "NOTE_DEADLINE_DAY"), "deadline day is announced")
	c.end_season()
	_check(m.offers.size() <= TransferMarket.CLOSED_OFFERS_KEEP + 50, "the offer list stays bounded")
	return first_window


func _test_determinism(first: Array) -> void:
	var c := CareerState.start(db, USER)
	_setup(c)
	var again: Array = []
	var seen := {}
	for w in 6:
		c.advance_week()
		for o: TransferOffer in c.market.offers:
			if o.to_club == USER and o.from_club != USER and not seen.has(o.id):
				seen[o.id] = true
				again.append(o.to_dict())
	_check(JSON.stringify(again) == JSON.stringify(first) and not first.is_empty(), "the same world gives exactly the same AI offers", "%d vs %d" % [first.size(), again.size()])


## The user negotiates with AI clubs and answers their offers in the window: the same rules for both sides.
func _test_user_offers_to_ai() -> void:
	var c := CareerState.start(db, USER)
	var m := c.market
	var s := _setup(c)
	c.advance_week()
	c.advance_week()
	var pending: Array = m.user_offers("incoming").filter(func(o: TransferOffer) -> bool: return o.status == TransferOffer.PENDING and not o.is_loan())
	var guard := 0
	while pending.is_empty() and guard < 3:
		c.advance_week()
		guard += 1
		pending = m.user_offers("incoming").filter(func(o: TransferOffer) -> bool: return o.status == TransferOffer.PENDING and not o.is_loan())
	if pending.is_empty():
		_check(false, "(setup) an incoming offer to answer")
		return
	var o: TransferOffer = pending[0]
	var p: PlayerData = db.get_player(o.player_id)
	var buyer := o.from_club
	var bal := c.ledger().balance
	var buyer_bal: int = (c.ledgers[buyer] as FinanceLedger).balance
	_check(m.answer_incoming(o.id, "accept") == "" and o.status == TransferOffer.COMPLETED and p.team_id == buyer,
			"accepting an AI offer in the window sells the player at once", o.status)
	_check(c.ledger().balance == bal + o.upfront() and (c.ledgers[buyer] as FinanceLedger).balance == buyer_bal - o.upfront() - AgentFees.signing(o.fee), "the fee moves between the ledgers")
	_check(m.history[-1]["kind"] == "transfer" and str(m.history[-1]["to"]) == buyer, "the sale is in the transfer history")
	# the user buys from an AI club through the same seller rules
	var target: PlayerData = null
	for q: PlayerData in db.players.values():
		if q.team_id != "" and q.team_id != USER and q.loan_parent == "" and q.status != PlayerData.Status.YOUTH \
				and db.get_team(q.team_id).squad_ids.size() > TransferMarket.MIN_SQUAD + 2 and int(m.squad_rank(q)["all"]) >= 3 \
				and m.refusal(q, USER, false) == "" and m.seller_price(q) < c.ledger().transfer_budget / 3:
			target = q
			break
	if target != null:
		var price := m.seller_price(target)
		var offer: TransferOffer = m.make_offer(USER, target.id, TransferOffer.PERMANENT, {"fee": int(price * 0.95)})["offer"]
		_check(offer.status == TransferOffer.COUNTERED, "an AI club counters an offer at 95 %", offer.status)
		_check(m.accept_counter(offer.id) == "", "the user accepts the counter")
		var demand: ContractOffer = m.player_answer(target, USER, ContractOffer.make(100, 3, "rotation"))["demand"]
		var err := m.propose_contract(offer.id, demand)
		_check(err == "" and target.team_id == USER, "personal terms agreed: the player joins the user in the window", err)
	var ok := true
	for id in c.ledgers:
		ok = ok and (c.ledgers[id] as FinanceLedger).is_consistent()
	_check(ok, "ledgers consistent")
	_check((s["star"] as PlayerData).team_id == USER, "the untouchable player is still at the club")
