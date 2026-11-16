## Career phase C7: ticket / shirt prices, sponsor offers, broadcast rights, bank loan, sustainability rule.
##   godot --headless --path . res://tests/economy_v2_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Economy v2 validation (C7) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	app.switch_world("")
	app.start_career("club_desert_kings")
	_test_prices()
	_test_sponsors()
	_test_loan()
	_test_sustainability()
	await _test_season()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_prices() -> void:
	var e := Economy.new()
	_check(not e.set_ticket_level("free") and e.set_ticket_level("high"), "only known ticket levels are accepted")
	e.set_ticket_level("normal")
	var normal := e.matchday_multiplier(60)
	e.set_ticket_level("high")
	var high := e.matchday_multiplier(60)
	_check(high > normal * 1.15, "+50% ticket prices bring more income per match (%.2f vs %.2f)" % [high, normal])
	var c: CareerState = app.career
	c.economy.set_ticket_level("high")
	c.fan_mood = 60
	var mood := c.fan_mood
	for i in 6:
		c.record_match_revenue(c.club_id)
	_check(c.fan_mood < mood, "...but high prices cost fan mood over time (%d -> %d)" % [mood, c.fan_mood])
	c.economy.set_ticket_level("normal")
	_check(e.matchday_multiplier(90) > e.matchday_multiplier(20), "a happier crowd fills the stadium")
	e.set_shirt_price(500)
	_check(e.shirt_price == 120, "shirt prices are clamped")
	var cheap := Economy.new()
	cheap.set_shirt_price(30)
	var dear := Economy.new()
	dear.set_shirt_price(110)
	_check(cheap.merchandise_income(60, 60) > 0 and dear.merchandise_income(60, 60) > 0 and cheap.merchandise_income(60, 60) != dear.merchandise_income(60, 60), "shirt price changes shirt income")
	_check(cheap.merchandise_income(80, 80) > cheap.merchandise_income(20, 30), "popular clubs sell more shirts")


func _test_sponsors() -> void:
	var offers := Economy.sponsor_offers(1, 5, 60)
	_check(offers.size() == 3 and offers == Economy.sponsor_offers(1, 5, 60), "three deterministic sponsor offers")
	_check(offers.map(func(o: Dictionary) -> String: return o["kind"]) == ["fixed", "variable", "goals"], "with different terms")
	var e := Economy.new()
	_check(not e.choose_sponsor({"kind": "bogus"}) and e.choose_sponsor(offers[1]), "an offer can be chosen")
	var champion := e.sponsor_season_payment(1, 20, 0)
	var last := e.sponsor_season_payment(20, 20, 0)
	_check(champion > last and last == 0, "a variable deal pays by final position (champion %d, last %d)" % [champion, last])
	var ai := Economy.ai_choose(offers, 2, 20)
	var weak := Economy.ai_choose(offers, 19, 20)
	_check(not ai.is_empty() and not weak.is_empty(), "the AI picks an offer with the same rule")
	var c: CareerState = app.career
	c.economy.choose_sponsor(offers[0])
	_check(c.weekly_sponsorship(c.club_id) == int(offers[0]["fixed_weekly"]), "the chosen deal sets the weekly sponsorship")
	_check(Economy.broadcast_income(1, 1, 20) > Economy.broadcast_income(1, 20, 20) and Economy.broadcast_income(1, 10, 20) > Economy.broadcast_income(3, 10, 20), "broadcast money grows with the tier and the final position")


func _test_loan() -> void:
	var c: CareerState = app.career
	var l := FinanceLedger.new("z", 100_000, 0, 0)
	var e := Economy.new()
	_check(e.take_loan(l, Economy.loan_limit(10_000) + 1, 10_000, 1) == "LOAN_ERR_LIMIT", "the bank limits the loan to the club's income")
	_check(e.take_loan(l, 200_000, 10_000, 1) == "" and l.balance == 300_000, "a loan pays out")
	_check(e.take_loan(l, 1000, 10_000, 1) == "LOAN_ERR_ACTIVE", "only one loan at a time")
	var paid := 0
	var weeks := 0
	while not e.loan.is_empty() and weeks < 100:
		var before := l.balance
		e.weekly_loan(l, 2 + weeks)
		paid += before - l.balance
		weeks += 1
	_check(weeks == Economy.LOAN_WEEKS and paid >= 200_000 and paid <= int(200_000 * (1.0 + Economy.LOAN_RATE)) + Economy.LOAN_WEEKS, "the loan is repaid with interest on schedule (%d paid in %d weeks)" % [paid, weeks])
	_check(l.is_consistent(), "the ledger is consistent")
	var back := Economy.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	_check(back.ticket_level == e.ticket_level and back.loan == e.loan, "economy state is saved")


func _test_sustainability() -> void:
	var e := Economy.new()
	var l := FinanceLedger.new("r", 10_000_000, 0, 0)
	_check(e.check_sustainability("r", 1000, 2000, l, 1) == "strike" and e.check_sustainability("r", 1000, 2000, l, 1) == "strike", "overspending for a season is a strike")
	_check(e.check_sustainability("r", 1000, 500, l, 1) == "" and e.strikes["r"] == 0, "a good season clears the strikes")
	e.check_sustainability("r", 1000, 2000, l, 1)
	e.check_sustainability("r", 1000, 2000, l, 1)
	var bal := l.balance
	var res := e.check_sustainability("r", 1000, 2000, l, 1)
	_check(res == "fined" and l.balance < bal and e.is_banned("r"), "three bad seasons in a row: fine and a transfer ban")
	_check(not e.is_banned("other"), "the ban is per club")
	e.window_passed()
	_check(not e.is_banned("r"), "the ban lasts one window")
	_check(l.is_consistent(), "the fine is booked in the ledger")


func _simulate_due() -> void:
	for pair in app.career.due_user_fixtures():
		app.simulate_fixture((pair[0] as Competition).id, str(pair[1]["match_id"]))


func _test_season() -> void:
	app.switch_world("")
	app.start_career("club_desert_kings")
	var c: CareerState = app.career
	c.economy.choose_sponsor(Economy.sponsor_offers(1, 5, 60)[1])
	var guard := 0
	while c.week < CareerState.WEEKS_PER_SEASON and guard < 80:
		guard += 1
		_simulate_due()
		await app.advance_week_async()
	_simulate_due()
	var bal := c.ledger().balance
	c.end_season(app.academies, app.squads)
	_check(c.ledger().is_consistent(), "a whole season with the new economy keeps the ledger consistent")
	var banned := 0
	for t in app.db.list_teams(TeamData.Category.CLUB):
		if c.economy.is_banned(t.id):
			banned += 1
	_check(banned == 0, "no club is banned after one ordinary season")
	var broke := 0
	for id in c.ledgers:
		if (c.ledgers[id] as FinanceLedger).balance < -20_000_000:
			broke += 1
	_check(broke == 0, "no club is in deep trouble after one season (%d)" % broke)
	# a ban really blocks a signing
	var b: TeamData = app.db.get_team("club_royal_harbor")
	c.economy.transfer_ban[b.id] = 1
	_check(c.market.ban_check.call(b.id) == true, "the market asks the economy about bans")
	var back := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.economy.transfer_ban == c.economy.transfer_ban and back.market.ban_check.is_valid(), "bans survive a save and the market is wired after loading")
