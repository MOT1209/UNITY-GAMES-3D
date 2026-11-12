class_name ManagerAI
extends RefCounted

## Manager-level AI (Phase T11): reacts to the match situation.
## `decide()` is pure and returns a list of orders:
##   {type:"mentality", value:int}, {type:"pressing", value:int},
##   {type:"substitute", slot:int, in_id:String, out_id:String}
## The match manager applies them (`apply()` helper below).

const MAX_SUBS := 3
const TIRED_STAMINA := 45.0
const LATE_MINUTE := 70.0


static func decide(state: MatchState, side: String, squad: Squad, tactics: TacticsPreset,
		db: Node) -> Array:
	var orders: Array = []
	var minute := state.display_minute()
	var diff := state.goal_difference(side)
	var M := TacticsPreset.Mentality
	# --- game-state tactics ---
	if minute >= LATE_MINUTE and diff < 0 and tactics.mentality != M.ULTRA_ATTACKING:
		var target: int = M.ULTRA_ATTACKING if (diff <= -2 or minute >= 82.0) else M.ATTACKING
		if int(tactics.mentality) < target:
			orders.append({"type": "mentality", "value": target})
			orders.append({"type": "pressing", "value": maxi(tactics.pressing, 75)})
	elif minute >= 75.0 and diff > 0 and int(tactics.mentality) > int(M.DEFENSIVE):
		orders.append({"type": "mentality", "value": int(M.DEFENSIVE)})
		orders.append({"type": "pressing", "value": mini(tactics.pressing, 40)})
	# --- substitutions: tired starters, same-role bench replacement ---
	if int(state.subs_used[side]) < MAX_SUBS and minute >= 55.0:
		var worst_slot := -1
		var worst := TIRED_STAMINA
		for slot in 11:
			var pid := squad.starting[slot]
			if pid == "":
				continue
			var st: float = float(state.stamina.get(pid, 100.0))
			if st < worst:
				worst = st
				worst_slot = slot
		if worst_slot >= 0:
			var in_id := _pick_replacement(squad, worst_slot, db)
			if in_id != "":
				orders.append({"type": "substitute", "slot": worst_slot, "in_id": in_id,
						"out_id": squad.starting[worst_slot]})
	return orders


## Best bench player for a slot: must match goalkeeper/outfield; highest
## (fit × overall × freshness).
static func _pick_replacement(squad: Squad, slot: int, db: Node) -> String:
	var slot_pos := FormationData.slot_position(squad.formation_id, slot)
	var best := ""
	var best_score := 0.0
	for pid in squad.bench:
		var p: PlayerData = db.get_player(pid)
		if p == null or p.status != PlayerData.Status.ACTIVE:
			continue
		var fit := FormationData.position_fit(p.position, slot_pos)
		if fit <= 0.0:
			continue
		var score := fit * p.get_overall() * (p.fitness / 100.0)
		if score > best_score:
			best_score = score
			best = pid
	return best


## Applies orders to a squad/tactics/state. Returns the list of applied substitutions.
static func apply(orders: Array, side: String, state: MatchState, squad: Squad,
		tactics: TacticsPreset, db: Node) -> Array:
	var subs: Array = []
	for o in orders:
		match o["type"]:
			"mentality":
				tactics.mentality = int(o["value"]) as TacticsPreset.Mentality
			"pressing":
				tactics.pressing = clampi(int(o["value"]), 0, 100)
			"substitute":
				var out_id: String = squad.starting[int(o["slot"])]
				if int(state.subs_used[side]) < MAX_SUBS \
						and squad.substitute(db, int(o["slot"]), str(o["in_id"])) == "":
					state.stamina[o["in_id"]] = 100.0
					state.record_substitution(side, out_id, str(o["in_id"]))    # counter + event + stats, once
					subs.append(o)
	return subs
