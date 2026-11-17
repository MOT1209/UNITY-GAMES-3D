## Match quality measurement (Phase M0): plays full-engine 3D matches and prints the quality table.
##   godot --headless --fixed-fps 60 --path . res://tools/qa_m3d.tscn -- [matches=4] [minutes=5] [human] [seed=100]
## `human` lets `SimulatedHuman` play the home side. Prints one line per match, the averages and a JSON block.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var matches := 4
	var minutes := 5.0
	var human := false
	var base_seed := 100
	for a in args:
		if a == "human":
			human = true
		elif a.begins_with("matches="):
			matches = int(a.substr(8))
		elif a.begins_with("minutes="):
			minutes = float(a.substr(8))
		elif a.begins_with("seed="):
			base_seed = int(a.substr(5))
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for i in matches:
		var r: Dictionary = await MatchQualityRunner.run_match(self, base_seed + i, minutes, human)
		if r.has("error"):
			print("ERROR ", r["error"])
			continue
		rows.append(r)
		print(MatchQualityRunner.line(r))
	var avg := MatchQualityRunner.average(rows)
	print("AVERAGE ", JSON.stringify(avg))
	print("wall time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit(0)
