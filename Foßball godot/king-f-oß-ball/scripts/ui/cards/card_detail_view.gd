class_name CardDetailView
extends Control

## Card Detail View (Phase V8-E): enlarged card + the full attribute list of the
## same live player. Modal overlay; closes with the button, Escape, or a click
## on the dimmed background. Emits `open_profile` instead of navigating itself.

signal open_profile(player_id: String)

var _player_id := ""


## Opens the overlay on `host` for `player_id`. Returns null for an unknown id.
static func open(host: Node, db: Node, player_id: String) -> CardDetailView:
	var card := PlayerCardData.from_player(db, player_id)
	if card == null:
		return null
	var view := CardDetailView.new()
	view._player_id = player_id
	view._build(db, card)
	host.add_child(view)
	return view


func _build(db: Node, card: PlayerCardData) -> void:
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
	big.compact = false
	big.setup(card, db)
	row.add_child(big)
	var info := UIKit.vbox(6)
	info.custom_minimum_size = Vector2(260, 0)
	row.add_child(info)
	info.add_child(UIKit.label(card.name, 24, CardCategory.GOLD))
	info.add_child(UIKit.muted(Loc.f("CARD_DETAIL_AGE_CLUB", [card.age, card.club if card.club != "" else "—"])))
	info.add_child(UIKit.label(Loc.f("CARD_DETAIL_CATEGORY", Loc.t(CardCategory.loc_key(card.category))), 15,
			CardCategory.theme(card.category)["accent"]))
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


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
