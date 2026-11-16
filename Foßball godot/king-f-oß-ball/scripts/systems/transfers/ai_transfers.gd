class_name AITransfers
extends RefCounted

## Transfer activity of the AI clubs during the transfer windows (Phase 6/7). Every deal goes through
## `TransferMarket.buy`, so every budget, wage, squad-size and contract rule applies to the AI exactly as it does to the user.
## Windows: weeks 1-6 and 24-29 of the season, at most MAX_DEALS_PER_WEEK deals per week in the whole world.
## The user's club is never touched (the user decides about their own players): AI clubs only make OFFERS for the user's
## players (`offers_to_user`), which the user accepts, counters or rejects.
## Deterministic: the order of clubs and the choices depend only on the season, the week and the data.

const WINDOWS: Array = TransferMarket.WINDOWS
const MAX_DEALS_PER_WEEK := 4
const BUDGET_SHARE := 0.6                  # an AI club spends at most 60 % of its transfer budget on one player
const SMALL_WORLD_CLUBS := 12
const SMALL_WORLD_UPGRADE := -2
## A small world tops AI transfer budgets up to this share of the balance when the winter window opens too (the season
## end does the same): with one top-up a year the budgets ran dry and trading faded from season to season.
const SMALL_WORLD_TOP_UP := 0.05
const MIN_UPGRADE := 3                     # the target must be this much better than the club's median player


static func in_window(week: int) -> bool:
	return TransferMarket.window_open(week)


## Runs one week. Returns the list of deals made: {player_id, from, to, fee}.
static func run_week(career: CareerState, squads: Dictionary = {}) -> Array:
	var deals: Array = []
	if not in_window(career.week):
		return deals
	var db: Node = career.db
	var market := career.market
	var rng := RandomNumberGenerator.new()
	rng.seed = career.season * 1000 + career.week

	# Build the sellable pool ONCE for the whole week, sorted by overall
	# (best first). Rebuilding it for every buyer used to re-scan all 8000+
	# players and re-sort them up to 300 times per week - about 10 s/week.
	# The pool is shared; each buyer only filters it by its own thresholds.
	var pool: Array = _build_pool(db, career.club_id)
	if career.week == int(WINDOWS[0][0]) or career.week == int(WINDOWS[1][0]):
		update_listings(career)
	if career.week == int(WINDOWS[1][0]) and db.teams.size() <= SMALL_WORLD_CLUBS:
		top_up_budgets(career)

	var clubs: Array = []
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != career.club_id and career.ledgers.has(t.id):
			clubs.append(t.id)
	clubs.sort()
	for i in range(clubs.size() - 1, 0, -1):           # deterministic shuffle
		var j := rng.randi_range(0, i)
		var tmp = clubs[i]
		clubs[i] = clubs[j]
		clubs[j] = tmp
	for buyer_id in clubs:
		if deals.size() >= MAX_DEALS_PER_WEEK:
			break
		var deal := _try_deal(career, buyer_id, squads, pool)
		if not deal.is_empty():
			deals.append(deal)
	return deals


## Sellable players, best overall first (ties by id). The order is packed into integer keys and sorted natively:
## (overall << 20) | (0xFFFFF - rank of the id) sorts exactly like "overall descending, then id ascending".
static func _build_pool(db: Node, user_club: String) -> Array:
	var ids: Array = db.players.keys()
	ids.sort()
	if ids.size() >= 0xFFFFF:
		return _build_pool_slow(db, user_club)
	var keys := PackedInt64Array()
	for rank in ids.size():
		var p: PlayerData = db.players[ids[rank]]
		if p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED:
			continue
		if p.loan_parent != "" or p.team_id == user_club:
			continue
		keys.append((p.get_overall() << 20) | (0xFFFFF - rank))
	keys.sort()
	var pool: Array = []
	for i in range(keys.size() - 1, -1, -1):
		var p: PlayerData = db.players[ids[0xFFFFF - (keys[i] & 0xFFFFF)]]
		pool.append({"p": p, "ov": keys[i] >> 20})
	return pool


static func _build_pool_slow(db: Node, user_club: String) -> Array:
	var pool: Array = []
	for p: PlayerData in db.players.values():
		if p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED or p.loan_parent != "" or p.team_id == user_club:
			continue
		pool.append({"p": p, "ov": p.get_overall()})
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ov"] != b["ov"]:
			return a["ov"] > b["ov"]
		return a["p"].id < b["p"].id)
	return pool


## Asking price of a pool entry, computed on first use (most of the pool is never a candidate in a week).
static func _price(market: TransferMarket, entry: Dictionary) -> int:
	if not entry.has("price"):
		entry["price"] = market.asking_price(entry["p"])
	return int(entry["price"])


static func _try_deal(career: CareerState, buyer_id: String, squads: Dictionary, pool: Array) -> Dictionary:
	var db: Node = career.db
	var market := career.market
	var ledger: FinanceLedger = career.ledgers[buyer_id]
	var team: TeamData = db.get_team(buyer_id)
	if team.squad_ids.size() >= TransferMarket.MAX_SQUAD - 1:
		return {}
	var overalls: Array = db.get_squad(buyer_id).map(func(p: PlayerData) -> int: return p.get_overall())
	if overalls.is_empty():
		return {}
	overalls.sort()
	var median: int = overalls[overalls.size() / 2]
	var budget := int(ledger.transfer_budget * BUDGET_SHARE)
	if budget <= 0:
		return {}
	# A small world (the 8-club fictional one) has no better players left to buy after one window: there a club also
	# buys a player as good as its median, so the market keeps moving (stagnation found by the 5-season balance test).
	var small_world: bool = db.teams.size() <= SMALL_WORLD_CLUBS
	var min_overall := median + (SMALL_WORLD_UPGRADE if small_world else MIN_UPGRADE)

	# The pool is sorted by overall (best first), so we stop as soon as the
	# overall drops below the threshold: nothing later can qualify.
	var candidates: Array = []
	for entry in pool:
		var p: PlayerData = entry["p"]
		if p.team_id == buyer_id:
			continue
		if int(entry["ov"]) < min_overall:
			break
		if _price(market, entry) > budget:
			continue
		candidates.append(entry)
	for entry in candidates:
		var p: PlayerData = entry["p"]
		if p.team_id == career.club_id:
			continue                                          # never the user's players
		var wage := maxi(market.minimum_wage(p), p.salary)
		var from_id := p.team_id
		if from_id == "":
			if market.buy(buyer_id, p.id, 0, wage, 3, career.week, squads) == "":
				return {"player_id": p.id, "from": from_id, "to": buyer_id, "fee": 0}
			continue
		# the same seller rules as for the user: refusals (untouchable, just signed, key loan player...) and its price
		if market.refusal(p, buyer_id, false) != "":
			continue
		var fee := market.seller_price(p)
		if fee > budget:
			continue
		if market._transfer(buyer_id, p.id, fee, wage, 3, career.week, squads, false) == "":
			return {"player_id": p.id, "from": from_id, "to": buyer_id, "fee": fee}
	return {}


# --- listings, offers and loan requests -----------------------------------------------------------------------------

const MAX_LOAN_LISTED_PER_CLUB := 2
const MAX_SALE_LISTED_PER_CLUB := 2


## At the start of each window every AI club lists its surplus: young fringe players for loan, older backups for sale.
static func update_listings(career: CareerState) -> void:
	var market := career.market
	var db: Node = career.db
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id == career.club_id:
			continue
		var squad: Array = db.get_squad(t.id)
		var by_pos := {}
		for p in squad:
			(by_pos.get_or_add(p.position, []) as Array).append(p)
		var loanees := 0
		var sales := 0
		for pos in by_pos:
			var group: Array = by_pos[pos]
			group.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
				return a.get_overall() > b.get_overall() or (a.get_overall() == b.get_overall() and a.id < b.id))
			for i in range(2, group.size()):
				var p: PlayerData = group[i]
				if p.loan_parent != "" or market.listing_of(p.id) != TransferMarket.LISTING_NONE:
					continue
				if p.age <= 22 and loanees < MAX_LOAN_LISTED_PER_CLUB:
					market.set_listing(t.id, p.id, TransferMarket.LISTING_LOAN, {"loan_min_split": 50})
					loanees += 1
				elif p.age >= 29 and sales < MAX_SALE_LISTED_PER_CLUB:
					market.set_listing(t.id, p.id, TransferMarket.LISTING_TRANSFER,
							{"price": Valuation.round_value(market.market_value(p) * 0.9)})
					sales += 1


## AI clubs make offers for the user's players during a window (at most MAX_INCOMING_PER_WEEK per week): first for the
## players the user listed (close to the listing price), sometimes for others the club needs (above the value), loan
## requests for young players who rarely play. Never for an untouchable player, unless a club pays his release clause.
static func offers_to_user(career: CareerState, squads: Dictionary = {}) -> Array:
	var made: Array = []
	var market := career.market
	var db: Node = career.db
	if not in_window(career.week) or career.manager.unemployed or db.get_team(career.club_id) == null:
		return made
	var rng := RandomNumberGenerator.new()
	rng.seed = career.season * 7919 + career.week * 131 + 17
	var now := market.abs_week()
	var already := 0
	for o: TransferOffer in market.offers:
		if o.to_club == career.club_id and o.created_week == now and o.from_club != career.club_id:
			already += 1
	var budget_left := TransferMarket.MAX_INCOMING_PER_WEEK - already
	if budget_left <= 0:
		return made
	var buyers: Array = []
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != career.club_id and career.ledgers.has(t.id):
			buyers.append(t)
	buyers.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.id < b.id)
	var mine: Array = db.get_squad(career.club_id)
	mine.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.id < b.id)
	var plans: Array = []                  # [player, kind] in priority order
	for p: PlayerData in mine:
		if p.loan_parent != "" or market.listing_of(p.id) == TransferMarket.LISTING_UNTOUCHABLE:
			continue
		if market.is_transfer_listed(p.id) and rng.randf() < 0.75:
			plans.append([p, "listed"])
	for p: PlayerData in mine:
		if p.loan_parent == "" and market.is_loan_listed(p.id) and rng.randf() < 0.5:
			plans.append([p, "loan"])
	for p: PlayerData in mine:
		if p.loan_parent != "" or market.listing_of(p.id) != TransferMarket.LISTING_NONE:
			continue
		if p.age <= 21 and is_fringe_youngster(career, p, squads) and rng.randf() < 0.12:
			plans.append([p, "loan"])
		elif p.get_overall() >= 60 and rng.randf() < 0.06:
			plans.append([p, "approach"])
	if rng.randf() < 0.05:                 # a release clause may be paid even for an untouchable player
		for p: PlayerData in mine:
			if market.release_clause(p.id) > 0 and p.loan_parent == "":
				plans.append([p, "clause"])
				break
	for plan in plans:
		if made.size() >= budget_left:
			break
		var p: PlayerData = plan[0]
		var kind: String = plan[1]
		if market.refusal(p, "", kind == "loan", market.release_clause(p.id) if kind == "clause" else 0) not in ["", "OFFER_REASON_OWN_PLAYER"]:
			continue
		var ask := _listed_ask(career, p) if kind == "listed" else market.asking_price(p)
		var buyer := _pick_buyer(career, buyers, p, kind, rng, ask)
		if buyer == "":
			if kind == "listed":
				var ext := _external_offer(career, p, ask, rng)
				if ext != null:
					made.append(ext)
			continue
		var terms := {}
		var type := TransferOffer.PERMANENT
		match kind:
			"listed":
				terms["fee"] = Valuation.round_value(ask * rng.randf_range(0.9, 1.0))
			"approach":
				terms["fee"] = Valuation.round_value(market.seller_price(p) * rng.randf_range(1.1, 1.3))
			"clause":
				terms["fee"] = market.release_clause(p.id)
			"loan":
				type = TransferOffer.LOAN
				terms["loan_weeks"] = TransferMarket.weeks_to_season_end(career.week) if rng.randf() < 0.6 \
						else TransferMarket.weeks_to_next_window(career.week)
				terms["wage_split_percent"] = [50, 60, 75, 100][rng.randi_range(0, 3)]
				terms["min_play_percent"] = 50 if rng.randf() < 0.5 else 0
		var res := market.make_offer(buyer, p.id, type, terms)
		if res["error"] != "":
			continue
		var o: TransferOffer = res["offer"]
		if kind == "clause":
			o.via_release_clause = true
			o.status = TransferOffer.ACCEPTED
			market.propose_contract(o.id, market.default_contract(p, buyer))
		made.append(o)
	return made


## Offers for a listed player come at a realistic price: when nobody has bid for 3 weeks and the asking price is well above
## his value, the bids follow the value, and the user is told that nobody is interested at this price.
static func _listed_ask(career: CareerState, p: PlayerData) -> int:
	var market := career.market
	var ask := market.asking_price(p)
	var value := market.market_value(p)
	if ask > value * 1.05 and market.weeks_listed(p.id) >= 3 \
			and market.offers_for(p.id, market.abs_week() - 3) == 0:
		if career.week % 3 == 0:
			market.note("NOTE_LISTING_NO_INTEREST", [p.id])
		return maxi(int(value * 1.05), 1000)
	return ask


## The weekly chance that a club from outside the loaded leagues bids for a listed player: 35 %, rising 10 points for each
## week he has been listed without an offer.
static func external_chance(career: CareerState, p: PlayerData) -> float:
	var market := career.market
	var quiet := maxi(0, market.weeks_listed(p.id) - 1) if market.offers_for(p.id, market.abs_week() - 3) == 0 else 0
	return clampf(EXTERNAL_BASE_CHANCE + 0.1 * quiet, 0.0, 0.85)


const EXTERNAL_BASE_CHANCE := 0.35
const EXTERNAL_MIN := 0.70
const EXTERNAL_MAX := 0.95
const EXTERNAL_CITIES: Array[String] = ["Almeria", "Varna", "Porto Alto", "Kassel", "Lund", "Tbilisi", "Split", "Izmir", "Genk",
		"Bursa", "Rijeka", "Krakow", "Aarhus", "Lyon Sud", "Ankara", "Brno", "Graz", "Cluj", "Haifa Bay", "Odense", "Belgrade East",
		"Plovdiv", "Torino Nord", "Seville Sur", "Lisbon West", "Malmo", "Antwerp", "Thessaly", "Riga", "Bergen"]
const EXTERNAL_SUFFIXES: Array[String] = ["FC", "United", "Athletic", "Sporting", "City", "Rovers", "Town", "SK"]
const EXTERNAL_COUNTRIES: Array[String] = ["Spain", "Bulgaria", "Portugal", "Germany", "Sweden", "Georgia", "Croatia", "Turkey",
		"Belgium", "Poland", "Denmark", "France", "Czechia", "Austria", "Romania", "Greece", "Latvia", "Norway", "Serbia", "Netherlands"]


## A bid from a club outside the loaded leagues (70-95 % of the price). It makes sure a listed player always has a market,
## also in a small fictional world where every club is stronger than he is.
static func _external_offer(career: CareerState, p: PlayerData, ask: int, rng: RandomNumberGenerator) -> TransferOffer:
	if rng.randf() >= external_chance(career, p):
		return null
	var city := EXTERNAL_CITIES[rng.randi_range(0, EXTERNAL_CITIES.size() - 1)]
	var name := "%s %s" % [city, EXTERNAL_SUFFIXES[rng.randi_range(0, EXTERNAL_SUFFIXES.size() - 1)]]
	var country := EXTERNAL_COUNTRIES[rng.randi_range(0, EXTERNAL_COUNTRIES.size() - 1)]
	var fee := Valuation.round_value(ask * rng.randf_range(EXTERNAL_MIN, EXTERNAL_MAX))
	var res := career.market.make_external_offer(p.id, name, country, fee)
	return res["offer"] if res["error"] == "" else null


const STATS_WEEK := 8                     # from this week on the real share of matches played decides a loan request
const FRINGE_PLAYING_SHARE := 0.30


## A youngster the club would loan out: not in the starting XI, not the captain or a set-piece taker, only the third (or a
## lower) choice at his position, and from week 8 on one who really played less than 30 % of the team's matches.
static func is_fringe_youngster(career: CareerState, p: PlayerData, squads: Dictionary = {}) -> bool:
	var market := career.market
	var sq: Variant = squads.get(p.team_id)
	if sq != null:
		var s: Squad = sq
		if p.id in s.starting or p.id == s.captain_id:
			return false
		for k in s.set_pieces:
			if s.set_pieces[k] == p.id:
				return false
	var r := market.squad_rank(p)
	if sq == null and int(r["all"]) < 11:
		return false                           # no lineup known: a top-11 player is never a fringe player
	if int(r["pos"]) < 2:
		return false
	if career.week >= STATS_WEEK:
		var apps := int((career.world_stats.get(p.id, {}) as Dictionary).get("apps", 0))
		return float(apps) < FRINGE_PLAYING_SHARE * career.week
	return true


## A club that can afford the deal and has room. For a permanent move the player is an upgrade (within 2 points of the
## club's level); a listed player is also wanted by a club that NEEDS his position (thin cover, or a worse player there),
## even when he is up to 10 points below its level.
static func _pick_buyer(career: CareerState, buyers: Array, p: PlayerData, kind: String, rng: RandomNumberGenerator, ask := 0) -> String:
	var market := career.market
	var db: Node = career.db
	var start := rng.randi_range(0, maxi(0, buyers.size() - 1))
	var fee := ask if ask > 0 and kind == "listed" else (market.asking_price(p) if kind == "listed" else (market.release_clause(p.id) if kind == "clause" else market.seller_price(p)))
	var user_rep: int = db.get_team(career.club_id).reputation
	for k in buyers.size():
		var t: TeamData = buyers[(start + k) % buyers.size()]
		if t.squad_ids.size() >= TransferMarket.MAX_SQUAD - 1:
			continue
		if market.offers.any(func(o: TransferOffer) -> bool: return o.is_open() and o.from_club == t.id and o.player_id == p.id):
			continue
		var ledger: FinanceLedger = career.ledgers[t.id]
		if kind == "loan":
			if t.reputation > user_rep or market.loans_in(t.id) >= TransferMarket.MAX_LOANS_IN:
				continue
			return t.id
		if fee > ledger.transfer_budget * 0.8 or not ledger.can_afford(-fee, "transfer_in"):
			continue
		if market.weekly_wages(t.id) + p.salary > ledger.wage_budget:
			continue
		var level: int = career.club_levels.get(t.id, 60)
		if p.get_overall() + 2 >= level:
			return t.id
		if kind == "listed" and p.get_overall() + LISTED_NEED_SLACK >= level and _needs_position(market, p, t.id):
			return t.id
	return ""


const LISTED_NEED_SLACK := 10


## Does `team_id` need this player's position: thin cover (at most two players there) or he would be one of its best two.
static func _needs_position(market: TransferMarket, p: PlayerData, team_id: String) -> bool:
	var r := market.squad_rank(p, team_id)
	return int(r["same"]) <= 2 or int(r["pos"]) <= 1


## Winter-window top-up of the AI clubs' transfer budgets in a small world (never lowers a budget).
static func top_up_budgets(career: CareerState) -> void:
	for tid in career.ledgers:
		if tid != career.club_id:
			var l: FinanceLedger = career.ledgers[tid]
			l.transfer_budget = maxi(l.transfer_budget, int(maxi(l.balance, 0) * SMALL_WORLD_TOP_UP))
