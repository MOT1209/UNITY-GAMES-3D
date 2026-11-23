class_name AdvancedPlay
extends RefCounted

## Match-level side of the Phase 2 advanced mechanics. Owned by `MatchManager` (`m.advanced`), ticked while the ball is
## in play. Uses its OWN seeded RNG (from the match seed), so the existing match RNG stream is not shifted.
##
##   DECEPTION  `on_feint`: every AI defender near a feint may bite (committed the wrong way for a moment: no tackle,
##              a step towards the fake) or read it (anticipates the real direction: a better tackle). The chance
##              depends on the feint (strength x execution quality), the defender (anticipation, defensive awareness,
##              reactions), the distance, his momentum towards the carrier, the difficulty and whether he is the last
##              man. A human defender is never steered — he reads the feint himself.
##   TACKLES    `tackle_rate_mult` (how eagerly an AI defender goes in) and `tackle_context` (the win chance) follow
##              the carrier's state: shielding protects, a skill move exposes the ball, a bitten defender cannot tackle,
##              a defender who read the move wins more. Both are exactly 1.0 when nothing special is going on, so the
##              tuned Phase 4 / M5 tackle numbers are unchanged in ordinary play.
##   PHYSICAL   shoulder challenges between opposing players in contact (strength, balance, mass, momentum along the
##              contact direction); the loser is nudged (<= PlayerController.MAX_NUDGE) and off balance briefly.
##              Shield contests: a defender pressing a shielding carrier contests the ball every SHIELD_CONTEST_EVERY s.

const FEINT_RADIUS := 5.0
const CONTACT_DISTANCE := 0.74
const DUEL_COOLDOWN := 0.9
const SHIELD_CONTEST_RADIUS := 1.15
const SHIELD_CONTEST_EVERY := 0.5

var m: MatchManager
var rng := RandomNumberGenerator.new()
var stats := {"skill_moves": 0, "skill_clean": 0, "feints": 0, "bites": 0, "reads": 0, "headers": 0,
		"shield_time": 0.0, "shield_contests": 0, "shield_lost": 0, "duels": 0, "techniques": {}, "contexts": {},
		"keeper_bites": 0, "skill_by_id": {},
		# decision funnel (diagnostics for tuning): carrier decisions by base action, take-ons, skill choices made,
		# aerial ticks (a player assigned to an aerial ball), header windows seen by assigned players, header presses
		"carrier": {}, "take_on": 0, "skill_choice": 0, "aerial_ticks": 0, "aerial_windows": 0, "aerial_presses": 0}
var _duel_cd := {}
var _shield_timer := 0.0


func _init(manager: MatchManager, seed_value: int) -> void:
	m = manager
	rng.seed = hash("advanced:%d" % seed_value)


func release() -> void:
	m = null


# --- wiring ------------------------------------------------------------------------------------------------------

## Connects one outfield entry (called by `MatchTeamBuilder` right after the spawn).
func wire(entry: Dictionary) -> void:
	var acts := entry["actions"] as FootballActions
	if acts == null:
		return
	var side: String = entry["side"]
	acts.nearest_opponent = _nearest_opponent.bind(side)
	acts.goals = _goals_for.bind(side)
	acts.skill.rng.seed = hash("skill:%s:%d" % [entry["player_id"], m.setup.rng_seed])
	acts.header.rng.seed = hash("header:%s:%d" % [entry["player_id"], m.setup.rng_seed])
	acts.feint_shown.connect(func(kind: StringName, d: Vector3, st: float) -> void: on_feint(entry, kind, d, st))
	acts.skill_move_started.connect(func(id: StringName, _q: float) -> void:
		stats["skill_moves"] += 1
		stats["skill_by_id"][id] = int(stats["skill_by_id"].get(id, 0)) + 1)
	acts.skill_move_finished.connect(func(_id: StringName, clean: bool) -> void:
		if clean:
			stats["skill_clean"] += 1)
	acts.header_played.connect(func(_k: StringName, _s: float, _q: float) -> void: stats["headers"] += 1)
	acts.shot_technique_used.connect(func(t: StringName, c: StringName) -> void:
		stats["techniques"][t] = int(stats["techniques"].get(t, 0)) + 1
		stats["contexts"][c] = int(stats["contexts"].get(c, 0)) + 1)


func _nearest_opponent(pos: Vector3, side: String) -> Vector3:
	if m == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := INF
	for e in m.entries["away" if side == "home" else "home"]:
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


func _goals_for(side: String) -> Array:
	if m == null:
		return []
	var frame := m.frame_side(side)
	return [PitchSpace.opponent_goal(frame), PitchSpace.own_goal(frame)]


# --- deception ---------------------------------------------------------------------------------------------------

## Chance that a defender bites on a feint (pure; tests and tuning read it).
## strength = feint strength x execution quality (0..1); read = the defender's reading of play (0..1).
static func bite_probability(strength: float, read: float, dist: float, closing_speed: float, difficulty: int,
		last_man: bool) -> float:
	var dist_f := 0.0
	if dist <= 2.6:
		dist_f = lerpf(0.55, 1.0, clampf((dist - 0.6) / 1.0, 0.0, 1.0))
	else:
		dist_f = clampf(1.0 - (dist - 2.6) / 2.4, 0.0, 1.0)
	var p := strength * dist_f * (1.25 - read)
	if closing_speed > 3.0:
		p += 0.12                      # committed momentum: a defender charging in is easier to wrong-foot
	match clampi(difficulty, 0, 2):
		0: p += 0.1
		2: p -= 0.08
	if last_man:
		p -= 0.1                       # the last man stays on his feet
	return clampf(p, 0.0, 0.85)


## How well a defender reads play, 0..1 (anticipation, defensive awareness, reactions).
static func read_of(mods: AttributeModifiers) -> float:
	if mods == null:
		return 0.5
	return mods.detail("anticipation") * 0.4 + mods.detail("defensive_awareness") * 0.35 + mods.detail("reactions") * 0.25


func on_feint(carrier: Dictionary, kind: StringName, dir: Vector3, strength: float) -> void:
	if m == null or m.state.phase != MatchState.Phase.PLAYING:
		return
	stats["feints"] += 1
	var cpos := (carrier["node"] as Node3D).global_position
	var enemy := "away" if carrier["side"] == "home" else "home"
	var own_goal := PitchSpace.own_goal(m.frame_side(enemy))
	for e in m.entries[enemy]:
		var node := e["node"] as Node3D
		var p := node.global_position
		var d := Vector2(p.x - cpos.x, p.z - cpos.z).length()
		if int(e["slot"]) == 0:
			if kind == &"shot" and d < 26.0 and node is TeamGoalkeeper:
				var r := read_of(e["mods"])
				if rng.randf() < clampf(strength * (1.1 - r), 0.0, 0.7):
					(node as TeamGoalkeeper).on_fake_shot()
					stats["keeper_bites"] += 1
			continue
		if e["ai"] == null or d > FEINT_RADIUS:
			continue
		var to_c := Vector3(cpos.x - p.x, 0.0, cpos.z - p.z)
		var vel := (node as CharacterBody3D).velocity
		var closing := Vector3(vel.x, 0.0, vel.z).dot(to_c.normalized()) if to_c.length() > 0.01 else 0.0
		var last_man := true
		var my_depth := absf(own_goal.z - p.z)
		for o in m.entries[enemy]:
			if o != e and int(o["slot"]) != 0 and absf(own_goal.z - (o["node"] as Node3D).global_position.z) < my_depth:
				last_man = false
				break
		var read := read_of(e["mods"])
		var p_bite := bite_probability(strength, read, d, closing, m.setup.difficulty, last_man)
		var roll := rng.randf()
		if roll < p_bite:
			e["bitten"] = 0.55 - 0.25 * (e["mods"] as AttributeModifiers).detail("reactions") if e["mods"] != null else 0.42
			e["bite_dir"] = dir
			e.erase("read")
			stats["bites"] += 1
		elif roll < p_bite + maxf(read - 0.45, 0.0) * 1.2:
			e["read"] = 0.7
			e["read_dir"] = -dir if kind in [&"step_over", &"body", &"elastico", &"spin", &"croqueta", &"roll"] else Vector3.ZERO
			stats["reads"] += 1


## Bitten / reading defenders: their movement this tick (true when the command was changed).
func steer_defender(e: Dictionary, carrier_pos: Vector3) -> bool:
	var bitten := float(e.get("bitten", 0.0))
	if bitten > 0.0:
		var cmd: Dictionary = (e["cmd"] as Dictionary).duplicate()
		cmd["move"] = (e["bite_dir"] as Vector3) * 0.85
		cmd["sprint"] = false
		cmd["action"] = &""
		e["cmd"] = cmd
		e["intent"] = "BITTEN"
		return true
	var read := float(e.get("read", 0.0))
	if read > 0.0 and (e.get("read_dir", Vector3.ZERO) as Vector3) != Vector3.ZERO:
		var pos := (e["node"] as Node3D).global_position
		var spot := carrier_pos + (e["read_dir"] as Vector3) * 1.2
		var to := Vector3(spot.x - pos.x, 0.0, spot.z - pos.z)
		var cmd2: Dictionary = (e["cmd"] as Dictionary).duplicate()
		cmd2["move"] = to.normalized() if to.length() > 0.3 else Vector3.ZERO
		cmd2["sprint"] = to.length() > 2.0
		e["cmd"] = cmd2
		e["intent"] = "READ_FEINT"
		return true
	return false


# --- tackles -----------------------------------------------------------------------------------------------------

## Multiplier on an AI defender's tackle attempt rate against `carrier` (1.0 in ordinary play).
func tackle_rate_mult(tackler: Dictionary, carrier: Dictionary) -> float:
	if float(tackler.get("bitten", 0.0)) > 0.0:
		return 0.0
	var mult := 1.0
	if float(tackler.get("read", 0.0)) > 0.0:
		mult *= 1.8
	var acts := carrier.get("actions") as FootballActions
	if acts != null:
		if acts.shielding.is_active():
			mult *= 1.0 - 0.5 * acts.shielding.protection()       # a well-shielded ball is not lunged at
		if acts.skill.is_active():
			mult *= 1.0 + 1.2 * acts.skill.exposure()
	return mult


## Multiplier on the tackle's win chance (1.0 in ordinary play), clamped 0.3 .. 1.6.
func tackle_context(tackler: Dictionary, victim: Dictionary) -> float:
	var mult := 1.0
	if float(tackler.get("read", 0.0)) > 0.0:
		mult *= 1.25
	var acts := victim.get("actions") as FootballActions
	if acts != null:
		if acts.shielding.is_active():
			mult *= 1.0 - 0.45 * acts.shielding.protection()
		if acts.skill.is_active():
			mult *= (1.0 + 0.6 * acts.skill.exposure()) * (1.0 - 0.5 * acts.skill.protect())
	return clampf(mult, 0.3, 1.6)


# --- per tick ----------------------------------------------------------------------------------------------------

func update(delta: float) -> void:
	if m == null:
		return
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e.has("bitten"):
				e["bitten"] = float(e["bitten"]) - delta
				if float(e["bitten"]) <= 0.0:
					e.erase("bitten")
			if e.has("read"):
				e["read"] = float(e["read"]) - delta
				if float(e["read"]) <= 0.0:
					e.erase("read")
	for k in _duel_cd.keys():
		_duel_cd[k] = float(_duel_cd[k]) - delta
		if float(_duel_cd[k]) <= 0.0:
			_duel_cd.erase(k)
	_shoulder_duels()
	_shield_contest(delta)


## Shoulder-to-shoulder / running duels: opposing outfield players in contact, at least one of them moving.
func _shoulder_duels() -> void:
	for a in m.entries["home"]:
		var na := a["node"] as PlayerController
		if na == null:
			continue
		for b in m.entries["away"]:
			var nb := b["node"] as PlayerController
			if nb == null:
				continue
			var rel := nb.global_position - na.global_position
			rel.y = 0.0
			if rel.length() > CONTACT_DISTANCE:
				continue
			var key := "%s|%s" % [a["player_id"], b["player_id"]]
			if _duel_cd.has(key):
				continue
			if na.get_current_speed() < 1.5 and nb.get_current_speed() < 1.5:
				continue
			_duel_cd[key] = DUEL_COOLDOWN
			resolve_shoulder(a, b)


## Contact strength of a player in a duel (0..~1.2): strength, balance, mass and momentum along the contact.
static func duel_power(mods: AttributeModifiers, speed_along: float) -> float:
	var st := mods.detail("strength") if mods != null else 0.5
	var bal := mods.detail("balance") if mods != null else 0.5
	var mass := mods.mass_kg() if mods != null else 76.0
	return st * 0.45 + bal * 0.25 + clampf((mass - 60.0) / 40.0, 0.0, 1.0) * 0.15 + clampf(speed_along / 8.0, -0.3, 1.0) * 0.15


## Resolves one contact between `a` and `b`. Returns the winner's side ("home"/"away").
func resolve_shoulder(a: Dictionary, b: Dictionary) -> String:
	var na := a["node"] as PlayerController
	var nb := b["node"] as PlayerController
	var n := nb.global_position - na.global_position
	n.y = 0.0
	n = n.normalized() if n.length_squared() > 0.0001 else Vector3.RIGHT
	var pa := duel_power(a["mods"], na.velocity.dot(n))
	var pb := duel_power(b["mods"], -nb.velocity.dot(n))
	if na.is_off_balance():
		pa -= 0.15
	if nb.is_off_balance():
		pb -= 0.15
	var p_a := clampf(0.5 + (pa - pb) * 1.6, 0.1, 0.9)
	var a_wins := rng.randf() < p_a
	var loser: Dictionary = b if a_wins else a
	var ln := loser["node"] as PlayerController
	var margin := absf(pa - pb)
	var push_dir := n if a_wins else -n
	ln.nudge(push_dir * (0.6 + 0.9 * clampf(margin * 2.0, 0.0, 1.0)))
	ln.lose_balance(0.3 + 0.2 * clampf(margin * 2.0, 0.0, 1.0), 0.72)
	var la := loser["actions"] as FootballActions
	if la != null:
		la.skill.cancel()
	stats["duels"] += 1
	return (a if a_wins else b)["side"]


func _shield_contest(delta: float) -> void:
	var carrier := m._owner_entry()
	if carrier.is_empty() or carrier["actions"] == null:
		_shield_timer = 0.0
		return
	var acts := carrier["actions"] as FootballActions
	if not acts.shielding.is_active():
		_shield_timer = 0.0
		return
	stats["shield_time"] += delta
	var cn := carrier["node"] as PlayerController
	var best: Dictionary = {}
	var best_d := SHIELD_CONTEST_RADIUS
	for e in m.entries["away" if carrier["side"] == "home" else "home"]:
		if int(e["slot"]) == 0:
			continue
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - cn.global_position.x, p.z - cn.global_position.z).length()
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		_shield_timer = 0.0
		return
	_shield_timer += delta
	if _shield_timer < SHIELD_CONTEST_EVERY:
		return
	_shield_timer = 0.0
	resolve_shield_contest(carrier, best)


## Chance that a pressing defender knocks a shielding carrier off the ball in one contest (pure).
static func shield_loss_probability(protection: float, carrier_mods: AttributeModifiers, defender_mods: AttributeModifiers,
		defender_defending: float) -> float:
	var cs := carrier_mods.detail("strength") if carrier_mods != null else 0.5
	var cb := carrier_mods.detail("balance") if carrier_mods != null else 0.5
	var ds := defender_mods.detail("strength") if defender_mods != null else 0.5
	var da := defender_mods.detail("aggression") if defender_mods != null else 0.5
	var cp := protection * 0.5 + cs * 0.3 + cb * 0.2
	var dp := ds * 0.45 + da * 0.2 + defender_defending * 0.35
	return clampf(0.22 + (dp - cp) * 1.1, 0.04, 0.6)


func resolve_shield_contest(carrier: Dictionary, defender: Dictionary) -> bool:
	var acts := carrier["actions"] as FootballActions
	var dd := float((defender["pdata"] as PlayerData).defending) / 100.0 if defender.get("pdata") != null else 0.5
	var p_lose := shield_loss_probability(acts.shielding.protection(), carrier["mods"], defender["mods"], dd)
	stats["shield_contests"] += 1
	if rng.randf() >= p_lose:
		return false
	stats["shield_lost"] += 1
	var cn := carrier["node"] as PlayerController
	var dn := defender["node"] as Node3D
	cn.lose_balance(0.45, 0.55)
	acts.shielding.release()
	# The defender gets a foot round the side: the ball is knocked out sideways of the duel (never through the carrier's
	# body), a little towards the defender. A real impulse, not a transfer of possession.
	var axis := dn.global_position - cn.global_position
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD
	var lateral := axis.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	m.ball.apply_kick((lateral + axis * 0.35).normalized(), 2.5)
	return true
