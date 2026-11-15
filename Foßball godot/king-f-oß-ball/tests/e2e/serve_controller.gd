## Helper for tests/e2e/controller_browser_e2e.js: runs the REAL KingControllerServer headless and prints one
## line per event (token, connect, input edges, pause, lost) so a browser test can assert what the game side saw.
##   godot --headless --path . --script tests/e2e/serve_controller.gd -- 17500 40
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 17500
	var secs := float(args[1]) if args.size() > 1 else 40.0
	var s := KingControllerServer.new()
	s.port = port
	root.add_child(s)
	await process_frame
	s.select_address("127.0.0.1")
	s.client_connected.connect(func(slot: int) -> void: print("EV connected ", slot))
	s.client_disconnected.connect(func(slot: int) -> void: print("EV lost ", slot))
	s.pause_requested.connect(func(slot: int) -> void: print("EV pause ", slot))
	s.input_received.connect(func(slot: int, move: Vector2, press: Array, release: Array) -> void:
		print("EV input ", slot, " move=(%.2f,%.2f) press=%s release=%s" % [move.x, move.y, str(press), str(release)]))
	print("EV token ", s.token, " port ", s.port)
	# a fresh token for every pairing, printed so the harness can re-pair
	s.registry.changed.connect(func() -> void: print("EV token ", s.token, " port ", s.port))
	await create_timer(secs).timeout
	s.stop()
	quit()
