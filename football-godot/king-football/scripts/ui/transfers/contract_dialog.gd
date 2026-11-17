class_name ContractDialog
extends RefCounted

## Personal terms with a player (transfers v2): after two clubs agree, for a free agent / pre-contract, or a renewal.
## Wage, length, signing bonus, release clause, promised role, loyalty bonus. The player accepts, names his demand
## (the fields then show it) or refuses with a reason. At most `TransferMarket.MAX_CONTRACT_ROUNDS` proposals.

var screen: HubScreen
var market: TransferMarket
var db: Node
var player: PlayerData
var offer_id := 0                   # 0 = renewal
var c := ContractOffer.new()
var ui: Dictionary = {}


static func open_for_offer(p_screen: HubScreen, p_offer_id: int) -> ContractDialog:
	var d := ContractDialog.new()
	d._setup(p_screen)
	var o := d.market.get_offer(p_offer_id)
	if o == null:
		return null
	d.offer_id = p_offer_id
	d.player = d.db.get_player(o.player_id)
	d.c = d.market.default_contract(d.player, o.from_club)
	d.c.salary = maxi(d.market.minimum_wage(d.player), d.player.salary)    # start low: the player names his price
	d._build()
	return d


static func open_renewal(p_screen: HubScreen, player_id: String) -> ContractDialog:
	var d := ContractDialog.new()
	d._setup(p_screen)
	d.player = d.db.get_player(player_id)
	if d.player == null:
		return null
	d.c = ContractOffer.make(d.player.salary, clampi(PlayerLifecycle.renewal_years(d.player) + 1, 1, TransferMarket.MAX_CONTRACT_YEARS),
			d.market.squad_role(player_id) if d.market.squad_role(player_id) != "" else ContractOffer.ROLES[d.market.deserved_role(d.player, d.player.team_id)],
			0, d.market.release_clause(player_id))
	d._build()
	return d


func _setup(p_screen: HubScreen) -> void:
	screen = p_screen
	db = p_screen.db()
	market = p_screen.app().career.market


func _build() -> void:
	ui = MarketUI.modal(screen.hub, Loc.f("MKT_CONTRACT_TITLE", player.display_name), "ContractDialog", 720.0)
	(ui["root"] as Node).set_meta("dialog", self)
	_fill()


func _fill() -> void:
	var body: VBoxContainer = ui["body"]
	for ch in body.get_children():
		body.remove_child(ch)
		ch.queue_free()
	var footer: Control = ui["footer"]
	for ch in footer.get_children():
		footer.remove_child(ch)
		ch.queue_free()
	var head := UIKit.hbox(12)
	head.add_child(MarketUI.flag(db, player, 28))
	var info := UIKit.vbox(2)
	info.add_child(UIKit.label(player.display_name, 18, UIKit.GOLD))
	info.add_child(UIKit.muted("%s · %s · %s" % [Loc.position_code(player.position), Loc.f("MKT_AGE", [player.age]), overall_line()]))
	info.add_child(UIKit.muted(Loc.f("MKT_WAGE_NOW", Loc.money(player.salary))))
	head.add_child(info)
	body.add_child(head)
	var max_wage := maxi(player.salary * 4, market.fair_wage(player) * 4)
	body.add_child(MarketUI.field(Loc.t("MKT_WEEKLY_WAGE"), MarketUI.money_field(c.salary, max_wage, func(v: int) -> void: c.salary = v, "WageField")))
	var years := UIKit.option(range(1, TransferMarket.MAX_CONTRACT_YEARS + 1).map(func(n: int) -> String: return Loc.f("MKT_N_YEARS", [n])),
			c.years - 1, func(i: int) -> void: c.years = i + 1)
	years.name = "YearsOption"
	body.add_child(MarketUI.field(Loc.t("MKT_CONTRACT_YEARS"), years))
	body.add_child(MarketUI.field(Loc.t("MKT_SIGNING_BONUS"), MarketUI.money_field(c.signing_bonus, maxi(c.salary * 52, 100_000),
			func(v: int) -> void: c.signing_bonus = v, "BonusField")))
	body.add_child(MarketUI.field(Loc.t("MKT_RELEASE_CLAUSE"), MarketUI.money_field(c.release_clause, maxi(market.market_value(player) * 5, 1_000_000),
			func(v: int) -> void: c.release_clause = v, "ClauseField"), Loc.t("MKT_RELEASE_CLAUSE_HINT")))
	var roles := UIKit.option(ContractOffer.ROLES.map(func(r: String) -> String: return MarketUI.role_name(r)), maxi(0, ContractOffer.ROLES.find(c.squad_role)),
			func(i: int) -> void: c.squad_role = ContractOffer.ROLES[i])
	roles.name = "RoleOption"
	var deserved := ContractOffer.ROLES[market.deserved_role(player, _club())]
	body.add_child(MarketUI.field(Loc.t("MKT_SQUAD_ROLE"), roles, Loc.f("MKT_ROLE_EXPECTED", MarketUI.role_name(deserved))))
	body.add_child(MarketUI.field(Loc.t("MKT_LOYALTY_BONUS"), MarketUI.money_field(c.loyalty_bonus, maxi(c.salary * 52, 100_000),
			func(v: int) -> void: c.loyalty_bonus = v, "LoyaltyField")))
	var o := market.get_offer(offer_id) if offer_id > 0 else null
	if o != null:
		body.add_child(UIKit.muted(Loc.f("MKT_CONTRACT_ROUNDS", [o.contract_rounds, TransferMarket.MAX_CONTRACT_ROUNDS])))
	var send := UIKit.button(Loc.t("MKT_PROPOSE_CONTRACT"), _propose, 190)
	send.name = "ProposeButton"
	footer.add_child(send)
	footer.add_child(UIKit.button(Loc.t("COMMON_CANCEL"), close, 110))


func overall_line() -> String:
	return Loc.ratio(player.get_overall(), player.potential)


func _club() -> String:
	if offer_id > 0:
		var o := market.get_offer(offer_id)
		return o.from_club if o != null else market.user_club
	return player.team_id


func close() -> void:
	if is_instance_valid(ui.get("root")):
		(ui["root"] as Node).queue_free()
	screen.rebuild()


func _say(text: String, bad := false) -> void:
	var l: Label = ui["status"]
	l.text = text
	l.add_theme_color_override("font_color", UIKit.BAD if bad else UIKit.GOOD)


func _propose() -> void:
	if offer_id > 0:
		var o := market.get_offer(offer_id)
		var err := market.propose_contract(offer_id, c)
		if o.status in [TransferOffer.COMPLETED, TransferOffer.DEFERRED]:
			if o.status == TransferOffer.COMPLETED:
				screen.say(Loc.f("MKT_SIGNED", [player.display_name]))
			else:
				screen.say(Loc.f("MKT_SIGNED_DEFERRED", [player.display_name, MarketUI.window_text(market.cur_week)]))
			close()
			return
		_answer(o.reason, o.status == TransferOffer.REJECTED, err)
		return
	var res := market.negotiate_renewal(player.team_id, player.id, c, market.cur_week)
	if res.get("error", "") != "":
		_say(ErrorText.localize(res["error"], db), true)
		return
	if res["status"] == TransferOffer.ACCEPTED:
		screen.say(Loc.f("MKT_RENEWED", player.display_name))
		close()
		return
	c = (res["demand"] as ContractOffer)
	_fill()
	_answer(str(res["reason"]), res["status"] == TransferOffer.REJECTED and res["reason"] != "CONTRACT_REASON_WAGE", "")


## The player's answer: his demand is put into the fields so the user sees what he wants.
func _answer(reason: String, final: bool, err: String) -> void:
	if offer_id > 0 and not final:
		var o := market.get_offer(offer_id)
		var p := market.player_answer(player, o.from_club, c)
		var demand: ContractOffer = p["demand"]
		c.salary = demand.salary
		c.squad_role = demand.squad_role
		_fill()
	var text := MarketUI.reason_text(reason) if reason != "" else ErrorText.localize(err, db)
	if not final:
		text += " " + Loc.f("MKT_PLAYER_DEMAND", Loc.money(c.salary))
	_say(text, true)
	if final and is_instance_valid(ui.get("footer")):
		MarketUI.lock(ui["body"])
