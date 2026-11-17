## Developer tool: screenshots of the transfer market (transfers v2) in one language and window size.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/transfers_shots.tscn -- <out dir> <lang> [phone]
## Shots: search, offers, my players, loans, negotiation, loan negotiation, contract, listing, player profile.
extends Node

const PACK := "real_2025"
const CLUB := "eng_leicester_city_fc"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://shots"
	var lang: String = a[1] if a.size() > 1 else "en"
	var phone := a.size() > 2 and a[2] == "phone"     # the phone layout (navigation drawer), as on an Android device
	if phone:
		HubRoot.force_compact = 1
	DirAccess.make_dir_recursive_absolute(out)
	Loc.set_language(lang, false)
	var app: Node = get_node("/root/AppHub")
	(get_node("/root/TeamDB") as TeamDatabase).load_world(PACK)
	app.career = null
	app.start_career(CLUB)
	var c: CareerState = app.career
	var m := c.market
	var mine: Array = app.db.get_squad(CLUB)
	mine.sort_custom(func(x: PlayerData, y: PlayerData) -> bool: return x.get_overall() > y.get_overall())
	m.set_listing(CLUB, mine[0].id, TransferMarket.LISTING_UNTOUCHABLE)
	m.set_listing(CLUB, mine[10].id, TransferMarket.LISTING_TRANSFER, {"price": Valuation.round_value(m.market_value(mine[10]) * 0.9)})
	m.set_listing(CLUB, mine[mine.size() - 1].id, TransferMarket.LISTING_LOAN, {"loan_min_split": 50})
	for i in 3:
		app.advance_week()
	# a loan in with an option, so the loans tab and the profile have something to show
	var loanee: PlayerData = null
	for p: PlayerData in app.db.players.values():
		if p.team_id != "" and p.team_id != CLUB and p.loan_parent == "" and p.status != PlayerData.Status.YOUTH \
				and int(m.squad_rank(p)["pos"]) >= 2 and p.get_overall() >= 70 and m.refusal(p, CLUB, true) == "":
			loanee = p
			break
	if loanee != null:
		m.make_offer(CLUB, loanee.id, TransferOffer.LOAN_WITH_OPTION, {"loan_weeks": 20, "wage_split_percent": 60,
				"option_fee": m.seller_price(loanee), "recall_after_weeks": 10, "min_play_percent": 50})
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await _settle(4)
	var win := DisplayServer.window_get_size()
	var tag := "%s_%dx%d%s" % [lang, win.x, win.y, "_phone" if phone else ""]
	for tab in ["search", "offers", "mine", "loans"]:
		hub.navigate("transfers", {"tab": tab})
		await _shot(out, "transfers_%s_%s" % [tab, tag])
	# negotiation for a player of another club
	var target: PlayerData = null
	for p: PlayerData in m.search_v2({"exclude_team": CLUB, "min_overall": 74, "max_overall": 78, "sort": "overall"}):
		if m.refusal(p, CLUB, false) == "":
			target = p
			break
	hub.navigate("transfers")
	await _settle(2)
	var nd := NegotiationDialog.open(hub.current, target.id)
	await _shot(out, "negotiation_%s" % tag)
	_clear(hub)
	var res := m.make_offer(CLUB, target.id, TransferOffer.PERMANENT, {"fee": int(m.seller_price(target) * 0.9)})
	var o: TransferOffer = res["offer"]
	NegotiationDialog.open(hub.current, target.id, "", o.id)
	await _shot(out, "counter_offer_%s" % tag)
	_clear(hub)
	NegotiationDialog.open(hub.current, target.id, TransferOffer.LOAN)
	await _shot(out, "loan_negotiation_%s" % tag)
	_clear(hub)
	m.accept_counter(o.id)
	ContractDialog.open_for_offer(hub.current, o.id)
	await _shot(out, "contract_%s" % tag)
	_clear(hub)
	ListingDialog.open(hub.current, mine[10].id, "sale")
	await _shot(out, "listing_%s" % tag)
	_clear(hub)
	hub.navigate("player_profile", {"player_id": mine[10].id})
	await _settle(30)
	await _shot(out, "profile_mine_%s" % tag)
	hub.navigate("player_profile", {"player_id": target.id})
	await _settle(30)
	await _shot(out, "profile_other_%s" % tag)
	# the search with its filters folded out (3-column grid)
	(load("res://scripts/ui/screens/transfers_screen.gd") as GDScript).set("_filters_open", 1)
	hub.navigate("transfers", {"tab": "search"})
	await _shot(out, "search_filters_%s" % tag)
	(load("res://scripts/ui/screens/transfers_screen.gd") as GDScript).set("_filters_open", 0)
	# an offer from a club outside the loaded leagues, in the offers tab
	var ext_p: PlayerData = mine[10]
	m.make_external_offer(ext_p.id, "Porto Alto SK", "Portugal", int(m.market_value(ext_p) * 0.85))
	hub.navigate("transfers", {"tab": "offers"})
	await _shot(out, "offers_external_%s" % tag)
	get_tree().quit()


func _clear(hub: Node) -> void:
	for ch in hub.get_children():
		if ch.has_meta("dialog"):
			hub.remove_child(ch)
			ch.queue_free()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(out: String, file_name: String) -> void:
	await _settle(8)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, file_name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
