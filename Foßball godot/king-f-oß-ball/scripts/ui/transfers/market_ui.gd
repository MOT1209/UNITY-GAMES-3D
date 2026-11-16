class_name MarketUI
extends RefCounted

## Shared pieces of the transfer-market UI (transfers v2): the modal overlay used by every market dialog, number fields,
## status badges and the one-line summaries of offers. All text goes through `Loc`; money through `Loc.money`.


## Modal overlay on `host` (the hub): dim background, centred panel with a title, a scrolling body and a footer row.
## Fits phones: the panel is never wider than the screen minus the 16 px gutters, the body scrolls.
static func modal(host: Control, title_text: String, node_name: String, max_width := 860.0) -> Dictionary:
	var root := Control.new()
	root.name = node_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var vp := host.get_viewport_rect().size if host.is_inside_tree() else Vector2(1280, 720)
	var w := minf(max_width, vp.x - 32.0)
	var panel := UIKit.panel()
	panel.name = "ModalPanel"
	panel.custom_minimum_size = Vector2(w, 0)
	center.add_child(panel)
	var box := UIKit.vbox(10)
	panel.add_child(box)
	var head := UIKit.hbox(8)
	var title := UIKit.label(title_text, 22, UIKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var close := UIKit.button("✕", root.queue_free, 44)
	close.name = "CloseButton"
	close.tooltip_text = Loc.t("COMMON_CLOSE") if Loc.has_key("COMMON_CLOSE") else ""
	head.add_child(close)
	box.add_child(head)
	var body := UIKit.vbox(8)
	body.name = "Body"
	var sc := UIKit.scroll(body)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(w - 24.0, clampf(vp.y - 190.0, 220.0, 560.0))
	box.add_child(sc)
	var footer := HFlowContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("h_separation", 8)
	footer.add_theme_constant_override("v_separation", 6)
	box.add_child(footer)
	var status := UIKit.label("", 15, UIKit.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text_direction = Control.TEXT_DIRECTION_AUTO
	box.add_child(status)
	host.add_child(root)
	return {"root": root, "body": body, "footer": footer, "status": status, "width": w}


## A row "label: control" that wraps on narrow screens.
static func field(label_text: String, control: Control, hint := "") -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	var l := UIKit.label(label_text, 15, UIKit.MUTED)
	l.custom_minimum_size = Vector2(190, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	row.add_child(control)
	if hint != "":
		var h := UIKit.label(hint, 13, UIKit.MUTED)
		h.name = "Hint"
		row.add_child(h)
	return row


## Whole-number field (money, weeks, percent). `on_change(int)`.
static func number(value: int, min_v: int, max_v: int, step: int, on_change: Callable, suffix := "", node_name := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.rounded = true
	s.value = clampi(value, min_v, max_v)
	s.suffix = suffix
	s.custom_minimum_size = Vector2(170, 40)
	s.select_all_on_focus = true
	if node_name != "":
		s.name = node_name
	if on_change.is_valid():
		s.value_changed.connect(func(v: float) -> void: on_change.call(int(v)))
	return s


## Money: a slider for quick changes plus the exact field, kept in step. `on_change(int)`.
static func money_field(value: int, max_v: int, on_change: Callable, node_name := "") -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 8)
	var top := maxi(max_v, value)
	var step := 10 if top <= 200_000 else (1000 if top <= 5_000_000 else 10_000)
	var spin := number(value, 0, top, step, Callable(), "", node_name)
	spin.custom_minimum_size = Vector2(190, 40)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = top
	slider.step = step
	slider.value = spin.value
	slider.custom_minimum_size = Vector2(200, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.name = (node_name + "Slider") if node_name != "" else "Slider"
	var shown := UIKit.label(Loc.money(int(spin.value)), 14, UIKit.GOLD)
	shown.name = "MoneyText"
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if int(spin.value) != value:
		on_change.call(int(spin.value))           # the field rounds to its step: the form holds what it shows
	spin.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(slider.value, v):
			slider.set_value_no_signal(v)
		shown.text = Loc.money(int(v))
		on_change.call(int(v)))
	slider.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(spin.value, v):
			spin.value = v)
	box.add_child(spin)
	box.add_child(shown)
	box.add_child(slider)
	return box


## Read-only view of a form (terms that cannot be changed any more).
static func lock(root: Node) -> void:
	for c in root.find_children("*", "", true, false):
		if c is SpinBox or c is HSlider:
			(c as Range).set("editable", false)
		elif c is BaseButton:
			(c as BaseButton).disabled = true


static func check(text: String, pressed: bool, on_toggle: Callable, node_name := "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	if node_name != "":
		c.name = node_name
	c.toggled.connect(func(on: bool) -> void: on_toggle.call(on))
	return c


## Small coloured tag ("For sale", "Loan", "Contract ends", ...).
static func badge(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.55)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UIKit.label(text, 12, color.lightened(0.2)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Status tags of a player on the market.
static func status_badges(market: TransferMarket, p: PlayerData) -> Array:
	var out: Array = []
	if market.is_transfer_listed(p.id):
		out.append(badge(Loc.t("MKT_BADGE_FOR_SALE"), UIKit.GOLD))
	if market.is_loan_listed(p.id):
		out.append(badge(Loc.t("MKT_BADGE_LOAN"), UIKit.GOOD))
	if market.listing_of(p.id) == TransferMarket.LISTING_UNTOUCHABLE:
		out.append(badge(Loc.t("MKT_BADGE_UNTOUCHABLE"), UIKit.BAD))
	if p.team_id == "":
		out.append(badge(Loc.t("MKT_BADGE_FREE"), UIKit.GOOD))
	elif p.contract_years <= 1 and p.loan_parent == "":
		out.append(badge(Loc.t("MKT_BADGE_EXPIRING"), Color(0.95, 0.6, 0.3)))
	if p.loan_parent != "":
		out.append(badge(Loc.t("MKT_BADGE_ON_LOAN"), UIKit.MUTED))
	return out


## Flag of a player's nationality (empty spacer when unknown).
static func flag(db: Node, p: PlayerData, px := 20) -> Control:
	var cid := p.nationality_id if p.nationality_id != "" else FlagService.id_for_name(db, p.nationality)
	var tex: Texture2D = FlagService.texture(cid, true) if cid != "" else null
	if tex == null:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(px, px * 0.67)
		return spacer
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px * 0.67)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.tooltip_text = Loc.country(p.nationality)
	return r


static func type_name(type: String) -> String:
	return Loc.t("MKT_TYPE_" + type.to_upper())


static func status_name(status: String) -> String:
	return Loc.t("MKT_STATUS_" + status.to_upper())


static func status_color(status: String) -> Color:
	match status:
		TransferOffer.COMPLETED, TransferOffer.ACCEPTED:
			return UIKit.GOOD
		TransferOffer.REJECTED, TransferOffer.EXPIRED, TransferOffer.WITHDRAWN:
			return UIKit.BAD
		TransferOffer.COUNTERED, TransferOffer.DEFERRED:
			return UIKit.GOLD
	return UIKit.TEXT


## Short terms of an offer: "€12,000,000 · 3 installments · 10 % sell-on" / "26 weeks · they pay 60 % · option €8,000,000".
static func terms_text(o: TransferOffer) -> String:
	var parts: PackedStringArray = []
	if o.is_loan():
		parts.append(Loc.f("MKT_TERMS_WEEKS", [o.loan_weeks]))
		if o.loan_fee > 0:
			parts.append(Loc.f("MKT_TERMS_LOAN_FEE", Loc.money(o.loan_fee)))
		parts.append(Loc.f("MKT_TERMS_WAGE_SPLIT", [o.wage_split_percent]))
		if o.option_fee > 0:
			parts.append(Loc.f("MKT_TERMS_OPTION" if o.type == TransferOffer.LOAN_WITH_OPTION else "MKT_TERMS_OBLIGATION", Loc.money(o.option_fee)))
		if o.type == TransferOffer.LOAN_WITH_OBLIGATION and o.obligation_apps > 0:
			parts.append(Loc.f("MKT_TERMS_OBLIGATION_APPS", [o.obligation_apps]))
		if o.recall_after_weeks > 0:
			parts.append(Loc.f("MKT_TERMS_RECALL", [o.recall_after_weeks]))
		if o.min_play_percent > 0:
			parts.append(Loc.f("MKT_TERMS_MIN_PLAY", [o.min_play_percent]))
	elif o.type == TransferOffer.FREE or o.type == TransferOffer.PRE_CONTRACT:
		parts.append(type_name(o.type))
	else:
		parts.append(Loc.money(o.fee))
		if o.installments > 1:
			parts.append(Loc.f("MKT_TERMS_INSTALLMENTS", [o.installments]))
		if o.sell_on_percent > 0:
			parts.append(Loc.f("MKT_TERMS_SELL_ON", [o.sell_on_percent]))
	return " · ".join(parts)


## Text of a refusal reason key ("" when none).
static func reason_text(key: String) -> String:
	return Loc.t(key) if key != "" else ""


## "Open — 4 weeks left" / "Deadline day" / "Closed — opens in week 24".
static func window_text(week: int) -> String:
	var w := TransferMarket.window_info(week)
	if w["open"]:
		return Loc.t("MKT_WINDOW_DEADLINE") if w["deadline"] else Loc.f("MKT_WINDOW_OPEN", [int(w["weeks_left"])])
	return Loc.f("MKT_WINDOW_CLOSED", [int(w["next_open"])])


static func role_name(role: String) -> String:
	return Loc.t("MKT_ROLE_" + role.to_upper()) if role != "" else "—"
