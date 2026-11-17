class_name CardDetailView
extends Control

## Card Detail View (round 3, C3): the full card next to a panel with everything the game knows about the
## same live player — full name, flag + country, crest + club + league, age and birth year, height and
## weight, preferred foot, main and secondary positions, shirt number, rating / potential, contract (years +
## weekly wage), market value, fitness and morale, traits as chips, the last five match ratings (when a career
## log has them) and the attribute bars. Modal overlay; closes with the button, Escape, or a click on the
## dimmed background. Emits `open_profile` instead of navigating itself.

signal open_profile(player_id: String)

var _player_id := ""
var card_data: PlayerCardData


## Opens the overlay on `host` for `player_id`. Returns null for an unknown id. `match_log` (a career's
## engine reports, oldest first) fills the "last 5 matches" row when given.
static func open(host: Node, db: Node, player_id: String, match_log: Array = [], is_captain := false) -> CardDetailView:
	var card := PlayerCardData.from_player(db, player_id)
	if card == null:
		return null
	card.is_captain = is_captain
	card.with_recent_ratings(match_log)
	var view := CardDetailView.new()
	view._player_id = player_id
	view.card_data = card
	view._build(db, card)
	host.add_child(view)
	return view


func _build(db: Node, card: PlayerCardData) -> void:
	name = "CardDetailView"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIKit.panel()
	center.add_child(panel)
	var row := UIKit.hbox(24)
	panel.add_child(row)
	var big := PlayerCard.new(300.0)
	big.name = "DetailCard"
	big.compact = false
	big.setup(card, db)
	row.add_child(big)
	var info := UIKit.vbox(6)
	info.name = "DetailInfo"
	info.custom_minimum_size = Vector2(380, 0)
	var scroll := UIKit.scroll(info)
	scroll.custom_minimum_size = Vector2(400, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_fill(info, db, card)


func _fill(info: VBoxContainer, db: Node, card: PlayerCardData) -> void:
	var th := CardCategory.theme(card.category)
	var title := UIKit.label(card.full_name, 24, CardCategory.GOLD)
	title.name = "FullName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	info.add_child(UIKit.label(Loc.f("CARD_DETAIL_CATEGORY", Loc.t(CardCategory.loc_key(card.category))), 15, th["accent"]))
	# identity rows: icon + text
	var country := _icon_row(card.flag, Vector2(36, 24), card.country_name, "DetailCountry")
	info.add_child(country)
	var club_text := card.club_name if card.club_name != "" else Loc.t("PROFILE_FREE_AGENT")
	if card.league_name != "":
		club_text = "%s · %s" % [Loc.iso(club_text), Loc.iso(card.league_name)]
	info.add_child(_icon_row(card.club_crest, Vector2(28, 28), club_text, "DetailClub"))
	var grid := GridContainer.new()
	grid.name = "DetailFacts"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	info.add_child(grid)
	var born := Loc.f("CARD_DETAIL_AGE_BORN", [card.age, card.birth_year]) if card.birth_year > 0 else Loc.f("CARD_DETAIL_AGE", card.age)
	_fact(grid, "CARD_DETAIL_L_AGE", born)
	_fact(grid, "CARD_DETAIL_L_BODY", Loc.f("CARD_DETAIL_BODY", [card.height_cm, card.weight_kg]))
	_fact(grid, "CARD_DETAIL_L_FOOT", Loc.enum_name("FOOT", card.preferred_foot))
	var pos_text := Loc.position_code(PlayerData.Position.get(card.position, 0))
	if not card.secondary_positions.is_empty():
		var sec: Array = []
		for sp in card.secondary_positions:
			sec.append(Loc.position_code(PlayerData.Position.get(str(sp), 0)))
		pos_text = "%s (%s)" % [pos_text, ", ".join(sec)]
	_fact(grid, "CARD_DETAIL_L_POSITIONS", pos_text)
	_fact(grid, "CARD_DETAIL_L_NUMBER", Loc.num(card.shirt_number) if card.shirt_number > 0 else "—")
	_fact(grid, "CARD_DETAIL_L_RATING", Loc.ratio(card.overall, card.potential))
	if card.status != "YOUTH":
		_fact(grid, "CARD_DETAIL_L_CONTRACT", Loc.f("CARD_DETAIL_CONTRACT", [card.contract_years, Loc.money(card.salary)]))
		_fact(grid, "CARD_DETAIL_L_VALUE", Loc.money(card.market_value))
	_fact(grid, "CARD_DETAIL_L_STATUS", Loc.enum_name("STATUS", card.status))
	info.add_child(UIKit.stat_bar(Loc.t("CARD_DETAIL_FITNESS"), card.fitness, 100))
	info.add_child(UIKit.stat_bar(Loc.t("CARD_DETAIL_MORALE"), card.morale, 100))
	if not card.traits.is_empty():
		info.add_child(UIKit.label(Loc.t("CARD_DETAIL_TRAITS"), 15, UIKit.GOLD))
		var chips := HFlowContainer.new()
		chips.name = "DetailTraits"
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		for tr_name in card.traits:
			chips.add_child(_chip(Loc.enum_name("TRAIT", str(tr_name))))
		info.add_child(chips)
	if not card.recent_ratings.is_empty():
		info.add_child(UIKit.label(Loc.t("CARD_DETAIL_LAST_MATCHES"), 15, UIKit.GOLD))
		var form := UIKit.hbox(6)
		form.name = "DetailForm"
		for r in card.recent_ratings:
			form.add_child(_chip(Loc.decimal(float(r), 1), _rating_color(float(r))))
		info.add_child(form)
	info.add_child(UIKit.label(Loc.t("CARD_DETAIL_ATTRIBUTES"), 15, UIKit.GOLD))
	for s in card.stats:
		info.add_child(UIKit.stat_bar(Loc.t("CARD_STAT_FULL_" + str(s["code"])), int(s["value"])))
	if card.is_goalkeeper:
		info.add_child(UIKit.stat_bar(Loc.t("CARD_STAT_GK"), card.goalkeeping))
	var buttons := UIKit.hbox(8)
	var prof := UIKit.button(Loc.t("CARD_DETAIL_OPEN_PROFILE"), func() -> void:
		open_profile.emit(_player_id)
		queue_free(), 150)
	prof.name = "OpenProfile"
	buttons.add_child(prof)
	var close := UIKit.button(Loc.t("CARD_DETAIL_CLOSE"), queue_free, 100)
	close.name = "Close"
	buttons.add_child(close)
	info.add_child(buttons)


func _icon_row(tex: Texture2D, px: Vector2, text: String, node_name: String) -> Control:
	var h := UIKit.hbox(8)
	h.name = node_name
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = tex
	icon.custom_minimum_size = px
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.visible = tex != null
	h.add_child(icon)
	var l := UIKit.label(text, 16)
	l.name = "Text"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	return h


func _fact(grid: GridContainer, key: String, value: String) -> void:
	var k := UIKit.label(Loc.t(key), 14, UIKit.MUTED)
	k.name = key
	grid.add_child(k)
	var v := UIKit.label(value, 15)
	v.name = key + "_value"
	grid.add_child(v)


func _chip(text: String, color: Color = UIKit.GOLD) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(color.r, color.g, color.b, 0.16)
	st.border_color = color
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.add_child(UIKit.label(text, 13, color.lightened(0.25)))
	return p


static func _rating_color(r: float) -> Color:
	if r >= 7.5:
		return UIKit.GOOD
	if r >= 6.0:
		return UIKit.GOLD
	return UIKit.BAD


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
