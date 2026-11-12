extends HubScreen

## Squad Management: Starting XI by formation slot, bench, reserves, captain
## and set-piece takers. All edits go through `Squad` (duplicates impossible).


func build() -> void:
	if not header(Loc.t("SQUAD_SQUAD_MANAGEMENT"), true):
		return
	var squad: Squad = app().squad()
	var pool: Array = db().get_squad(app().user_team_id).filter(
			func(p: PlayerData) -> bool: return p.status == PlayerData.Status.ACTIVE)
	pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	if pool.size() < 11:
		add_child(UIKit.empty_state(Loc.t("SQUAD_YOU_NEED_AT_LEAST_11_AVAILABLE_PLA")))
		return
	var bar := UIKit.hbox(8)
	var auto := UIKit.button(Loc.t("SQUAD_AUTO_PICK_BEST_XI"), _auto, 180)
	auto.name = "AutoPick"
	bar.add_child(auto)
	var errs := squad.validate(db())
	var status := UIKit.label(Loc.t("SQUAD_LINEUP_VALID") if errs.is_empty() else Loc.f("SQUAD_INVALID", errs[0]), 15,
			UIKit.GOOD if errs.is_empty() else UIKit.BAD)
	status.name = "Status"
	bar.add_child(status)
	add_child(bar)
	add_child(UIKit.muted(Loc.f("SQUAD_FORMATION_CHANGE_IT_IN_TACTICAL_FO", squad.formation_id)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	for slot in 11:
		var pos_name: String = PlayerData.Position.keys()[FormationData.slot_position(squad.formation_id, slot)]
		grid.add_child(UIKit.label("%d · %s" % [slot + 1, pos_name], 15, UIKit.GOLD))
		var names: Array = [Loc.t("SQUAD_EMPTY_SLOT")]
		var selected := 0
		for i in pool.size():
			var p: PlayerData = pool[i]
			names.append("%s (%s %d)" % [p.display_name, PlayerData.Position.keys()[p.position], p.get_overall()])
			if p.id == squad.starting[slot]:
				selected = i + 1
		var opt := UIKit.option(names, selected, _assign.bind(slot, pool))
		opt.name = "Slot_%d" % slot
		grid.add_child(opt)
		grid.add_child(UIKit.label("C" if squad.captain_id == squad.starting[slot] and squad.captain_id != "" else "", 15, UIKit.GOLD))
	add_child(UIKit.panel(grid))
	add_child(_card_strip(Loc.t("CARD_SQUAD_STARTING_CARDS"), squad.starting))
	# Captain + set pieces
	var starters: Array = squad.starting.filter(func(id: String) -> bool: return id != "")
	var starter_names: Array = starters.map(func(id: String) -> String: return db().get_player(id).display_name)
	if not starters.is_empty():
		var roles := UIKit.hbox(10)
		roles.add_child(UIKit.label(Loc.t("SQUAD_CAPTAIN"), 14, UIKit.MUTED))
		var cap := UIKit.option(starter_names, maxi(starters.find(squad.captain_id), 0), _set_captain.bind(starters))
		cap.name = "CaptainOption"
		roles.add_child(cap)
		for kind in ["penalty", "free_kick", "corner"]:
			roles.add_child(UIKit.label(Loc.enum_name("SETPIECE", kind), 14, UIKit.MUTED))
			var o := UIKit.option(starter_names, maxi(starters.find(squad.set_pieces[kind]), 0), _set_piece.bind(kind, starters))
			o.name = "SetPiece_%s" % kind
			roles.add_child(o)
		add_child(roles)
	# Bench & reserves
	add_child(UIKit.label(Loc.f("SQUAD_SUBSTITUTES", [squad.bench.size(), Squad.MAX_BENCH]), 16, UIKit.GOLD))
	if squad.bench.is_empty():
		add_child(UIKit.muted(Loc.t("SQUAD_BENCH_IS_EMPTY")))
	for pid in squad.bench:
		add_child(_bench_row(pid, true))
	add_child(UIKit.label(Loc.f("SQUAD_RESERVES", squad.reserves.size()), 16, UIKit.GOLD))
	for pid in squad.reserves:
		add_child(_bench_row(pid, false))


func _bench_row(pid: String, on_bench: bool) -> Control:
	var p: PlayerData = db().get_player(pid)
	var row := UIKit.hbox(8)
	row.add_child(UIKit.label("%s  %s  %s" % [p.display_name, PlayerData.Position.keys()[p.position], overall_text(p)], 15))
	row.add_child(UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": pid}), 80))
	if on_bench:
		row.add_child(UIKit.button(Loc.t("SQUAD_TO_RESERVES"), _move.bind(pid, false), 110))
	else:
		var b := UIKit.button(Loc.t("SQUAD_TO_BENCH"), _move.bind(pid, true), 100)
		b.name = "ToBench_%s" % pid
		row.add_child(b)
	return row


func _assign(index: int, slot: int, pool: Array) -> void:
	var squad: Squad = app().squad()
	if index == 0:
		squad.starting[slot] = ""
		say(Loc.t("SQUAD_SLOT_CLEARED"))
	else:
		var err := squad.assign_starter(db(), slot, (pool[index - 1] as PlayerData).id)
		say(err if err != "" else Loc.t("SQUAD_ASSIGNED"), err != "")
	rebuild()


func _auto() -> void:
	app().squad().auto_pick(db())
	say(Loc.t("SQUAD_BEST_XI_SELECTED"))
	rebuild()


func _set_captain(index: int, starters: Array) -> void:
	var err: String = app().squad().set_captain(starters[index])
	say(err if err != "" else Loc.t("SQUAD_CAPTAIN_SET"), err != "")
	rebuild()


func _set_piece(index: int, kind: String, starters: Array) -> void:
	var err: String = app().squad().set_set_piece_taker(kind, starters[index])
	say(err if err != "" else Loc.t("SQUAD_SET_PIECE_TAKER_SET"), err != "")
	rebuild()


func _move(pid: String, to_bench: bool) -> void:
	var err: String = app().squad().add_to_bench(db(), pid) if to_bench else app().squad().add_to_reserves(db(), pid)
	say(err if err != "" else Loc.t("SQUAD_MOVED"), err != "")
	rebuild()


## Compact player cards of `ids` (read-only view of the same PlayerData the slot
## pickers edit; the lineup logic above is untouched).
func _card_strip(title_text: String, ids: Array) -> Control:
	var box := UIKit.vbox(6)
	box.name = "CardStrip"
	box.add_child(UIKit.label(title_text, 16, UIKit.GOLD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for pid in ids:
		if str(pid) == "" or db().get_player(pid) == null:
			continue
		var card := PlayerCard.new(96.0)
		card.name = "Card_%s" % pid
		card.setup(PlayerCardData.from_player(db(), pid), db())
		card.pressed.connect(func(id: String) -> void:
			var view := CardDetailView.open(hub, db(), id)
			if view != null:
				view.open_profile.connect(func(p2: String) -> void: go("player_profile", {"player_id": p2})))
		flow.add_child(card)
	box.add_child(flow)
	return box
