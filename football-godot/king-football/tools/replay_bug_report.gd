## Plays back an F8 bug report (Phase M0) on the real stadium with the replay ghosts.
##   godot --path . res://tools/replay_bug_report.tscn                    (newest report in user://bug_reports)
##   godot --path . res://tools/replay_bug_report.tscn -- path=<file.json> [speed=0.5]
## Keys: Space pause/resume, R restart, Left/Right step 0.5 s. The console prints the per-player state at the moment
## of the report (owner, AI intent, action state, kick being charged). Headless: prints the summary and quits.
extends Node3D

var player: ReplayPlayer
var clip: Dictionary
var speed := 1.0
var _colors: Array[Color] = []


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("path="):
			path = a.substr(5)
		elif a.begins_with("speed="):
			speed = float(a.substr(6))
	if path == "":
		path = _newest()
	var report := MatchBugReport.load_report(path)
	if report.is_empty():
		print("no bug report found (", path, ")")
		get_tree().quit(1)
		return
	print("bug report ", path, "  minute %.0f  owner %s" % [float(report["display_minute"]), report["ball_owner"]])
	for p in report["players"]:
		print("  %s %2d %-14s %-10s %-11s charge=%s owner=%s" % [p["side"], int(p["slot"]), p["player_id"], p["intent"], p["action_state"], p["charging"], p["owner"]])
	clip = MatchBugReport.replay_clip(report)
	print("replay: %d frames, %.1f s" % [(clip["frames"] as Array).size(), float(clip["duration"])])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var arena: Node3D = (load(MatchManager.ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	var stray := arena.get_node_or_null("Player")
	if stray != null:
		stray.queue_free()
	_colors = [Color.WHITE]
	for p in report["players"]:
		_colors.append(Color(0.3, 0.6, 1.0) if p["side"] == "home" else Color(1.0, 0.4, 0.3))
	player = ReplayPlayer.new()
	add_child(player)
	player.start(clip, _colors, speed)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not (event is InputEventKey) or not event.pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			player.paused = not player.paused
		KEY_R:
			player.start(clip, _colors, speed)
		KEY_RIGHT:
			player.seek(player.time + 0.5)
		KEY_LEFT:
			player.seek(maxf(player.time - 0.5, 0.0))


func _newest() -> String:
	var dir := DirAccess.open(MatchBugReport.DIR)
	if dir == null:
		return ""
	var best := ""
	for f in dir.get_files():
		if f.ends_with(".json") and f > best:
			best = f
	return MatchBugReport.DIR + "/" + best if best != "" else ""
