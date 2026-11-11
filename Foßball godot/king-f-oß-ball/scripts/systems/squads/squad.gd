class_name Squad
extends RefCounted

## First-team squad (Phase T3): Starting XI aligned to formation slots,
## substitute bench, reserves, captain, set-piece takers and presets.
## A player id lives in exactly one place (slot / bench / reserve); every
## mutator moves the player out of any previous place, so duplicates are
## impossible by construction. Mutators return "" on success or an error text.

const MAX_BENCH := 7

var team_id: String = ""
var formation_id: String = "4-3-3"
var starting: Array[String] = []   # size 11, "" = empty slot
var bench: Array[String] = []
var reserves: Array[String] = []
var captain_id: String = ""
var set_pieces: Dictionary = {"penalty": "", "free_kick": "", "corner": ""}
var presets: Array[TacticsPreset] = []
var active_preset: int = 0


func _init(p_team_id := "", p_formation := "4-3-3") -> void:
	team_id = p_team_id
	formation_id = p_formation
	starting.resize(11)
	starting.fill("")
	presets.append(TacticsPreset.new())


func contains(pid: String) -> bool:
	return pid in starting or pid in bench or pid in reserves


func _remove_everywhere(pid: String) -> void:
	for i in starting.size():
		if starting[i] == pid:
			starting[i] = ""
	bench.erase(pid)
	reserves.erase(pid)


func _check_player(db: Node, pid: String) -> String:
	var p: PlayerData = db.get_player(pid)
	if p == null:
		return "unknown player '%s'" % pid
	if p.team_id != team_id:
		return "player '%s' does not belong to team '%s'" % [pid, team_id]
	if p.status != PlayerData.Status.ACTIVE:
		return "player '%s' is not available" % pid
	return ""


func set_formation(fid: String) -> String:
	if not FormationData.is_valid(fid):
		return "unknown formation '%s'" % fid
	formation_id = fid
	return ""


func assign_starter(db: Node, slot: int, pid: String) -> String:
	if slot < 0 or slot > 10:
		return "slot %d out of range" % slot
	var err := _check_player(db, pid)
	if err != "":
		return err
	var p: PlayerData = db.get_player(pid)
	var is_gk_slot := FormationData.slot_position(formation_id, slot) == PlayerData.Position.GK
	if is_gk_slot != (p.position == PlayerData.Position.GK):
		return "goalkeeper/outfield mismatch for slot %d" % slot
	var displaced := starting[slot]
	_remove_everywhere(pid)
	starting[slot] = pid
	if displaced != "" and displaced != pid:
		_add_to_reserves_or_bench(displaced)
	return ""


func _add_to_reserves_or_bench(pid: String) -> void:
	if bench.size() < MAX_BENCH:
		bench.append(pid)
	else:
		reserves.append(pid)


func add_to_bench(db: Node, pid: String) -> String:
	var err := _check_player(db, pid)
	if err != "":
		return err
	if not (pid in bench) and bench.size() >= MAX_BENCH:
		return "bench is full (%d)" % MAX_BENCH
	_remove_everywhere(pid)
	bench.append(pid)
	if captain_id == pid:
		captain_id = ""
	_clear_takers(pid)
	return ""


func add_to_reserves(db: Node, pid: String) -> String:
	var err := _check_player(db, pid)
	if err != "":
		return err
	_remove_everywhere(pid)
	reserves.append(pid)
	if captain_id == pid:
		captain_id = ""
	_clear_takers(pid)
	return ""


func _clear_takers(pid: String) -> void:
	for k in set_pieces:
		if set_pieces[k] == pid:
			set_pieces[k] = ""


func set_captain(pid: String) -> String:
	if not (pid in starting):
		return "captain must be in the starting XI"
	captain_id = pid
	return ""


func set_set_piece_taker(kind: String, pid: String) -> String:
	if not set_pieces.has(kind):
		return "unknown set piece '%s'" % kind
	if not (pid in starting):
		return "set-piece taker must be in the starting XI"
	set_pieces[kind] = pid
	return ""


## Swaps a starter with a bench player (substitution).
func substitute(db: Node, slot: int, bench_pid: String) -> String:
	if slot < 0 or slot > 10 or starting[slot] == "":
		return "no starter in slot %d" % slot
	if not (bench_pid in bench):
		return "'%s' is not on the bench" % bench_pid
	var out_pid := starting[slot]
	var is_gk_slot := FormationData.slot_position(formation_id, slot) == PlayerData.Position.GK
	var incoming: PlayerData = db.get_player(bench_pid)
	var incoming_gk := incoming != null and incoming.position == PlayerData.Position.GK
	if incoming_gk != is_gk_slot:
		return "goalkeeper/outfield mismatch"
	bench[bench.find(bench_pid)] = out_pid
	starting[slot] = bench_pid
	if captain_id == out_pid:
		captain_id = bench_pid
	for k in set_pieces:
		if set_pieces[k] == out_pid:
			set_pieces[k] = bench_pid
	return ""


## Fills the XI (best fit × overall), then a 7-man bench, rest to reserves.
func auto_pick(db: Node) -> void:
	starting.fill("")
	bench.clear()
	reserves.clear()
	var pool: Array[PlayerData] = []
	for p: PlayerData in db.get_squad(team_id):
		if p.status == PlayerData.Status.ACTIVE:
			pool.append(p)
	var used := {}
	for slot in 11:
		var slot_pos := FormationData.slot_position(formation_id, slot)
		var best: PlayerData = null
		var best_score := 0.0
		for p in pool:
			if used.has(p.id):
				continue
			var fit := FormationData.position_fit(p.position, slot_pos)
			if fit <= 0.0:
				continue
			var score := fit * p.get_overall()
			if score > best_score:
				best_score = score
				best = p
		if best != null:
			starting[slot] = best.id
			used[best.id] = true
	pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	for p in pool:
		if not used.has(p.id):
			_add_to_reserves_or_bench(p.id)
	captain_id = ""
	# Default captain: highest-experience starter.
	var top := -1
	for pid in starting:
		var pd: PlayerData = db.get_player(pid) if pid != "" else null
		if pd != null and pd.experience > top:
			top = pd.experience
			captain_id = pid


## Full integrity check against the database.
func validate(db: Node) -> Array[String]:
	var errors: Array[String] = []
	if not FormationData.is_valid(formation_id):
		errors.append("unknown formation '%s'" % formation_id)
		return errors
	var seen := {}
	var all_ids: Array[String] = []
	all_ids.append_array(starting)
	all_ids.append_array(bench)
	all_ids.append_array(reserves)
	for pid in all_ids:
		if pid == "":
			continue
		if seen.has(pid):
			errors.append("player '%s' appears more than once" % pid)
		seen[pid] = true
		var err := _check_player(db, pid)
		if err != "":
			errors.append(err)
	var filled := 0
	for slot in 11:
		if starting[slot] == "":
			continue
		filled += 1
		var p: PlayerData = db.get_player(starting[slot])
		if p != null:
			var gk_slot := FormationData.slot_position(formation_id, slot) == PlayerData.Position.GK
			if gk_slot != (p.position == PlayerData.Position.GK):
				errors.append("slot %d goalkeeper/outfield mismatch" % slot)
	if filled != 11:
		errors.append("starting XI has %d players, needs 11" % filled)
	if bench.size() > MAX_BENCH:
		errors.append("bench has %d players, max %d" % [bench.size(), MAX_BENCH])
	if captain_id != "" and not (captain_id in starting):
		errors.append("captain not in starting XI")
	for k in set_pieces:
		if set_pieces[k] != "" and not (set_pieces[k] in starting):
			errors.append("%s taker not in starting XI" % k)
	return errors


func get_tactics() -> TacticsPreset:
	return presets[clampi(active_preset, 0, presets.size() - 1)]


func save_preset(preset: TacticsPreset) -> String:
	var errs := preset.validate()
	if not errs.is_empty():
		return errs[0]
	for i in presets.size():
		if presets[i].preset_name == preset.preset_name:
			presets[i] = preset
			return ""
	presets.append(preset)
	return ""


func select_preset(preset_name: String) -> bool:
	for i in presets.size():
		if presets[i].preset_name == preset_name:
			active_preset = i
			return true
	return false


func to_dict() -> Dictionary:
	return {"team_id": team_id, "formation": formation_id, "starting": Array(starting),
			"bench": Array(bench), "reserves": Array(reserves), "captain": captain_id,
			"set_pieces": set_pieces.duplicate(), "active_preset": active_preset,
			"presets": presets.map(func(p: TacticsPreset) -> Dictionary: return p.to_dict())}


static func from_dict(d: Dictionary) -> Squad:
	var s := Squad.new(str(d.get("team_id", "")), str(d.get("formation", "4-3-3")))
	s.starting.assign((d.get("starting", []) as Array).map(func(x: Variant) -> String: return str(x)))
	s.starting.resize(11)
	s.bench.assign((d.get("bench", []) as Array).map(func(x: Variant) -> String: return str(x)))
	s.reserves.assign((d.get("reserves", []) as Array).map(func(x: Variant) -> String: return str(x)))
	s.captain_id = str(d.get("captain", ""))
	for k in s.set_pieces:
		s.set_pieces[k] = str((d.get("set_pieces", {}) as Dictionary).get(k, ""))
	var ps: Array = d.get("presets", [])
	if not ps.is_empty():
		s.presets.clear()
		for pd in ps:
			s.presets.append(TacticsPreset.from_dict(pd))
	s.active_preset = int(d.get("active_preset", 0))
	return s
