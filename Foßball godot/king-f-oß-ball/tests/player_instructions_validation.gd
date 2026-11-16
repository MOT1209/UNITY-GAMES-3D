## Individual player instructions: each one must move the AI's target; invalid ones are refused; saves keep them.
##   godot --headless --path . res://tests/player_instructions_validation.tscn
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


func _targets(t: TacticsPreset, has_ball: bool, ball_z: float = 0.0) -> Array[Vector3]:
	return TeamAI.formation_targets("home", "4-3-3", t, Vector3(0, 0, ball_z), has_ball)


## Team-relative depth (0 own goal .. 1 opponent goal) of a world target, via PitchSpace.
func _depth(v: Vector3) -> float:
	return PitchSpace.progress_of(v, "home")


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Player instructions validation ===")
	var base := TacticsPreset.new()
	# 4-3-3 slots: 1 LB, 2 CB, 3 CB, 4 RB, 5 CDM, 6 CM, 7 CM, 8 LW, 9 ST, 10 RW
	var b_att := _targets(base, true)
	var b_def := _targets(base, false)

	var t := TacticsPreset.new()
	_check(t.set_instruction(4, "join_attack") and t.set_instruction(1, "stay_back") and t.set_instruction(8, "stay_wide")
			and t.set_instruction(10, "cut_inside") and t.set_instruction(6, "hold_position") and t.set_instruction(9, "get_forward"),
			"all six instructions can be set on outfield slots")
	_check(not t.set_instruction(0, "join_attack"), "the goalkeeper slot refuses an instruction")
	_check(not t.set_instruction(3, "mark_man"), "an unknown instruction is refused (no fake options)")
	_check(not t.set_instruction(11, "stay_back"), "a slot outside the formation is refused")
	_check(t.validate().is_empty(), "a tactic with valid instructions validates")

	var att := _targets(t, true)
	var dff := _targets(t, false)
	_check(_depth(att[4]) > _depth(b_att[4]) + 0.05, "join_attack: the right-back stands higher with the ball", "%f vs %f" % [_depth(att[4]), _depth(b_att[4])])
	_check(_depth(att[1]) <= _depth(b_att[1]) + 0.001, "stay_back: the left-back never goes beyond the base line")
	_check(_depth(att[9]) > _depth(b_att[9]) - 0.0001 and _depth(att[9]) >= _depth(b_att[9]), "get_forward: the striker is at least as high")
	var rel_wide := t.apply_instruction(8, Vector2(0.3, 0.7), -0.8, 0.78, true)
	_check(is_equal_approx(rel_wide.x, -0.85) or rel_wide.x <= -0.85, "stay_wide: a left winger is pushed to the touchline", str(rel_wide))
	var rel_cut := t.apply_instruction(10, Vector2(0.8, 0.78), 0.8, 0.78, true)
	_check(is_equal_approx(rel_cut.x, 0.36), "cut_inside: x shrinks to 45 % with the ball", str(rel_cut))
	_check(is_equal_approx(t.apply_instruction(10, Vector2(0.8, 0.78), 0.8, 0.78, false).x, 0.8), "cut_inside: no change without the ball")
	var hold := t.apply_instruction(6, Vector2(0.1, 0.9), -0.4, 0.52, true)
	_check(hold == Vector2(-0.4, 0.52), "hold_position: back to the formation slot whatever the ball does", str(hold))
	_check(_depth(dff[4]) > _depth(b_def[4]) - 0.0001, "join_attack without the ball still moves up a little")
	var other := _targets(t, true)
	_check(_depth(other[2]) == _depth(b_att[2]) and other[2].x == b_att[2].x, "slots without an instruction are untouched")
	_check(_targets(base, true)[4] == b_att[4], "the default tactic gives the same targets as before (no regression)")

	var d := t.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(d))
	var back := TacticsPreset.from_dict(json)
	_check(back.player_instructions == t.player_instructions, "instructions survive a JSON save/load", str(back.player_instructions))
	var old := TacticsPreset.from_dict({"name": "Old", "pressing": 60})
	_check(old.player_instructions.is_empty() and old.pressing == 60, "a save without instructions loads unchanged")
	var bad := TacticsPreset.from_dict({"instructions": {"0": "stay_back", "3": "fly", "2": "stay_back"}})
	_check(bad.player_instructions == {2: "stay_back"}, "invalid saved instructions are dropped on load", str(bad.player_instructions))
	t.set_instruction(4, "")
	_check(not t.player_instructions.has(4), "an instruction can be cleared")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
