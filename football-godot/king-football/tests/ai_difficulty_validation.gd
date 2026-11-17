## AI difficulty profiles (F3) validation:
##   godot --headless --path . res://tests/ai_difficulty_validation.tscn
## Verifies: NORMAL is behaviour-neutral (bit-identical engine), EASY narrows
## the option space, HARD widens it, the input profile is never mutated, out
## of-range difficulties clamp, and everything is deterministic. Integration
## with a real TacticsPreset is included (build-up SHORT / DIRECT x style).
extends Node

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
	print("=== KING FOOTBALL — AI difficulty validation ===")
	_test_normal_is_neutral()
	_test_easy_narrows()
	_test_hard_widens()
	_test_no_mutation()
	_test_clamping()
	_test_determinism()
	_test_tactics_integration()
	_test_keepers_and_pressing()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _base() -> Dictionary:
	return TacticsPreset.new().pass_profile()


func _test_normal_is_neutral() -> void:
	var base := _base()
	_check(AIDifficulty.apply(base, 1) == base, "normal: the profile is returned unchanged")
	_check(AIDifficulty.apply(base, 1) == AIDifficulty.apply(base, 1), "normal: stable across calls")
	# every PlayerAI-consumed key must survive unchanged
	for key in ["min_dist", "max_dist", "progress_weight", "dist_weight", "min_progress", "cover_radius", "pressure_radius"]:
		_check(float(AIDifficulty.apply(base, 1).get(key)) == float(base[key]), "normal: '%s' untouched" % key)
	_check(AIDifficulty.shoot_range_bonus(1) == 0.0, "normal: shoot range bonus is zero")
	_check(AIDifficulty.keeper_speed_factor(1) == 1.0, "normal: keeper factor is 1.0")
	_check(AIDifficulty.press_distance_bonus(1) == 0.0, "normal: pressing bonus is zero")


func _test_easy_narrows() -> void:
	var easy: Dictionary = AIDifficulty.apply(_base(), 0)
	_check(float(easy["max_dist"]) < float(_base()["max_dist"]), "easy: shorter passing vision",
			str(easy["max_dist"]))
	_check(float(easy["max_dist"]) <= 28.0, "easy: vision is capped at 28 m")
	_check(float(easy["cover_radius"]) > float(_base()["cover_radius"]), "easy: receivers must be more open")
	_check(float(easy["pressure_radius"]) > float(_base()["pressure_radius"]), "easy: passes earlier under pressure")
	_check(AIDifficulty.shoot_range_bonus(0) < 0.0, "easy: shoots only from closer")
	_check(AIDifficulty.keeper_speed_factor(0) < 1.0, "easy: keeper slower")
	_check(AIDifficulty.press_distance_bonus(0) > 0.0, "easy: presses later")
	# a SHORT build-up team (max_dist 20) must not become unable to pass (min < max still holds)
	var short_easy: Dictionary = AIDifficulty.apply(TacticsPreset.new().pass_profile(), 0)
	var t := TacticsPreset.new()
	t.build_up = TacticsPreset.BuildUp.SHORT
	var short_prof: Dictionary = AIDifficulty.apply(t.pass_profile(), 0)
	_check(float(short_prof["min_dist"]) < float(short_prof["max_dist"]), "easy: SHORT build-up stays passable")


func _test_hard_widens() -> void:
	var hard: Dictionary = AIDifficulty.apply(_base(), 2)
	_check(float(hard["cover_radius"]) < float(_base()["cover_radius"]), "hard: finds tighter receivers")
	_check(float(hard["cover_radius"]) >= 1.0, "hard: cover radius never below 1 m")
	_check(float(hard["pressure_radius"]) < float(_base()["pressure_radius"]), "hard: keeps the ball under pressure")
	_check(float(hard["pressure_radius"]) >= 2.0, "hard: pressure radius never below 2 m")
	_check(float(hard["max_dist"]) > float(_base()["max_dist"]), "hard: longer vision")
	_check(float(hard["max_dist"]) <= 45.0, "hard: vision capped at the engine's old DIRECT maximum")
	_check(AIDifficulty.shoot_range_bonus(2) > 0.0, "hard: shoots a bit earlier")
	_check(AIDifficulty.keeper_speed_factor(2) > 1.0 and AIDifficulty.keeper_speed_factor(2) <= 1.06,
			"hard: keeper slightly quicker, never excessive")
	_check(AIDifficulty.press_distance_bonus(2) < 0.0, "hard: presses earlier")


func _test_no_mutation() -> void:
	var base := _base()
	var snapshot := str(base)
	AIDifficulty.apply(base, 0)
	AIDifficulty.apply(base, 2)
	_check(str(base) == snapshot, "apply never mutates the input profile")


func _test_clamping() -> void:
	var out_of_range: Dictionary = AIDifficulty.apply(_base(), 9)
	_check(out_of_range == AIDifficulty.apply(_base(), 2), "difficulty 9 clamps to HARD")
	var negative: Dictionary = AIDifficulty.apply(_base(), -3)
	_check(negative == AIDifficulty.apply(_base(), 0), "difficulty -3 clamps to EASY")
	_check(AIDifficulty.shoot_range_bonus(7) == AIDifficulty.shoot_range_bonus(2), "shoot bonus clamps")
	_check(AIDifficulty.keeper_speed_factor(-1) == AIDifficulty.keeper_speed_factor(0), "keeper factor clamps")


func _test_determinism() -> void:
	var a: Dictionary = AIDifficulty.apply(_base(), 0)
	var b: Dictionary = AIDifficulty.apply(_base(), 0)
	_check(str(a) == str(b), "easy: fully deterministic across calls")
	var c: Dictionary = AIDifficulty.apply(_base(), 2)
	var d: Dictionary = AIDifficulty.apply(_base(), 2)
	_check(str(c) == str(d), "hard: fully deterministic across calls")


func _test_tactics_integration() -> void:
	# SHORT + SAFE (the most possession-oriented preset) on each difficulty.
	var t := TacticsPreset.new()
	t.build_up = TacticsPreset.BuildUp.SHORT
	t.passing_style = TacticsPreset.PassingStyle.SAFE
	var base: Dictionary = t.pass_profile()
	var easy: Dictionary = AIDifficulty.apply(base, 0)
	var hard: Dictionary = AIDifficulty.apply(base, 2)
	_check(float(easy["max_dist"]) == minf(float(base["max_dist"]) * 0.75, 28.0),
			"SHORT+SAFE easy: max_dist scales from the tactic value", str(easy["max_dist"]))
	_check(float(hard["cover_radius"]) == maxf(1.0, float(base["cover_radius"]) - 0.8),
			"SHORT+SAFE hard: cover radius shrinks from the tactic value")
	# DIRECT + RISKY (the most direct preset): hard vision must stay capped at 45.
	t.build_up = TacticsPreset.BuildUp.DIRECT
	t.passing_style = TacticsPreset.PassingStyle.RISKY
	var direct_base: Dictionary = t.pass_profile()
	var direct_hard: Dictionary = AIDifficulty.apply(direct_base, 2)
	_check(float(direct_hard["max_dist"]) <= 45.0, "DIRECT+RISKY hard: vision never exceeds 45 m",
			str(direct_hard["max_dist"]))
	# progress/min_progress keys are tactics-owned and pass through untouched
	_check(float(easy["min_progress"]) == float(base["min_progress"]), "style-owned min_progress untouched")
	_check(float(direct_hard["progress_weight"]) == float(direct_base["progress_weight"]), "style-owned progress_weight untouched")


func _test_keepers_and_pressing() -> void:
	# ordering: easy keeper < normal < hard keeper
	_check(AIDifficulty.keeper_speed_factor(0) < AIDifficulty.keeper_speed_factor(1)
			and AIDifficulty.keeper_speed_factor(1) < AIDifficulty.keeper_speed_factor(2),
			"keeper speed orders easy < normal < hard")
	# shooting range orders easy < normal < hard (with the same tactics)
	_check(AIDifficulty.shoot_range_bonus(0) < AIDifficulty.shoot_range_bonus(1)
			and AIDifficulty.shoot_range_bonus(1) < AIDifficulty.shoot_range_bonus(2),
			"shoot range bonus orders easy < normal < hard")
	# pressing orders: easy presses later (larger distance) than hard
	_check(AIDifficulty.press_distance_bonus(0) > AIDifficulty.press_distance_bonus(1)
			and AIDifficulty.press_distance_bonus(1) > AIDifficulty.press_distance_bonus(2),
			"press distance bonus orders easy > normal > hard")
