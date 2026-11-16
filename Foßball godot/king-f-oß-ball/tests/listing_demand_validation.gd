## Transfers v2, round 4 (logic): the user's players put on the transfer list find buyers (also in the 8-club fictional
## world), loan requests only target real fringe youngsters, and the promised squad role follows the player's real place
## in the buying club.
##   godot --headless --path . res://tests/listing_demand_validation.tscn
extends Node

const FICTIONAL_USER := "club_royal_harbor"
const REAL_PACK := "real_2025"
const REAL_USER := "eng_manchester_city"

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
	print("=== KING FOOTBALL — listing demand, loan requests and promised roles ===")
	db = get_node("/root/TeamDB")
	db.load_world("")
	_test_listing_demand("fictional world", FICTIONAL_USER)
	db.load_world(REAL_PACK)
	_test_listing_demand("real pack", REAL_USER)
	db.load_world("")
	_test_loan_requests()
	db.load_world("")
	_test_untouchable_and_ratio()
	db.load_world("")
	_test_external_sale()
	db.load_world("")
	_test_roles()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## The user's reserves sorted from the weakest; `n` of them that are not captain / set-piece takers.
func _fringe_players(c: CareerState, club: String, n: int, lo := 60, hi := 72) -> Array:
	var mine: Array = db.get_squad(club)
	mine.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return a.get_overall() < b.get_overall() or (a.get_overall() == b.get_overall() and a.id < b.id))
	var out: Array = []
	for p: PlayerData in mine:
		if p.get_overall() >= lo and p.get_overall() <= hi and p.loan_parent == "":
			out.append(p)
		if out.size() >= n:
			break
	if out.size() < n:                       # the squad is stronger than the range: take the weakest players anyway
		out.clear()
		for p: PlayerData in mine:
			if p.loan_parent == "":
				out.append(p)
			if out.size() >= n:
				break
	return out


func _permanent_offers(c: CareerState, club: String, pids: Array) -> Dictionary:
	var by_player := {}
	for o: TransferOffer in c.market.offers:
		if o.to_club == club and not o.is_loan() and o.player_id in pids:
			by_player[o.player_id] = int(by_player.get(o.player_id, 0)) + 1
	return by_player


func _test_listing_demand(label: String, club: String) -> void:
	var c := CareerState.start(db, club)
	var m := c.market
	var five := _fringe_players(c, club, 5)
	var ids := five.map(func(p: PlayerData) -> String: return p.id)
	print("  %s: listed overalls %s (club level %d)" % [label, str(five.map(func(p: PlayerData) -> int: return p.get_overall())), db.get_team_rating(club)])
	for p: PlayerData in five:
		m.set_listing(club, p.id, TransferMarket.LISTING_TRANSFER, {"price": m.market_value(p)})
	for w in 6:
		c.advance_week()
	var got := _permanent_offers(c, club, ids)
	_check(got.size() >= 4, "%s: at least 4 of 5 listed players (60-72) get an offer in one window" % label, str(got.size()))
	var ok := true
	for id in c.ledgers:
		ok = ok and (c.ledgers[id] as FinanceLedger).is_consistent()
	_check(ok, "%s: every ledger stays consistent" % label)


func _ledgers_ok(c: CareerState) -> bool:
	for id in c.ledgers:
		if not (c.ledgers[id] as FinanceLedger).is_consistent():
			return false
	return true


func _default_squads(c: CareerState) -> Dictionary:
	var sq := Squad.new(c.club_id)
	sq.auto_pick(db)
	sq.ensure_roles(db)
	return {c.club_id: sq}


## Loan requests: never for a starter (not even a 19-year-old in the first weeks of the season), but for a youngster who
## is only the third choice at his position.
func _test_loan_requests() -> void:
	var c := CareerState.start(db, FICTIONAL_USER)
	var squads := _default_squads(c)
	var sq: Squad = squads[c.club_id]
	var starters: Array = []
	var fringe: Array = []
	for p: PlayerData in db.get_squad(c.club_id):
		if p.id in sq.starting:
			starters.append(p)
		elif int(c.market.squad_rank(p)["pos"]) >= 2 and p.id != sq.captain_id:
			fringe.append(p)
	for p: PlayerData in starters:
		p.age = 19
	for p: PlayerData in fringe:
		p.age = 19
	var starter_ids := starters.map(func(p: PlayerData) -> String: return p.id)
	var fringe_ids := fringe.map(func(p: PlayerData) -> String: return p.id)
	_check(not starters.is_empty() and not fringe.is_empty(), "(setup) starters and third-choice youngsters exist", "%d / %d" % [starters.size(), fringe.size()])
	var starter_requests := 0
	var fringe_requests := 0
	for w in 6:
		c.advance_week(squads)
		for o: TransferOffer in c.market.offers:
			if o.is_loan() and o.to_club == c.club_id:
				if o.player_id in starter_ids:
					starter_requests += 1
				elif o.player_id in fringe_ids:
					fringe_requests += 1
	_check(starter_requests == 0, "no loan request for a 19-year-old starter during the first window", str(starter_requests))
	for w in 40:
		c.advance_week(squads)
	c.end_season()
	for w in 6:
		c.advance_week(squads)
		for o: TransferOffer in c.market.offers:
			if o.is_loan() and o.to_club == c.club_id and o.player_id in fringe_ids:
				fringe_requests += 1
	_check(fringe_requests >= 1, "a 19-year-old who is only the third choice gets a loan request within two windows", str(fringe_requests))
	var captain_id := sq.captain_id
	_check(captain_id == "" or not c.market.offers.any(func(o: TransferOffer) -> bool: return o.is_loan() and o.player_id == captain_id and o.to_club == c.club_id),
			"no loan request for the captain")


## An untouchable player gets nothing, and listed players get at least 3 times as many offers as the others (5 windows).
func _test_untouchable_and_ratio() -> void:
	var c := CareerState.start(db, FICTIONAL_USER)
	var m := c.market
	var club := FICTIONAL_USER
	var star: PlayerData = db.get_squad(club).reduce(func(a: PlayerData, b: PlayerData) -> PlayerData: return a if a.get_overall() >= b.get_overall() else b)
	var listed := _fringe_players(c, club, 5)
	var listed_ids := listed.map(func(p: PlayerData) -> String: return p.id)
	m.set_listing(club, star.id, TransferMarket.LISTING_UNTOUCHABLE)
	for p: PlayerData in listed:
		m.set_listing(club, p.id, TransferMarket.LISTING_TRANSFER, {"price": m.market_value(p)})
	var others: Array = db.get_squad(club).filter(func(p: PlayerData) -> bool: return p != star and not (p.id in listed_ids))
	var other_ids := others.map(func(p: PlayerData) -> String: return p.id)
	var seen := {}
	var listed_offers := 0
	var other_offers := 0
	var star_offers := 0
	var windows := 0
	for season in 3:
		for w in CareerState.WEEKS_PER_SEASON:
			c.advance_week()
			if windows >= 5:
				break
			if c.week == 1 or c.week == 24:
				windows += 1
			for o: TransferOffer in m.offers:
				if o.to_club != club or o.is_loan() or seen.has(o.id):
					continue
				seen[o.id] = true
				if o.player_id == star.id:
					star_offers += 1
				elif o.player_id in listed_ids:
					listed_offers += 1
				elif o.player_id in other_ids:
					other_offers += 1
		if windows >= 5:
			break
		c.end_season()
	var per_listed := float(listed_offers) / maxf(1.0, listed_ids.size())
	var per_other := float(other_offers) / maxf(1.0, other_ids.size())
	print("  offers per listed player %.2f, per other player %.2f (%d windows)" % [per_listed, per_other, windows])
	_check(star_offers == 0, "an untouchable player gets no offer", str(star_offers))
	_check(per_listed >= 3.0 * per_other and listed_offers > 0, "listed players get at least 3 times as many offers as the others", "%.2f vs %.2f" % [per_listed, per_other])
	_check(_ledgers_ok(c), "ledgers stay consistent over five windows")


## Selling to an external club: the fee reaches the ledger, the player leaves the game, history and save keep it.
func _test_external_sale() -> void:
	var c := CareerState.start(db, FICTIONAL_USER)
	var m := c.market
	var club := FICTIONAL_USER
	var p: PlayerData = _fringe_players(c, club, 1)[0]
	m.set_listing(club, p.id, TransferMarket.LISTING_TRANSFER, {"price": m.market_value(p)})
	c.advance_week()
	var res := m.make_external_offer(p.id, "Test Town FC", "Spain", int(m.market_value(p) * 0.8))
	var o: TransferOffer = res["offer"]
	_check(res["error"] == "" and o != null and TransferMarket.is_external(o.from_club), "an external club can bid for a listed player")
	var bal := c.ledger().balance
	var data := c.to_dict()
	var c2 := CareerState.from_dict(db, data)
	_check(c2.market.externals.size() == m.externals.size() and c2.market.get_offer(o.id) != null, "an open external offer survives save and load")
	_check(m.answer_incoming(o.id, "accept") == "" and o.status == TransferOffer.COMPLETED, "accepting an external offer completes the sale")
	_check(c.ledger().balance == bal + o.fee, "the external fee is paid into the user's ledger")
	_check(not (p.id in db.get_team(club).squad_ids) and p.team_id == "", "the sold player has left the squad and the game")
	_check(m.history[-1]["to"] == o.from_club and m.club_name(o.from_club) == "Test Town FC", "the sale is in the history with the external club's name")
	_check(m.abroad.has(p.id), "the player is recorded as playing abroad")
	var news := NewsFeed.build(c, 50, true)
	_check(news.any(func(n: Dictionary) -> bool: return n["key"] == "NEWS_TRANSFER" and "Test Town FC" in (n["args"] as Array)), "the sale is in the news with the external club's name")
	var data2 := c.to_dict()
	var c3 := CareerState.from_dict(db, data2)
	_check(c3.market.abroad.has(p.id) and c3.market.club_name(o.from_club) == "Test Town FC", "externals and abroad players survive save and load")
	# a v2 save written before this round (no external clubs, no listing dates) still loads
	var old_save := c.to_dict()
	var mk: Dictionary = old_save["market"]
	for k in ["externals", "abroad", "next_external_id"]:
		mk.erase(k)
	for pid in (mk["listings"] as Dictionary):
		(mk["listings"][pid] as Dictionary).erase("since")
	var c4 := CareerState.from_dict(db, old_save)
	_check(c4 != null and c4.market.externals.is_empty() and c4.market.abroad.is_empty() and c4.market.history.size() == c.market.history.size(),
			"a transfers-v2 save without external clubs still loads")
	_check(_ledgers_ok(c), "ledgers stay consistent after the external sale")
	var audit := CareerValidator.validate(c, false)
	_check((audit["errors"] as Array).is_empty(), "the career passes the integrity audit", str((audit["errors"] as Array).slice(0, 3)))
	# a counter-offer: within the limit it is accepted, far above it the club walks away or meets halfway
	var q: PlayerData = _fringe_players(c, club, 1)[0]
	var o2: TransferOffer = m.make_external_offer(q.id, "Counter FC", "Poland", int(m.market_value(q) * 0.7))["offer"]
	_check(m.answer_incoming(o2.id, "counter", {"fee": int(m.asking_price(q) * 3)}) == "" and o2.status in [TransferOffer.PENDING, TransferOffer.WITHDRAWN],
			"an external club does not pay three times the price", o2.status)


## The role a signing is promised follows his real place in the buying club (rank at his position with him counted in,
## compared with the club's level), and the player's answer rewards a fitting promise and punishes a lower one.
func _test_roles() -> void:
	var m := TransferMarket.new(db, {})
	var found := {}
	var teams: Array = db.list_teams(TeamData.Category.CLUB)
	for t: TeamData in teams:
		var level := db.get_team_rating(t.id)
		for p: PlayerData in db.players.values():
			if p.team_id == t.id or p.team_id == "" or p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED:
				continue
			var r := m.squad_rank(p, t.id)
			var ov := p.get_overall()
			var slots := 2 if p.position in [PlayerData.Position.CB, PlayerData.Position.CM] else 1
			var key := ""
			if int(r["pos"]) == 0 and ov >= level + 2:
				key = "star"
			elif int(r["pos"]) == 0 and ov < level - 1 and ov >= level - 8:
				key = "starter"
			elif int(r["pos"]) >= slots + 1 and ov <= level - 12 and p.age >= 22:
				key = "backup"
			elif p.age <= 19 and ov <= level - 12 and int(r["pos"]) >= slots + 1:
				key = "prospect"
			if key != "" and not found.has(key):
				found[key] = [p, t.id, level]
	print("  role table: %s" % str(found.keys()))
	var want := {"star": 0, "starter": 1, "backup": 3, "prospect": 4}
	for key in want:
		if not found.has(key):
			_check(false, "(setup) a %s case exists" % key)
			continue
		var p: PlayerData = found[key][0]
		var tid: String = found[key][1]
		var got := m.deserved_role(p, tid)
		_check(got == int(want[key]), "a %s signing (%d to a club of %d) is promised the role '%s'" % [key, p.get_overall(), found[key][2], key],
				ContractOffer.ROLES[got])
		var c := m.default_contract(p, tid)
		_check(c.squad_role == ContractOffer.ROLES[got], "the default contract for the %s case carries that role" % key, c.squad_role)
		_check(m.player_answer(p, tid, c)["status"] == TransferOffer.ACCEPTED, "the player accepts his default contract (%s)" % key)
	# nobody who is better than the club's level and among its first choices at his position is offered a rotation role
	var strong := 0
	var wrong := []
	for t: TeamData in teams:
		var level := db.get_team_rating(t.id)
		for p: PlayerData in db.players.values():
			if p.team_id == t.id or p.team_id == "" or p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED:
				continue
			var slots := 2 if p.position in [PlayerData.Position.CB, PlayerData.Position.CM] else 1
			if p.get_overall() >= level + 2 and int(m.squad_rank(p, t.id)["pos"]) <= slots - 1 + 1:
				strong += 1
				if m.deserved_role(p, t.id) > 1 and wrong.size() < 3:
					wrong.append("%s(%d)->%s" % [p.id, p.get_overall(), t.id])
	_check(strong > 0 and wrong.is_empty(), "a player above the club's level who is a first or second choice is a star or a starter (%d cases)" % strong, str(wrong))
	if found.has("star"):
		var p: PlayerData = found["star"][0]
		var tid: String = found["star"][1]
		var low := ContractOffer.make(m.default_contract(p, tid).salary, 3, "backup")
		var a_low := m.player_answer(p, tid, low)
		_check(a_low["status"] != TransferOffer.ACCEPTED, "a star promised only a backup role does not simply accept", str(a_low["status"]))
		var star_c := m.default_contract(p, tid)
		var other := ContractOffer.make(star_c.salary, star_c.years, "rotation")
		var a_rot := m.player_answer(p, tid, other)
		_check(int((a_rot["demand"] as ContractOffer).salary) >= star_c.salary, "a lower promise costs at least as much wage as the deserved role")
		var starter_wage := m.default_contract(found["starter"][0], found["starter"][1]).salary if found.has("starter") else 0
		_check(star_c.salary >= int(m.fair_wage(p) * 1.25 * 0.95) or star_c.salary >= starter_wage, "a star's proposed wage reflects the star role")
