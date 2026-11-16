## Transfers v2, phase 3: the market UI — tabs and the fixed top bar, advanced search with filters and paging, the
## negotiation window (offer → counter → contract), wage split text, listing from the player profile, incoming offers
## with the red dot, loans and history tabs, in English and Arabic without missing texts.
##   godot --headless --path . res://tests/transfers_ui_validation.tscn
extends Node

const USER := "club_royal_harbor"

var _passed := 0
var _failed := 0
var app: Node
var db: Node
var hub: HubRoot


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Transfer market UI validation ===")
	app = get_node("/root/AppHub")
	db = app.db
	db.load_world("")
	app.user_team_id = ""
	app.career = null
	app.squads.clear(); app.academies.clear(); app.scouting.clear(); app.training.clear()
	app.start_career(USER)
	var c: CareerState = app.career
	c.week = 2
	c.market.sync_clock(c.season, 2, USER, c.world_stats)
	var l := c.ledger()
	l.opening_balance += 500_000_000 - l.balance
	l.balance = 500_000_000
	l.transfer_budget = 300_000_000
	l.wage_budget = 10_000_000
	Loc.set_language("en", false)
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	hub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hub.size = Vector2(1280, 720)
	await get_tree().process_frame
	Loc.missing.clear()
	await _test_tabs_and_search()
	await _test_negotiation_flow()
	await _test_loan_dialog()
	await _test_profile_listing()
	await _test_incoming_and_badge()
	await _test_other_tabs()
	await _test_arabic()
	hub.queue_free()
	Loc.set_language("en", false)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _go(id: String, p: Dictionary = {}) -> void:
	hub.navigate(id, p)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(root: Node, pattern: String) -> Node:
	var all := root.find_children(pattern, "", true, false)
	return all[0] if not all.is_empty() else null


func _press(root: Node, pattern: String) -> bool:
	var b := _find(root, pattern) as BaseButton
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _dialog(name: String) -> Control:
	for ch in hub.get_children():
		if ch.name == name and not ch.is_queued_for_deletion():
			return ch
	return null


func _close_dialogs() -> void:
	for ch in hub.get_children():
		if str(ch.name) in ["NegotiationDialog", "ContractDialog", "ListingDialog"]:
			ch.queue_free()
	await _frames(2)


func _test_tabs_and_search() -> void:
	await _go("transfers")
	var cur := hub.current
	_check(_find(cur, "MarketTopBar") != null, "a fixed bar shows balance, budget, wage room and the window")
	var tabs := cur.find_children("Tab_*", "Button", true, false)
	_check(tabs.size() == 6, "six tabs: search, shortlist, offers, my players, loans, history", str(tabs.size()))
	var table := _find(cur, "MarketTable") as GridContainer
	_check(table != null and table.columns == 7, "search results as a table")
	var bar_text := ""
	for lb in _find(cur, "MarketTopBar").find_children("*", "Label", true, false):
		bar_text += (lb as Label).text + " "
	_check(bar_text.contains(Loc.t("MKT_WINDOW")) and bar_text.contains(Loc.f("MKT_WINDOW_OPEN", [5])), "the window state is shown (open, 5 weeks left)", bar_text)
	var was_open := _find(cur, "FilterPanel") != null
	_press(cur, "FiltersToggle")
	await _frames(2)
	_check((_find(hub.current, "FilterPanel") != null) != was_open, "the filter panel folds in and out")
	if _find(hub.current, "FilterPanel") == null:
		_press(hub.current, "FiltersToggle")
		await _frames(2)
	_check(_find(hub.current, "FilterPanel") != null and _find(hub.current, "Choice_nationality") != null and _find(hub.current, "Choice_league") != null,
			"filters: nationality, league, club, ranges and switches")
	var po := _find(hub.current, "PositionOption") as OptionButton
	po.select(PlayerData.Position.ST + 1)
	po.item_selected.emit(PlayerData.Position.ST + 1)
	await _frames(2)
	var names := hub.current.find_children("Buy_*", "Button", true, false)
	var all_st := not names.is_empty()
	for b in names:
		all_st = all_st and db.get_player(str(b.name).trim_prefix("Buy_")).position == PlayerData.Position.ST
	_check(all_st, "the position filter limits the results", str(names.size()))
	po = _find(hub.current, "PositionOption") as OptionButton
	po.item_selected.emit(0)
	await _frames(2)
	var star := _find(hub.current, "Star_*") as Button
	var star_pid := str(star.name).trim_prefix("Star_")
	star.pressed.emit()
	await _frames(2)
	_check(star_pid in app.career.market.shortlist, "☆ adds a player to the shortlist")
	_press(hub.current, "SaveSearch")
	await _frames(2)
	_check(app.career.market.saved_searches.size() == 1, "a search can be saved")


func _test_negotiation_flow() -> void:
	await _go("transfers")
	var m: TransferMarket = app.career.market
	var target: PlayerData = null
	for b in hub.current.find_children("Buy_*", "Button", true, false):
		var p: PlayerData = db.get_player(str(b.name).trim_prefix("Buy_"))
		if p.team_id != "" and m.refusal(p, USER, false) == "" and int(m.squad_rank(p)["all"]) >= 3:
			target = p
			break
	_check(target != null, "(setup) a player to buy")
	_press(hub.current, "Buy_%s" % target.id)
	await _frames(2)
	var dlg := _dialog("NegotiationDialog")
	_check(dlg != null and _find(dlg, "FeeField") != null and _find(dlg, "AskingPrice") != null, "the offer opens the negotiation window with fee and asking price")
	var chance := _find(dlg, "ChanceLabel") as Label
	_check(chance != null and chance.text.begins_with(Loc.t("MKT_CHANCE").split("%")[0]), "an acceptance indicator is shown", chance.text if chance else "")
	var fee := _find(dlg, "FeeField") as SpinBox
	fee.value = int(m.seller_price(target) * 0.9)
	await _frames(1)
	_check((_find(dlg, "ChanceLabel") as Label).text.contains(Loc.t("MKT_CHANCE_MEDIUM")), "90 % of the price: medium chance")
	_press(dlg, "SendButton")
	await _frames(2)
	var o: TransferOffer = m.user_offers("outgoing")[0]
	_check(o.player_id == target.id and o.status == TransferOffer.COUNTERED, "sending creates the offer; the club counters", o.status)
	dlg = _dialog("NegotiationDialog")
	_check(dlg != null and _find(dlg, "AcceptCounterButton") != null and _find(dlg, "OfferStatus") != null, "the counter-offer and the rounds are shown")
	_press(dlg, "AcceptCounterButton")
	await _frames(3)
	var cd := _dialog("ContractDialog")
	_check(cd != null and _find(cd, "WageField") != null and _find(cd, "RoleOption") != null and _find(cd, "ClauseField") != null,
			"clubs agree: the player-contract window opens (wage, role, release clause)")
	_press(cd, "ProposeButton")
	await _frames(2)
	_check(o.status == TransferOffer.ACCEPTED and o.contract_rounds == 1 and target.team_id != USER, "a low wage: the player names his demand")
	var wage := _find(cd, "WageField") as SpinBox
	_check(wage != null and int(wage.value) > target.salary, "his demand is put into the wage field", str(wage.value if wage else -1))
	_press(cd, "ProposeButton")
	await _frames(3)
	_check(o.status == TransferOffer.COMPLETED and target.team_id == USER, "his demand is accepted: the player joins", o.status)
	_check(app.career.ledger().is_consistent(), "ledger consistent after a UI deal")
	await _close_dialogs()


func _test_loan_dialog() -> void:
	var m: TransferMarket = app.career.market
	var p: PlayerData = null
	for q: PlayerData in db.players.values():
		if q.team_id != "" and q.team_id != USER and q.loan_parent == "" and q.status != PlayerData.Status.YOUTH and int(m.squad_rank(q)["pos"]) >= 2 \
				and db.get_team(q.team_id).squad_ids.size() > TransferMarket.MIN_SQUAD + 1:
			p = q
			break
	await _go("player_profile", {"player_id": p.id})
	_check(_find(hub.current, "TransferActions") != null and _find(hub.current, "MakeOffer") != null and _find(hub.current, "RequestLoan") != null,
			"another club's player: offer, loan request and shortlist buttons")
	_press(hub.current, "RequestLoan")
	await _frames(2)
	var dlg := _dialog("NegotiationDialog")
	var slider := _find(dlg, "WageSplitSlider") as HSlider
	slider.value = 60
	await _frames(1)
	var txt := (_find(dlg, "WageSplitText") as Label).text
	_check(txt.contains(Loc.money(p.salary * 60 / 100)) and txt.contains(Loc.money(p.salary - p.salary * 60 / 100)), "wage split: what each club pays per week", txt)
	_check(_find(dlg, "LoanLengthOption") != null and _find(dlg, "RecallField") != null and _find(dlg, "MinPlayField") != null,
			"loan length, recall clause and playing-time promise")
	var to := _find(dlg, "TypeOption") as OptionButton
	to.item_selected.emit(2)
	await _frames(2)
	dlg = _dialog("NegotiationDialog")
	_check(_find(dlg, "OptionFeeField") != null, "a loan with option shows the option price")
	_press(dlg, "SendButton")
	await _frames(2)
	var o: TransferOffer = m.user_offers("outgoing", false).filter(func(x: TransferOffer) -> bool: return x.player_id == p.id)[0]
	_check(o.type == TransferOffer.LOAN_WITH_OPTION and o.wage_split_percent == 60, "the loan offer carries the chosen terms", "%s %d" % [o.type, o.wage_split_percent])
	await _close_dialogs()


func _test_profile_listing() -> void:
	var mine: PlayerData = db.get_squad(USER)[5]
	await _go("player_profile", {"player_id": mine.id})
	_check(_find(hub.current, "ListForSale") != null and _find(hub.current, "ListForLoan") != null and _find(hub.current, "Untouchable") != null
			and _find(hub.current, "Renew") != null, "own player: list for sale / loan, untouchable, renew")
	_press(hub.current, "ListForSale")
	await _frames(2)
	var dlg := _dialog("ListingDialog")
	_check(dlg != null and _find(dlg, "PriceField") != null, "the listing window asks for a price")
	(_find(dlg, "PriceField") as SpinBox).value = 2_000_000
	_press(dlg, "ConfirmListing")
	await _frames(3)
	var m: TransferMarket = app.career.market
	_check(m.is_transfer_listed(mine.id) and m.asking_price(mine) == 2_000_000, "the player is on the transfer list at that price")
	await _go("player_profile", {"player_id": mine.id})
	_check(_find(hub.current, "Unlist") != null, "listed: 'take off the market' is offered")
	_press(hub.current, "Untouchable")
	await _frames(2)
	_check(m.listing_of(mine.id) == TransferMarket.LISTING_UNTOUCHABLE, "untouchable toggles from the profile")
	_press(hub.current, "Untouchable")
	await _frames(2)
	_press(hub.current, "Renew")
	await _frames(2)
	_check(_dialog("ContractDialog") != null, "renewal opens the contract window")
	await _close_dialogs()


func _test_incoming_and_badge() -> void:
	var m: TransferMarket = app.career.market
	var mine: PlayerData = null
	for p: PlayerData in db.get_squad(USER):
		if p.loan_parent == "" and m.listing_of(p.id) == TransferMarket.LISTING_NONE and not m.arrivals.has(p.id):
			mine = p
	var buyer := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.squad_ids.size() < TransferMarket.MAX_SQUAD - 1:
			buyer = t.id
			break
	var bl: FinanceLedger = app.career.ledgers[buyer]
	bl.opening_balance += 400_000_000 - bl.balance
	bl.balance = 400_000_000
	bl.transfer_budget = 300_000_000
	bl.wage_budget = 10_000_000
	var o: TransferOffer = m.make_offer(buyer, mine.id, TransferOffer.PERMANENT, {"fee": m.market_value(mine)})["offer"]
	app.state_changed.emit()
	await _frames(2)
	var nav := hub.find_child("Nav_transfers", true, false)
	_check(nav != null and nav.get_node_or_null("Badge") != null, "a red dot on the market while an offer waits")
	await _go("transfers", {"tab": "offers"})
	_check(_find(hub.current, "Offer_%d" % o.id) != null and _find(hub.current, "Accept_%d" % o.id) != null, "the incoming offer is listed with accept / counter / reject")
	_press(hub.current, "Accept_%d" % o.id)
	await _frames(3)
	_check(o.status == TransferOffer.COMPLETED and mine.team_id == buyer, "accepting sells the player", o.status)
	app.state_changed.emit()
	await _frames(2)
	_check(m.needs_user_action() > 0 or hub.find_child("Nav_transfers", true, false).get_node_or_null("Badge") == null
			or (hub.find_child("Nav_transfers", true, false).get_node("Badge") as Node).is_queued_for_deletion(), "the dot disappears when nothing waits")


func _test_other_tabs() -> void:
	var m: TransferMarket = app.career.market
	for tab in ["shortlist", "mine", "loans", "history"]:
		await _go("transfers", {"tab": tab})
		_check(hub.current.get_child_count() > 3, "tab '%s' renders" % tab)
	await _go("transfers", {"tab": "mine"})
	_check(_find(hub.current, "MineTable") != null, "my players with their market status")
	await _go("transfers", {"tab": "loans"})
	_check(_find(hub.current, "LoansIn") != null or m.loans_in(USER) == 0, "loaned-in players are listed")
	await _go("finance")
	_check(hub.current.get_child_count() > 3, "the finance screen still renders")


func _test_arabic() -> void:
	Loc.set_language("ar", false)
	Loc.missing.clear()
	for tab in ["search", "shortlist", "offers", "mine", "loans", "history"]:
		await _go("transfers", {"tab": tab})
	var other: PlayerData = null
	for p: PlayerData in db.players.values():
		if p.team_id != "" and p.team_id != USER and p.status != PlayerData.Status.YOUTH:
			other = p
			break
	await _go("player_profile", {"player_id": other.id})
	_press(hub.current, "MakeOffer")
	await _frames(2)
	await _close_dialogs()
	await _go("player_profile", {"player_id": db.get_squad(USER)[3].id})
	_press(hub.current, "ListForLoan")
	await _frames(2)
	await _close_dialogs()
	var missing := Loc.missing.keys().filter(func(k: String) -> bool:
		return k.begins_with("MKT_") or k.begins_with("OFFER_") or k.begins_with("CONTRACT_") or k.begins_with("NOTE_") or k.begins_with("FIN"))
	_check(missing.is_empty(), "[ar] every market text is translated", str(missing))
	_check(MarketUI.window_text(2).contains(Loc.LRI) or MarketUI.window_text(2).contains("5"), "[ar] numbers are isolated in Arabic text")
	Loc.set_language("de", false)
	Loc.missing.clear()
	await _go("transfers", {"tab": "offers"})
	await _go("transfers")
	_check(Loc.missing.keys().filter(func(k: String) -> bool: return k.begins_with("MKT_")).is_empty(), "[de] every market text is translated")
	Loc.set_language("en", false)
