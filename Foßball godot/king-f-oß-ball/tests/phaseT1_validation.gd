## Phase T1/T2 validation — team + player database and attribute modifiers:
##   godot --headless --path . res://tests/phaseT1_validation.tscn
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
	print("=== KING FOOTBALL — Phase T1/T2 validation ===")
	_test_seed_data()
	_test_team_validation()
	_test_player_validation()
	_test_duplicates()
	_test_remove_isolation()
	_test_roundtrip()
	_test_roundtrip_precision()
	_test_modifiers()
	_test_gameplay_hooks()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_db() -> TeamDatabase:
	var db: TeamDatabase = load("res://scripts/core/team_database.gd").new()
	return db


func _test_seed_data() -> void:
	var db := _new_db()
	db.reload()
	_check(db.errors.is_empty(), "seed data loads without errors", str(db.errors))
	_check(db.teams.size() == 12, "12 seed teams loaded", str(db.teams.size()))
	_check(db.list_teams(TeamData.Category.CLUB).size() == 8, "8 clubs")
	_check(db.list_teams(TeamData.Category.NATIONAL).size() == 4, "4 national teams")
	_check(db.list_teams(-1, 1).is_empty(), "no real-team records shipped")
	for t: TeamData in db.teams.values():
		_check(db.get_squad(t.id).size() == 23, "squad of 23 for %s" % t.id)
		_check(db.get_team_rating(t.id) > 30, "team rating for %s" % t.id)
	var gks := 0
	for p in db.get_squad("club_royal_harbor"):
		if p.position == PlayerData.Position.GK:
			gks += 1
	_check(gks >= 2, "squad has goalkeepers")
	_check(db.get_team_rating("club_royal_harbor") > db.get_team_rating("club_obsidian"),
			"higher-reputation club has higher rating")
	db.free()


func _good_team() -> TeamData:
	return TeamData.from_dict({"id": "t_x", "name": "X", "short_name": "X", "country": "Y",
			"kits": {"home": {}, "away": {}, "goalkeeper": {}}})


func _test_team_validation() -> void:
	_check(_good_team().validate().is_empty(), "valid team passes")
	var t := _good_team(); t.id = ""
	_check(not t.validate().is_empty(), "empty id rejected")
	t = _good_team(); t.short_name = "TOOLONG"
	_check(not t.validate().is_empty(), "long short name rejected")
	t = _good_team(); t.kits.erase("home")
	_check(not t.validate().is_empty(), "missing home kit rejected")
	t = _good_team(); t.reputation = 120
	_check(not t.validate().is_empty(), "reputation range enforced")
	t = _good_team(); t.squad_ids = PackedStringArray(["a", "a"])
	_check(not t.validate().is_empty(), "duplicate squad entry rejected")


func _good_player(pid := "p1") -> PlayerData:
	return PlayerData.from_dict({"id": pid, "name": "A B", "age": 20, "position": "ST",
			"pace": 60, "shooting": 60, "passing": 60, "dribbling": 60, "defending": 40,
			"physical": 60, "goalkeeping": 5, "potential": 80})


func _test_player_validation() -> void:
	_check(_good_player().validate().is_empty(), "valid player passes")
	var p := _good_player(); p.pace = 100
	_check(not p.validate().is_empty(), "attribute above 99 rejected")
	p = _good_player(); p.shooting = 0
	_check(not p.validate().is_empty(), "attribute below 1 rejected")
	p = _good_player(); p.potential = 10
	_check(not p.validate().is_empty(), "potential below overall rejected")
	p = _good_player(); p.id = ""
	_check(not p.validate().is_empty(), "empty player id rejected")
	var st := _good_player(); var cb := _good_player()
	cb.position = PlayerData.Position.CB
	_check(st.get_overall() != cb.get_overall(), "overall depends on position")
	var unk := PlayerData.from_dict({"id": "z", "position": "NOPE"})
	_check(unk.position == PlayerData.Position.CM, "unknown position falls back")
	for pos in PlayerData.OVERALL_WEIGHTS:
		var sum := 0.0
		for w in PlayerData.OVERALL_WEIGHTS[pos].values():
			sum += w
		_check(absf(sum - 1.0) < 0.001, "overall weights sum to 1 for %s" % PlayerData.Position.keys()[pos])


func _test_duplicates() -> void:
	var db := _new_db()
	var roster: Array[PlayerData] = [_good_player("p1"), _good_player("p2")]
	_check(db.register_team(_good_team(), roster), "register valid team")
	var roster2: Array[PlayerData] = [_good_player("p9")]
	var dup := _good_team()
	_check(not db.register_team(dup, roster2), "duplicate team id rejected")
	_check(not db.players.has("p9"), "rejected team adds no players")
	var t2 := _good_team(); t2.id = "t_y"
	var roster3: Array[PlayerData] = [_good_player("p1")]
	_check(not db.register_team(t2, roster3), "duplicate player id across teams rejected")
	var roster4: Array[PlayerData] = [_good_player("q1"), _good_player("q1")]
	_check(not db.register_team(t2, roster4), "duplicate player id inside a team rejected")
	_check(db.teams.size() == 1, "only the valid team registered")
	_check(not db.load_file("res://data/does_not_exist.json"), "missing file handled")
	_check(db.remove_team("t_x") and db.players.is_empty(), "remove team removes its players")
	db.free()


func _test_remove_isolation() -> void:
	var db := _new_db()
	var ta := _good_team()
	ta.id = "t_a"
	var tb := _good_team()
	tb.id = "t_b"
	var ra: Array[PlayerData] = [_good_player("a1"), _good_player("a2")]
	var rb: Array[PlayerData] = [_good_player("b1"), _good_player("b2")]
	_check(db.register_team(ta, ra) and db.register_team(tb, rb), "two teams registered")
	_check(ta.squad_ids.size() == 2 and (db.get_player("a1") as PlayerData).team_id == "t_a",
			"register_team links the roster to the team (squad_ids + team_id)")
	_check(db.remove_team("t_a") and not db.players.has("a1") and not db.players.has("a2"),
			"removing a team removes exactly its own players")
	_check(db.players.has("b1") and db.players.has("b2") and db.get_team("t_b").squad_ids.size() == 2 and db.teams.size() == 1,
			"unrelated teams and their players are untouched")
	_check(not db.remove_team("t_a"), "removing an already removed team is a harmless no-op")
	db.free()


## Regression for lossy saves: default JSON.stringify keeps 14 digits and turns
## ints into floats; the full-precision write + int restore must be lossless.
func _test_roundtrip_precision() -> void:
	var q := _good_player("q_prec")
	q.growth_progress = {"pace": 0.6964363636363634, "passing": 0.12345678901234568}
	q.development_history = [{"event": "train", "week": 3, "from": 50, "to": 51, "nested": {"a": [1, 2, {"b": 7}]}}]
	var q2 := PlayerData.from_dict(JSON.parse_string(JSON.stringify(q.to_dict(), "	", true, true)))
	_check(q2.to_dict() == q.to_dict(), "player JSON round-trip keeps float precision and nested integers")
	_check(q2.development_history[0]["nested"]["a"][2]["b"] is int and q2.development_history[0]["from"] is int,
			"integers inside nested history stay integers after a JSON round trip")
	var lossy := PlayerData.from_dict(JSON.parse_string(JSON.stringify(q.to_dict())))
	_check(lossy.growth_progress["pace"] != q.growth_progress["pace"],
			"(documents the cause) default stringify really truncates floats, so writers must use full precision")


func _test_roundtrip() -> void:
	var p := _good_player()
	p.development_history.append({"season": 1, "overall": 55})
	var p2 := PlayerData.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	_check(p2.to_dict() == p.to_dict(), "player JSON round-trip identical")
	var t := _good_team()
	t.primary_color = Color("c0392b")
	var t2 := TeamData.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	_check(t2.to_dict() == t.to_dict(), "team JSON round-trip identical")


func _test_modifiers() -> void:
	var p := _good_player()
	p.pace = 50; p.physical = 50; p.shooting = 50; p.passing = 50; p.fitness = 100
	var m := AttributeModifiers.new(p)
	_check(is_equal_approx(m.speed_multiplier(), 1.0), "neutral pace = 1.0x speed")
	_check(is_equal_approx(m.shot_power_multiplier(), 1.0), "neutral shooting = 1.0x power")
	p.pace = 99
	_check(m.speed_multiplier() > 1.1, "high pace speeds up")
	p.pace = 1
	_check(m.speed_multiplier() < 0.9, "low pace slows down")
	p.shooting = 99; var hi := m.shot_error_degrees()
	p.shooting = 1; var lo := m.shot_error_degrees()
	_check(hi < lo, "higher shooting = smaller aim error")
	p.shooting = 99; p.fitness = 100; var fresh := m.shot_error_degrees()
	p.fitness = 20
	_check(m.shot_error_degrees() > fresh, "low fitness increases error")
	_check(AttributeModifiers.new(null).speed_multiplier() == 1.0, "null player = neutral")
	p.defending = 99
	_check(m.defending_factor() > 1.0, "defending factor scales")


func _test_gameplay_hooks() -> void:
	var pc_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := pc_scene.instantiate() as PlayerController
	add_child(player)
	await get_tree().process_frame
	_check(player.attribute_modifiers == null, "player defaults to no modifiers (Phase 2 behaviour)")
	var fast := _good_player(); fast.pace = 99
	player.attribute_modifiers = AttributeModifiers.new(fast)
	_check(player._resolve_max_speed(Vector2.ZERO) > player.config.normal_speed * 1.1,
			"pace raises controller max speed")
	var actions := player.get_node_or_null("BallActions") as FootballActions
	_check(actions != null, "player has BallActions")
	if actions:
		_check(actions.attribute_modifiers == null, "actions default to no modifiers")
		_check(actions._with_error(Vector3.FORWARD, 0.0) == Vector3.FORWARD, "zero error keeps direction")
		var d := actions._with_error(Vector3.FORWARD, 10.0)
		_check(absf(d.angle_to(Vector3.FORWARD)) <= deg_to_rad(10.01), "aim error bounded by max degrees")
	player.queue_free()
