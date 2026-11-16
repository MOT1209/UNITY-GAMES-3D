class_name NegotiationDialog
extends RefCounted

## Negotiation window used for every club-to-club deal (transfers v2): a new offer (buy, loan, loan with option or
## obligation), the reply to a counter-offer, and the user's counter to an AI offer for one of their players.
## Left: the player, his value, the asking price and the user's budget. Right: the terms of the chosen deal type.
## Below: the chance of acceptance, the rounds so far and the actions. Every rule is applied by `TransferMarket`.

var screen: HubScreen
var market: TransferMarket
var db: Node
var player: PlayerData
var offer: TransferOffer           # null for a new offer
var incoming := false              # the user answers an AI offer with a counter
var type: String = TransferOffer.PERMANENT
var terms: Dictionary = {}
var ui: Dictionary = {}
var _loan_length := 1              # 0 = half season, 1 = full season, 2 = custom


## Opens the window for `player_id`. `offer_id` > 0 continues an existing negotiation.
static func open(p_screen: HubScreen, player_id: String, p_type := "", offer_id := 0) -> NegotiationDialog:
	var d := NegotiationDialog.new()
	d.screen = p_screen
	d.db = p_screen.db()
	d.market = p_screen.app().career.market
	d.player = d.db.get_player(player_id)
	if d.player == null:
		return null
	d.offer = d.market.get_offer(offer_id) if offer_id > 0 else null
	if d.offer != null:
		d.type = d.offer.type
		d.terms = d.offer.terms()
		d.incoming = d.offer.to_club == d.market.user_club and d.offer.from_club != d.market.user_club
	else:
		var free := d.market.free_type(d.player)
		d.type = p_type if p_type != "" else (free if free == TransferOffer.FREE else TransferOffer.PERMANENT)
		d.terms = d._default_terms(d.type)
	d._build()
	return d


func _default_terms(t: String) -> Dictionary:
	var price := market.seller_price(player) if player.team_id != "" else 0
	var out := {"fee": Valuation.round_value(price * 0.9), "installments": 1, "sell_on_percent": 0,
			"loan_weeks": TransferMarket.weeks_to_season_end(market.cur_week), "loan_fee": 0, "wage_split_percent": 100,
			"option_fee": 0, "obligation_apps": 0, "recall_after_weeks": 0, "min_play_percent": 0}
	if t == TransferOffer.LOAN_WITH_OPTION or t == TransferOffer.LOAN_WITH_OBLIGATION:
		out["option_fee"] = price
	if t == TransferOffer.LOAN_WITH_OBLIGATION:
		out["obligation_apps"] = 15
	if player.team_id != "" and (t == TransferOffer.LOAN or t == TransferOffer.LOAN_WITH_OPTION or t == TransferOffer.LOAN_WITH_OBLIGATION):
		out["wage_split_percent"] = market.min_wage_split(player)
		out["loan_fee"] = market.expected_loan_fee(player, int(out["loan_weeks"]))
	return out


func _types() -> Array:
	var free := market.free_type(player)
	if free == TransferOffer.FREE:
		return [TransferOffer.FREE]
	var out: Array = [TransferOffer.PERMANENT, TransferOffer.LOAN, TransferOffer.LOAN_WITH_OPTION, TransferOffer.LOAN_WITH_OBLIGATION]
	if free == TransferOffer.PRE_CONTRACT:
		out.append(TransferOffer.PRE_CONTRACT)
	return out


func _build() -> void:
	var title := Loc.f("MKT_NEGOTIATE_TITLE", player.display_name)
	ui = MarketUI.modal(screen.hub, title, "NegotiationDialog")
	(ui["root"] as Node).set_meta("dialog", self)       # the overlay keeps this controller alive
	_fill()


func _fill() -> void:
	var body: VBoxContainer = ui["body"]
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var footer: Control = ui["footer"]
	for c in footer.get_children():
		footer.remove_child(c)
		c.queue_free()
	var cols := HFlowContainer.new()
	cols.add_theme_constant_override("h_separation", 18)
	cols.add_theme_constant_override("v_separation", 12)
	body.add_child(cols)
	cols.add_child(_player_panel())
	var right := UIKit.vbox(8)
	right.name = "Terms"
	right.custom_minimum_size = Vector2(minf(460.0, float(ui["width"]) - 40.0), 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_terms_fields(right)
	_chance_and_rounds(body)
	_actions(footer)


func _player_panel() -> Control:
	var box := UIKit.vbox(4)
	box.name = "PlayerSide"
	box.custom_minimum_size = Vector2(230, 0)
	var card := PlayerCard.new(150.0)
	card.setup(PlayerCardData.from_data(db, player), db)
	box.add_child(card)
	var club: TeamData = db.get_team(player.team_id)
	box.add_child(UIKit.label(player.display_name, 17, UIKit.GOLD))
	box.add_child(UIKit.muted("%s · %s · %s" % [Loc.position_code(player.position), Loc.f("MKT_AGE", [player.age]),
			Loc.iso(club.display_name) if club != null else Loc.t("PROFILE_FREE_AGENT")]))
	box.add_child(UIKit.label(Loc.f("MKT_MARKET_VALUE", Loc.money(market.market_value(player))), 14))
	if player.team_id != "" and not incoming:
		var ask := UIKit.label(Loc.f("MKT_ASKING_PRICE", Loc.money(market.seller_price(player))), 14, UIKit.GOLD)
		ask.name = "AskingPrice"
		box.add_child(ask)
	box.add_child(UIKit.label(Loc.f("MKT_WAGE_NOW", Loc.money(player.salary)), 14, UIKit.MUTED))
	var l: FinanceLedger = screen.app().career.ledger()
	box.add_child(UIKit.label(Loc.f("MKT_MY_BUDGET", [Loc.money(l.transfer_budget), Loc.money(l.balance)]), 13, UIKit.MUTED))
	return box


func _terms_fields(right: VBoxContainer) -> void:
	var types := _types()
	var editable := offer == null or incoming or offer.status in [TransferOffer.COUNTERED]
	if offer == null:
		var opt := UIKit.option(types.map(func(t: String) -> String: return MarketUI.type_name(t)), maxi(0, types.find(type)),
				func(i: int) -> void:
					var was_loan := type in [TransferOffer.LOAN, TransferOffer.LOAN_WITH_OPTION, TransferOffer.LOAN_WITH_OBLIGATION]
					type = types[i]
					var fresh := _default_terms(type)
					if was_loan:                       # keep the loan terms already chosen when switching between loan types
						for k in ["loan_weeks", "loan_fee", "wage_split_percent", "recall_after_weeks", "min_play_percent"]:
							fresh[k] = terms[k]
					terms = fresh
					_fill())
		opt.name = "TypeOption"
		right.add_child(MarketUI.field(Loc.t("MKT_DEAL_TYPE"), opt))
	else:
		right.add_child(MarketUI.field(Loc.t("MKT_DEAL_TYPE"), UIKit.label(MarketUI.type_name(type), 15)))
	if type == TransferOffer.FREE or type == TransferOffer.PRE_CONTRACT:
		right.add_child(UIKit.muted(Loc.t("MKT_FREE_EXPLAIN" if type == TransferOffer.FREE else "MKT_PRE_CONTRACT_EXPLAIN")))
		return
	var max_fee := maxi(int(market.market_value(player) * 3), 1_000_000)
	if type == TransferOffer.PERMANENT:
		var fee := MarketUI.money_field(int(terms["fee"]), max_fee, _set_term.bind("fee"), "FeeField")
		right.add_child(MarketUI.field(Loc.t("MKT_FEE"), fee))
		var inst := UIKit.option(range(1, TransferOffer.MAX_INSTALLMENTS + 1).map(func(n: int) -> String:
				return Loc.t("MKT_ONE_PAYMENT") if n == 1 else Loc.f("MKT_N_INSTALLMENTS", [n])),
				int(terms["installments"]) - 1, func(i: int) -> void: _set_term(i + 1, "installments"))
		inst.name = "InstallmentsOption"
		right.add_child(MarketUI.field(Loc.t("MKT_INSTALLMENTS"), inst, Loc.t("MKT_INSTALLMENTS_HINT")))
		right.add_child(MarketUI.field(Loc.t("MKT_SELL_ON"), MarketUI.number(int(terms["sell_on_percent"]), 0, TransferOffer.MAX_SELL_ON, 5,
				_set_term.bind("sell_on_percent"), " %", "SellOnField")))
	else:
		_loan_fields(right, max_fee)
	if not editable:
		MarketUI.lock(right)


func _loan_fields(right: VBoxContainer, max_fee: int) -> void:
	var w := market.cur_week
	var half := TransferMarket.weeks_to_next_window(w)
	var full := TransferMarket.weeks_to_season_end(w)
	var weeks := int(terms["loan_weeks"])
	_loan_length = 0 if weeks == half else (1 if weeks == full else 2)
	var len_opt := UIKit.option([Loc.f("MKT_HALF_SEASON", [half]), Loc.f("MKT_FULL_SEASON", [full]), Loc.t("MKT_CUSTOM")], _loan_length,
			func(i: int) -> void:
				_loan_length = i
				terms["loan_weeks"] = half if i == 0 else (full if i == 1 else int(terms["loan_weeks"]))
				_fill())
	len_opt.name = "LoanLengthOption"
	right.add_child(MarketUI.field(Loc.t("MKT_LOAN_LENGTH"), len_opt))
	if _loan_length == 2:
		right.add_child(MarketUI.field(Loc.t("MKT_WEEKS"), MarketUI.number(weeks, TransferMarket.MIN_LOAN_WEEKS, TransferMarket.MAX_LOAN_WEEKS, 1,
				_set_term.bind("loan_weeks"), "", "LoanWeeksField")))
	right.add_child(MarketUI.field(Loc.t("MKT_LOAN_FEE"), MarketUI.money_field(int(terms["loan_fee"]), maxi(market.market_value(player) / 4, 500_000),
			_set_term.bind("loan_fee"), "LoanFeeField")))
	# wage split: the borrower's share (the user's when the user borrows). Title | slider with ticks, live text below it.
	var split_box := UIKit.vbox(2)
	split_box.name = "WageSplitBox"
	var slider := HSlider.new()
	slider.name = "WageSplitSlider"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = int(terms["wage_split_percent"])
	slider.custom_minimum_size = Vector2(200, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tick_count = 5
	slider.ticks_on_borders = true
	var split_text := UIKit.label(_split_text(int(terms["wage_split_percent"])), 14, UIKit.GOLD)
	split_text.name = "WageSplitText"
	split_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slider.value_changed.connect(func(v: float) -> void:
		terms["wage_split_percent"] = int(v)
		split_text.text = _split_text(int(v))
		_refresh_chance())
	split_box.add_child(slider)
	var ticks := HBoxContainer.new()
	ticks.name = "WageSplitTicks"
	for i in 5:
		var t := UIKit.label("%d%%" % (i * 25), 11, UIKit.MUTED)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var first := HORIZONTAL_ALIGNMENT_RIGHT if Loc.is_rtl() else HORIZONTAL_ALIGNMENT_LEFT     # the row is mirrored in Arabic
		var last := HORIZONTAL_ALIGNMENT_LEFT if Loc.is_rtl() else HORIZONTAL_ALIGNMENT_RIGHT
		t.horizontal_alignment = first if i == 0 else (last if i == 4 else HORIZONTAL_ALIGNMENT_CENTER)
		ticks.add_child(t)
	split_box.add_child(ticks)
	split_box.add_child(split_text)
	right.add_child(MarketUI.field(Loc.t("MKT_WAGE_SPLIT"), split_box))
	if type == TransferOffer.LOAN_WITH_OPTION or type == TransferOffer.LOAN_WITH_OBLIGATION:
		right.add_child(MarketUI.field(Loc.t("MKT_OPTION_FEE" if type == TransferOffer.LOAN_WITH_OPTION else "MKT_OBLIGATION_FEE"),
				MarketUI.money_field(int(terms["option_fee"]), max_fee, _set_term.bind("option_fee"), "OptionFeeField")))
	if type == TransferOffer.LOAN_WITH_OBLIGATION:
		right.add_child(MarketUI.field(Loc.t("MKT_OBLIGATION_APPS"), MarketUI.number(int(terms["obligation_apps"]), 0, 46, 1,
				_set_term.bind("obligation_apps"), "", "ObligationAppsField"), Loc.t("MKT_OBLIGATION_APPS_HINT")))
	right.add_child(MarketUI.field(Loc.t("MKT_RECALL"), MarketUI.number(int(terms["recall_after_weeks"]), 0, 52, 1,
			_set_term.bind("recall_after_weeks"), "", "RecallField"), Loc.t("MKT_RECALL_HINT")))
	right.add_child(MarketUI.field(Loc.t("MKT_MIN_PLAY"), MarketUI.number(int(terms["min_play_percent"]), 0, 100, 10,
			_set_term.bind("min_play_percent"), " %", "MinPlayField")))


## "You pay 60 % = €1,240/week · they pay 40 %" (from the user's side of the deal).
func _split_text(split: int) -> String:
	var borrower_part := player.salary * split / 100
	var user_borrows := not incoming
	if user_borrows:
		return Loc.f("MKT_SPLIT_YOU_PAY", [split, Loc.money(borrower_part), 100 - split, Loc.money(player.salary - borrower_part)])
	return Loc.f("MKT_SPLIT_THEY_PAY", [split, Loc.money(borrower_part), 100 - split, Loc.money(player.salary - borrower_part)])


func _set_term(v: int, key: String) -> void:
	terms[key] = v
	_refresh_chance()


func _probe() -> TransferOffer:
	var o := TransferOffer.new()
	o.from_club = market.user_club
	o.to_club = player.team_id
	o.player_id = player.id
	o.type = type
	o.set_terms(terms)
	if offer != null:
		o.rounds = offer.rounds.duplicate(true)
	return o


func _chance_and_rounds(body: VBoxContainer) -> void:
	if not incoming and type != TransferOffer.FREE and type != TransferOffer.PRE_CONTRACT and (offer == null or offer.status == TransferOffer.COUNTERED):
		var chance := UIKit.label("", 15)
		chance.name = "ChanceLabel"
		body.add_child(chance)
		ui["chance"] = chance
		_refresh_chance()
	if offer != null:
		body.add_child(UIKit.label(Loc.t("MKT_ROUNDS"), 15, UIKit.GOLD))
		for r in offer.rounds:
			var probe := TransferOffer.new()
			probe.type = offer.type
			probe.set_terms(r["terms"])
			var who: TeamData = db.get_team(str(r["by"]))
			var line := UIKit.muted("%s: %s" % [Loc.iso(who.display_name) if who != null else (Loc.iso(market.club_name(str(r["by"]))) if TransferMarket.is_external(str(r["by"])) else "?"), MarketUI.terms_text(probe)])
			line.text_direction = Control.TEXT_DIRECTION_AUTO
			body.add_child(line)
		var st := UIKit.label(MarketUI.status_name(offer.status) + ((" — " + MarketUI.reason_text(offer.reason)) if offer.reason != "" else ""),
				15, MarketUI.status_color(offer.status))
		st.name = "OfferStatus"
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(st)


func _refresh_chance() -> void:
	if not ui.has("chance") or not is_instance_valid(ui["chance"]):
		return
	var c := market.acceptance_chance(_probe())
	var l: Label = ui["chance"]
	l.text = Loc.f("MKT_CHANCE", Loc.t("MKT_CHANCE_" + c.to_upper()))
	l.add_theme_color_override("font_color", UIKit.GOOD if c == "high" else (UIKit.GOLD if c == "medium" else UIKit.BAD))


func _actions(footer: Control) -> void:
	if incoming:
		var send := UIKit.button(Loc.t("MKT_SEND_COUNTER"), _send_counter_incoming, 170)
		send.name = "SendButton"
		footer.add_child(send)
	elif offer == null:
		var send := UIKit.button(Loc.t("MKT_SEND_OFFER"), _send, 170)
		send.name = "SendButton"
		footer.add_child(send)
	elif offer.status == TransferOffer.COUNTERED:
		var acc := UIKit.button(Loc.t("MKT_ACCEPT_COUNTER"), _accept_counter, 170)
		acc.name = "AcceptCounterButton"
		footer.add_child(acc)
		var rev := UIKit.button(Loc.t("MKT_SEND_NEW_TERMS"), _revise, 170)
		rev.name = "SendButton"
		footer.add_child(rev)
	elif offer.status == TransferOffer.ACCEPTED and offer.contract.is_empty() and not offer.is_loan():
		var c := UIKit.button(Loc.t("MKT_PLAYER_CONTRACT"), _open_contract, 170)
		c.name = "ContractButton"
		footer.add_child(c)
	if offer != null and offer.is_open() and not incoming:
		footer.add_child(UIKit.button(Loc.t("MKT_WITHDRAW"), _withdraw, 120))
	footer.add_child(UIKit.button(Loc.t("COMMON_CANCEL"), close, 110))


func close() -> void:
	if is_instance_valid(ui.get("root")):
		(ui["root"] as Node).queue_free()
	screen.rebuild()


func _say(text: String, bad := false) -> void:
	var l: Label = ui["status"]
	l.text = text
	l.add_theme_color_override("font_color", UIKit.BAD if bad else UIKit.GOOD)


func _send() -> void:
	var res := market.make_offer(market.user_club, player.id, type, terms)
	if res["error"] != "":
		_say(ErrorText.localize(res["error"], db), true)
		return
	offer = res["offer"]
	_after_answer()


func _revise() -> void:
	var err := market.revise_offer(offer.id, terms)
	if err != "":
		_say(ErrorText.localize(err, db), true)
		return
	_after_answer()


func _accept_counter() -> void:
	var err := market.accept_counter(offer.id)
	if err != "":
		_say(ErrorText.localize(err, db), true)
		return
	_after_answer()


func _open_contract() -> void:
	(ui["root"] as Node).queue_free()
	ContractDialog.open_for_offer(screen, offer.id)


func _withdraw() -> void:
	market.withdraw(offer.id)
	close()


func _send_counter_incoming() -> void:
	var err := market.answer_incoming(offer.id, "counter", terms)
	if err != "":
		_say(ErrorText.localize(err, db), true)
		return
	terms = offer.terms()
	incoming = offer.status == TransferOffer.PENDING
	_fill()
	_say(Loc.f("MKT_RESULT_" + offer.status.to_upper(), [player.display_name]), offer.status != TransferOffer.PENDING and offer.status != TransferOffer.COMPLETED)


## Shows the club's answer; an agreed permanent / free deal continues with the player's contract.
func _after_answer() -> void:
	terms = offer.terms()
	offer.unread = false
	if offer.status == TransferOffer.ACCEPTED and not offer.is_loan() and offer.contract.is_empty():
		(ui["root"] as Node).queue_free()
		ContractDialog.open_for_offer(screen, offer.id)
		screen.say(Loc.f("MKT_CLUBS_AGREE", player.display_name))
		return
	_fill()
	var bad := offer.status in [TransferOffer.REJECTED, TransferOffer.EXPIRED, TransferOffer.WITHDRAWN]
	var text := Loc.f("MKT_RESULT_" + offer.status.to_upper(), [player.display_name])
	if offer.reason != "":
		text += " — " + MarketUI.reason_text(offer.reason)
	_say(text, bad)
