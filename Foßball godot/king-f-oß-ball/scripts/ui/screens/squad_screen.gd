extends HubScreen

## Squad Management on ONE screen (no scrolling): the Starting XI as cards on a pitch that fills the
## available height (goalkeeper and all lines always visible) next to the bench panel (substitutes, and
## reserves in a collapsible section). Tap a starter and then a substitute (or the other way round) to swap
## them; on desktop one can also be dragged onto the other. Every edit goes through `Squad`, so duplicates
## stay impossible. Captain / set-piece takers live in a "Roles" dialog and show as badges on the cards.
## The old per-slot dropdown list is still there (hidden) as an accessible alternative.

const BENCH_W := 310.0
const ROW_H := 44.0
const WARN := Color(0.95, 0.78, 0.25)
## Below this width the bench becomes a drawer opened with a button.
const NARROW := 700.0

var _squad: Squad
var _pool: Array = []
var _sel: Dictionary = {}              # {} or {"kind": "slot"|"bench"|"reserve", "slot": int, "pid": String}
var _pitch: SquadPitch
var _rows: Dictionary = {}             # player id -> Button (bench / reserve rows)
var _bench_col: Control
var _bench_open := false
var _bench_btn: Button
var _info: Label
var _sel_buttons: HBoxContainer
var _reserves_box: Control
var _reserves_open := false


func _init() -> void:
	super()
	own_scroll = true       # one fixed screen: only the bench list scrolls (inside its panel)


func build() -> void:
	if app().user_team_id == "":
		header(Loc.t("SQUAD_SQUAD_MANAGEMENT"), true)       # shows the "select a team first" state
		return
	_squad = app().squad()
	_sel = {}
	_rows.clear()
	_pool = db().get_squad(app().user_team_id).filter(
			func(p: PlayerData) -> bool: return p.status == PlayerData.Status.ACTIVE)
	_pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	if _pool.size() < 11:
		add_child(UIKit.title(Loc.t("SQUAD_SQUAD_MANAGEMENT")))
		add_child(UIKit.empty_state(Loc.t("SQUAD_YOU_NEED_AT_LEAST_11_AVAILABLE_PLA")))
		return
	_squad.ensure_roles(db())
	add_child(_build_bar())
	var body := UIKit.hbox(12)
	body.name = "SquadBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	body.add_child(_build_pitch_column())
	_bench_col = _build_bench()
	body.add_child(_bench_col)
	if not resized.is_connected(_responsive):
		resized.connect(_responsive)
	_responsive()


# --- top bar -------------------------------------------------------------------------------

func _build_bar() -> Control:
	var bar := UIKit.hbox(8)
	bar.name = "SquadBar"
	# Title and controls share one row: every pixel of height goes to the pitch.
	var title := UIKit.label(Loc.t("SQUAD_SQUAD_MANAGEMENT"), 22, UIKit.GOLD)
	title.name = "ScreenTitle"
	bar.add_child(title)
	var fids := FormationData.ids()
	var fo := UIKit.option(fids.map(func(f: String) -> String: return Loc.ltr(f)), maxi(fids.find(_squad.formation_id), 0), _on_formation.bind(fids))
	fo.name = "SquadFormation"
	fo.tooltip_text = Loc.t("SQUAD_FORMATION_LABEL")
	fo.custom_minimum_size = Vector2(110, 44)
	bar.add_child(fo)
	var auto := UIKit.button(Loc.t("SQUAD_AUTO_PICK_BEST_XI"), _auto, 160)
	auto.name = "AutoPick"
	auto.custom_minimum_size.y = 44
	bar.add_child(auto)
	var roles := UIKit.button(Loc.t("SQUAD_ROLES"), _open_roles, 90)
	roles.name = "RolesButton"
	roles.custom_minimum_size.y = 44
	roles.tooltip_text = Loc.t("SQUAD_ROLES_HINT")
	bar.add_child(roles)
	var toggle := UIKit.button("", _toggle_list, 48)
	toggle.name = "ToggleSlotList"
	toggle.custom_minimum_size = Vector2(48, 44)
	toggle.tooltip_text = Loc.t("SQUAD_SHOW_SLOT_LIST")
	var icon_box := CenterContainer.new()
	icon_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(NavIcon.new("menu", 20.0))
	toggle.add_child(icon_box)
	bar.add_child(toggle)
	_bench_btn = UIKit.button(Loc.t("SQUAD_BENCH_TOGGLE"), func() -> void:
		_bench_open = not _bench_open
		_responsive(), 90)
	_bench_btn.name = "BenchToggle"
	_bench_btn.custom_minimum_size.y = 44
	bar.add_child(_bench_btn)
	var errs := _squad.validate(db())
	var status := UIKit.label(Loc.t("SQUAD_LINEUP_VALID") if errs.is_empty() else Loc.f("SQUAD_INVALID", errs[0]), 15,
			UIKit.GOOD if errs.is_empty() else UIKit.BAD)
	status.name = "Status"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.clip_text = true
	status.custom_minimum_size.x = 60
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(status)
	return bar


func _responsive() -> void:
	if _bench_col == null or not is_instance_valid(_bench_col):
		return
	var narrow := size.x < NARROW
	_bench_btn.visible = narrow
	_bench_col.visible = not narrow or _bench_open


func _toggle_list() -> void:
	var list := find_child("SlotListPanel", true, false) as Control
	var wrap := find_child("PitchWrap", true, false) as Control
	if list == null or wrap == null:
		return
	list.visible = not list.visible
	wrap.visible = not list.visible


# --- pitch ---------------------------------------------------------------------------------

func _build_pitch_column() -> Control:
	var col := UIKit.vbox(0)
	col.name = "PitchColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wrap := AspectRatioContainer.new()
	wrap.name = "PitchWrap"
	wrap.ratio = 0.8
	wrap.stretch_mode = AspectRatioContainer.STRETCH_FIT
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pitch = SquadPitch.new()
	_pitch.name = "SquadPitch"
	_pitch.setup(db(), _squad.formation_id, _squad.starting, _squad.captain_id, _squad.set_pieces)
	_pitch.slot_pressed.connect(_click_slot)
	_pitch.swap_requested.connect(_pair)
	wrap.add_child(_pitch)
	col.add_child(wrap)
	var list := _build_slot_list()
	list.visible = false
	col.add_child(list)
	return col


## The accessible alternative: one dropdown per slot (hidden unless "slot list" is toggled).
func _build_slot_list() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	for slot in 11:
		var pos_name: String = Loc.position_code(FormationData.slot_position(_squad.formation_id, slot))
		grid.add_child(UIKit.label("%d · %s" % [slot + 1, pos_name], 15, UIKit.GOLD))
		var names: Array = [Loc.t("SQUAD_EMPTY_SLOT")]
		var selected := 0
		for i in _pool.size():
			var p: PlayerData = _pool[i]
			names.append("%s (%s %d)" % [p.display_name, Loc.position_code(p.position), p.get_overall()])
			if p.id == _squad.starting[slot]:
				selected = i + 1
		var opt := UIKit.option(names, selected, _assign.bind(slot, _pool))
		opt.name = "Slot_%d" % slot
		grid.add_child(opt)
		grid.add_child(UIKit.label(Loc.t("SQUAD_CAPTAIN_SHORT") if _squad.captain_id == _squad.starting[slot] and _squad.captain_id != "" else "", 15, UIKit.GOLD))
	var list_panel := UIKit.panel(UIKit.scroll(grid))
	list_panel.name = "SlotListPanel"
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return list_panel


# --- bench ---------------------------------------------------------------------------------

func _build_bench() -> Control:
	var panel := UIKit.panel()
	panel.name = "BenchPanel"
	panel.custom_minimum_size = Vector2(BENCH_W, 0)
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := UIKit.vbox(6)
	panel.add_child(col)
	var title := UIKit.label(Loc.f("SQUAD_SUBSTITUTES", [_squad.bench.size(), Squad.MAX_BENCH]), 16, UIKit.GOLD)
	title.name = "BenchTitle"
	col.add_child(title)
	var list := UIKit.vbox(3)
	list.name = "BenchList"
	if _squad.bench.is_empty():
		list.add_child(UIKit.muted(Loc.t("SQUAD_BENCH_IS_EMPTY")))
	for pid in _squad.bench:
		list.add_child(_bench_row(pid, "bench"))
	# Reserves: a collapsible section under the substitutes (inside the same scroll area).
	var res_head := UIKit.button(Loc.f("SQUAD_RESERVES", _squad.reserves.size()), Callable(), 0)
	res_head.name = "ReservesToggle"
	res_head.custom_minimum_size.y = ROW_H
	res_head.tooltip_text = Loc.t("SQUAD_RESERVES_TOGGLE")
	res_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_reserves_box = UIKit.vbox(3)
	_reserves_box.name = "ReservesList"
	_reserves_box.visible = _reserves_open
	for pid in _squad.reserves:
		_reserves_box.add_child(_bench_row(pid, "reserve"))
	res_head.pressed.connect(func() -> void:
		_reserves_open = not _reserves_open
		_reserves_box.visible = _reserves_open)
	list.add_child(res_head)
	list.add_child(_reserves_box)
	var sc := UIKit.scroll(list)
	sc.name = "BenchScroll"
	col.add_child(sc)
	_info = UIKit.muted(Loc.t("SQUAD_SELECT_HINT"))
	_info.name = "SelectionInfo"
	_info.add_theme_font_size_override("font_size", 12)
	col.add_child(_info)
	_sel_buttons = UIKit.hbox(6)
	_sel_buttons.name = "SelectionActions"
	_sel_buttons.visible = false
	col.add_child(_sel_buttons)
	return panel


func _bench_row(pid: String, kind: String) -> Control:
	var p: PlayerData = db().get_player(pid)
	var row := Button.new()
	row.name = "Row_%s" % pid
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.focus_mode = Control.FOCUS_ALL
	row.set_meta("kind", kind)
	var h := UIKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8.0
	h.offset_right = -6.0
	var bar := ColorRect.new()
	bar.name = "FitBar"
	bar.color = Color(0.4, 0.45, 0.55)
	bar.custom_minimum_size = Vector2(5, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var pos := UIKit.label(Loc.position_code(p.position), 14, UIKit.GOLD)
	pos.custom_minimum_size.x = 40
	pos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pos)
	var nm := UIKit.label(p.display_name, 15)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	var ovr := UIKit.label(Loc.num(p.get_overall()), 16, UIKit.TEXT)
	ovr.custom_minimum_size.x = 30
	ovr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ovr)
	row.add_child(h)
	row.pressed.connect(_click_bench.bind(pid, kind))
	row.set_drag_forwarding(_drag_row.bind(pid, kind, row), _can_drop_row.bind(kind), _drop_on_row.bind(pid, kind))
	_rows[pid] = row
	_style_row(row, false, Color(0, 0, 0, 0))
	if kind == "bench":
		row.tooltip_text = "%s — %s" % [p.display_name, Loc.t("SQUAD_TO_RESERVES")]
	return row


func _style_row(row: Button, selected: bool, fit: Color) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = UIKit.PANEL.lightened(0.10 if not selected else 0.2)
	st.set_corner_radius_all(6)
	st.set_border_width_all(2 if (selected or fit.a > 0.0) else 0)
	st.border_color = UIKit.GOLD if selected else fit
	for state in ["normal", "pressed", "hover", "focus", "hover_pressed", "disabled"]:
		row.add_theme_stylebox_override(state, st)
	var bar := row.find_child("FitBar", true, false) as ColorRect
	if bar != null and fit.a > 0.0:
		bar.color = fit
	elif bar != null:
		bar.color = Color(0.4, 0.45, 0.55)


# --- selection / swapping --------------------------------------------------------------------

func _fit_color(p: PlayerData, slot: int) -> Color:
	var f := FormationData.position_fit(p.position, FormationData.slot_position(_squad.formation_id, slot))
	if f >= 1.0:
		return UIKit.GOOD
	return WARN if f > 0.0 else UIKit.BAD


func _click_slot(slot: int, pid: String) -> void:
	_pick({"kind": "slot", "slot": slot, "pid": pid})


func _click_bench(pid: String, kind: String) -> void:
	_pick({"kind": kind, "slot": -1, "pid": pid})


## First tap selects; a second tap on another place swaps the two; the same place deselects.
func _pick(target: Dictionary) -> void:
	if _sel.is_empty():
		_sel = target
	elif _same(_sel, target):
		_sel = {}
	elif _sel["kind"] != "slot" and target["kind"] != "slot" and _sel["kind"] == target["kind"]:
		_sel = target           # two bench (or two reserve) players: just move the selection
	else:
		_pair(_sel, target)
		return
	_refresh_selection()


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a["kind"] == b["kind"] and a["slot"] == b["slot"] and a["pid"] == b["pid"]


func _refresh_selection() -> void:
	var fits: Dictionary = {}
	var selected_slot := -1
	if not _sel.is_empty():
		if _sel["kind"] == "slot":
			selected_slot = _sel["slot"]
		elif db().get_player(_sel["pid"]) != null:
			var sp: PlayerData = db().get_player(_sel["pid"])
			for slot in 11:
				fits[slot] = _fit_color(sp, slot)
	_pitch.set_marks(selected_slot, fits)
	for pid in _rows:
		var row: Button = _rows[pid]
		var is_sel: bool = not _sel.is_empty() and _sel["pid"] == pid and _sel["kind"] != "slot"
		var fit := Color(0, 0, 0, 0)
		if selected_slot >= 0:
			fit = _fit_color(db().get_player(pid), selected_slot)
			row.tooltip_text = _fit_text(db().get_player(pid), selected_slot)
		_style_row(row, is_sel, fit)
	for c in _sel_buttons.get_children():
		c.queue_free()
	if _sel.is_empty():
		_info.text = Loc.t("SQUAD_SELECT_HINT")
		_sel_buttons.visible = false
		return
	var who: String = Loc.t("SQUAD_EMPTY_SLOT")
	if _sel["pid"] != "" and db().get_player(_sel["pid"]) != null:
		who = db().get_player(_sel["pid"]).display_name
	_info.text = Loc.f("SQUAD_SELECTED", who)
	_sel_buttons.visible = true
	if _sel["pid"] != "":
		var prof := UIKit.button(Loc.t("COMMON_PROFILE"), go.bind("player_profile", {"player_id": _sel["pid"]}), 80)
		prof.name = "SelProfile"
		prof.custom_minimum_size.y = 44
		_sel_buttons.add_child(prof)
	if _sel["kind"] == "slot" and _sel["pid"] != "":
		var clear := UIKit.button(Loc.t("SQUAD_CLEAR_SLOT"), _clear_selected, 80)
		clear.name = "SelClear"
		clear.custom_minimum_size.y = 44
		_sel_buttons.add_child(clear)
	elif _sel["kind"] == "bench":
		var to_res := UIKit.button(Loc.t("SQUAD_TO_RESERVES"), _move.bind(_sel["pid"], false), 80)
		to_res.name = "SelToReserves"
		to_res.custom_minimum_size.y = 44
		_sel_buttons.add_child(to_res)
	elif _sel["kind"] == "reserve":
		var to_b := UIKit.button(Loc.t("SQUAD_TO_BENCH"), _move.bind(_sel["pid"], true), 80)
		to_b.name = "ToBench_%s" % _sel["pid"]
		to_b.custom_minimum_size.y = 44
		_sel_buttons.add_child(to_b)


func _fit_text(p: PlayerData, slot: int) -> String:
	var f := FormationData.position_fit(p.position, FormationData.slot_position(_squad.formation_id, slot))
	return Loc.t("SQUAD_FIT_NATURAL") if f >= 1.0 else (Loc.t("SQUAD_FIT_PLAYABLE") if f > 0.0 else Loc.t("SQUAD_FIT_POOR"))


## Swaps two places of the lineup (slot, bench player, reserve) through `Squad`.
func _pair(a: Dictionary, b: Dictionary) -> void:
	var err := _apply_pair(a, b)
	say(err if err != "" else Loc.t("SQUAD_SWAPPED"), err != "")
	if err == "":
		_squad.ensure_roles(db(), false)
		rebuild()
	else:
		_sel = {}
		_refresh_selection()


func _apply_pair(a: Dictionary, b: Dictionary) -> String:
	if a["kind"] != "slot" and b["kind"] == "slot":
		return _apply_pair(b, a)
	if a["kind"] == "slot":
		var slot: int = a["slot"]
		match str(b["kind"]):
			"slot":
				if a["pid"] != "" and b["pid"] != "":
					return _squad.swap_starters(db(), slot, b["slot"])
				if a["pid"] == "" and b["pid"] == "":
					return ""
				var from_slot: int = a["slot"] if a["pid"] != "" else b["slot"]
				var to_slot: int = b["slot"] if a["pid"] != "" else a["slot"]
				return _squad.assign_starter(db(), to_slot, _squad.starting[from_slot])
			"bench":
				if a["pid"] != "":
					return _squad.substitute(db(), slot, b["pid"])
				return _squad.assign_starter(db(), slot, b["pid"])
			"reserve":
				return _squad.assign_starter(db(), slot, b["pid"])
	# bench <-> reserve
	var bench_pid: String = a["pid"] if a["kind"] == "bench" else b["pid"]
	var res_pid: String = a["pid"] if a["kind"] == "reserve" else b["pid"]
	if bench_pid == "" or res_pid == "" or a["kind"] == b["kind"]:
		return "cannot swap"
	var err := _squad.add_to_reserves(db(), bench_pid)
	if err != "":
		return err
	return _squad.add_to_bench(db(), res_pid)


func _clear_selected() -> void:
	if _sel.is_empty() or _sel["kind"] != "slot":
		return
	_squad.starting[_sel["slot"]] = ""
	say(Loc.t("SQUAD_SLOT_CLEARED"))
	rebuild()


# --- drag and drop of bench rows ----------------------------------------------------------------

func _drag_row(_at: Vector2, pid: String, kind: String, src: Control) -> Variant:
	var l := Label.new()
	l.text = db().get_player(pid).display_name
	l.add_theme_color_override("font_color", UIKit.GOLD)
	src.set_drag_preview(l)
	return {"squad_drag": true, "kind": kind, "slot": -1, "pid": pid}


func _can_drop_row(_at: Vector2, data: Variant, kind: String) -> bool:
	return data is Dictionary and data.get("squad_drag", false) and data.get("kind") != kind


func _drop_on_row(_at: Vector2, data: Variant, pid: String, kind: String) -> void:
	_pair(data, {"kind": kind, "slot": -1, "pid": pid})


# --- roles ------------------------------------------------------------------------------------

func _open_roles() -> void:
	var starters: Array = _squad.starting.filter(func(id: String) -> bool: return id != "")
	if starters.is_empty():
		return
	var names: Array = starters.map(func(id: String) -> String:
		var p: PlayerData = db().get_player(id)
		return "%s  %s" % [p.display_name, Loc.position_code(p.position)])
	var d := AcceptDialog.new()
	d.name = "RolesDialog"
	d.title = Loc.t("SQUAD_ROLES")
	d.ok_button_text = Loc.t("COMMON_CLOSE")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(UIKit.label(Loc.t("SQUAD_CAPTAIN"), 15, UIKit.MUTED))
	var cap := UIKit.option(names, maxi(starters.find(_squad.captain_id), 0), _set_captain.bind(starters))
	cap.name = "CaptainOption"
	cap.custom_minimum_size = Vector2(260, 44)
	grid.add_child(cap)
	for kind in ["penalty", "free_kick", "corner"]:
		grid.add_child(UIKit.label(Loc.enum_name("SETPIECE", kind), 15, UIKit.MUTED))
		var o := UIKit.option(names, maxi(starters.find(_squad.set_pieces[kind]), 0), _set_piece.bind(kind, starters))
		o.name = "SetPiece_%s" % kind
		o.custom_minimum_size = Vector2(260, 44)
		grid.add_child(o)
	d.add_child(grid)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(600, 300))


func _refresh_pitch() -> void:
	_pitch.setup(db(), _squad.formation_id, _squad.starting, _squad.captain_id, _squad.set_pieces)
	_refresh_selection()


func _set_captain(index: int, starters: Array) -> void:
	var err: String = _squad.set_captain(starters[index])
	say(err if err != "" else Loc.t("SQUAD_CAPTAIN_SET"), err != "")
	_refresh_pitch()


func _set_piece(index: int, kind: String, starters: Array) -> void:
	var err: String = _squad.set_set_piece_taker(kind, starters[index])
	say(err if err != "" else Loc.t("SQUAD_SET_PIECE_TAKER_SET"), err != "")
	_refresh_pitch()


# --- actions ---------------------------------------------------------------------------------

func _on_formation(index: int, ids: Array) -> void:
	var err: String = _squad.set_formation(ids[index])
	if err == "":
		_squad.auto_pick(db())     # re-fit the XI to the new shape (same as the tactics screen)
		say(Loc.f("TACTICS_FORMATION_LINEUP_REFRESHED", Loc.ltr(ids[index])))
	else:
		say(err, true)
	rebuild()


func _assign(index: int, slot: int, pool: Array) -> void:
	if index == 0:
		_squad.starting[slot] = ""
		say(Loc.t("SQUAD_SLOT_CLEARED"))
	else:
		var err := _squad.assign_starter(db(), slot, (pool[index - 1] as PlayerData).id)
		say(err if err != "" else Loc.t("SQUAD_ASSIGNED"), err != "")
	rebuild()


func _auto() -> void:
	_squad.auto_pick(db())
	say(Loc.t("SQUAD_BEST_XI_SELECTED"))
	rebuild()


func _move(pid: String, to_bench: bool) -> void:
	var err: String = _squad.add_to_bench(db(), pid) if to_bench else _squad.add_to_reserves(db(), pid)
	say(err if err != "" else Loc.t("SQUAD_MOVED"), err != "")
	rebuild()
