extends HubScreen

## Player Profile: identity, attributes, development, contract and history.


func _init() -> void:
	own_scroll = true


func build() -> void:
	if not header(Loc.t("PROFILE_PLAYER_PROFILE")):
		return
	var p: PlayerData = db().get_player(str(params.get("player_id", "")))
	if p == null:
		add_child(UIKit.empty_state(Loc.t("PROFILE_OPEN_A_PLAYER_FROM_A_SQUAD_OR_ACAD")))
		return
	var scroll := ScrollContainer.new()      # the profile scrolls; the market actions below it stay in view
	scroll.name = "ProfileScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false              # a focused button further down must not scroll the page away from the card
	scroll.scroll_deadzone = UIKit.SCROLL_DEADZONE
	add_child(scroll)
	var content := UIKit.vbox(10)
	content.name = "ProfileContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var top := HFlowContainer.new()          # wraps on narrow windows instead of clipping the attribute bars
	top.add_theme_constant_override("h_separation", 20)
	top.add_theme_constant_override("v_separation", 12)
	var big := PlayerCard.new(210.0)
	big.name = "ProfileCard"
	big.compact = false
	big.setup(PlayerCardData.from_data(db(), p), db())
	big.tooltip_text = Loc.t("CARD_DETAIL_HINT")
	big.pressed.connect(func(pid: String) -> void:      # the full detail panel (C3) on a click / Enter
		var log: Array = app().career.match_log if app().career != null else []
		var sq: Squad = app().squad()
		CardDetailView.open(hub, db(), pid, log, sq != null and sq.captain_id == pid))
	top.add_child(big)
	var preview := PlayerPreview.new(Vector2(240, 320))
	preview.name = "ProfilePreview"
	preview.auto_spin = false               # faces the camera in the idle pose; drag to turn him
	preview.setup(PlayerCardData.from_data(db(), p), db())
	top.add_child(preview)
	var info := UIKit.vbox(2)
	info.add_child(UIKit.label(p.display_name, 26, UIKit.GOLD))
	info.add_child(UIKit.muted(Loc.f("PROFILE_AGE_FOOT", [Loc.position_code(p.position), p.age,
			Loc.country(p.nationality), Loc.enum_name("FOOT", PlayerData.Foot.keys()[p.preferred_foot])])))
	if p.player_type == PlayerData.PlayerType.REAL:
		var facts: PackedStringArray = []
		if p.shirt_number > 0:
			facts.append("#%d" % p.shirt_number)
		if p.height_cm > 0:
			facts.append(Loc.f("PROFILE_HEIGHT", p.height_cm))
		if p.birth_year > 0:
			facts.append(Loc.f("PROFILE_BORN", p.birth_year))
		if not p.secondary_positions.is_empty():
			var codes: PackedStringArray = []
			for s in p.secondary_positions:
				if PlayerData.Position.has(str(s)):
					codes.append(Loc.position_code(PlayerData.Position[str(s)]))
			if not codes.is_empty():
				facts.append(Loc.f("PROFILE_ALSO_PLAYS", ", ".join(codes)))
		if not facts.is_empty():
			info.add_child(UIKit.muted(" · ".join(facts)))
	var ac: Academy = app().academy()
	if ac != null and p.id in ac.roster_ids:
		info.add_child(UIKit.label(Loc.f("PROFILE_OVERALL_POTENTIAL", [p.get_overall(), YouthDevelopment.potential_text(ac, p)]), 18))
		var prog: Array = (YouthDevelopment.state(ac)["progress"] as Dictionary).get(p.id, [])
		if prog.size() >= 2:
			info.add_child(SparkChart.new(prog))
	else:
		info.add_child(UIKit.label(Loc.f("PROFILE_OVERALL_POTENTIAL", [p.get_overall(), p.potential]), 18))
	var team: TeamData = db().get_team(p.team_id)
	info.add_child(UIKit.label(Loc.f("PROFILE_CLUB", [team.display_name if team != null else Loc.t("PROFILE_FREE_AGENT"),
			Loc.f("PROFILE_ON_LOAN_FROM", p.loan_parent) if p.loan_parent != "" else ""]), 15))
	info.add_child(UIKit.label(Loc.f("PROFILE_STATUS_FITNESS_MORALE_EXPERIENCE", [
			Loc.enum_name("STATUS", PlayerData.Status.keys()[p.status]), p.fitness, p.morale, p.experience]), 14, UIKit.MUTED))
	if p.status != PlayerData.Status.YOUTH:
		info.add_child(UIKit.label(Loc.f("PROFILE_SHIRT_CONTRACT_YR_WAGE_WK_VALUE", [
				p.shirt_number, p.contract_years, p.salary, p.transfer_value]), 14, UIKit.MUTED))
	info.add_child(UIKit.label(_appearance_text(p), 13, UIKit.MUTED))
	if not p.traits.is_empty():
		info.add_child(UIKit.label(Loc.f("PROFILE_TRAITS", Loc.traits_text(p.traits)), 14, UIKit.GOLD))
	top.add_child(info)
	var bars := UIKit.vbox(3)
	for attr in PlayerData.ATTRIBUTES:
		if attr == "goalkeeping" and p.position != PlayerData.Position.GK:
			continue
		bars.add_child(UIKit.stat_bar(Loc.enum_name("ATTR", attr), p.get_attribute(attr)))
	top.add_child(bars)
	content.add_child(UIKit.panel(top))
	content.add_child(_personality_panel(p))
	if p.status == PlayerData.Status.YOUTH and app().academy() != null and p.id in app().academy().roster_ids:
		var why := PromotionSystem.why_not(db(), app().academy(), p.id)
		var btn := UIKit.button(Loc.t("COMMON_PROMOTE_TO_FIRST_TEAM"), func() -> void:
			UIKit.confirm(self, Loc.t("PROMO_PROMOTE_THIS_PLAYER_TO_THE_FIRST_T"), func() -> void:
				var err := PromotionSystem.promote(db(), app().academy(), p.id)
				say(err if err != "" else Loc.f("PROMO_DONE", p.display_name), err != "")
				app().state_changed.emit()
				rebuild()), 220)
		btn.disabled = why != ""
		btn.tooltip_text = why
		content.add_child(btn)
	content.add_child(UIKit.label(Loc.t("PROFILE_DEVELOPMENT_HISTORY"), 16, UIKit.GOLD))
	if p.development_history.is_empty():
		content.add_child(UIKit.muted(Loc.t("PROFILE_NO_HISTORY_YET")))
	var recent: Array = p.development_history.slice(-10)
	recent.reverse()
	for h in recent:
		content.add_child(UIKit.muted(_describe(h)))
	scroll.scroll_vertical = 0
	if app().career != null and p.status != PlayerData.Status.YOUTH and p.status != PlayerData.Status.RETIRED:
		add_child(_transfer_panel(p))           # a fixed bar under the scrolling profile


func _describe(h: Dictionary) -> String:
	match str(h.get("event", "")):
		"train":
			return Loc.f("PROFILE_HIST_TRAIN", [int(h.get("week", 0)), Loc.enum_name("ATTR", str(h["attribute"])), int(h["from"]), int(h["to"])])
		"promoted":
			return Loc.f("PROFILE_HIST_PROMOTED", [int(h.get("age", 0)), int(h.get("shirt_number", 0))])
		"generated":
			return Loc.f("PROFILE_HIST_ENTERED", [int(h.get("age", 0)), int(h.get("overall", 0))])
		_:
			return str(h.get("event", "event"))


func _appearance_text(p: PlayerData) -> String:
	var a := PlayerAppearance.sanitize(PlayerAppearance.ensure(p))
	var beard := int(a["beard_style"])
	var beard_text := "" if beard == 0 else " + " + Loc.t("CARD_BEARD_" + str(PlayerLook.BEARD_STYLES[beard]).to_upper())
	return Loc.f("CARD_PROFILE_APPEARANCE", [Loc.t("CARD_HAIR_" + str(a["cut"]).to_upper()),
			beard_text, roundi(float(a["build_pm"]) / 10.0),
			roundi(float(a["height_pm"]) / 10.0)])


# --- transfers v2: what the user can do with this player --------------------------------------------------------------

func _transfer_panel(p: PlayerData) -> Control:
	var career: CareerState = app().career
	var market := career.market
	var me := career.club_id
	var box := UIKit.vbox(8)
	box.name = "TransferActions"
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 10)
	head.add_child(UIKit.label(Loc.t("MKT_PROFILE_MARKET"), 17, UIKit.GOLD))
	head.add_child(UIKit.label(Loc.f("MKT_MARKET_VALUE", Loc.money(market.market_value(p))), 15))
	for b in MarketUI.status_badges(market, p):
		head.add_child(b)
	if market.release_clause(p.id) > 0:
		head.add_child(UIKit.label(Loc.f("MKT_HAS_CLAUSE", Loc.money(market.release_clause(p.id))), 14, UIKit.MUTED))
	if market.squad_role(p.id) != "":
		head.add_child(UIKit.label(Loc.f("MKT_ROLE_IS", MarketUI.role_name(market.squad_role(p.id))), 14, UIKit.MUTED))
	box.add_child(head)
	var hist: Array = market.value_history.get(p.id, [])
	var row := UIKit.hbox(8)
	row.name = "ValueTrendRow"
	row.add_child(UIKit.label(Loc.t("MKT_VALUE_TREND"), 13, UIKit.MUTED))
	if hist.size() >= 2:
		var spark := ValueSparkline.new(hist)
		spark.name = "ValueTrend"
		row.add_child(spark)
	else:
		var none := UIKit.label(Loc.t("MKT_VALUE_TREND_NONE"), 13, UIKit.MUTED)    # one point would draw a flat line
		none.name = "ValueTrendNone"
		row.add_child(none)
	box.add_child(row)
	var actions := HFlowContainer.new()
	actions.name = "TransferButtons"
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	var loan: Dictionary = market.loans.get(p.id, {})
	if p.team_id == me and p.loan_parent == "":
		# one of the user's own players
		if market.is_transfer_listed(p.id):
			actions.add_child(_btn("MKT_UPDATE_PRICE", func() -> void: ListingDialog.open(self, p.id, "sale"), "ListForSale"))
		else:
			actions.add_child(_btn("MKT_LIST_SALE", func() -> void: ListingDialog.open(self, p.id, "sale"), "ListForSale"))
		actions.add_child(_btn("MKT_LIST_LOAN", func() -> void: ListingDialog.open(self, p.id, "loan"), "ListForLoan"))
		if market.listing_of(p.id) != TransferMarket.LISTING_NONE and market.listing_of(p.id) != TransferMarket.LISTING_UNTOUCHABLE:
			actions.add_child(_btn("MKT_UNLIST", func() -> void:
				market.set_listing(me, p.id, TransferMarket.LISTING_NONE)
				rebuild(), "Unlist"))
		var untouchable := market.listing_of(p.id) == TransferMarket.LISTING_UNTOUCHABLE
		actions.add_child(_btn("MKT_UNTOUCHABLE_OFF" if untouchable else "MKT_UNTOUCHABLE_ON", func() -> void:
			market.set_listing(me, p.id, TransferMarket.LISTING_NONE if untouchable else TransferMarket.LISTING_UNTOUCHABLE)
			rebuild(), "Untouchable"))
		actions.add_child(_btn("MKT_RENEW_CONTRACT", func() -> void: ContractDialog.open_renewal(self, p.id), "Renew"))
		var offers := market.user_offers("incoming").filter(func(o: TransferOffer) -> bool: return o.player_id == p.id)
		if not offers.is_empty():
			var ob := UIKit.button(Loc.f("MKT_INCOMING_FOR", [offers.size()]), go.bind("transfers", {"tab": "offers"}))
			ob.name = "IncomingOffers"
			ob.add_theme_color_override("font_color", UIKit.BAD.lightened(0.2))
			actions.add_child(ob)
	elif p.team_id != me and not loan.is_empty() and str(loan["from"]) == me:
		# loaned out by the user: the loan report and the recall
		box.add_child(_loan_report(p, loan, market))
		var rc := _btn("MKT_RECALL_NOW", func() -> void:
			var err := market.recall(p.id, market.cur_week, app().squads)
			say(err if err != "" else Loc.f("MKT_RECALLED", p.display_name), err != "")
			rebuild(), "Recall")
		rc.disabled = not market.can_recall(p.id)
		actions.add_child(rc)
		if bool(loan.get("complained", false)) and not bool(loan.get("compensated", false)):
			var cb := UIKit.button(Loc.f("MKT_CLAIM_COMPENSATION", Loc.money(market.compensation_for(p.id))), func() -> void:
				var err := market.claim_compensation(p.id)
				say(err if err != "" else Loc.f("MKT_COMPENSATION_PAID", p.display_name), err != "")
				rebuild())
			cb.name = "Compensation"
			actions.add_child(cb)
	elif p.team_id == me and not loan.is_empty():
		# loaned in
		box.add_child(_loan_report(p, loan, market))
		if str(loan["type"]) == TransferOffer.LOAN_WITH_OPTION:
			actions.add_child(_btn("MKT_EXERCISE_OPTION", func() -> void:
				var err := market.exercise_option(p.id, market.cur_week, app().squads)
				say(err if err != "" else Loc.f("MKT_RESULT_COMPLETED", [p.display_name]), err != "")
				rebuild(), "ExerciseOption"))
	elif p.team_id == "":
		var terms := market.free_agent_terms(p, me)
		var sign := UIKit.button("", func() -> void:
			UIKit.confirm(self, Loc.f("MKT_SIGN_FREE_CONFIRM", [p.display_name, Loc.money(terms.salary), terms.years]), func() -> void:
				var err := market.sign_free_agent(me, p.id)
				say(err if err != "" else Loc.f("MKT_RESULT_COMPLETED", [p.display_name]), err != "")
				rebuild()), 220)
		sign.name = "SignFreeNow"
		sign.text = Loc.f("MKT_SIGN_FREE_NOW", [Loc.money(terms.salary)])
		UIKit.variant(sign, UIKit.V_PRIMARY)
		actions.add_child(sign)
		actions.add_child(_btn("MKT_NEGOTIATE_FREE", func() -> void: NegotiationDialog.open(self, p.id, TransferOffer.FREE), "NegotiateFree"))
	elif p.loan_parent == "":
		actions.add_child(_btn("MKT_MAKE_OFFER", func() -> void: _open_offer(p.id, TransferOffer.PERMANENT), "MakeOffer"))
		actions.add_child(_btn("MKT_REQUEST_LOAN", func() -> void: _open_offer(p.id, TransferOffer.LOAN), "RequestLoan"))
		if market.free_type(p) == TransferOffer.PRE_CONTRACT:
			actions.add_child(_btn("MKT_PRE_CONTRACT", func() -> void: _open_offer(p.id, TransferOffer.PRE_CONTRACT), "PreContract"))
		actions.add_child(_btn("MKT_SHORTLIST_REMOVE" if p.id in market.shortlist else "MKT_SHORTLIST_ADD", func() -> void:
			market.toggle_shortlist(p.id)
			rebuild(), "Shortlist"))
		if market.release_clause(p.id) > 0:
			actions.add_child(_btn("MKT_PAY_CLAUSE", func() -> void: _pay_clause(p), "PayClause"))
	box.add_child(actions)
	return UIKit.panel(box)


func _btn(key: String, cb: Callable, node_name: String) -> Button:
	var b := UIKit.button(Loc.t(key), cb, 150)
	b.name = node_name
	return b


func _open_offer(pid: String, type: String) -> void:
	var market: TransferMarket = app().career.market
	for o: TransferOffer in market.user_offers("outgoing"):
		if o.player_id == pid:
			if o.status == TransferOffer.ACCEPTED and o.contract.is_empty() and not o.is_loan():
				ContractDialog.open_for_offer(self, o.id)
			else:
				NegotiationDialog.open(self, pid, "", o.id)
			return
	NegotiationDialog.open(self, pid, type)


func _pay_clause(p: PlayerData) -> void:
	var market: TransferMarket = app().career.market
	var res := market.make_offer(app().career.club_id, p.id, TransferOffer.PERMANENT, {"fee": market.release_clause(p.id)})
	if res["error"] != "":
		say(res["error"], true)
		return
	var o: TransferOffer = res["offer"]
	if o.status == TransferOffer.ACCEPTED:
		ContractDialog.open_for_offer(self, o.id)
	else:
		say(MarketUI.status_name(o.status) + " — " + MarketUI.reason_text(o.reason), true)


func _loan_report(p: PlayerData, loan: Dictionary, market: TransferMarket) -> Control:
	var apps := int(loan["apps"])
	var avg := float(loan["rating_sum"]) / apps if apps > 0 else 0.0
	var other: TeamData = db().get_team(str(loan["to"]) if p.team_id != app().career.club_id else str(loan["from"]))
	var v := UIKit.vbox(2)
	v.name = "LoanReport"
	v.add_child(UIKit.label(Loc.f("MKT_LOAN_WITH", [Loc.iso(other.display_name) if other != null else "?", maxi(0, p.loan_weeks_left)]), 15))
	v.add_child(UIKit.muted(Loc.f("MKT_LOAN_STATS_ROW", [apps, int(loan["goals"]), Loc.decimal(avg, 1)]) + "  ·  "
			+ Loc.f("MKT_SPLIT_SHORT", [int(loan["wage_split"])])
			+ ("  ·  " + MarketUI.type_name(str(loan["type"])) + " " + Loc.money(int(loan["option_fee"])) if int(loan["option_fee"]) > 0 else "")))
	if bool(loan.get("complained", false)):
		v.add_child(UIKit.label(Loc.t("MKT_PLAY_PROMISE_BROKEN"), 14, UIKit.BAD))
	return v


## C3.1 / C3.2: personality traits and why his morale moved.
func _personality_panel(p: PlayerData) -> Control:
	var box := UIKit.vbox(3)
	box.name = "PersonalityPanel"
	box.add_child(UIKit.label(Loc.t("PERSONALITY_TITLE"), 16, UIKit.GOLD))
	var pers := PlayerPersonality.for_player(p)
	for t in PlayerPersonality.TRAITS:
		box.add_child(UIKit.stat_bar(Loc.t("PERS_" + str(t).to_upper()), int(pers[t]), 20))
	var career: CareerState = app().career
	if career != null and p.team_id == career.club_id:
		box.add_child(UIKit.label(Loc.t("TALK_PLAYER_TITLE"), 15, UIKit.GOLD))
		var talks := HFlowContainer.new()
		talks.name = "PlayerTalks"
		for kind in PlayerRelations.TALK_KINDS:
			var tb := UIKit.button(Loc.t("TALK_PLAYER_" + str(kind).to_upper()), _talk_player.bind(p.id, str(kind)), 110)
			tb.name = "PTalk_%s" % kind
			talks.add_child(tb)
		box.add_child(talks)
		box.add_child(UIKit.label(Loc.t("MORALE_REASONS"), 15, UIKit.GOLD))
		var reasons := career.morale.reasons(p.id)
		if reasons.is_empty():
			box.add_child(UIKit.muted(Loc.t("MORALE_NO_REASONS")))
		for r in reasons:
			var d := int(r["delta"])
			var l := UIKit.label("%s  %s" % [Loc.t(str(r["key"])), Loc.ltr(("+%d" % d) if d > 0 else str(d))], 14, UIKit.GOOD if d > 0 else UIKit.BAD)
			l.name = "MoraleReason"
			box.add_child(l)
	return UIKit.panel(box)


func _talk_player(pid: String, kind: String) -> void:
	var career: CareerState = app().career
	var r := career.relations.talk(career, db().get_player(pid), kind)
	say(Loc.t(str(r["reply"])), not bool(r["success"]))
	app().state_changed.emit()
	rebuild()
