## Helper for tests/e2e/controller_browser_e2e.js: runs the REAL KingControllerServer headless and prints one
## line per event (token, connect, input edges, pause, lost, view) so a browser test can assert what the game side saw.
##   godot --headless --path . --script tests/e2e/serve_controller.gd -- 17500 40
## Events are ALSO mirrored to tests/e2e/.events (one line each) so a harness that cannot capture piped stdout
## (the Godot console build deadlocks when its stdout is a pipe on Windows) can still read them.
extends SceneTree

const EVENTS_FILE := "res://tests/e2e/.events"


func _log(line: String) -> void:
	print(line)


func _initialize() -> void:
	# truncate the event log for this run
	var tf := FileAccess.open(EVENTS_FILE, FileAccess.WRITE)
	if tf:
		tf.close()
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 17500
	var secs := float(args[1]) if args.size() > 1 else 40.0
	var s := KingControllerServer.new()
	s.port = port
	root.add_child(s)
	await process_frame
	s.select_address("127.0.0.1")
	s.client_connected.connect(func(slot: int) -> void: _log("EV connected %d" % slot))
	s.client_disconnected.connect(func(slot: int) -> void: _log("EV lost %d" % slot))
	s.pause_requested.connect(func(slot: int) -> void: _log("EV pause %d" % slot))
	s.input_received.connect(func(slot: int, move: Vector2, press: Array, release: Array) -> void:
		_log("EV input %d move=(%.2f,%.2f) press=%s release=%s" % [slot, move.x, move.y, str(press), str(release)]))
	s.view_changed.connect(func(slot: int, view: String, on: bool) -> void:
		_log("EV view %d %s on=%s" % [slot, view, str(on)]))
	_log("EV token %s port %d" % [s.token, s.port])
	# a fresh token for every pairing, printed so the harness can re-pair
	s.registry.changed.connect(func() -> void: _log("EV token %s port %d" % [s.token, s.port]))
	await create_timer(secs).timeout
	s.stop()
	quit()