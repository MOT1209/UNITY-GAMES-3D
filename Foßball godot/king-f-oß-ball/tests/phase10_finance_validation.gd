## Finance and transfers: sponsorship, financial reports, negotiation, AI transfer windows.
##   godot --headless --path . res://tests/phase10_finance_validation.tscn
extends Node

const PACK := "real_2025"
const USER_CLUB := "eng_leicester_city_fc"

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
	print("=== KING FOOTBALL — Finance and transfers validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	_test_report()
	_test_negotiation()
	var first := _test_ai_window()
	db.load_world(PACK)
	_test_determinism(first)
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_report() -> void:
	var l := FinanceLedger.new("x", 1000, 500, 500)
	l.record("match_revenue", 400, "m", 1)
	l.record("sponsorship", 100, "s", 2)
	l.record("salary", -250, "w", 2)
	l.record("transfer_in", -300, "t", 5)
	var r := l.report()
	_check(r["total_income"] == 500 and r["total_expense"] == -550 and r["net"] == -50 and r["entries"] == 4, "the report totals income and expenses", str(r))
	_check(l.balance - l.opening_balance == r["net"], "the report's net result equals the balance movement")
	var part := l.report(2, 4)
	_check(part["entries"] == 2 and part["income"].has("sponsorship") and not part["income"].has("match_revenue"), "the report can be limited to a range of weeks")
	_check(l.record("sponsorship", 50, "s2", 6) == "" and "sponsorship" in FinanceLedger.CATEGORIES, "sponsorship is a ledger category")


func _find_player(c: CareerState, exclude_team: String) -> PlayerData:
	for p in c.market.search({"exclude_team": exclude_team, "min_overall": 60}):
		if p.team_id != "" and db.get_team(p.team_id).squad_ids.size() > TransferMarket.MIN_SQUAD + 2:
			return p
	return null


func _test_negotiation() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var p := _find_player(c, USER_CLUB)
	var price := c.market.asking_price(p)
	var a := c.market.negotiate(USER_CLUB, p.id, price, 3)
	_check(a["status"] == "accepted", "an offer at the asking price is accepted")
	var low := c.market.negotiate(USER_CLUB, p.id, int(price * 0.5), 3)
	_check(low["status"] == "rejected", "a very low offer is rejected")
	var mid := c.market.negotiate(USER_CLUB, p.id, int(price * 0.9), 3)
	_check(mid["status"] == "counter" and mid["counter"] >= int(price * 0.9) and mid["counter"] <= price and mid["round"] == 1, "a decent offer gets a counter-offer", str(mid))
	c.market.negotiate(USER_CLUB, p.id, int(price * 0.9), 3)
	c.market.negotiate(USER_CLUB, p.id, int(price * 0.9), 3)
	var broken := c.market.negotiate(USER_CLUB, p.id, int(price * 0.9), 3)
	_check(broken["status"] == "rejected", "after three counters the negotiation breaks down")
	_check(c.market.negotiate(USER_CLUB, p.id, int(price * 0.9), 4)["status"] == "counter", "a new week starts a new negotiation")
	_check(c.market.negotiate(USER_CLUB, db.get_squad(USER_CLUB)[0].id, 1_000_000_000, 3)["status"] == "rejected", "own players are not for sale to oneself")
	var fee: int = a["fee"]
	var err := c.market.buy(USER_CLUB, p.id, fee, maxi(p.salary, c.market.minimum_wage(p)), 3, 3)
	_check(err == "" or err.contains("budget") or err.contains("wage") or err.contains("funds"), "the agreed fee goes through the normal buy rules (they may still refuse)", err)


## Plays the first transfer window; returns the deals of week 1 for the determinism check.
func _test_ai_window() -> Array:
	var c := CareerState.start(db, USER_CLUB)
	var user_squad_before := db.get_team(USER_CLUB).squad_ids.duplicate()
	var week1: Array = []
	var all_deals: Array = []
	var sponsor_ok := true
	for w in 6:
		var before := {}
		for id in c.ledgers:
			before[id] = (c.ledgers[id] as FinanceLedger).total("sponsorship")
		var info := c.advance_week()
		if w == 0:
			week1 = info["ai_transfers"].duplicate(true)
		all_deals.append_array(info["ai_transfers"])
		for id in c.ledgers:
			if (c.ledgers[id] as FinanceLedger).total("sponsorship") - before[id] != c.weekly_sponsorship(id):
				sponsor_ok = false
	_check(sponsor_ok, "every club books its weekly sponsorship every week")
	_check(all_deals.size() > 0 and all_deals.size() <= 6 * AITransfers.MAX_DEALS_PER_WEEK, "AI clubs make transfers in the window, within the weekly limit", str(all_deals.size()))
	_check(not AITransfers.in_window(10) and AITransfers.in_window(1) and AITransfers.in_window(24), "windows are weeks 1-6 and 24-29")
	var ok_squads := true
	var ok_ledgers := true
	var ok_owner := true
	var seen := {}
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.squad_ids.size() < TransferMarket.MIN_SQUAD - 2 or t.squad_ids.size() > TransferMarket.MAX_SQUAD + 2:
			ok_squads = false
		if not (c.ledgers[t.id] as FinanceLedger).is_consistent():
			ok_ledgers = false
		for pid in t.squad_ids:
			if seen.has(pid) or db.get_player(pid).team_id != t.id:
				ok_owner = false
			seen[pid] = true
	_check(ok_squads, "squad sizes stay sane after the window")
	_check(ok_ledgers, "every ledger stays consistent (opening + entries == balance)")
	_check(ok_owner, "no player is in two squads and every player's club matches the squad that lists him")
	var moved_from_user := all_deals.any(func(d: Dictionary) -> bool: return d["from"] == USER_CLUB)
	_check(not moved_from_user and db.get_team(USER_CLUB).squad_ids == user_squad_before, "the user's squad is never touched by AI transfers")
	var consistent_deals := all_deals.all(func(d: Dictionary) -> bool: return db.get_player(d["player_id"]).team_id == d["to"] or c.market.history.any(func(h: Dictionary) -> bool: return h["player_id"] == d["player_id"] and h["from"] == d["to"]))
	_check(consistent_deals and c.market.history.size() >= all_deals.size(), "every deal is in the transfer history and the player is at his new club")
	var broke := 0
	for id in c.ledgers:
		if (c.ledgers[id] as FinanceLedger).transfer_budget < 0:
			broke += 1
	_check(broke == 0, "no club ends with a negative transfer budget")
	c.advance_week()
	for i in 3:
		c.advance_week()
	_check(c.week == 10 and c.advance_week()["ai_transfers"].is_empty(), "outside a window nobody trades")
	return week1


func _test_determinism(first: Array) -> void:
	var c := CareerState.start(db, USER_CLUB)
	var again: Array = c.advance_week()["ai_transfers"]
	_check(first == again and not first.is_empty(), "the same world and week produce exactly the same AI deals", "%d vs %d" % [first.size(), again.size()])
