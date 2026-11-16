class_name ListingDialog
extends RefCounted

## Puts one of the user's players on the market (transfers v2): "sale" = transfer list with an asking price (quick
## ±10 %) and optionally loan offers too; "loan" = loan list with the preferred length, the lowest wage share a
## borrower must pay and an optional purchase option.

var screen: HubScreen
var market: TransferMarket
var player: PlayerData
var mode := "sale"
var price := 0
var also_loan := false
var loan_weeks := 0
var min_split := 50
var allow_option := false
var option_fee := 0
var ui: Dictionary = {}


static func open(p_screen: HubScreen, player_id: String, p_mode := "sale") -> ListingDialog:
	var d := ListingDialog.new()
	d.screen = p_screen
	d.market = p_screen.app().career.market
	d.player = p_screen.db().get_player(player_id)
	if d.player == null:
		return null
	d.mode = p_mode
	var cur: Dictionary = d.market.listings.get(player_id, {})
	d.price = int(cur.get("price", 0)) if int(cur.get("price", 0)) > 0 else d.market.market_value(d.player)
	d.also_loan = d.market.listing_of(player_id) == TransferMarket.LISTING_BOTH
	d.loan_weeks = int(cur.get("loan_weeks", TransferMarket.weeks_to_season_end(d.market.cur_week)))
	d.min_split = int(cur.get("loan_min_split", 50))
	d.allow_option = bool(cur.get("loan_option", false))
	d.option_fee = int(cur.get("loan_option_fee", d.price))
	var title := Loc.f("MKT_LIST_FOR_SALE_TITLE" if p_mode == "sale" else "MKT_LIST_FOR_LOAN_TITLE", d.player.display_name)
	d.ui = MarketUI.modal(p_screen.hub, title, "ListingDialog", 640.0)
	(d.ui["root"] as Node).set_meta("dialog", d)
	d._fill()
	return d


func _fill() -> void:
	var body: VBoxContainer = ui["body"]
	for ch in body.get_children():
		body.remove_child(ch)
		ch.queue_free()
	var footer: Control = ui["footer"]
	for ch in footer.get_children():
		footer.remove_child(ch)
		ch.queue_free()
	body.add_child(UIKit.label(Loc.f("MKT_MARKET_VALUE", Loc.money(market.market_value(player))), 15))
	if mode == "sale":
		body.add_child(MarketUI.field(Loc.t("MKT_ASKING_PRICE_FIELD"), MarketUI.money_field(price, maxi(market.market_value(player) * 4, 1_000_000),
				func(v: int) -> void: price = v, "PriceField")))
		var quick := UIKit.hbox(8)
		quick.add_child(UIKit.button("-10%", func() -> void:
			price = Valuation.round_value(price * 0.9)
			_fill(), 80))
		quick.add_child(UIKit.button("+10%", func() -> void:
			price = Valuation.round_value(price * 1.1)
			_fill(), 80))
		quick.add_child(UIKit.button(Loc.t("MKT_USE_VALUE"), func() -> void:
			price = market.market_value(player)
			_fill(), 140))
		body.add_child(quick)
		body.add_child(MarketUI.check(Loc.t("MKT_ALSO_LOAN"), also_loan, func(on: bool) -> void:
			also_loan = on
			_fill(), "AlsoLoanCheck"))
	if mode == "loan" or also_loan:
		var w := market.cur_week
		var half := TransferMarket.weeks_to_next_window(w)
		var full := TransferMarket.weeks_to_season_end(w)
		var idx := 0 if loan_weeks == half else (1 if loan_weeks == full else 2)
		var len_opt := UIKit.option([Loc.f("MKT_HALF_SEASON", [half]), Loc.f("MKT_FULL_SEASON", [full]), Loc.t("MKT_CUSTOM")], idx,
				func(i: int) -> void:
					loan_weeks = half if i == 0 else (full if i == 1 else loan_weeks)
					_fill())
		body.add_child(MarketUI.field(Loc.t("MKT_PREFERRED_LENGTH"), len_opt))
		if idx == 2:
			body.add_child(MarketUI.field(Loc.t("MKT_WEEKS"), MarketUI.number(loan_weeks, TransferMarket.MIN_LOAN_WEEKS, TransferMarket.MAX_LOAN_WEEKS, 1,
					func(v: int) -> void: loan_weeks = v)))
		body.add_child(MarketUI.field(Loc.t("MKT_MIN_SPLIT"), MarketUI.number(min_split, 0, 100, 5, func(v: int) -> void: min_split = v, " %", "MinSplitField"),
				Loc.t("MKT_MIN_SPLIT_HINT")))
		body.add_child(MarketUI.check(Loc.t("MKT_ALLOW_OPTION"), allow_option, func(on: bool) -> void:
			allow_option = on
			_fill(), "AllowOptionCheck"))
		if allow_option:
			body.add_child(MarketUI.field(Loc.t("MKT_OPTION_FEE"), MarketUI.money_field(option_fee, maxi(market.market_value(player) * 4, 1_000_000),
					func(v: int) -> void: option_fee = v, "OptionPriceField")))
	var ok := UIKit.button(Loc.t("MKT_CONFIRM_LISTING"), _confirm, 180)
	ok.name = "ConfirmListing"
	footer.add_child(ok)
	footer.add_child(UIKit.button(Loc.t("COMMON_CANCEL"), _close, 110))


func _confirm() -> void:
	var listing := TransferMarket.LISTING_LOAN
	if mode == "sale":
		listing = TransferMarket.LISTING_BOTH if also_loan else TransferMarket.LISTING_TRANSFER
	elif market.is_transfer_listed(player.id):
		listing = TransferMarket.LISTING_BOTH
	var err := market.set_listing(player.team_id, player.id, listing, {"price": price, "loan_weeks": loan_weeks,
			"loan_min_split": min_split, "loan_option": allow_option, "loan_option_fee": option_fee if allow_option else 0})
	if err != "":
		(ui["status"] as Label).text = ErrorText.localize(err, screen.db())
		return
	if mode == "sale":
		screen.say(Loc.f("MKT_LISTED_SALE", [player.display_name, Loc.money(price)]))
	else:
		screen.say(Loc.f("MKT_LISTED_LOAN", [player.display_name]))
	_close()


func _close() -> void:
	if is_instance_valid(ui.get("root")):
		(ui["root"] as Node).queue_free()
	screen.rebuild()
