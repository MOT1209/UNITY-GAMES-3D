class_name AITransfers
extends RefCounted

## Transfer activity of the AI clubs during the transfer windows (Phase 6/7). Every deal goes through
## `TransferMarket.buy`, so every budget, wage, squad-size and contract rule applies to the AI exactly as it does to the user.
## Windows: weeks 1-6 and 24-29 of the season, at most MAX_DEALS_PER_WEEK deals per week in the whole world.
## The user's club is never touched (the user decides about their own players).
## Deterministic: the order of clubs and the choices depend only on the season, the week and the data.

const WINDOWS: Array = [[1, 6], [24, 29]]
const MAX_DEALS_PER_WEEK := 4
const BUDGET_SHARE := 0.6                  # an AI club spends at most 60 % of its transfer budget on one player
const MIN_UPGRADE := 3                     # the target must be this much better than the club's median player


static func in_window(week: int) -> bool:
	for w in WINDOWS:
		if week >= int(w[0]) and week <= int(w[1]):
			return true
	return false


## Runs one week. Returns the list of deals made: {player_id, from, to, fee}.
static func run_week(career: CareerState, squads: Dictionary = {}) -> Array:
	var deals: Array = []
	if not in_window(career.week):
		return deals
	var db: Node = career.db
	var rng := RandomNumberGenerator.new()
	rng.seed = career.season * 1000 + career.week
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
		var deal := _try_deal(career, buyer_id, squads)
		if not deal.is_empty():
			deals.append(deal)
	return deals


static func _try_deal(career: CareerState, buyer_id: String, squads: Dictionary) -> Dictionary:
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
	var candidates := market.search({"exclude_team": buyer_id, "min_overall": median + MIN_UPGRADE, "max_price": budget})
	for p in candidates:
		if p.team_id == career.club_id:
			continue                                          # never the user's players
		var seller: TeamData = db.get_team(p.team_id) if p.team_id != "" else null
		var fee := market.asking_price(p) if seller != null else 0
		var wage := maxi(market.minimum_wage(p), p.salary)
		var from_id := p.team_id
		if market.buy(buyer_id, p.id, fee, wage, 3, career.week, squads) == "":
			return {"player_id": p.id, "from": from_id, "to": buyer_id, "fee": fee}
	return {}
