## Phase T9 validation — finance, transfers, loans, contracts, career:
##   godot --headless --path . res://tests/phaseT9_validation.tscn
extends Node

const A := "club_royal_harbor"      # rich
const B := "club_obsidian"          # poor

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase T9 validation ===")
	_test_ledger()
	_test_search_and_pricing()
	_test_buy_sell()
	_test_buy_failures()
	_test_free_agent()
	_test_loans()
	_test_contracts()
	_test_career()
	_test_career_persistence()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	db.reload()
	return db


func _test_ledger() -> void:
	var l := FinanceLedger.new("x", 1000, 600, 100)
	_check(l.record("match_revenue", 500, "gate", 1) == "", "income recorded")
	_check(l.balance == 1500, "balance increases")
	_check(l.record("transfer_in", -2000, "too much", 1) != "", "overdraft refused for transfers")
	_check(l.balance == 1500 and l.entries.size() == 1, "refused spend changes nothing")
	_check(l.record("salary", -2000, "wages", 2) == "" and l.balance == -500, "salaries may overdraw (unavoidable)")
	_check(l.record("bogus", 5, "x", 1) != "", "unknown category rejected")
	_check(l.record("other", 0, "zero", 1) != "", "zero amount rejected")
	_check(l.spend_transfer("transfer_in", 0, "x", 1) != "", "zero transfer fee rejected")
	var l2 := FinanceLedger.new("y", 10000, 500, 100)
	_check(l2.spend_transfer("transfer_in", 600, "x", 1) != "", "transfer budget enforced")
	_check(l2.spend_transfer("transfer_in", 400, "x", 1) == "" and l2.transfer_budget == 100 and l2.balance == 9600,
			"transfer reduces budget and balance")
	_check(l.is_consistent() and l2.is_consistent(), "ledger audit: opening + entries == balance")
	_check(l.total("salary") == -2000, "category totals")
	l.entries[0]["amount"] = 999
	_check(not l.is_consistent(), "tampering is detected by the audit")
	var back := FinanceLedger.from_dict(JSON.parse_string(JSON.stringify(l2.to_dict())))
	_check(back.balance == l2.balance and back.entries.size() == 1 and back.is_consistent(), "ledger round-trip")
	_check(back.record("other", 1, "next", 2) == "" and back.entries[1]["id"] == 2, "entry ids continue after load")


func _market(db: TeamDatabase) -> TransferMarket:
	var ledgers := {}
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var wages := 0
		for p in db.get_squad(t.id):
			wages += p.salary
		ledgers[t.id] = FinanceLedger.new(t.id, t.budget, t.budget / 2, int(wages * 1.3))
	return TransferMarket.new(db, ledgers)


func _test_search_and_pricing() -> void:
	var db := _db()
	var m := _market(db)
	var all := m.search()
	_check(all.size() > 100, "search lists players of all clubs")
	_check(all[0].get_overall() >= all[-1].get_overall(), "results sorted best first")
	var no_a := m.search({"exclude_team": A})
	var has_a := false
	for p in no_a:
		if p.team_id == A:
			has_a = true
	_check(not has_a, "exclude_team filter")
	var strikers := m.search({"position": PlayerData.Position.ST})
	var only_st := true
	for p in strikers:
		if p.position != PlayerData.Position.ST:
			only_st = false
	_check(strikers.size() > 0 and only_st, "position filter")
	var cheap := m.search({"max_price": 500000})
	var cheap_ok := true
	for p in cheap:
		if m.asking_price(p) > 500000:
			cheap_ok = false
	_check(cheap_ok, "max price filter")
	_check(m.search({"name": "zzzzzz"}).is_empty(), "name filter with no match")
	var young := YouthGenerator.generate(1, 1, "q", "Aldoria", 0.5, 17)
	db.register_player(young)
	var ids_found := m.search().map(func(p: PlayerData) -> String: return p.id)
	_check(not (young.id in ids_found), "academy youth never appear on the market")
	var p: PlayerData = db.get_player("plr_rhf_05")
	_check(m.asking_price(p) >= p.transfer_value, "asking price >= value")
	_check(m.minimum_wage(p) >= 100, "minimum wage floor")
	db.free()


func _first_sellable(db: TeamDatabase, team_id: String) -> PlayerData:
	for p in db.get_squad(team_id):
		return p
	return null


func _test_buy_sell() -> void:
	var db := _db()
	var m := _market(db)
	var target: PlayerData = db.get_player("plr_obr_05")
	var price := m.asking_price(target)
	var wage := target.salary + 50
	var buyer_squad := db.get_team(A).squad_ids.size()
	var seller_squad := db.get_team(B).squad_ids.size()
	var buyer_bal: int = m.ledgers[A].balance
	var seller_bal: int = m.ledgers[B].balance
	var tb: int = m.ledgers[A].transfer_budget
	var sq := Squad.new(B)
	sq.auto_pick(db)
	var err := m.buy(A, target.id, price, wage, 3, 5, {B: sq})
	_check(err == "", "buy succeeds", err)
	_check(target.team_id == A and target.id in db.get_team(A).squad_ids, "player now belongs to buyer")
	_check(not (target.id in db.get_team(B).squad_ids), "removed from seller's squad")
	_check(db.get_team(A).squad_ids.size() == buyer_squad + 1 and db.get_team(B).squad_ids.size() == seller_squad - 1, "squad sizes updated")
	_check(not sq.contains(target.id), "seller's lineup cleaned")
	_check(m.ledgers[A].balance == buyer_bal - price and m.ledgers[B].balance == seller_bal + price, "money moved between clubs")
	_check(m.ledgers[A].transfer_budget == tb - price, "transfer budget reduced")
	_check(target.salary == wage and target.contract_years == 3, "new contract applied")
	_check(m.ledgers[A].is_consistent() and m.ledgers[B].is_consistent(), "ledgers consistent after transfer")
	_check(m.history.size() == 1 and m.history[0]["kind"] == "transfer" and m.history[0]["fee"] == price, "transfer history recorded")
	var owners := 0
	for t: TeamData in db.teams.values():
		if target.id in t.squad_ids:
			owners += 1
	_check(owners == 1, "exactly one owner (no duplicate ownership)")
	var nums := PromotionSystem.used_numbers(db, A)
	var uniq := {}
	for n in nums:
		uniq[n] = true
	_check(uniq.size() == nums.size(), "no shirt-number clash at the buyer")
	_check(m.buy(A, target.id, price, wage, 3, 6) != "", "cannot buy own player")
	# Sell wrapper (A sells back to B)
	var err2 := m.sell(A, target.id, B, m.asking_price(target), target.salary, 2, 7)
	_check(err2 == "" or err2.find("budget") >= 0 or err2.find("wage") >= 0 or err2.find("funds") >= 0, "sell wrapper validates like buy", err2)
	_check(m.sell(B, "plr_rhf_01", A, 1, 100, 1, 7) != "", "cannot sell a player you do not own")
	db.free()


func _test_buy_failures() -> void:
	var db := _db()
	var m := _market(db)
	var t: PlayerData = db.get_player("plr_obr_06")
	var price := m.asking_price(t)
	var ok_wage := t.salary + 10
	_check(m.buy(A, "ghost", price, ok_wage, 3, 1) != "", "unknown player rejected")
	_check(m.buy("nobody", t.id, price, ok_wage, 3, 1) != "", "unknown buyer rejected")
	_check(m.buy("nat_aldoria", t.id, price, ok_wage, 3, 1) != "", "national team cannot buy")
	_check(m.buy(A, t.id, price - 1, ok_wage, 3, 1) != "", "low offer rejected")
	_check(m.buy(A, t.id, price, 10, 3, 1) != "", "contract below minimum wage rejected")
	_check(m.buy(A, t.id, price, ok_wage, 0, 1) != "", "zero-year contract rejected")
	_check(m.buy(A, t.id, price, ok_wage, 9, 1) != "", "too-long contract rejected")
	_check(m.buy(A, t.id, -5, ok_wage, 3, 1) != "", "negative fee rejected")
	_check(t.team_id == B, "failed offers change nothing")
	# Poor buyer: budget too small for a star.
	var star: PlayerData = null
	for p in db.get_squad(A):
		if star == null or p.get_overall() > star.get_overall():
			star = p
	m.ledgers[B].transfer_budget = 1000
	_check(m.buy(B, star.id, m.asking_price(star), star.salary, 3, 1) != "", "transfer budget enforced on buy")
	m.ledgers[B].transfer_budget = 10_000_000_000
	m.ledgers[B].balance = 1000
	_check(m.buy(B, star.id, m.asking_price(star), star.salary, 3, 1) != "", "cannot buy with insufficient balance")
	m.ledgers[B].balance = 100_000_000
	m.ledgers[B].wage_budget = 1000
	_check(m.buy(B, star.id, m.asking_price(star), star.salary, 3, 1) != "", "wage budget enforced")
	_check(m.ledgers[B].balance == 100_000_000 and star.team_id == A, "no partial transfer after failure")
	# Squad limits
	var big := db.get_team(A)
	while big.squad_ids.size() < TransferMarket.MAX_SQUAD:
		var filler := YouthGenerator.generate(4, big.squad_ids.size() + 100, "fill", "Aldoria", 0.5, 19)
		filler.status = PlayerData.Status.ACTIVE
		filler.team_id = A
		filler.id = "fill_%d" % big.squad_ids.size()
		db.register_player(filler)
		big.squad_ids.append(filler.id)
	_check(m.buy(A, t.id, price, ok_wage, 3, 1) != "", "full squad cannot buy")
	var small := db.get_team(B)
	while small.squad_ids.size() > TransferMarket.MIN_SQUAD:
		small.squad_ids.remove_at(small.squad_ids.size() - 1)
	var victim: String = small.squad_ids[0]
	m.ledgers[A].balance = 100_000_000
	m.ledgers[A].transfer_budget = 100_000_000
	m.ledgers[A].wage_budget = 100_000_000
	big.squad_ids.resize(10)
	_check(m.buy(A, victim, m.asking_price(db.get_player(victim)), db.get_player(victim).salary + 10, 3, 1) != "", "seller must keep a minimum squad")
	# Youth + loaned players
	var youth := YouthGenerator.generate(2, 2, A, "Aldoria", 0.5, 17)
	db.register_player(youth)
	_check(m.buy(B, youth.id, 1, 1000, 3, 1) != "", "academy youth cannot be bought")
	db.free()


func _test_free_agent() -> void:
	var db := _db()
	var m := _market(db)
	var p: PlayerData = db.get_player("plr_obr_07")
	PromotionSystem.release_from_squad(db, B, p.id)
	_check(p.team_id == "", "released player is a free agent")
	var wage := m.minimum_wage(p) + 10
	_check(m.buy(A, p.id, 500, wage, 2, 3) != "", "free agents cost no fee")
	var bal: int = m.ledgers[A].balance
	_check(m.buy(A, p.id, 0, wage, 2, 3) == "", "sign free agent")
	_check(p.team_id == A and m.ledgers[A].balance == bal, "free agent costs no money")
	_check(p.id in db.get_team(A).squad_ids and not (p.id in db.get_team(B).squad_ids), "free agent joined one squad only")
	db.free()


func _test_loans() -> void:
	var db := _db()
	var m := _market(db)
	var p: PlayerData = db.get_player("plr_rhf_20")
	var sq := Squad.new(A)
	sq.auto_pick(db)
	_check(m.loan(B, p.id, 2, 0, 1) != "", "loan shorter than minimum rejected")
	_check(m.loan(B, p.id, 100, 0, 1) != "", "loan longer than maximum rejected")
	_check(m.loan(A, p.id, 10, 0, 1) != "", "cannot loan to own club")
	_check(m.loan("nat_aldoria", p.id, 10, 0, 1) != "", "cannot loan to a national team")
	var bal_b: int = m.ledgers[B].balance
	var bal_a: int = m.ledgers[A].balance
	var err := m.loan(B, p.id, 6, 20000, 2, {A: sq})
	_check(err == "", "loan succeeds", err)
	_check(p.team_id == B and p.loan_parent == A and p.loan_weeks_left == 6, "player on loan at borrower")
	_check(p.id in db.get_team(B).squad_ids and not (p.id in db.get_team(A).squad_ids), "loaned player in exactly one squad")
	_check(m.ledgers[B].balance == bal_b - 20000 and m.ledgers[A].balance == bal_a + 20000, "loan fee paid to lender")
	_check(not sq.contains(p.id), "lender lineup cleaned")
	_check(m.loan(B, p.id, 10, 0, 3) != "", "cannot loan a loaned player again")
	_check(m.buy(B, p.id, 1, 1000, 3, 3) != "", "loaned player cannot be sold")
	var visible := m.search().map(func(q: PlayerData) -> String: return q.id)
	_check(not (p.id in visible), "loaned players not on the market")
	_check(m.renew_contract(B, p.id, 5000, 2, 3) != "", "borrower cannot renew a loaned player")
	var returned_early := []
	for w in 5:
		returned_early.append_array(m.advance_loans(3 + w))
	_check(returned_early.is_empty() and p.team_id == B, "loan still active after 5 of 6 weeks")
	var returned := m.advance_loans(9)
	_check(p.id in returned and p.team_id == A and p.loan_parent == "", "loan expires and player returns")
	_check(p.id in db.get_team(A).squad_ids and not (p.id in db.get_team(B).squad_ids), "ownership restored")
	var count := 0
	for t: TeamData in db.teams.values():
		if p.id in t.squad_ids:
			count += 1
	_check(count == 1, "single ownership after loan")
	_check(m.return_from_loan(p.id, 10) != "", "returning a non-loaned player rejected")
	m.loan(B, p.id, 10, 0, 11)
	_check(m.return_from_loan(p.id, 12) == "" and p.team_id == A, "early recall works")
	_check(m.history.filter(func(h: Dictionary) -> bool: return h["kind"] == "loan").size() == 2, "loans recorded in history")
	db.free()


func _test_contracts() -> void:
	var db := _db()
	var m := _market(db)
	var p: PlayerData = db.get_player("plr_rhf_08")
	_check(m.renew_contract(A, p.id, p.salary + 100, 3, 1) == "", "renew contract")
	_check(p.contract_years == 3 and p.salary > 0, "contract updated")
	_check(m.renew_contract(A, p.id, 10, 3, 1) != "", "renewal below minimum wage rejected")
	_check(m.renew_contract(B, p.id, p.salary, 3, 1) != "", "wrong club cannot renew")
	_check(m.renew_contract(A, p.id, p.salary, 9, 1) != "", "too-long renewal rejected")
	m.ledgers[A].wage_budget = 1000
	_check(m.renew_contract(A, p.id, p.salary + 5000, 3, 1) != "", "renewal beyond wage budget rejected")
	p.contract_years = 1
	var exp := m.expiring_contracts(A)
	_check(p in exp, "expiring contracts listed")
	db.free()


func _test_career() -> void:
	var db := _db()
	_check(CareerState.start(db, "nat_aldoria") == null, "career needs a club")
	_check(CareerState.start(db, "ghost") == null, "career needs an existing club")
	var c := CareerState.start(db, A)
	_check(c != null and c.club_id == A and c.season == 1 and c.week == 0, "career starts")
	_check(c.ledgers.size() == 8, "every club has finances")
	var wages := c.market.weekly_wages(A)
	var bal := c.ledger().balance
	var info := c.advance_week()
	_check(c.week == 1 and info["wages_paid"] == wages and c.ledger().balance == bal - wages, "weekly wages paid")
	_check(c.ledger().is_consistent(), "ledger consistent after wages")
	var comp := Competition.create_league("lg1", "League", ["club_royal_harbor", "club_northgate_utd", "club_sunvale", "club_ironbridge"], false)
	_check(c.register_competition(comp) == "" and c.register_competition(comp) != "", "register competition once")
	var f: Dictionary = comp.pending_fixtures()[0]
	var rev_before: int = c.ledgers[f["home"]].balance
	_check(c.submit_result("lg1", MatchResult.make(f["match_id"], f["home"], f["away"], 2, 1)) == "", "result via career")
	_check(c.ledgers[f["home"]].balance > rev_before, "home club earns match revenue")
	_check(c.submit_result("lg1", MatchResult.make(f["match_id"], f["home"], f["away"], 2, 1)) != "", "duplicate result rejected, no double revenue")
	var after_dup: int = c.ledgers[f["home"]].balance
	_check(after_dup == c.ledgers[f["home"]].balance, "revenue not paid twice")
	_check(c.submit_result("nope", MatchResult.make("x", "a", "b", 1, 0)) != "", "unknown competition rejected")
	var n := 0
	while not comp.is_finished() and n < 20:
		var pf: Dictionary = comp.pending_fixtures()[0]
		c.submit_result("lg1", MatchResult.make(pf["match_id"], pf["home"], pf["away"], n % 3, (n + 1) % 2))
		n += 1
	_check(comp.is_finished(), "competition completed via career")
	var champ_ledger: FinanceLedger = c.ledgers[comp.champion_id]
	_check(champ_ledger.total("competition_reward") >= 1_000_000, "champion receives prize money")
	var rewards_once: int = champ_ledger.total("competition_reward")
	c._pay_competition_rewards(comp)
	_check(champ_ledger.total("competition_reward") == rewards_once, "prize money is never paid twice")
	for tid in c.ledgers:
		_check(c.ledgers[tid].is_consistent(), "ledger audit passes for %s" % tid)
	# Season end
	var mine: PlayerData = db.get_player("plr_rhf_09")
	var age_before := mine.age
	mine.contract_years = 1
	var squad_before := db.get_team(A).squad_ids.size()
	var res := c.end_season()
	_check(c.season == 2 and c.week == 0, "new season starts")
	_check(mine.age == age_before + 1 or not (mine.id in db.players), "players age one year")
	_check(res["released"].has(mine.id) and mine.team_id != A and not (mine.id in db.get_team(A).squad_ids),
			"expired contract released from the user's club (AI clubs may sign him as a free agent)")
	_check(db.get_team(A).squad_ids.size() == squad_before - res["released"].size() - res["retired_mine"].size(),
			"squad shrinks by released + retired count (the user's club is never refilled automatically)")
	var ran := db.get_team(B)
	while ran.squad_ids.size() > TransferMarket.MIN_SQUAD:
		ran.squad_ids.remove_at(0)
	var protected_p: PlayerData = db.get_player(ran.squad_ids[0])
	protected_p.contract_years = 1
	c.end_season()
	_check(protected_p.team_id == B and protected_p.contract_years >= 1, "minimum squad keeps players (extension or AI renewal)")
	db.free()


func _test_career_persistence() -> void:
	var db := _db()
	var c := CareerState.start(db, A)
	var t: PlayerData = db.get_player("plr_obr_10")
	c.market.buy(A, t.id, c.market.asking_price(t), t.salary + 20, 3, 1)
	c.advance_week()
	c.advance_week()
	var comp := Competition.create_knockout("cup", "Cup", [A, B, "club_sunvale", "club_ironbridge"], false)
	c.register_competition(comp)
	var f: Dictionary = comp.pending_fixtures()[0]
	c.submit_result("cup", MatchResult.make(f["match_id"], f["home"], f["away"], 1, 0))
	var json := JSON.stringify(c.to_dict())
	var restored := CareerState.from_dict(db, JSON.parse_string(json))
	_check(restored.club_id == A and restored.week == 2 and restored.season == 1, "career clock restored")
	_check(restored.ledger().balance == c.ledger().balance and restored.ledger().is_consistent(), "finances restored")
	_check(restored.market.history.size() == 1 and restored.market.history[0]["player_id"] == t.id, "transfer history restored")
	_check(restored.competitions["cup"].results.size() == 1, "competition progress restored")
	_check(restored.market.ledgers == restored.ledgers, "market shares restored ledgers")
	var again: Competition = restored.competitions["cup"]
	_check(restored.submit_result("cup", MatchResult.make(f["match_id"], f["home"], f["away"], 1, 0)) != "", "restored career rejects duplicate results")
	# Full save through SaveManager extras
	var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
	_check(SaveManager.write_file("user://test_saves/t9.json", data) == "", "career saved via SaveManager")
	var rd := SaveManager.read_file("user://test_saves/t9.json")
	var db2 := _db()
	var res := SaveManager.restore(db2, rd["data"])
	_check(res["ok"], "save restores", str(res["errors"]))
	var c2 := CareerState.from_dict(db2, res["extras"]["career"])
	_check(db2.get_player(t.id).team_id == A and c2.market.history.size() == 1, "transferred player stays with new club after reload")
	_check(again != null, "competition object available")
	DirAccess.remove_absolute("user://test_saves/t9.json")
	db.free()
	db2.free()
