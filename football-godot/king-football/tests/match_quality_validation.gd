## Phase M acceptance (SLOW, --full only): full-engine 3D matches measured by `MatchQualityProbe`.
##   6 x 5-minute AI-vs-AI matches (Royal Harbor v Northgate, seeds 300..305) and 3 x 5-minute matches with
##   `SimulatedHuman` on the home side (seeds 400..402), `--fixed-fps 60`. Prints the quality table (averages, min, max)
##   and fails on every value outside its target (see TARGETS).
##   godot --headless --fixed-fps 60 --path . res://tests/match_quality_validation.tscn
extends Node

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s — %s" % [name, detail])
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — match quality validation (Phase M, 3D engine) ===")
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var ai_rows: Array = []
	for i in 6:
		var r: Dictionary = await MatchQualityRunner.run_match(self, 300 + i, 5.0, false)
		print("  ", MatchQualityRunner.line(r))
		ai_rows.append(r)
	var h_rows: Array = []
	for i in 3:
		var r: Dictionary = await MatchQualityRunner.run_match(self, 400 + i, 5.0, true)
		print("  ", MatchQualityRunner.line(r))
		h_rows.append(r)
	var ai := MatchQualityRunner.average(ai_rows)
	var hu := MatchQualityRunner.average(h_rows)
	print("AI AVERAGE ", JSON.stringify(ai))
	print("HUMAN AVERAGE ", JSON.stringify(hu))
	_check(ai["pass_pct"] >= 70.0, "AI pass accuracy >= 70 %", "%.1f %% (%.0f-%.0f)" % [ai["pass_pct"], ai["pass_pct_min"], ai["pass_pct_max"]])
	_check(ai["passes"] >= 120.0, "passes per match (both teams) >= 120", "%.0f" % ai["passes"])
	_check(ai["on_target_pct"] >= 35.0 and ai["on_target_pct"] <= 50.0, "shots on target 35-50 %", "%.1f %%" % ai["on_target_pct"])
	_check(ai["goals"] >= 2.0 and ai["goals"] <= 3.0, "goals per match 2.0-3.0", "%.2f (%.0f-%.0f)" % [ai["goals"], ai["goals_min"], ai["goals_max"]])
	_check(ai["offsides"] > 0.0, "offsides are called", "%.1f per match" % ai["offsides"])
	_check(ai["out_samples"] <= 2.0 and hu["out_samples"] <= 2.0, "players outside the pitch ~ 0 samples", "AI %.1f, human %.1f" % [ai["out_samples"], hu["out_samples"]])
	_check(ai["still_pct"] <= 3.0, "outfield players standing > 3 s <= 3 %", "%.1f %%" % ai["still_pct"])
	_check(ai["crowd"] <= 2.5 and hu["human_crowd"] <= 2.5, "team-mates within 10 m of the ball <= 2.5 (AI and human side)", "AI %.2f, human %.2f" % [ai["crowd"], hu["human_crowd"]])
	_check(hu["home_pass_pct"] >= 75.0, "simulated human's passes arrive >= 75 %", "%.1f %%" % hu["home_pass_pct"])
	_check(hu["human_support_pct"] >= 70.0, ">= 2 team-mates 10-30 m ahead in 70 % of the human's possession", "%.0f %%" % hu["human_support_pct"])
	# M5: strength shows. Desert Kings (rating 83) v Obsidian (74) — the widest gap in the default world, 9 points —
	# 20 x 2-minute matches, home and away alternating: the stronger side wins at least 55 %.
	var strong := "club_desert_kings"
	var weak := "club_obsidian"
	var wins := 0
	var draws := 0
	for i in 20:
		var strong_home := i % 2 == 0
		var r: Dictionary = await MatchQualityRunner.run_match(self, 500 + i, 2.0, false, strong if strong_home else weak, weak if strong_home else strong)
		var sc: PackedStringArray = str(r.get("score", "0-0")).split("-")
		var hs := int(sc[0])
		var as_ := int(sc[1])
		var strong_goals := hs if strong_home else as_
		var weak_goals := as_ if strong_home else hs
		if strong_goals > weak_goals:
			wins += 1
		elif strong_goals == weak_goals:
			draws += 1
	print("  strength: %s (%d) v %s (%d): %d wins, %d draws, %d losses in 20" % [strong, db.get_team_rating(strong), weak, db.get_team_rating(weak), wins, draws, 20 - wins - draws])
	_check(wins >= 11, "the stronger team (+%d rating) wins >= 55 %% of 20 matches" % (db.get_team_rating(strong) - db.get_team_rating(weak)), "%d / 20" % wins)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
