extends HubScreen

## Transfer Market: search players, buy, and sell/loan your own players to
## other clubs. Offers use the asking price and a fair contract; every rule
## (budget, wages, squad size) is enforced by `TransferMarket`.

var _position := 0          # 0 = any
var _max_price := 0
var _partner := 0


func build() -> void:
	if not header(Loc.t("MARKET_TRANSFER_MARKET"), true, true):
		return
	var career: CareerState = app().career
	var market: TransferMarket = career.market
	var ledger := career.ledger()
	add_child(UIKit.label(Loc.f("MARKET_BALANCE_TRANSFER_BUDGET_WAGE_ROOM", [ledger.balance,
			ledger.transfer_budget, ledger.wage_budget - market.weekly_wages(career.club_id)]), 16))
	var filt := UIKit.hbox(8)
	filt.add_child(UIKit.label(Loc.t("MARKET_POSITION"), 14, UIKit.MUTED))
	var po := UIKit.option([Loc.t("MARKET_ANY")] + PlayerData.Position.keys(), _position, func(i: int) -> void:
		_position = i
		rebuild())
	po.name = "PositionOption"
	filt.add_child(po)
	filt.add_child(UIKit.label(Loc.t("MARKET_MAX_PRICE_0_ANY"), 14, UIKit.MUTED))
	var mp := SpinBox.new()
	mp.min_value = 0
	mp.max_value = 500000000
	mp.step = 100000
	mp.value = _max_price
	mp.custom_minimum_size = Vector2(150, 0)
	mp.value_changed.connect(func(v: float) -> void: _max_price = int(v))
	filt.add_child(mp)
	filt.add_child(UIKit.button(Loc.t("MARKET_SEARCH"), rebuild, 90))
	add_child(filt)
	var filters := {"exclude_team": career.club_id}
	if _position > 0:
		filters["position"] = _position - 1
	if _max_price > 0:
		filters["max_price"] = _max_price
	var results: Array = market.search(filters).slice(0, 25)
	add_child(UIKit.label(Loc.t("MARKET_AVAILABLE_PLAYERS"), 16, UIKit.GOLD))
	if results.is_empty():
		add_child(UIKit.empty_state(Loc.t("MARKET_NO_PLAYERS_MATCH_YOUR_SEARCH")))
	for p: PlayerData in results:
		var row := UIKit.hbox(8)
		var club: TeamData = db().get_team(p.team_id)
		row.add_child(UIKit.crest(db(), club, 22))
		row.add_child(UIKit.label("%s · %s · %d · %s · %s" % [p.display_name, PlayerData.Position.keys()[p.position], p.age,
				overall_text(p), club.short_name if club != null else "free"], 15))
		row.add_child(UIKit.label(Loc.f("MARKET_PRICE", (market.asking_price(p) if club != null else 0)), 14, UIKit.GOLD))
		row.add_child(UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": p.id}), 70))
		var buy := UIKit.button(Loc.t("MARKET_BUY"), _buy.bind(p.id), 60)
		buy.name = "Buy_%s" % p.id
		row.add_child(buy)
		add_child(row)
	# Own players: sell / loan
	add_child(UIKit.label(Loc.t("MARKET_YOUR_PLAYERS"), 16, UIKit.GOLD))
	var clubs: Array = db().list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.id != career.club_id)
	var partner_row := UIKit.hbox(8)
	partner_row.add_child(UIKit.label(Loc.t("MARKET_PARTNER_CLUB"), 14, UIKit.MUTED))
	partner_row.add_child(UIKit.option(clubs.map(func(t: TeamData) -> String: return t.display_name), _partner,
			func(i: int) -> void: _partner = i))
	add_child(partner_row)
	for p: PlayerData in db().get_squad(career.club_id):
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(Loc.f("MARKET_WAGE_YR", [p.display_name, PlayerData.Position.keys()[p.position],
				overall_text(p), p.salary, p.contract_years, Loc.t("MARKET_LOAN_SUFFIX") if p.loan_parent != "" else ""]), 15))
		if p.loan_parent == "" and not clubs.is_empty():
			var sell := UIKit.button(Loc.t("MARKET_SELL"), _sell.bind(p.id, clubs), 60)
			sell.name = "Sell_%s" % p.id
			row.add_child(sell)
			row.add_child(UIKit.button(Loc.t("MARKET_LOAN_OUT"), _loan.bind(p.id, clubs), 90))
			row.add_child(UIKit.button(Loc.t("MARKET_RENEW"), _renew.bind(p.id), 70))
		add_child(row)
	add_child(UIKit.label(Loc.t("MARKET_TRANSFER_HISTORY"), 16, UIKit.GOLD))
	if market.history.is_empty():
		add_child(UIKit.muted(Loc.t("MARKET_NO_TRANSFERS_YET")))
	for h in market.history.slice(-8):
		var pl: PlayerData = db().get_player(h["player_id"])
		add_child(UIKit.muted(Loc.f("MARKET_WEEK_FEE", [h["week"], h["kind"], pl.display_name if pl != null else "?", h["to"], h["fee"]])))


func _buy(pid: String) -> void:
	var career: CareerState = app().career
	var p: PlayerData = db().get_player(pid)
	var fee := career.market.asking_price(p) if p.team_id != "" else 0
	var wage := maxi(career.market.minimum_wage(p), int(p.salary * 1.05))
	var err := career.market.buy(career.club_id, pid, fee, wage, 3, career.week, app().squads)
	say(Loc.f("MARKET_SIGNED_FOR", [p.display_name, fee]) if err == "" else err, err != "")
	rebuild()


func _sell(pid: String, clubs: Array) -> void:
	var career: CareerState = app().career
	var buyer: TeamData = clubs[clampi(_partner, 0, clubs.size() - 1)]
	var p: PlayerData = db().get_player(pid)
	var fee := career.market.asking_price(p)
	var err := career.market.sell(career.club_id, pid, buyer.id, fee, maxi(career.market.minimum_wage(p), p.salary), 3, career.week, app().squads)
	say(Loc.f("MARKET_SOLD_TO_FOR", [p.display_name, buyer.display_name, fee]) if err == "" else err, err != "")
	rebuild()


func _loan(pid: String, clubs: Array) -> void:
	var career: CareerState = app().career
	var borrower: TeamData = clubs[clampi(_partner, 0, clubs.size() - 1)]
	var err := career.market.loan(borrower.id, pid, 26, 0, career.week, app().squads)
	say(Loc.f("MARKET_LOANED_OUT_TO", borrower.display_name) if err == "" else err, err != "")
	rebuild()


func _renew(pid: String) -> void:
	var career: CareerState = app().career
	var p: PlayerData = db().get_player(pid)
	var err := career.market.renew_contract(career.club_id, pid, int(p.salary * 1.1) + 1, 3, career.week)
	say(Loc.t("MARKET_CONTRACT_RENEWED") if err == "" else err, err != "")
	rebuild()
