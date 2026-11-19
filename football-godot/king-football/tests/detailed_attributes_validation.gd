## Detailed player attributes: catalog, lazy storage, compatibility with the seven broad attributes, training, saves.
##   godot --headless --path . res://tests/detailed_attributes_validation.tscn
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
	print("=== KING FOOTBALL — Detailed attributes validation ===")
	_test_catalog()
	_test_untouched_player()
	_test_materialise_and_training()
	_test_potential_cap()
	_test_broad_change_propagates()
	_test_goalkeeper_details()
	_test_persistence()
	_test_validation()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _player(id := "t_1", pos := PlayerData.Position.ST) -> PlayerData:
	var p := PlayerData.new()
	p.id = id
	p.display_name = "Test Player"
	p.position = pos
	p.age = 19
	p.pace = 70
	p.shooting = 72
	p.passing = 60
	p.dribbling = 66
	p.defending = 40
	p.physical = 64
	p.goalkeeping = 10
	p.potential = 99
	return p


func _broad(p: PlayerData) -> Array:
	var out := []
	for a in PlayerData.ATTRIBUTES:
		out.append(p.get_attribute(a))
	return out


func _test_catalog() -> void:
	var wanted := ["finishing", "shot_power", "long_shots", "volleys", "penalties", "heading", "short_passing", "long_passing", "vision", "crossing",
			"curve", "ball_control", "dribbling_skill", "agility", "balance", "tackling", "interceptions", "marking", "defensive_positioning",
			"defensive_awareness", "acceleration", "sprint_speed", "stamina", "strength", "jumping", "composure", "concentration", "anticipation",
			"decisions", "reactions", "positioning", "work_rate", "aggression", "teamwork", "reflexes", "diving", "handling", "gk_positioning",
			"kicking", "one_on_one"]
	var missing := wanted.filter(func(n: String) -> bool: return not DetailedAttributes.has(n))
	_check(missing.is_empty(), "every requested detailed attribute exists", str(missing))
	_check(DetailedAttributes.names().size() == wanted.size(), "no unrequested or duplicate detailed attributes", "%d vs %d" % [DetailedAttributes.names().size(), wanted.size()])
	var p := _player()
	var ok := true
	for n in DetailedAttributes.names():
		ok = ok and (DetailedAttributes.parent_of(p, str(n)) in PlayerData.ATTRIBUTES) and (DetailedAttributes.group_of(str(n)) in DetailedAttributes.GROUPS)
	_check(ok, "every detailed attribute has exactly one valid broad parent and a valid group")
	_check(DetailedAttributes.names().all(func(n: String) -> bool: return not (n in PlayerData.ATTRIBUTES)), "no detailed name collides with a broad attribute")
	var complete := true
	for pos in PlayerData.Position.values():
		var q := _player("pos", pos)
		var t := 0
		for b in PlayerData.ATTRIBUTES:
			t += DetailedAttributes.count_under(q, b)
		if t != DetailedAttributes.names().size():
			complete = false
	_check(complete, "each detailed attribute is counted under exactly one parent for every position (no double counting)")


func _test_untouched_player() -> void:
	var p := _player()
	var overall := p.get_overall()
	_check(p.detail.is_empty() and not DetailedAttributes.is_materialised(p), "a new / old player has no stored detail (nothing to migrate)")
	var ok := true
	for n in DetailedAttributes.names():
		var parent := DetailedAttributes.parent_of(p, str(n))
		var v := DetailedAttributes.value(p, str(n))
		ok = ok and v >= 1 and v <= 99 and absi(v - p.get_attribute(parent)) <= DetailedAttributes.OFFSET
	_check(ok, "derived values are 1..99 and within the offset of their parent")
	var snap := DetailedAttributes.all_for(p)
	_check(snap == DetailedAttributes.all_for(p), "derived values are deterministic")
	var q := _player("t_2")
	_check(DetailedAttributes.all_for(q) != snap, "a different id gives a different offset pattern")
	_check(p.get_overall() == overall and p.detail.is_empty(), "reading detailed attributes never changes the overall or stores anything")
	_check(not p.to_dict().has("detail"), "an untouched player saves exactly like before (no detail key)")
	p.shooting = 80
	_check(absi(DetailedAttributes.value(p, "finishing") - 80) <= DetailedAttributes.OFFSET, "an untouched player's derived values follow a legacy broad change")
	_check(p.get_attribute("finishing") == DetailedAttributes.value(p, "finishing") and p.get_attribute("nonsense") == 0, "get_attribute understands detailed names and rejects unknown ones")


func _test_materialise_and_training() -> void:
	var p := _player()
	var broad_before := _broad(p)
	var overall := p.get_overall()
	DetailedAttributes.ensure(p)
	_check(p.detail.size() == DetailedAttributes.names().size(), "ensure stores every detailed attribute")
	_check(_broad(p) == broad_before and p.get_overall() == overall, "materialising changes neither the broad attributes nor the overall (match engine unchanged)")
	var siblings := {}
	for n in DetailedAttributes.names():
		siblings[n] = p.detail[n]
	var z := DetailedAttributes.count_under(p, "shooting")
	var fin0 := int(p.detail["finishing"])
	var sh0 := p.shooting
	var g := ProgressionModel.apply_points(p, "finishing", 1.0, 5, "plan")
	_check(g == 1 and int(p.detail["finishing"]) == fin0 + 1, "training a detailed attribute raises it by one")
	_check(p.shooting == sh0, "one detailed point gives its parent only 1/Z of a point (no instant broad jump)", "Z=%d" % z)
	_check(absf(float(p.growth_progress.get("shooting", 0.0)) - 1.0 / float(z)) < 0.001, "the parent received exactly 1/Z progress")
	for i in z - 1:
		ProgressionModel.apply_points(p, "finishing", 1.0, 6 + i, "plan")
	_check(int(p.detail["finishing"]) == fin0 + z and p.shooting == sh0 + 1, "Z detailed points move the parent by exactly one (counted once)", "%d / %d" % [p.shooting, sh0])
	var untouched := true
	for n in DetailedAttributes.names():
		if n != "finishing" and int(p.detail[n]) != int(siblings[n]):
			untouched = false
	_check(untouched, "the parent's rise is not propagated back into the sibling details (no double counting)")
	var hist := p.development_history.filter(func(e: Variant) -> bool: return e is Dictionary and (e as Dictionary).get("attribute", "") == "finishing")
	_check(hist.size() == z and int((hist[0] as Dictionary)["from"]) == fin0, "each detailed point is recorded in the development history")
	_check(ProgressionModel.weekly_points(p, "finishing", 0.5, 0.6) > 0.0 and ProgressionModel.weekly_points(p, "nonsense", 0.5, 0.6) == 0.0, "weekly points exist for detailed attributes and not for unknown names")
	var cap := _player("cap")
	DetailedAttributes.ensure(cap)
	cap.detail["finishing"] = 99
	_check(ProgressionModel.apply_points(cap, "finishing", 5.0, 1) == 0 and int(cap.detail["finishing"]) == 99, "the 99 limit holds for detailed attributes")
	var legacy := _player("legacy")
	ProgressionModel.apply_points(legacy, "passing", 1.0, 1, "plan")
	_check(legacy.passing == 61 and legacy.detail.is_empty(), "legacy broad training still works and does not materialise anything")


func _test_potential_cap() -> void:
	var p := _player("pot")
	p.potential = p.get_overall()
	DetailedAttributes.ensure(p)
	var refused := 0
	for round in 6:
		for n in ["finishing", "shot_power", "long_shots", "volleys", "penalties", "heading", "composure", "positioning"]:
			if ProgressionModel.apply_points(p, n, 1.0, round) == 0:
				refused += 1
	_check(p.get_overall() <= p.potential, "potential limits detailed training (overall never passes potential)", "%d / %d" % [p.get_overall(), p.potential])
	_check(refused > 0 and float(p.growth_progress.get("shooting", 0.0)) <= 0.99, "a point that would break potential is refused for the detail as well", "refused %d" % refused)


func _test_broad_change_propagates() -> void:
	var p := _player("prop")
	DetailedAttributes.ensure(p)
	var before := DetailedAttributes.all_for(p)
	p.defending += 3
	var ok_def := true
	var ok_other := true
	for n in DetailedAttributes.names():
		if not DetailedAttributes.applicable(p, str(n)):
			continue
		if DetailedAttributes.parent_of(p, str(n)) == "defending":
			ok_def = ok_def and int(p.detail[n]) == int(before[n]) + 3
		else:
			ok_other = ok_other and int(p.detail[n]) == int(before[n])
	_check(ok_def, "a broad change (ageing / lifecycle) moves every detailed attribute under it by the same amount")
	_check(ok_other, "details under other broad attributes are untouched by that change")
	p.defending = 99
	p.defending += 5
	var clamp_ok := true
	for n in p.detail:
		clamp_ok = clamp_ok and int(p.detail[n]) >= 1 and int(p.detail[n]) <= 99
	_check(clamp_ok, "propagation stays within 1..99")
	var d := _player("dec")
	var acc0 := DetailedAttributes.derived(d, "acceleration")
	DetailedAttributes.ensure(d)
	d.pace -= 4
	_check(int(d.detail["acceleration"]) == acc0 - 4, "a decline (ageing) lowers the details under that attribute too")


func _test_goalkeeper_details() -> void:
	var out := _player("out", PlayerData.Position.CM)
	var gk := _player("gk", PlayerData.Position.GK)
	gk.goalkeeping = 78
	_check(not DetailedAttributes.applicable(out, "reflexes") and DetailedAttributes.applicable(gk, "reflexes"), "goalkeeping details apply to goalkeepers only")
	_check(not DetailedAttributes.all_for(out).has("diving") and DetailedAttributes.all_for(gk).has("diving"), "an outfield player's detailed list hides the goalkeeping group")
	_check(ProgressionModel.apply_points(out, "reflexes", 3.0, 1) == 0 and out.detail.is_empty(), "training a goalkeeping detail on an outfield player does nothing")
	_check(DetailedAttributes.parent_of(gk, "positioning") == "goalkeeping" and DetailedAttributes.parent_of(out, "positioning") == "passing"
			and DetailedAttributes.parent_of(_player("st"), "positioning") == "shooting", "positioning follows the position")
	var before := gk.goalkeeping
	var n := DetailedAttributes.count_under(gk, "goalkeeping")
	for i in n:
		ProgressionModel.apply_points(gk, "reflexes", 1.0, i)
	_check(gk.goalkeeping == before + 1, "goalkeeper detail training feeds the goalkeeping attribute the match engine reads", "%d (Z=%d)" % [gk.goalkeeping, n])


func _test_persistence() -> void:
	var p := _player("save")
	for i in 3:
		ProgressionModel.apply_points(p, "short_passing", 1.0, i)
	var restored := PlayerData.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary)
	_check(restored.detail == p.detail and _broad(restored) == _broad(p), "detailed attributes survive a JSON save / load")
	_check(restored.validate().is_empty(), "a loaded materialised player validates", str(restored.validate()))
	var old: Dictionary = _player("old").to_dict()
	_check(not old.has("detail") and PlayerData.from_dict(old).detail.is_empty(), "an old save without the detail key loads untouched")
	var bad: Dictionary = _player("bad").to_dict()
	bad["detail"] = {"finishing": 150, "vision": "fast", "ghost": 50, "composure": 0.0, "agility": 63.0}
	var fixed := PlayerData.from_dict(bad)
	_check(fixed.detail.size() == DetailedAttributes.names().size(), "an incomplete stored dictionary is completed")
	_check(not fixed.detail.has("ghost") and int(fixed.detail["finishing"]) == 99 and int(fixed.detail["composure"]) == 1 and int(fixed.detail["agility"]) == 63,
			"unknown names are dropped and out-of-range values are clamped")
	_check(int(fixed.detail["vision"]) == DetailedAttributes.derived(fixed, "vision"), "a non-numeric value is replaced by the derived one")
	_check(fixed.validate().is_empty(), "a repaired player validates", str(fixed.validate()))
	var stored := _player("stored")
	DetailedAttributes.ensure(stored)
	stored.detail["finishing"] = 90
	_check(AttributeDetail.value(stored, "finishing") == 90, "the database export view reports the stored value")
	var twin := PlayerData.from_dict(stored.to_dict())
	twin.shooting += 2
	_check(int(twin.detail["finishing"]) == 92, "a loaded materialised player keeps propagating broad changes")


func _test_validation() -> void:
	var p := _player("val")
	DetailedAttributes.ensure(p)
	p.detail["finishing"] = 150
	p.detail["bogus"] = 40
	p.detail.erase("vision")
	var errs := p.validate()
	_check(errs.any(func(e: String) -> bool: return "finishing" in e and "out of range" in e), "an out-of-range detailed value is reported")
	_check(errs.any(func(e: String) -> bool: return "bogus" in e), "an unknown detailed attribute is reported")
	_check(errs.any(func(e: String) -> bool: return "vision" in e and "missing" in e), "a missing detailed attribute is reported")
