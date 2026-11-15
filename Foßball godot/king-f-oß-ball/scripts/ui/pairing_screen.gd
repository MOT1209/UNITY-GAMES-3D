class_name PairingScreen
extends Control

## PC-side KING CONTROLLER pairing screen (P5, reworked in P9).
##
## The screen is only a VIEW of the shared server (`GameManager.ensure_controller_server()`): closing it never
## stops the server or drops a connected phone, reopening it never starts a second server. Everything shown
## comes from the real server / registry state (slots, session states, token age, ports, network), refreshed
## on every `pairing_changed` and once per second (token countdown, session age).

const GOLD := Color(0.93, 0.75, 0.3)
const RED := Color(0.85, 0.25, 0.25)
const GREEN := Color(0.35, 0.85, 0.5)

var server: KingControllerServer

var _qr: TextureRect
var _url: Label
var _token: Label
var _status: Label
var _problem: Label
var _slots_box: VBoxContainer
var _addr_pick: OptionButton
var _addr_values: Array[String] = []
var _regen: Button
var _toggle: Button
var _close: Button
var _tick := 0.0
var _last_url := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # usable while the match is paused
	_build_ui()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("ensure_controller_server"):
		server = gm.ensure_controller_server()
	else:
		server = KingControllerServer.new()
		add_child(server)
	server.pairing_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	# The shared server stays alive (owned by GameManager); only this view disconnects.
	if server != null and is_instance_valid(server) and server.pairing_changed.is_connected(_refresh):
		server.pairing_changed.disconnect(_refresh)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh()


func _label(size: int = 16, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.97)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var heading := _label(40, GOLD)
	heading.text = Loc.t("PAIR_HEADING")
	box.add_child(heading)
	var sub := _label(16)
	sub.text = Loc.t("PAIR_SCAN_HINT")
	box.add_child(sub)

	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(260, 260)
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(_qr)

	_url = _label(15)
	box.add_child(_url)
	_token = _label(20, GOLD)
	box.add_child(_token)
	_problem = _label(16, RED)
	box.add_child(_problem)

	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var addr_lbl := Label.new()
	addr_lbl.text = Loc.t("PAIR_ADDRESS")
	addr_row.add_child(addr_lbl)
	_addr_pick = OptionButton.new()
	_addr_pick.custom_minimum_size.x = 300
	_addr_pick.item_selected.connect(_on_address_selected)
	addr_row.add_child(_addr_pick)
	box.add_child(addr_row)

	_status = _label(16)
	box.add_child(_status)

	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 4)
	box.add_child(_slots_box)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_regen = Button.new()
	_regen.text = Loc.t("PAIR_NEW_CODE")
	_regen.custom_minimum_size = Vector2(200, 44)
	_regen.pressed.connect(_on_regen)
	row.add_child(_regen)
	_toggle = Button.new()
	_toggle.custom_minimum_size = Vector2(200, 44)
	_toggle.pressed.connect(_on_toggle)
	row.add_child(_toggle)
	_close = Button.new()
	_close.text = Loc.t("PAIR_CLOSE")
	_close.custom_minimum_size = Vector2(200, 44)
	_close.pressed.connect(queue_free)
	row.add_child(_close)

	var fw := _label(13, Color(0.7, 0.7, 0.7))
	fw.text = Loc.t("PAIR_FIREWALL_NOTE")
	box.add_child(fw)
	var sec := _label(13, Color(0.7, 0.7, 0.7))
	sec.text = Loc.t("PAIR_SECURITY_NOTE")
	box.add_child(sec)


func _on_regen() -> void:
	if server != null:
		server.rotate_token()


func _on_toggle() -> void:
	if server == null:
		return
	if server.running:
		server.stop()                       # also ends every session: the phones are told and release input
	else:
		server.start()
	_refresh()


func _on_address_selected(index: int) -> void:
	if server != null and index >= 0 and index < _addr_values.size():
		server.select_address(_addr_values[index])


func _on_revoke(slot: int) -> void:
	if server != null:
		server.revoke(slot)


func _state_text(state: String) -> String:
	return Loc.t("PAIR_STATE_" + state.to_upper())


func _refresh() -> void:
	if server == null or server.registry == null:
		return
	var reg := server.registry
	var now := Time.get_ticks_msec()

	# Address list (several adapters -> the user can choose)
	_addr_values.clear()
	_addr_pick.clear()
	var selected := -1
	for c in server.lan_candidates:
		var a: String = str(c["address"])
		_addr_values.append(a)
		var label := "%s  (%s)" % [a, str(c["interface"])]
		if str(c.get("note", "")) != "":
			label += " - " + Loc.t("PAIR_NOTE_" + str(c["note"]).to_upper())
		_addr_pick.add_item(Loc.ltr(label))
		if a == server.lan_ip:
			selected = _addr_values.size() - 1
	if selected >= 0:
		_addr_pick.select(selected)
	_addr_pick.disabled = _addr_values.size() < 2

	# Problems are shown, never hidden behind a stale QR code.
	var problem := ""
	if server.startup_error == "port_in_use":
		problem = Loc.t("PAIR_ERR_PORT")
	elif not server.running:
		problem = Loc.t("PAIR_ERR_STOPPED")
	elif server.network_error != "":
		problem = Loc.t("PAIR_ERR_NET_" + server.network_error.to_upper())
	_problem.text = problem
	_problem.visible = problem != ""

	var url := server.pairing_url() if server.running else ""
	_url.text = Loc.ltr(url) if url != "" else ""
	_url.visible = url != ""
	var left := int(ceil(reg.token_remaining_ms(now) / 1000.0))
	_token.text = Loc.f("PAIR_TOKEN_EXPIRES", [Loc.ltr(reg.token), left]) if server.running else ""
	_token.visible = server.running
	_toggle.text = Loc.t("PAIR_STOP") if server.running else Loc.t("PAIR_START")
	_regen.disabled = not server.running

	var line := Loc.f("PAIR_CONNECTED_DEVICES", [reg.connected_count(), KingControllerProtocol.SUPPORTED_SLOTS])
	if server.running:
		line += "   " + Loc.f("PAIR_PORTS", [Loc.ltr(str(server.port)), Loc.ltr(str(server.port + 1))])
	_status.text = line

	_rebuild_slots(reg.snapshot(now))
	if url != _last_url:
		_last_url = url
		_render_qr()


func _rebuild_slots(snap: Array) -> void:
	for ch in _slots_box.get_children():
		_slots_box.remove_child(ch)
		ch.queue_free()
	for e in snap:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		var slot_no := int(e["slot"]) + 1
		if not bool(e["supported"]):
			l.text = Loc.f("PAIR_SLOT_UNSUPPORTED", [slot_no])
			l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			row.add_child(l)
		else:
			var who := str(e["name"])
			var st := str(e["state"])
			l.text = Loc.f("PAIR_SLOT_LINE", [slot_no, _state_text(st), Loc.ltr(who) if who != "" else "-"])
			l.add_theme_color_override("font_color", GREEN if st == "connected" else (GOLD if st != "disconnected" else Color(0.8, 0.8, 0.8)))
			row.add_child(l)
			if st != "disconnected":
				var b := Button.new()
				b.text = Loc.t("PAIR_DISCONNECT")
				b.pressed.connect(_on_revoke.bind(int(e["slot"])))
				row.add_child(b)
		_slots_box.add_child(row)


func _render_qr() -> void:
	var m := server.qr_matrix() if server != null else {}
	var sz: int = int(m.get("size", 0))
	if sz <= 0:
		_qr.texture = null
		return
	var modules: Array = m["modules"]
	var scale := 8
	var quiet := 2
	var dim := (sz + quiet * 2) * scale
	var img := Image.create(dim, dim, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for r in range(sz):
		for c in range(sz):
			if modules[r][c]:
				img.fill_rect(Rect2i((c + quiet) * scale, (r + quiet) * scale, scale, scale), Color.BLACK)
	_qr.texture = ImageTexture.create_from_image(img)
