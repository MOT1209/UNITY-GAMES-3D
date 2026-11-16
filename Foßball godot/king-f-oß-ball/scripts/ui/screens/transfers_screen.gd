extends HubScreen

## Transfer Market (transfers v2). Tabs: Search · Shortlist · Offers (count of new ones) · My players on the market ·
## Loans · History, under a fixed bar with balance, transfer budget (with commitments), wage room and the window.
## Every deal goes through `TransferMarket` offers (NegotiationDialog / ContractDialog): nothing is bought directly.

const TABS: Array[String] = ["search", "shortlist", "offers", "mine", "loans", "history"]
const PAGE_SIZE := 50
const SORTS: Array[String] = ["need", "overall", "potential", "price", "age", "value_ratio"]
## Position choices of the filter: "any", the twelve positions, then the three lines.
const LINES := {"DEF": [PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB],
		"MID": [PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM, PlayerData.Position.RM],
		"ATT": [PlayerData.Position.LW, PlayerData.Position.RW, PlayerData.Position.ST]}

## Search state survives a visit to a player profile (static: one market screen at a time).
static var _f: Dictionary = {}
static var _sort := "need"
static var _page := 0
static var _cards := false
static var _filters_open := 0           # the filters fold out on demand: the results come first

var _tab := "search"


func build() -> void:
	if not header(Loc.t("MARKET_TRANSFER_MARKET"), true, true):
		return
	if params.has("tab") and str(params["tab"]) in TABS and not has_meta("tab_set"):
		_tab = str(params["tab"])
		set_meta("tab_set", true)
	var career: CareerState = app().career
	var market: TransferMarket = career.market
	add_child(_top_bar(career, market))
	add_child(_tab_bar(market))
	match _tab:
		"search":
			_search_tab(career, market)
		"shortlist":
			_shortlist_tab(career, market)
		"offers":
			_offers_tab(career, market)
		"mine":
			_mine_tab(career, market)
		"loans":
			_loans_tab(career, market)
		"history":
			_history_tab(career, market)


# --- top bar / tabs ------------------------------------------------------------------------------------------------

func _top_bar(career: CareerState, market: TransferMarket) -> Control:
	var l := career.ledger()
	var com := market.commitments(career.club_id)
	var flow := HFlowContainer.new()
	flow.name = "MarketTopBar"
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 6)
	flow.add_child(_fact(Loc.t("MKT_BALANCE"), Loc.money(l.balance), UIKit.BAD if l.balance < 0 else UIKit.TEXT))
	var tb := Loc.money(l.transfer_budget)
	if int(com["pay"]) + int(com["obligations"]) > 0:
		tb += "  " + Loc.f("MKT_COMMITTED", Loc.money(int(com["pay"]) + int(com["obligations"])))
	flow.add_child(_fact(Loc.t("MKT_TRANSFER_BUDGET"), tb, UIKit.GOLD))
	flow.add_child(_fact(Loc.t("MKT_WAGE_ROOM"), Loc.f("MKT_PER_WEEK", Loc.money(l.wage_budget - market.wage_bill(career.club_id))), UIKit.TEXT))
	var open := TransferMarket.window_open(career.week)
	flow.add_child(_fact(Loc.t("MKT_WINDOW"), MarketUI.window_text(career.week), UIKit.GOOD if open else UIKit.MUTED))
	return UIKit.panel(flow)


func _fact(title: String, value: String, color: Color) -> Control:
	var v := UIKit.vbox(0)
	v.add_child(UIKit.label(title, 12, UIKit.MUTED))
	var val := UIKit.label(value, 16, color)
	val.text_direction = Control.TEXT_DIRECTION_AUTO
	v.add_child(val)
	return v


func _tab_bar(market: TransferMarket) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "MarketTabs"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for id in TABS:
		var text := Loc.t("MKT_TAB_" + id.to_upper())
		if id == "offers":
			var n := market.needs_user_action()
			if n > 0:
				text += " (%s)" % Loc.num(n)
		elif id == "shortlist" and not market.shortlist.is_empty():
			text += " (%s)" % Loc.num(market.shortlist.size())
		var b := UIKit.button(text, _set_tab.bind(id), 0)
		b.name = "Tab_%s" % id
		b.toggle_mode = true
		b.button_pressed = id == _tab
		b.custom_minimum_size = Vector2(0, 40)
		if id == "offers" and market.needs_user_action() > 0:
			b.add_theme_color_override("font_color", UIKit.BAD.lightened(0.2))
		flow.add_child(b)
	return flow


func _set_tab(id: String) -> void:
	_tab = id
	rebuild()


# --- search --------------------------------------------------------------------------------------------------------

func _search_tab(career: CareerState, market: TransferMarket) -> void:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	var name_edit := LineEdit.new()
	name_edit.name = "NameFilter"
	name_edit.placeholder_text = Loc.t("MKT_SEARCH_NAME")
	name_edit.text = str(_f.get("name", ""))
	name_edit.custom_minimum_size = Vector2(200, 40)
	name_edit.text_submitted.connect(func(t: String) -> void:
		_f["name"] = t
		_page = 0
		rebuild())
	bar.add_child(name_edit)
	var pos_items: Array = [Loc.t("MARKET_ANY")]
	for i in PlayerData.Position.size():
		pos_items.append(Loc.position_code(i))
	for k in LINES:
		pos_items.append(Loc.t("MKT_LINE_" + k))
	var po := UIKit.option(pos_items, int(_f.get("pos_index", 0)), func(i: int) -> void:
		_f["pos_index"] = i
		_page = 0
		rebuild())
	po.name = "PositionOption"
	bar.add_child(po)
	var sort := UIKit.option(SORTS.map(func(s: String) -> String: return Loc.t("MKT_SORT_" + s.to_upper())), maxi(0, SORTS.find(_sort)),
			func(i: int) -> void:
				_sort = SORTS[i]
				_page = 0
				rebuild())
	sort.name = "SortOption"
	bar.add_child(sort)
	bar.add_child(UIKit.button(Loc.t("MARKET_SEARCH"), func() -> void:
		_f["name"] = name_edit.text
		_page = 0
		rebuild(), 90))
	var tog := UIKit.button(Loc.t("MKT_FILTERS") + (" ▴" if _filters_open == 1 else " ▾"), func() -> void:
		_filters_open = 0 if _filters_open == 1 else 1
		rebuild(), 120)
	tog.name = "FiltersToggle"
	bar.add_child(tog)
	bar.add_child(UIKit.button(Loc.t("MKT_VIEW_CARDS") if not _cards else Loc.t("MKT_VIEW_TABLE"), func() -> void:
		_cards = not _cards
		rebuild(), 110))
	bar.add_child(UIKit.button(Loc.t("MKT_RESET_FILTERS"), func() -> void:
		_f = {}
		_page = 0
		rebuild(), 110))
	add_child(bar)
	if _filters_open == 1:
		add_child(_filter_panel(market))
	add_child(_saved_searches_row(market))
	var filters := _filters_dict(career)
	var found: Array = market.search_v2(filters)
	if _sort == "need":
		found = by_team_need(found, app().squad(), db())
	var pages := maxi(1, ceili(found.size() / float(PAGE_SIZE)))
	_page = clampi(_page, 0, pages - 1)
	var results: Array = found.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE)
	add_child(UIKit.label(Loc.t("MARKET_AVAILABLE_PLAYERS"), 16, UIKit.GOLD))
	add_child(UIKit.muted(Loc.f("MKT_RESULTS", [found.size()]) + ("  ·  " + Loc.t("MARKET_SORTED_BY_NEED") if _sort == "need" else "")))
	if results.is_empty():
		add_child(UIKit.empty_state(Loc.t("MARKET_NO_PLAYERS_MATCH_YOUR_SEARCH")))
	elif _cards:
		add_child(_card_grid(results, market))
	else:
		add_child(_market_table(results, market))
	if pages > 1:
		var nav := UIKit.hbox(8)
		var prev := UIKit.button(Loc.t("MKT_PREV"), func() -> void:
			_page -= 1
			rebuild(), 90)
		prev.disabled = _page == 0
		nav.add_child(prev)
		nav.add_child(UIKit.label(Loc.f("MKT_PAGE", [_page + 1, pages]), 14, UIKit.MUTED))
		var nxt := UIKit.button(Loc.t("MKT_NEXT"), func() -> void:
			_page += 1
			rebuild(), 90)
		nxt.disabled = _page >= pages - 1
		nav.add_child(nxt)
		add_child(nav)


## The search filters as `TransferMarket.search_v2` takes them.
func _filters_dict(career: CareerState) -> Dictionary:
	var f := {"exclude_team": career.club_id}
	var pi := int(_f.get("pos_index", 0))
	if pi >= 1 and pi <= PlayerData.Position.size():
		f["positions"] = [pi - 1]
	elif pi > PlayerData.Position.size():
		f["positions"] = LINES[LINES.keys()[pi - PlayerData.Position.size() - 1]]
	for k in ["name", "min_age", "max_age", "min_overall", "max_overall", "min_potential", "max_potential", "min_price", "max_price",
			"max_wage", "nationality", "league", "club", "min_height", "max_height", "secondary", "expiring", "listed_only",
			"loan_available", "free_only"]:
		if _f.has(k) and str(_f[k]) != "" and str(_f[k]) != "0" and str(_f[k]) != "false":
			f[k] = _f[k]
	if int(_f.get("foot", -1)) >= 0:
		f["foot"] = int(_f["foot"])
	return f


func _filter_panel(market: TransferMarket) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "FilterPanel"
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 8)
	flow.add_child(_range("MKT_F_AGE", "min_age", "max_age", 15, 45, 1))
	flow.add_child(_range("MKT_F_OVERALL", "min_overall", "max_overall", 1, 99, 1))
	flow.add_child(_range("MKT_F_POTENTIAL", "min_potential", "max_potential", 1, 99, 1))
	flow.add_child(_range("MKT_F_PRICE", "min_price", "max_price", 0, 500_000_000, 100_000))
	flow.add_child(_range("MKT_F_HEIGHT", "min_height", "max_height", 150, 210, 1))
	flow.add_child(_single("MKT_F_MAX_WAGE", "max_wage", 0, 2_000_000, 1000))
	# nationality / league / club / foot
	var nats := {}
	var leagues := {}
	for t: TeamData in db().list_teams(TeamData.Category.CLUB):
		if t.league_id != "":
			leagues[t.league_id] = true
	for p: PlayerData in db().players.values():
		if p.nationality != "" and p.status != PlayerData.Status.RETIRED:
			nats[p.nationality] = true
	var nat_list: Array = nats.keys()
	nat_list.sort_custom(func(a: String, b: String) -> bool: return Loc.country(a) < Loc.country(b))
	flow.add_child(_choice("MKT_F_NATIONALITY", "nationality", nat_list, nat_list.map(func(n: String) -> String: return Loc.country(n))))
	var league_list: Array = leagues.keys()
	league_list.sort()
	flow.add_child(_choice("MKT_F_LEAGUE", "league", league_list, league_list.map(func(id: String) -> String:
		return Loc.t("LEAGUE_" + id.to_upper()) if Loc.has_key("LEAGUE_" + id.to_upper()) else id)))
	var clubs: Array = db().list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool:
		return str(_f.get("league", "")) == "" or t.league_id == str(_f["league"]))
	clubs.sort_custom(func(a: TeamData, b: TeamData) -> bool: return a.display_name < b.display_name)
	flow.add_child(_choice("MKT_F_CLUB", "club", clubs.map(func(t: TeamData) -> String: return t.id),
			clubs.map(func(t: TeamData) -> String: return t.display_name)))
	var feet: Array = [Loc.t("MARKET_ANY")]
	for k in PlayerData.Foot.keys():
		feet.append(Loc.enum_name("FOOT", k))
	var foot := UIKit.option(feet, int(_f.get("foot", -1)) + 1, func(i: int) -> void:
		_f["foot"] = i - 1
		_page = 0
		rebuild())
	flow.add_child(MarketUI.field(Loc.t("MKT_F_FOOT"), foot))
	for k in ["secondary", "expiring", "listed_only", "loan_available", "free_only"]:
		flow.add_child(MarketUI.check(Loc.t("MKT_F_" + k.to_upper()), bool(_f.get(k, false)), func(on: bool) -> void:
			_f[k] = on
			_page = 0
			rebuild(), "Check_" + k))
	return UIKit.panel(flow)


func _range(title_key: String, k_min: String, k_max: String, lo: int, hi: int, step: int) -> Control:
	var row := UIKit.hbox(6)
	row.add_child(UIKit.label(Loc.t(title_key), 14, UIKit.MUTED))
	var a := MarketUI.number(int(_f.get(k_min, lo)), lo, hi, step, Callable(), "", "Min_" + k_min)
	var b := MarketUI.number(int(_f.get(k_max, hi)), lo, hi, step, Callable(), "", "Max_" + k_max)
	a.custom_minimum_size = Vector2(120 if hi < 1000 else 170, 36)
	b.custom_minimum_size = a.custom_minimum_size
	a.value_changed.connect(func(v: float) -> void: _f[k_min] = int(v) if int(v) != lo else 0)
	b.value_changed.connect(func(v: float) -> void:
		if int(v) == hi:
			_f.erase(k_max)
		else:
			_f[k_max] = int(v))
	row.add_child(a)
	row.add_child(UIKit.label("–", 14, UIKit.MUTED))
	row.add_child(b)
	return row


func _single(title_key: String, key: String, lo: int, hi: int, step: int) -> Control:
	var s := MarketUI.number(int(_f.get(key, 0)), lo, hi, step, func(v: int) -> void: _f[key] = v, "", "Field_" + key)
	return MarketUI.field(Loc.t(title_key), s)


func _choice(title_key: String, key: String, values: Array, labels: Array) -> Control:
	var items: Array = [Loc.t("MARKET_ANY")] + labels
	var sel := values.find(str(_f.get(key, ""))) + 1
	var o := UIKit.option(items, sel, func(i: int) -> void:
		_f[key] = "" if i == 0 else str(values[i - 1])
		if key == "league":
			_f["club"] = ""
		_page = 0
		rebuild())
	o.name = "Choice_" + key
	o.custom_minimum_size = Vector2(200, 36)
	o.fit_to_longest_item = false
	return MarketUI.field(Loc.t(title_key), o)


func _saved_searches_row(market: TransferMarket) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	if not market.saved_searches.is_empty():
		row.add_child(UIKit.label(Loc.t("MKT_SAVED_SEARCHES"), 14, UIKit.MUTED))
		for i in market.saved_searches.size():
			var s: Dictionary = market.saved_searches[i]
			row.add_child(UIKit.button(str(s["name"]), func() -> void:
				_f = (s["filters"] as Dictionary).duplicate(true)
				_page = 0
				rebuild()))
			row.add_child(UIKit.button("✕", func() -> void:
				market.saved_searches.remove_at(i)
				rebuild(), 36))
	var save := UIKit.button(Loc.t("MKT_SAVE_SEARCH"), func() -> void:
		var err := market.save_search(Loc.f("MKT_SEARCH_N", [market.saved_searches.size() + 1]), _f)
		if err != "":
			say(err, true)
		rebuild(), 150)
	save.name = "SaveSearch"
	save.disabled = market.saved_searches.size() >= TransferMarket.SAVED_SEARCHES_MAX
	row.add_child(save)
	return row


## Search results as a table with column headers: name, position, age, OVR/POT, club, price, actions.
func _market_table(results: Array, market: TransferMarket) -> Control:
	var grid := GridContainer.new()
	grid.name = "MarketTable"
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for h in [Loc.t("COMMON_NAME"), Loc.t("COMMON_POS"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT"), Loc.t("MARKET_CLUB"),
			Loc.t("MARKET_PRICE_HEADER"), ""]:
		grid.add_child(UIKit.label(h, 14, UIKit.GOLD))
	for p: PlayerData in results:
		var club: TeamData = db().get_team(p.team_id)
		var name_cell := UIKit.hbox(6)
		name_cell.add_child(MarketUI.flag(db(), p, 20))
		var nl := UIKit.label(p.display_name, 15)
		nl.text_direction = Control.TEXT_DIRECTION_AUTO
		name_cell.add_child(nl)
		for b in MarketUI.status_badges(market, p):
			name_cell.add_child(b)
		grid.add_child(name_cell)
		grid.add_child(UIKit.label(Loc.position_code(p.position), 15))
		grid.add_child(UIKit.label(Loc.num(p.age), 15))
		grid.add_child(UIKit.label(overall_text(p), 15))
		var club_cell := UIKit.hbox(6)
		club_cell.add_child(UIKit.crest(db(), club, 20))
		club_cell.add_child(UIKit.label(Loc.iso(club.short_name) if club != null else Loc.t("PROFILE_FREE_AGENT"), 14, UIKit.MUTED))
		grid.add_child(club_cell)
		grid.add_child(UIKit.label(Loc.money(market.asking_price(p) if club != null else 0), 14, UIKit.GOLD))
		grid.add_child(_row_actions(p, market))
	return grid


func _row_actions(p: PlayerData, market: TransferMarket) -> Control:
	var actions := UIKit.hbox(4)
	actions.add_child(UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": p.id}), 70))
	var star := UIKit.button("★" if p.id in market.shortlist else "☆", func() -> void:
		market.toggle_shortlist(p.id)
		rebuild(), 40)
	star.name = "Star_%s" % p.id
	star.tooltip_text = Loc.t("MKT_SHORTLIST_TOGGLE")
	actions.add_child(star)
	var offer := UIKit.button(Loc.t("MKT_OFFER"), _offer.bind(p.id), 70)
	offer.name = "Buy_%s" % p.id
	actions.add_child(offer)
	return actions


func _card_grid(results: Array, market: TransferMarket) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "MarketCards"
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	for p: PlayerData in results:
		var box := UIKit.vbox(4)
		var card := PlayerCard.new(120.0)
		card.setup(PlayerCardData.from_data(db(), p), db())
		card.pressed.connect(func(pid: String) -> void: go("player_profile", {"player_id": pid}))
		box.add_child(card)
		box.add_child(UIKit.label(Loc.money(market.asking_price(p) if p.team_id != "" else 0), 13, UIKit.GOLD))
		box.add_child(_row_actions(p, market))
		flow.add_child(box)
	return flow


## Orders market results by what the squad needs: positions of the formation with the fewest players
## of that position in the squad come first, then the best players (by overall). Before, the list was
## sorted by overall only and started with goalkeepers (their overall is dominated by goalkeeping).
static func by_team_need(players: Array, squad: Squad, db: Node) -> Array:
	var need := {}
	if squad != null:
		for slot in 11:
			var pos := FormationData.slot_position(squad.formation_id, slot)
			need[pos] = int(need.get(pos, 0)) + 2          # two players per formation slot is a healthy depth
		for p: PlayerData in db.get_squad(squad.team_id):
			need[p.position] = int(need.get(p.position, 0)) - 1
	var out := players.duplicate()
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var na := int(need.get(a.position, -99))
		var nb := int(need.get(b.position, -99))
		if na != nb:
			return na > nb
		if a.get_overall() != b.get_overall():
			return a.get_overall() > b.get_overall()
		return a.id < b.id)
	return out


func _offer(pid: String, type := "") -> void:
	var market: TransferMarket = app().career.market
	for o: TransferOffer in market.user_offers("outgoing"):
		if o.player_id == pid:
			if o.status == TransferOffer.ACCEPTED and o.contract.is_empty() and not o.is_loan():
				ContractDialog.open_for_offer(self, o.id)
			else:
				NegotiationDialog.open(self, pid, "", o.id)
			return
	NegotiationDialog.open(self, pid, type)


# --- shortlist -------------------------------------------------------------------------------------------------------

func _shortlist_tab(_career: CareerState, market: TransferMarket) -> void:
	var players: Array = []
	for pid in market.shortlist:
		var p: PlayerData = db().get_player(pid)
		if p != null:
			players.append(p)
	if players.is_empty():
		add_child(UIKit.empty_state(Loc.t("MKT_SHORTLIST_EMPTY"), Loc.t("MKT_TAB_SEARCH"), _set_tab.bind("search"), "ball"))
		return
	add_child(_market_table(players, market))


# --- offers ----------------------------------------------------------------------------------------------------------

func _offers_tab(career: CareerState, market: TransferMarket) -> void:
	var incoming := market.user_offers("incoming")
	var outgoing := market.user_offers("outgoing")
	add_child(UIKit.label(Loc.f("MKT_INCOMING", [incoming.size()]), 18, UIKit.GOLD))
	if incoming.is_empty():
		add_child(UIKit.muted(Loc.t("MKT_NO_INCOMING")))
	for o: TransferOffer in incoming:
		add_child(_offer_card(o, market, true))
	add_child(UIKit.label(Loc.f("MKT_OUTGOING", [outgoing.size()]), 18, UIKit.GOLD))
	if outgoing.is_empty():
		add_child(UIKit.muted(Loc.t("MKT_NO_OUTGOING")))
	for o: TransferOffer in outgoing:
		add_child(_offer_card(o, market, false))
	var decisions: Array = market.loans.keys().filter(func(pid: String) -> bool:
		return bool(market.loans[pid].get("decision", false)) and str(market.loans[pid]["to"]) == career.club_id)
	if not decisions.is_empty():
		add_child(UIKit.label(Loc.t("MKT_OPTION_DECISIONS"), 18, UIKit.GOLD))
		for pid in decisions:
			add_child(_decision_row(pid, market))
	market.mark_read()
	if hub.has_method("refresh_badges"):
		hub.refresh_badges()


func _offer_card(o: TransferOffer, market: TransferMarket, incoming: bool) -> Control:
	var p: PlayerData = db().get_player(o.player_id)
	var other: TeamData = db().get_team(o.from_club if incoming else o.to_club)
	var row := HFlowContainer.new()
	row.name = "Offer_%d" % o.id
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 6)
	if p != null:
		var card := PlayerCard.new(70.0)
		card.setup(PlayerCardData.from_data(db(), p), db())
		row.add_child(card)
	var info := UIKit.vbox(2)
	info.custom_minimum_size = Vector2(300, 0)
	var head := UIKit.hbox(6)
	head.add_child(UIKit.crest(db(), other, 22))
	var title := UIKit.label("%s · %s" % [p.display_name if p != null else o.player_id,
			Loc.iso(other.display_name) if other != null else Loc.t("PROFILE_FREE_AGENT")], 16)
	title.text_direction = Control.TEXT_DIRECTION_AUTO
	head.add_child(title)
	if o.unread:
		head.add_child(MarketUI.badge(Loc.t("MKT_NEW"), UIKit.BAD))
	info.add_child(head)
	info.add_child(UIKit.label(MarketUI.type_name(o.type) + " — " + MarketUI.terms_text(o), 14, UIKit.GOLD))
	var st := MarketUI.status_name(o.status)
	if o.reason != "":
		st += " — " + MarketUI.reason_text(o.reason)
	if o.status in [TransferOffer.PENDING, TransferOffer.COUNTERED]:
		st += "  ·  " + Loc.f("MKT_EXPIRES", [maxi(0, o.expires_week - market.abs_week())])
	var sl := UIKit.label(st, 13, MarketUI.status_color(o.status))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sl)
	row.add_child(info)
	var actions := UIKit.hbox(6)
	if incoming and o.status == TransferOffer.PENDING:
		var acc := UIKit.button(Loc.t("MKT_ACCEPT"), _answer.bind(o.id, "accept"), 100)
		acc.name = "Accept_%d" % o.id
		actions.add_child(acc)
		actions.add_child(UIKit.button(Loc.t("MKT_COUNTER"), func() -> void: NegotiationDialog.open(self, o.player_id, "", o.id), 110))
		var rej := UIKit.button(Loc.t("MKT_REJECT"), _answer.bind(o.id, "reject"), 100)
		rej.name = "Reject_%d" % o.id
		actions.add_child(rej)
	elif not incoming:
		if o.status == TransferOffer.COUNTERED:
			actions.add_child(UIKit.button(Loc.t("MKT_OPEN_TALKS"), func() -> void: NegotiationDialog.open(self, o.player_id, "", o.id), 140))
		elif o.status == TransferOffer.ACCEPTED and o.contract.is_empty() and not o.is_loan():
			actions.add_child(UIKit.button(Loc.t("MKT_PLAYER_CONTRACT"), func() -> void: ContractDialog.open_for_offer(self, o.id), 160))
		if o.is_open():
			actions.add_child(UIKit.button(Loc.t("MKT_WITHDRAW"), func() -> void:
				market.withdraw(o.id)
				rebuild(), 110))
	row.add_child(actions)
	return UIKit.panel(row)


func _answer(offer_id: int, action: String) -> void:
	var market: TransferMarket = app().career.market
	var o := market.get_offer(offer_id)
	var err := market.answer_incoming(offer_id, action)
	if err != "":
		say(err, true)
	elif o.status == TransferOffer.COMPLETED:
		say(Loc.f("MKT_RESULT_COMPLETED", [db().get_player(o.player_id).display_name]))
	elif o.status == TransferOffer.DEFERRED:
		say(Loc.f("MKT_RESULT_DEFERRED", [db().get_player(o.player_id).display_name]))
	else:
		say(MarketUI.status_name(o.status) + ((" — " + MarketUI.reason_text(o.reason)) if o.reason != "" else ""), o.status == TransferOffer.REJECTED and action == "accept")
	rebuild()


func _decision_row(pid: String, market: TransferMarket) -> Control:
	var p: PlayerData = db().get_player(pid)
	var l: Dictionary = market.loans[pid]
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_child(UIKit.label(Loc.f("MKT_OPTION_DECIDE", [p.display_name, Loc.money(int(l["option_fee"]))]), 15))
	var buy := UIKit.button(Loc.t("MKT_EXERCISE_OPTION"), func() -> void:
		var err := market.exercise_option(pid, market.cur_week, app().squads)
		say(err if err != "" else Loc.f("MKT_RESULT_COMPLETED", [p.display_name]), err != "")
		rebuild(), 170)
	buy.name = "Exercise_%s" % pid
	row.add_child(buy)
	row.add_child(UIKit.button(Loc.t("MKT_SEND_BACK"), func() -> void:
		market.return_from_loan(pid, market.cur_week, app().squads)
		rebuild(), 130))
	return UIKit.panel(row)


# --- my players on the market ----------------------------------------------------------------------------------------

func _mine_tab(career: CareerState, market: TransferMarket) -> void:
	add_child(UIKit.muted(Loc.t("MKT_MINE_HINT")))
	var grid := GridContainer.new()
	grid.name = "MineTable"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for h in [Loc.t("COMMON_NAME"), Loc.t("COMMON_OVR_POT"), Loc.t("MKT_VALUE"), Loc.t("MKT_STATUS"), ""]:
		grid.add_child(UIKit.label(h, 14, UIKit.GOLD))
	var squad: Array = db().get_squad(career.club_id)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var la := market.listing_of(a.id) != TransferMarket.LISTING_NONE
		var lb := market.listing_of(b.id) != TransferMarket.LISTING_NONE
		if la != lb:
			return la
		return a.get_overall() > b.get_overall() or (a.get_overall() == b.get_overall() and a.id < b.id))
	for p: PlayerData in squad:
		var name_cell := UIKit.vbox(0)
		var nl := UIKit.label("%s · %s" % [p.display_name, Loc.position_code(p.position)], 15)
		nl.text_direction = Control.TEXT_DIRECTION_AUTO
		name_cell.add_child(nl)
		name_cell.add_child(UIKit.label(Loc.f("MKT_WAGE_YEARS", [Loc.money(p.salary), p.contract_years]), 12, UIKit.MUTED))
		grid.add_child(name_cell)
		grid.add_child(UIKit.label(overall_text(p), 15))
		grid.add_child(UIKit.label(Loc.money(market.market_value(p)), 14, UIKit.GOLD))
		var st := UIKit.hbox(4)
		for b in MarketUI.status_badges(market, p):
			st.add_child(b)
		if market.is_transfer_listed(p.id):
			st.add_child(UIKit.label(Loc.money(market.asking_price(p)), 13, UIKit.GOLD))
		grid.add_child(st)
		var actions := UIKit.hbox(4)
		if p.loan_parent == "":
			var sell := UIKit.button(Loc.t("MKT_LIST_SALE") if not market.is_transfer_listed(p.id) else Loc.t("MKT_UPDATE_PRICE"),
					func() -> void: ListingDialog.open(self, p.id, "sale"), 0)
			sell.name = "Sell_%s" % p.id
			actions.add_child(sell)
			actions.add_child(UIKit.button(Loc.t("MKT_LIST_LOAN"), func() -> void: ListingDialog.open(self, p.id, "loan"), 0))
			if market.listing_of(p.id) != TransferMarket.LISTING_NONE:
				actions.add_child(UIKit.button("✕", func() -> void:
					market.set_listing(career.club_id, p.id, TransferMarket.LISTING_NONE)
					rebuild(), 40))
				(actions.get_child(actions.get_child_count() - 1) as Button).tooltip_text = Loc.t("MKT_UNLIST")
		grid.add_child(actions)
	add_child(grid)


# --- loans -----------------------------------------------------------------------------------------------------------

func _loans_tab(career: CareerState, market: TransferMarket) -> void:
	var out_ids: Array = []
	var in_ids: Array = []
	for pid in market.loans:
		if str(market.loans[pid]["from"]) == career.club_id:
			out_ids.append(pid)
		elif str(market.loans[pid]["to"]) == career.club_id:
			in_ids.append(pid)
	out_ids.sort()
	in_ids.sort()
	add_child(UIKit.label(Loc.f("MKT_LOANED_OUT", [out_ids.size(), TransferMarket.MAX_LOANS_OUT]), 18, UIKit.GOLD))
	if out_ids.is_empty():
		add_child(UIKit.muted(Loc.t("MKT_NO_LOANS_OUT")))
	else:
		add_child(_loan_table(out_ids, market, true))
	add_child(UIKit.label(Loc.f("MKT_LOANED_IN", [in_ids.size(), TransferMarket.MAX_LOANS_IN]), 18, UIKit.GOLD))
	if in_ids.is_empty():
		add_child(UIKit.muted(Loc.t("MKT_NO_LOANS_IN")))
	else:
		add_child(_loan_table(in_ids, market, false))


func _loan_table(ids: Array, market: TransferMarket, out: bool) -> Control:
	var grid := GridContainer.new()
	grid.name = "LoansOut" if out else "LoansIn"
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for h in [Loc.t("COMMON_NAME"), Loc.t("MARKET_CLUB"), Loc.t("MKT_WEEKS_LEFT"), Loc.t("MKT_LOAN_STATS"), Loc.t("MKT_WAGE_SPLIT_SHORT"),
			Loc.t("MKT_OPTION"), ""]:
		grid.add_child(UIKit.label(h, 14, UIKit.GOLD))
	for pid in ids:
		var p: PlayerData = db().get_player(pid)
		var l: Dictionary = market.loans[pid]
		var nl := UIKit.label(p.display_name, 15)
		nl.text_direction = Control.TEXT_DIRECTION_AUTO
		grid.add_child(nl)
		grid.add_child(UIKit.team_cell(db(), str(l["to"]) if out else str(l["from"]), 20))
		grid.add_child(UIKit.label(Loc.num(maxi(0, p.loan_weeks_left)), 15))
		var apps := int(l["apps"])
		var avg := float(l["rating_sum"]) / apps if apps > 0 else 0.0
		grid.add_child(UIKit.label(Loc.f("MKT_LOAN_STATS_ROW", [apps, int(l["goals"]), Loc.decimal(avg, 1)]), 14))
		grid.add_child(UIKit.label(Loc.f("MKT_SPLIT_SHORT", [int(l["wage_split"])]), 14))
		grid.add_child(UIKit.label(Loc.money(int(l["option_fee"])) if str(l["type"]) != TransferOffer.LOAN else "—", 14,
				UIKit.GOLD if str(l["type"]) != TransferOffer.LOAN else UIKit.MUTED))
		var actions := UIKit.hbox(4)
		actions.add_child(UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": pid}), 70))
		if out:
			var rc := UIKit.button(Loc.t("MKT_RECALL_NOW"), func() -> void:
				var err := market.recall(pid, market.cur_week, app().squads)
				say(err if err != "" else Loc.f("MKT_RECALLED", p.display_name), err != "")
				rebuild(), 110)
			rc.disabled = not market.can_recall(pid)
			rc.name = "Recall_%s" % pid
			actions.add_child(rc)
		elif str(l["type"]) == TransferOffer.LOAN_WITH_OPTION:
			var ex := UIKit.button(Loc.t("MKT_EXERCISE_OPTION"), func() -> void:
				var err := market.exercise_option(pid, market.cur_week, app().squads)
				say(err if err != "" else Loc.f("MKT_RESULT_COMPLETED", [p.display_name]), err != "")
				rebuild(), 160)
			ex.name = "Exercise_%s" % pid
			actions.add_child(ex)
		grid.add_child(actions)
	return grid


# --- history ---------------------------------------------------------------------------------------------------------

func _history_tab(career: CareerState, market: TransferMarket) -> void:
	add_child(UIKit.label(Loc.t("MARKET_TRANSFER_HISTORY"), 16, UIKit.GOLD))
	if market.history.is_empty():
		add_child(UIKit.muted(Loc.t("MARKET_NO_TRANSFERS_YET")))
	var recent: Array = market.history.slice(-40)
	recent.reverse()
	for h in recent:
		var pl: PlayerData = db().get_player(h["player_id"])
		var to_team: TeamData = db().get_team(str(h["to"]))
		var line := UIKit.muted(Loc.f("MARKET_WEEK_FEE", [h["week"], Loc.enum_name("TRANSFERKIND", str(h["kind"])),
				pl.display_name if pl != null else "?", to_team.display_name if to_team != null else Loc.t("PROFILE_FREE_AGENT"), h["fee"]]))
		line.text_direction = Control.TEXT_DIRECTION_AUTO
		if str(h["from"]) == career.club_id or str(h["to"]) == career.club_id:
			line.add_theme_color_override("font_color", UIKit.GOLD)
		add_child(line)
	var closed: Array = []
	for o: TransferOffer in market.offers:
		if not o.is_open() and (o.from_club == career.club_id or o.to_club == career.club_id):
			closed.append(o)
	closed.reverse()
	if not closed.is_empty():
		add_child(UIKit.label(Loc.t("MKT_CLOSED_OFFERS"), 16, UIKit.GOLD))
		for o: TransferOffer in closed.slice(0, 20):
			var p: PlayerData = db().get_player(o.player_id)
			var line := UIKit.label("%s — %s — %s" % [p.display_name if p != null else o.player_id, MarketUI.terms_text(o),
					MarketUI.status_name(o.status)], 14, MarketUI.status_color(o.status))
			line.text_direction = Control.TEXT_DIRECTION_AUTO
			add_child(line)
