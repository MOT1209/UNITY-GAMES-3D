## Strength probe: strong v weak 3D matches, prints score / shots / passes per match. Not a test.
##   godot --headless --fixed-fps 60 --path . res://tools/exp/strength_probe.tscn -- n=10 min=2 base=500
extends Node

func _arg(name: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return float(a.split("=")[1])
	return def

func _ready() -> void:
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var n := int(_arg("n", 10))
	var minutes := _arg("min", 2.0)
	var base := int(_arg("base", 500))
	var strong := "club_desert_kings"
	var weak := "club_obsidian"
	var w := 0
	var d := 0
	var gs := 0
	var gw := 0
	for i in n:
		var strong_home := i % 2 == 0
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await MatchQualityRunner.run_match(self, base + i, minutes, false, strong if strong_home else weak, weak if strong_home else strong)
		var sc: PackedStringArray = str(r.get("score", "0-0")).split("-")
		var s_g := int(sc[0]) if strong_home else int(sc[1])
		var w_g := int(sc[1]) if strong_home else int(sc[0])
		gs += s_g
		gw += w_g
		if s_g > w_g: w += 1
		elif s_g == w_g: d += 1
		print("match %d strong_home=%s strong %d - %d weak | shots %s | on_target %.0f%% | passes %s pass%% %.0f | %d ms" % [i, strong_home, s_g, w_g, r.get("shots", "?"), float(r.get("on_target_pct", 0)), r.get("passes", "?"), float(r.get("pass_pct", 0)), Time.get_ticks_msec() - t0])
	print("STRENGTH n=%d min=%.1f: W %d D %d L %d | goals strong %d weak %d" % [n, minutes, w, d, n - w - d, gs, gw])
	get_tree().quit()
