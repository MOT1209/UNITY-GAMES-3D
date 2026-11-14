class_name PairingScreen
extends Control

## PC-side KING CONTROLLER pairing screen (P5).
## Generates a one-time token, starts the WebSocket server, renders the QR code
## and connection status. Launched as an overlay from the main menu.

var server: KingControllerServer

@onready var _title: Label = null
var _qr: TextureRect
var _url: Label
var _token: Label
var _status: Label
var _close: Button


func _ready() -> void:
	_build_ui()
	server = KingControllerServer.new()
	add_child(server)
	server.pairing_changed.connect(_refresh_status)
	_refresh_status()
	# keep server reachable by the match scene
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and "king_controller_server" in gm:
		gm.king_controller_server = server


func _exit_tree() -> void:
	# Leave the server running so the match can use it; detach from this node
	# by reparenting to GameManager if possible.
	if server != null and is_instance_valid(server):
		if server.get_parent() == self:
			remove_child(server)
			var gm := get_node_or_null("/root/GameManager")
			if gm != null:
				gm.add_child(server)
				if "king_controller_server" in gm:
					gm.king_controller_server = server


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 0.96)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var center := CenterContainer.new()
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var heading := Label.new()
	heading.text = "KING CONTROLLER"
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", Color(0.93, 0.75, 0.3))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	var sub := Label.new()
	sub.text = "Scan the QR with your phone on the same Wi-Fi"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(280, 280)
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(_qr)

	_url = Label.new()
	_url.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_url.add_theme_font_size_override("font_size", 16)
	box.add_child(_url)

	_token = Label.new()
	_token.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_token.add_theme_font_size_override("font_size", 22)
	_token.add_theme_color_override("font_color", Color(0.93, 0.75, 0.3))
	box.add_child(_token)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_close = Button.new()
	_close.text = "Close"
	_close.custom_minimum_size = Vector2(200, 44)
	_close.pressed.connect(queue_free)
	box.add_child(_close)


func _refresh_status() -> void:
	if server == null:
		return
	_url.text = server.pairing_url()
	_token.text = "Token: " + server.token
	var connected := 0
	for s in server._slots:
		if s != -1:
			connected += 1
	_status.text = "Connected devices: %d / %d" % [connected, server.max_slots]
	_render_qr()


func _render_qr() -> void:
	if server == null:
		return
	var m := server.qr_matrix()
	var sz: int = m.get("size", 0)
	if sz <= 0:
		return
	var modules: Array = m["modules"]
	var scale := 8
	var img := Image.create(sz * scale, sz * scale, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for r in range(sz):
		for c in range(sz):
			if modules[r][c]:
				for dy in range(scale):
					for dx in range(scale):
						img.set_pixel(c * scale + dx, r * scale + dy, Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	_qr.texture = tex