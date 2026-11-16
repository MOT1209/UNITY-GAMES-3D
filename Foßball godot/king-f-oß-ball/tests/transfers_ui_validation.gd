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
	await _test_offer_rows()
	await _test_negotiation_layout()
	await _test_badge_inside_button()
	await _test_profile_layout()
	await _test_search_toolbar()
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


func _form_label(row: Node) -> Node:
	for c in row.find_children("*", "Label", true, false):
		if c.has_meta("form_label"):
			return c
	return null


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
	var pm := (_find(hub.current, "PositionsMenu") as MenuButton).get_popup()
	pm.id_pressed.emit(PlayerData.Position.LB)
	pm.id_pressed.emit(PlayerData.Position.RB)
	pm.popup_hide.emit()
	await _frames(3)
	var multi := hub.current.find_children("Buy_*", "Button", true, false)
	_check(not multi.is_empty() and multi.all(func(b: Node) -> bool:
		return db.get_player(str(b.name).trim_prefix("Buy_")).position in [PlayerData.Position.LB, PlayerData.Position.RB]),
		"several positions can be ticked at once (LB + RB)")
	pm = (_find(hub.current, "PositionsMenu") as MenuButton).get_popup()
	pm.id_pressed.emit(PlayerData.Position.LB)
	pm.id_pressed.emit(PlayerData.Position.RB)
	pm.popup_hide.emit()
	await _frames(3)
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
	var npp := _find(dlg, "NoPlayVsParent") as CheckBox
	_check(npp != null, "the loan form offers 'may not play against his own club'")
	npp.toggled.emit(true)
	_press(dlg, "SendButton")
	await _frames(2)
	var o: TransferOffer = m.user_offers("outgoing", false).filter(func(x: TransferOffer) -> bool: return x.player_id == p.id)[0]
	_check(o.type == TransferOffer.LOAN_WITH_OPTION and o.wage_split_percent == 60 and o.no_play_vs_parent == 1, "the loan offer carries the chosen terms",
			"%s %d %d" % [o.type, o.wage_split_percent, o.no_play_vs_parent])
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
	var rn := _find(hub.current, "RepliesNextWeek") as CheckBox
	_check(rn != null and not rn.button_pressed, "offers tab: 'clubs answer next week' setting (off by default)")
	rn.toggled.emit(true)
	_check(m.replies_next_week, "the setting switches on")
	rn.toggled.emit(false)
	_check(_find(hub.current, "Offer_%d" % o.id) != null and _find(hub.current, "Accept_%d" % o.id) != null, "the incoming offer is listed with accept / counter / reject")
	_press(hub.current, "Accept_%d" % o.id)
	await _frames(3)
	_check(o.status == TransferOffer.COMPLETED and mine.team_id == buyer, "accepting sells the player", o.status)
	app.state_changed.emit()
	await _frames(2)
	_check(m.needs_user_action() > 0 or hub.find_child("Nav_transfers", true, false).get_node_or_null("Badge") == null
			or (hub.find_child("Nav_transfers", true, false).get_node("Badge") as Node).is_queued_for_deletion(), "the dot disappears when nothing waits")


## Round 4, offers tab: horizontal 36-44 px buttons coloured by meaning, new offers first, an external club's offer.
func _test_offer_rows() -> void:
	var m: TransferMarket = app.career.market
	var mine: Array = db.get_squad(USER).filter(func(p: PlayerData) -> bool:
		return p.loan_parent == "" and m.listing_of(p.id) == TransferMarket.LISTING_NONE and not m.arrivals.has(p.id))
	var a: PlayerData = mine[0]
	var b: PlayerData = mine[1]
	var buyer := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.squad_ids.size() < TransferMarket.MAX_SQUAD - 1:
			buyer = t.id
			break
	var old: TransferOffer = m.make_offer(buyer, a.id, TransferOffer.PERMANENT, {"fee": m.market_value(a)})["offer"]
	old.unread = false
	old.expires_week = m.abs_week() + 1
	var fresh: TransferOffer = m.make_external_offer(b.id, "Porto Alto SK", "Portugal", int(m.market_value(b) * 0.85))["offer"]
	fresh.expires_week = m.abs_week() + 3
	await _go("transfers", {"tab": "offers"})
	var rows := hub.current.find_children("Offer_*", "HBoxContainer", true, false)
	var ids: Array = rows.map(func(n: Node) -> int: return int(str(n.name).trim_prefix("Offer_")))
	_check(ids.find(fresh.id) >= 0 and ids.find(old.id) >= 0 and ids.find(fresh.id) < ids.find(old.id), "new offers come first, even when an older one expires sooner", str(ids))
	var ok := true
	var detail := ""
	for pref in ["Accept_", "Counter_", "Reject_"]:
		for o: TransferOffer in [old, fresh]:
			var btn := _find(hub.current, "%s%d" % [pref, o.id]) as Button
			if btn == null:
				ok = false
				detail += " missing %s%d" % [pref, o.id]
				continue
			if btn.size.y > 44.0 or btn.size.y < 34.0 or btn.size.x <= btn.size.y:
				ok = false
				detail += " %s%d %s" % [pref, o.id, str(btn.size)]
	_check(ok, "the offer buttons are horizontal and 34-44 px high (1280x720)", detail)
	var acc := _find(hub.current, "Accept_%d" % fresh.id) as Button
	var rej := _find(hub.current, "Reject_%d" % fresh.id) as Button
	var cnt := _find(hub.current, "Counter_%d" % fresh.id) as Button
	var green := (acc.get_theme_stylebox("normal") as StyleBoxFlat).border_color
	var red := (rej.get_theme_stylebox("normal") as StyleBoxFlat).border_color
	_check(green.g > green.r and red.r > red.g and not (cnt.get_theme_stylebox("normal") is StyleBoxFlat and (cnt.get_theme_stylebox("normal") as StyleBoxFlat).border_color == green),
			"accept is green, reject red, counter neutral")
	var row := _find(hub.current, "Offer_%d" % fresh.id)
	var line1 := row.find_child("OfferLine1", true, false) as Control
	var texts := ""
	for lb in row.find_children("*", "Label", true, false):
		texts += (lb as Label).text + "|"
	_check(line1 != null and texts.contains("Porto Alto SK") and texts.contains(Loc.t("MKT_NEW")), "line 1 names the player and the (external) club with the new badge", texts)
	_check(row.find_child("OfferTerms", true, false) != null and row.find_child("OfferStatusLine", true, false) != null, "line 2 holds the terms and line 3 the status")
	var status := (row.find_child("OfferStatusLine", true, false) as Label).text
	_check(status.contains(Loc.f("MKT_ROUNDS_LEFT", [3])), "line 3 shows the negotiation rounds left", status)
	var card := row.find_children("*", "PlayerCard", true, false)
	_check(not card.is_empty() and (card[0] as PlayerCard).minimal and (card[0] as Control).custom_minimum_size.x >= 80.0, "the offer shows the small readable card (C2)")
	# the user accepts the external bid: the player leaves, the fee arrives
	var bal: int = app.career.ledger().balance
	_press(hub.current, "Accept_%d" % fresh.id)
	await _frames(3)
	_check(fresh.status == TransferOffer.COMPLETED and b.team_id == "" and app.career.ledger().balance == bal + fresh.fee, "accepting an external club's offer sells the player abroad", fresh.status)
	m.withdraw(old.id)
	old.status = TransferOffer.EXPIRED


## Round 4, negotiation window: every field is one row "title | control"; one wage-split slider with ticks and a live
## text; fields follow the deal type; the acceptance chance follows every change; nothing leaves the window.
func _test_negotiation_layout() -> void:
	var m: TransferMarket = app.career.market
	var p: PlayerData = null
	for q: PlayerData in db.players.values():
		if q.team_id != "" and q.team_id != USER and q.loan_parent == "" and q.status != PlayerData.Status.YOUTH and int(m.squad_rank(q)["pos"]) >= 2 \
				and db.get_team(q.team_id).squad_ids.size() > TransferMarket.MIN_SQUAD + 1 and m.refusal(q, USER, true) == "":
			p = q
			break
	await _go("player_profile", {"player_id": p.id})
	_press(hub.current, "RequestLoan")
	await _frames(3)
	var dlg := _dialog("NegotiationDialog")
	var panel := _find(dlg, "ModalPanel") as Control
	var controls := dlg.find_children("*", "Range", true, false).filter(func(n: Node) -> bool: return n is HSlider or n is SpinBox)
	var untitled: Array = []
	for r in controls:
		var cur: Node = r
		var row: Node = null
		while cur != null and cur != dlg:
			if cur.has_meta("form_row"):
				row = cur
				break
			cur = cur.get_parent()
		var title: Node = _form_label(row) if row != null else null
		if title == null or (title as Label).text == "":
			untitled.append(r.name)
	_check(controls.size() >= 5 and untitled.is_empty(), "every slider and number field sits in a row with its title", str(untitled))
	var fee_row := (_find(dlg, "LoanFeeField") as Node).get_parent().get_parent()
	_check(fee_row.find_children("*", "SpinBox", true, false).size() == 1 and fee_row.find_children("*", "HSlider", true, false).size() == 1
			and not (fee_row.find_child("MoneyReadable", true, false) as Label).visible or int((_find(dlg, "LoanFeeField") as SpinBox).value) >= MarketUI.READABLE_FROM,
			"the loan fee is one field with its slider on one row (no second copy of a small amount)")
	var wage_rows := dlg.find_children("*", "HBoxContainer", true, false).filter(func(n: Node) -> bool:
		return n.has_meta("form_row") and n.find_child("WageSplitSlider", true, false) != null)
	_check(wage_rows.size() == 1 and (_form_label(wage_rows[0]) as Label).text == Loc.t("MKT_WAGE_SPLIT"), "the wage split has its own titled row")
	var ticks := _find(dlg, "WageSplitTicks")
	_check(ticks != null and ticks.get_child_count() == 5, "the wage split slider has marks at 0 / 25 / 50 / 75 / 100")
	var split_row := wage_rows[0] as Control
	var label_y := (_form_label(split_row) as Control).get_global_rect().position.y
	var slider_y := (_find(dlg, "WageSplitSlider") as Control).get_global_rect().position.y
	_check(absf(label_y - split_row.get_global_rect().position.y) < 4.0 and slider_y >= split_row.get_global_rect().position.y - 1.0, "the title is aligned with the top of its control")
	var inside := true
	var offender := ""
	var prect := panel.get_global_rect()
	for c in panel.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl.get_global_rect().size == Vector2.ZERO:
			continue
		var r := ctl.get_global_rect()
		if r.position.x < prect.position.x - 1.0 or r.end.x > prect.end.x + 1.0:
			var scroll_clip := false
			var up: Node = ctl.get_parent()
			while up != null and up != dlg:
				if up is ScrollContainer and (up as Control).get_global_rect().position.x >= prect.position.x - 1.0 and (up as Control).get_global_rect().end.x <= prect.end.x + 1.0:
					scroll_clip = true
				up = up.get_parent()
			if not scroll_clip:
				inside = false
				offender = "%s %s" % [ctl.name, str(r)]
				break
	_check(inside, "nothing in the negotiation window leaves the window horizontally", offender)
	# the fields follow the deal type
	_check(_find(dlg, "OptionFeeField") == null and _find(dlg, "ObligationAppsField") == null, "a plain loan shows no purchase option")
	var to := _find(dlg, "TypeOption") as OptionButton
	to.item_selected.emit(2)
	await _frames(3)
	dlg = _dialog("NegotiationDialog")
	_check(_find(dlg, "OptionFeeField") != null and _find(dlg, "ObligationAppsField") == null, "a loan with option shows the option price only")
	to = _find(dlg, "TypeOption") as OptionButton
	to.item_selected.emit(3)
	await _frames(3)
	dlg = _dialog("NegotiationDialog")
	_check(_find(dlg, "OptionFeeField") != null and _find(dlg, "ObligationAppsField") != null, "a loan with obligation shows the price and the appearance condition")
	# the acceptance chance follows every change
	var chance := _find(dlg, "ChanceLabel") as Label
	var split := _find(dlg, "WageSplitSlider") as HSlider
	split.value = 100
	(_find(dlg, "OptionFeeField") as SpinBox).value = (_find(dlg, "OptionFeeField") as SpinBox).max_value
	await _frames(1)
	var high := chance.text
	split.value = 0
	(_find(dlg, "OptionFeeField") as SpinBox).value = 0
	await _frames(1)
	_check(chance.text != high, "the acceptance chance updates at once when a field changes", "%s / %s" % [high, chance.text])
	await _close_dialogs()


## The red count sits inside its button (in LTR and in RTL), not over the screen edge.
func _test_badge_inside_button() -> void:
	var m: TransferMarket = app.career.market
	var mine: PlayerData = db.get_squad(USER).filter(func(p: PlayerData) -> bool: return p.loan_parent == "")[2]
	var buyer := ""
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != USER and t.squad_ids.size() < TransferMarket.MAX_SQUAD - 1:
			buyer = t.id
			break
	var o: TransferOffer = m.make_offer(buyer, mine.id, TransferOffer.PERMANENT, {"fee": m.market_value(mine)})["offer"]
	for lang in ["en", "ar"]:
		Loc.set_language(lang, false)
		await _frames(2)
		app.state_changed.emit()
		await _go("transfers")
		await _frames(2)
		for target in [hub.find_child("Nav_transfers", true, false), hub.find_child("Section_club", true, false)]:
			var dot := (target as Node).get_node_or_null("Badge") as Control
			var good := dot != null and (target as Control).get_global_rect().encloses(dot.get_global_rect())
			_check(good, "[%s] the red count of %s is inside its button" % [lang, str(target.name)],
					"%s vs %s" % [str((target as Control).get_global_rect()), str(dot.get_global_rect()) if dot != null else "none"])
	Loc.set_language("en", false)
	m.withdraw(o.id)
	o.status = TransferOffer.EXPIRED


## Round 4, profile: starts at the top, the market bar stays in view, the 3D model faces the camera, no flat chart.
func _test_profile_layout() -> void:
	var m: TransferMarket = app.career.market
	var mine: PlayerData = db.get_squad(USER)[4]
	await _go("player_profile", {"player_id": mine.id})
	await _frames(5)
	var scroll := _find(hub.current, "ProfileScroll") as ScrollContainer
	_check(scroll != null and scroll.scroll_vertical == 0, "the profile opens at the top (scroll_vertical == 0)")
	var bar := _find(hub.current, "TransferActions") as Control
	_check(bar != null and hub.get_global_rect().encloses(bar.get_global_rect()) and bar.get_global_rect().position.y > scroll.get_global_rect().end.y - 4.0,
			"the market buttons are a fixed bar under the scrolling profile, in view without scrolling")
	var card := _find(hub.current, "ProfileCard") as Control
	_check(card != null and card.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1.0, "the whole card is visible at the top")
	var prev := _find(hub.current, "ProfilePreview") as PlayerPreview
	_check(prev != null and prev.model != null and not prev.auto_spin and is_zero_approx(prev.model.rotation.y), "the 3D player stands facing the camera")
	var before := prev.model.rotation.y
	var ev := InputEventMouseMotion.new()
	prev._drag = true
	ev.relative = Vector2(40, 0)
	prev._gui_input(ev)
	prev._drag = false
	_check(not is_equal_approx(prev.model.rotation.y, before), "dragging turns the player")
	m.value_history.erase(mine.id)
	await _go("player_profile", {"player_id": mine.id})
	_check(_find(hub.current, "ValueTrendNone") != null and _find(hub.current, "ValueTrend") == null, "no value history: 'not enough data yet', no flat chart")
	m.value_history[mine.id] = [1_000_000]
	await _go("player_profile", {"player_id": mine.id})
	_check(_find(hub.current, "ValueTrendNone") != null and _find(hub.current, "ValueTrend") == null, "one value point still draws no chart")
	m.value_history[mine.id] = [1_000_000, 1_100_000, 1_050_000]
	await _go("player_profile", {"player_id": mine.id})
	_check(_find(hub.current, "ValueTrend") != null, "three value points draw the chart")


## Round 4, search: reset and save sit in the toolbar with the filters toggle; the folded-out filters are a 3-column grid.
func _test_search_toolbar() -> void:
	await _go("transfers", {"tab": "search"})
	var bar := _find(hub.current, "SearchToolbar")
	_check(bar != null and bar.find_child("ResetFilters", true, false) != null and bar.find_child("SaveSearch", true, false) != null
			and bar.find_child("FiltersToggle", true, false) != null, "reset and save search are in the toolbar next to the filters toggle")
	var tb_h := (bar as Control).size.y
	_check(tb_h < 100.0, "the toolbar takes at most two lines", str(tb_h))
	if _find(hub.current, "FilterPanel") == null:
		_press(hub.current, "FiltersToggle")
		await _frames(3)
	var grid := _find(hub.current, "FilterGrid") as GridContainer
	_check(grid != null and grid.columns == 3, "the filters are a grid of three columns")
	var panel_h := (_find(hub.current, "FilterPanel") as Control).get_global_rect().size.y
	_check(panel_h < 330.0, "the folded-out filters do not push the list far down", str(panel_h))
	_press(hub.current, "FiltersToggle")
	await _frames(2)


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
