## Broadcast camera framing (round 3, A3): during an automatic AI-vs-AI match the ball must sit near the
## vertical middle of the picture — its projected screen position between 35 % and 65 % of the height in
## at least 95 % of the sampled frames (it used to drift into the upper half, leaving a third of the
## screen as empty grass at the bottom).
##   godot --headless --path . res://tests/camera_framing_validation.tscn
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"
const FRAMES := 2400            # 40 s of play at 60 physics frames per second
const LOW := 0.35
const HIGH := 0.65

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Camera framing validation ===")
	var db: Node = get_node("/root/TeamDB")
	db.load_world("")
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 10
	setup.human_side = "none"
	setup.rng_seed = 11
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	var err := m.begin(setup, db)
	_check(err == "", "AI-vs-AI match builds", err)
	if err != "":
		_finish()
		return
	var cam := m.camera as GameCamera
	_check(cam != null and cam.mode == GameCamera.Mode.BROADCAST and cam.tracked_ball == m.ball, "AI match uses the broadcast camera that tracks the ball")
	var inside := 0
	var samples := 0
	var lo := 1.0
	var hi := 0.0
	var hist := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var max_abs_x := 0.0
	for i in FRAMES:
		await get_tree().physics_frame
		if i < 30 or cam.mode != GameCamera.Mode.BROADCAST:
			continue
		var vp := cam.get_viewport().get_visible_rect().size
		var b := m.ball.global_position
		max_abs_x = maxf(max_abs_x, absf(b.x))
		if cam.is_position_behind(b):
			samples += 1
			continue
		var f := cam.unproject_position(b).y / vp.y
		samples += 1
		lo = minf(lo, f)
		hi = maxf(hi, f)
		hist[clampi(int(f * 10.0), 0, 9)] += 1
		if f >= LOW and f <= HIGH:
			inside += 1
	var share := float(inside) / maxf(samples, 1)
	print("[INFO] ball screen height: min %.2f max %.2f, ball |x| max %.1f m, deciles %s" % [lo, hi, max_abs_x, str(hist)])
	_check(samples > FRAMES * 0.8, "enough frames sampled", str(samples))
	_check(share >= 0.95, "ball within 35-65 % of the screen height in >= 95 % of frames", "%.1f %%" % (share * 100.0))
	_check(max_abs_x > 10.0, "the ball really travelled across the pitch during the sample", "%.1f m" % max_abs_x)
	# The look point follows the ball across the pitch closely enough that a far-touchline ball is still framed.
	_check(cam.config.broadcast_track_x_factor >= 0.7, "broadcast camera tracks the ball across the pitch (x factor >= 0.7)", str(cam.config.broadcast_track_x_factor))
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	_finish()


func _finish() -> void:
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
