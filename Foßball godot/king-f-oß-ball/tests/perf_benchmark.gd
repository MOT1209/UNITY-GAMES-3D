## Match performance benchmark (needs a real window — NOT headless):
##   godot --path . res://tests/perf_benchmark.tscn --resolution 1600x720
## Plays a real 11-v-11 AI match for BENCH_SECONDS per graphics level ("low" = phone, "high") and writes
## average FPS, 1 % low FPS, frame time, draw calls, rendered objects and memory to
## KING_QA_OUT/perf_report.txt (default docs/qa). The numbers describe THIS machine's GPU / driver; on a
## software renderer (llvmpipe) they are a pessimistic lower bound, not a phone measurement.
extends Node

const BENCH_SECONDS := 12.0
const WARMUP_SECONDS := 2.0

var _out := "res://docs/qa"
var _lines: Array[String] = []


func _ready() -> void:
	if OS.get_environment("KING_QA_OUT") != "":
		_out = OS.get_environment("KING_QA_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var original: String = GameSettings.settings_path
	GameSettings.settings_path = "user://perf_bench_settings.cfg"
	Engine.max_fps = 0
	var db := get_node("/root/TeamDB")
	db.load_world("")
	_lines.append("KING FOOTBALL match benchmark  %s" % Time.get_datetime_string_from_system())
	_lines.append("renderer: %s | adapter: %s | window %s" % [RenderingServer.get_current_rendering_driver_name(),
			RenderingServer.get_video_adapter_name(), str(get_window().size)])
	for level in ["low", "high"]:
		GameSettings.set_value("graphics", "shadows", level)
		GameSettings.set_value("graphics", "msaa", 0 if level == "low" else 2)
		GameSettings.apply_graphics(get_tree().root)
		Engine.max_fps = 0
		await _run(db, level)
	GameSettings.settings_path = original
	var f := FileAccess.open("%s/perf_report.txt" % _out, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit(0)


func _run(db: Node, level: String) -> void:
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 10
	setup.human_side = "home"
	setup.rng_seed = 31
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	(m.camera as GameCamera).set_mode(GameCamera.Mode.BROADCAST)
	var t := 0.0
	while t < WARMUP_SECONDS:
		await get_tree().process_frame
		t += get_process_delta_time()
	var frames: Array[float] = []
	var draws := 0.0
	var objects := 0.0
	t = 0.0
	while t < BENCH_SECONDS:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames.append(dt)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var n := maxi(frames.size(), 1)
	var sorted := frames.duplicate()
	sorted.sort()
	var worst: Array = sorted.slice(int(n * 0.99), n)
	var worst_avg := 0.0
	for w in worst:
		worst_avg += float(w)
	worst_avg /= maxf(worst.size(), 1)
	var avg_fps := float(n) / maxf(t, 0.001)
	_lines.append("[%s] avg %.1f FPS | 1%% low %.1f FPS | avg frame %.1f ms | draw calls %d | objects %d | static RAM %.0f MB | spectators %d" % [
			level, avg_fps, 1.0 / maxf(worst_avg, 0.0001), 1000.0 * t / n, int(draws / n), int(objects / n),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, m.stand_crowd.spectators if m.stand_crowd != null else 0])
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()
	for i in 3:
		await get_tree().process_frame
