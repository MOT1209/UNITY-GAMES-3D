## Long-career validation: 12 seasons with the real data pack.
##   godot --headless --path . res://tests/career_longevity_validation.tscn
## Every season ends with a save that must validate and round-trip; players retire, AI squads
## stay complete, league strength stays stable and the calendar stops at week 46.
extends Node

const PACK := "real_2025"
const USER_CLUB := "eng_leicester_city_fc"
const SEASONS := 12

var _passed := 0
var _failed := 0
var db: TeamDatabase


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Career longevity validation ===")
	db = get_node("/root/TeamDB")
	db.load_world(PACK)
	_test_unit_rules()
	_test_long_career()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_unit_rules() -> void:
	_check(PlayerLifecycle.retire_chance(30, false) == 0.0 and PlayerLifecycle.retire_chance(40, false) == 1.0, "retirement window 33..40")
	_check(PlayerLifecycle.retire_chance(41, true) < 1.0 and PlayerLifecycle.retire_chance(42, true) == 1.0, "keepers play two years longer")
	_check(PlayerLifecycle.retire_chance(36, false) > PlayerLifecycle.retire_chance(34, false), "retirement chance rises with age")
	var young := PlayerData.from_dict(db.get_player(db.get_squad("eng_arsenal")[0].id).to_dict())
	young.age = 19
	young.potential = mini(young.get_overall() + 10, 99)
	var before := young.get_overall()
	var rng := RandomNumberGenerator.new()
	for i in 6:
		rng.seed = i
		PlayerLifecycle.develop(young, rng)
	_check(young.get_overall() >= before and young.get_overall() <= young.potential, "young players grow, never past potential")
	var old := PlayerData.from_dict(young.to_dict())
	old.age = 35
	var ob := old.get_overall()
	rng.seed = 3
	PlayerLifecycle.develop(old, rng)
	_check(old.get_overall() < ob and old.potential >= old.get_overall(), "players past 34 decline; potential stays >= overall")


func _division_avgs(c: CareerState) -> Dictionary:
	var out := {}
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			var total := 0
			for t in d["team_ids"]:
				total += db.get_team_rating(t)
			out[d["id"]] = float(total) / float((d["team_ids"] as Array).size())
	return out


func _test_long_career() -> void:
	var c := CareerState.start(db, USER_CLUB)
	var start_avgs := _division_avgs(c)
	var total_retired := 0
	var total_new := 0
	var t0 := Time.get_ticks_msec()
	for s in SEASONS:
		for w in CareerState.WEEKS_PER_SEASON:
			c.advance_week()
		var blocked := c.advance_week()
		if s == 0:
			_check(blocked.get("blocked", false) and c.week == CareerState.WEEKS_PER_SEASON, "advance_week stops at week 46")
		var res := c.end_season()
		total_retired += int(res["retired"])
		for t in res["ai_generated"]:
			total_new += (res["ai_generated"][t] as Array).size()
		for t in res["ai_signed"]:
			total_new += (res["ai_signed"][t] as Array).size()
		# save -> validate -> JSON round trip
		var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
		var errs := SaveManager.validate(SaveManager.migrate(parsed))
		_check(errs.is_empty(), "season %d: save validates" % (s + 1), str(errs.slice(0, 3)))
		# active players never too old, retired players gone from squads
		var too_old := 0
		var retired_in_squad := 0
		for p: PlayerData in db.players.values():
			if p.status != PlayerData.Status.RETIRED and p.age > 45:
				too_old += 1
			if p.status == PlayerData.Status.RETIRED and p.team_id != "":
				retired_in_squad += 1
		_check(too_old == 0 and retired_in_squad == 0, "season %d: no active player over 45, retired players hold no club" % (s + 1),
				"%d / %d" % [too_old, retired_in_squad])
		var bad := []
		var seen := {}
		var dup := false
		for t: TeamData in db.list_teams(TeamData.Category.CLUB):
			var sq := db.get_squad(t.id)
			for p: PlayerData in sq:
				dup = dup or seen.has(p.id)
				seen[p.id] = true
			if t.id == USER_CLUB:
				continue
			var gks := sq.filter(func(p: PlayerData) -> bool: return p.position == PlayerData.Position.GK).size()
			if sq.size() < PlayerLifecycle.SQUAD_MIN or sq.size() > TransferMarket.MAX_SQUAD or gks < 2:
				bad.append("%s:%d/%d" % [t.id, sq.size(), gks])
		_check(bad.is_empty(), "season %d: every AI club has 22+ players and 2+ keepers" % (s + 1), str(bad.slice(0, 5)))
		_check(not dup, "season %d: no player in two squads" % (s + 1))
	print("[INFO] %d seasons simulated in %d ms; %d retirements, %d players signed or brought in by AI clubs" % [
			SEASONS, Time.get_ticks_msec() - t0, total_retired, total_new])
	_check(total_retired > 200, "players retire over a long career", str(total_retired))
	_check(total_new > 200, "AI clubs replace departures", str(total_new))
	var end_avgs := _division_avgs(c)
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			var base_sum := 0
			for t in d["team_ids"]:
				base_sum += c.base_level(t)
			print("[INFO] %s: start %.1f, now %.1f; base level of current members %.1f" % [d["id"], start_avgs[d["id"]], end_avgs[d["id"]],
					float(base_sum) / float((d["team_ids"] as Array).size())])
	var drift := []
	for d in start_avgs:
		if absf(end_avgs[d] - start_avgs[d]) > 5.0:
			drift.append("%s %.1f -> %.1f" % [d, start_avgs[d], end_avgs[d]])
	_check(drift.is_empty(), "average squad rating per division within ±5 after %d seasons" % SEASONS, str(drift))
	var sizes_ok := true
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			sizes_ok = sizes_ok and (d["team_ids"] as Array).size() == (db.leagues[k] as LeagueDef).division(d["id"])["team_ids"].size()
	_check(sizes_ok, "division sizes unchanged after %d seasons" % SEASONS)
	var c2 := CareerState.from_dict(db, JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true)))
	_check(c2.season == c.season and c2.pyramids.size() == 5, "the long career loads")
