class_name MatchAIDriver
extends RefCounted

## Turns the AI layers' decisions into intents (UX phase 5.4, split out of `MatchManager`): every tick each
## AI-controlled player gets a `PlayerAI.decide` command (on its think interval) built from the team's
## formation targets and pressing, and the command is applied to its `AIIntent` — movement, sprint,
## dribble and charged kicks (aim compensation, distance-based charge). Static: the state lives in the
## manager's entries.


static func update(m: MatchManager, delta: float) -> void:
	var owner := m._owner_entry()
	var owner_side: String = owner.get("side", "")
	_expire_incoming(m, owner)
	for side in ["home", "away"]:
		var other := "away" if side == "home" else "home"
		var data: Dictionary = m.sides[side]
		var tactics: TacticsPreset = data["tactics"]
		var mine := m._positions(side)
		var theirs := m._positions(other)
		var has_ball_team: bool = owner_side == side
		var frame := m.frame_side(side)
		var targets := TeamAI.formation_targets(frame, data["formation"], tactics, m.ball.global_position, has_ball_team)
		# Phase M4: only a side WITHOUT the ball sends players at it. Before, the closest team-mate of the carrier also
		# "chased" the ball and ran into his own carrier.
		var chasers: Array[int] = []
		if not has_ball_team:
			chasers = TeamAI.pressers(mine, m.ball.global_position, frame, tactics,
					AIDifficulty.press_distance_bonus(m.setup.difficulty))
		var markers: Dictionary = {}
		if not has_ball_team:
			# Nov 2026: a compact block that slides with the ball, a flat back line, man marking near the own goal
			TeamAI.defensive_shape(targets, data["formation"], frame, m.ball.global_position)
			markers = TeamAI.marking_targets(mine, targets, theirs, frame, m.ball.global_position, chasers)
			for s in markers:
				targets[s] = markers[s]
		var goal_here := PitchSpace.opponent_goal(frame)
		if has_ball_team:
			var line := PlayerAI.offside_line(goal_here, m.ball.global_position, theirs)
			_hold_the_line(targets, goal_here, line, _early_runners(m, side, targets, goal_here, line, delta))
		var supporters: Dictionary = {}
		if has_ball_team:
			supporters = _support_spots(m, side, owner, targets, theirs, frame)
		var aerial := _aerial_players(m, side)
		for e in m.entries[side]:
			var ai: AIIntent = e["ai"]
			if ai == null:
				continue                         # human controlled
			ai.begin_tick()
			if e.has("hdr_release"):
				ai.release(e["hdr_release"])
				e.erase("hdr_release")
			e["skill_cd"] = float(e.get("skill_cd", 0.0)) - delta
			e["shield_left"] = float(e.get("shield_left", 0.0)) - delta
			e["think"] -= delta
			if e["think"] <= 0.0:
				e["think"] = MatchManager.THINK_INTERVAL[clampi(m.setup.difficulty, 0, 2)]
				var slot: int = e["slot"]
				var pos: Vector3 = (e["node"] as Node3D).global_position
				var is_owner: bool = not owner.is_empty() and owner["player_id"] == e["player_id"]
				var team_mates: Array[Vector3] = []
				for i in mine.size():
					if i != slot:
						team_mates.append(mine[i])
				e["cmd"] = PlayerAI.decide({
					"pos": pos, "ball": m.ball.global_position, "has_ball": is_owner,
					"is_chaser": (slot in chasers) and not is_owner,
					"target": targets[slot], "goal": PitchSpace.opponent_goal(frame),
					"own_goal": PitchSpace.own_goal(frame), "teammates": team_mates,
					"opponents": theirs, "is_keeper": slot == 0,
					"difficulty": m.setup.difficulty, "attributes": e["mods"],
					"profile": AIDifficulty.apply(tactics.pass_profile(), m.setup.difficulty),
					"shoot_range": tactics.shoot_range() + AIDifficulty.shoot_range_bonus(m.setup.difficulty),
					"opp_keeper": theirs[0] if not theirs.is_empty() else Vector3.INF, "time": m._clock, "slot": slot,
					"offside_mistake": m._rng.randf() < OFFSIDE_MISTAKE})
				e["intent"] = intent_name(slot == 0, is_owner, (slot in chasers) and not is_owner, has_ball_team, e["cmd"])
				if markers.has(slot) and not is_owner and not (slot in chasers):
					e["intent"] = "MARK"
				if is_owner and m.advanced != null:
					_advanced_carrier(m, e, pos, theirs, frame)
				if supporters.has(slot) and e["cmd"]["action"] == &"":
					var spot: Vector3 = supporters[slot]
					var to_spot := Vector3(spot.x - pos.x, 0.0, spot.z - pos.z)
					e["cmd"]["move"] = to_spot.normalized() * clampf(to_spot.length() / 4.0, 0.0, 1.0) if to_spot.length() > 0.8 \
							else PlayerAI.shape_shuffle(pos, m.ball.global_position, spot, m._clock, slot)
					e["cmd"]["sprint"] = to_spot.length() > 10.0
					e["intent"] = "SUPPORT_RUN"
			if not m.incoming_pass.is_empty() and m.incoming_pass["receiver_id"] == e["player_id"] and e["charging"] == &"" \
					and not e["cmd"].is_empty():
				var rc: Dictionary = (e["cmd"] as Dictionary).duplicate()
				rc["move"] = receive_move((e["node"] as Node3D).global_position, m.ball.global_position, m.ball.linear_velocity)
				rc["sprint"] = (rc["move"] as Vector3).length() > 0.95
				rc["action"] = &""
				e["cmd"] = rc
				e["intent"] = "RECEIVE"
			if m.advanced != null and not e["cmd"].is_empty() and not owner.is_empty() and owner["player_id"] != e["player_id"]:
				m.advanced.steer_defender(e, (owner["node"] as Node3D).global_position)
			_apply_cmd(m, e, ai)
			if aerial.has(e["player_id"]):
				_aerial_step(m, e, ai, frame, mine)


## Phase M4: share of pass decisions that do not see an offside team-mate (the odd mistake: offsides still happen).
const OFFSIDE_MISTAKE := 0.12


## Phase M4: with the ball the forwards' targets stay level with the offside line (0.6 m onside) — they used to run
## beyond the last defender and 9-14 offsides were called in every 5-minute match.
## Phase 1: a forward on an early run (`early` slots, see `_early_runners`) goes EARLY_RUN_DEPTH beyond the line
## instead. Holding everyone onside all the time gave 0 offsides in every match (the 12 % pass mistakes never had an
## offside man to find).
static func _hold_the_line(targets: Array[Vector3], goal: Vector3, line: float, early: Array = []) -> void:
	for i in targets.size():
		if i == 0:
			continue
		var t := targets[i]
		if i in early:
			t.z = goal.z - signf(goal.z) * maxf(line - EARLY_RUN_DEPTH, 1.0)
			targets[i] = t
		elif absf(goal.z - t.z) < line + 0.6 and absf(goal.z - t.z) < PitchSpace.HALF_LENGTH:
			t.z = goal.z - signf(goal.z) * (line + 0.6)
			targets[i] = t


## Phase 1: the forwards of the side in possession (targets held at the offside line) now and then start their run
## in behind too early — EARLY_RUN_RATE runs per second per forward, each EARLY_RUN_TIME s long. Drawn from the match
## RNG (deterministic per seed); kept in the entries ("early_run" = seconds left). Returns the running slots.
const EARLY_RUN_RATE := 0.08
const EARLY_RUN_TIME := 1.2
const EARLY_RUN_DEPTH := 1.5


static func _early_runners(m: MatchManager, side: String, targets: Array[Vector3], goal: Vector3, line: float, delta: float) -> Array:
	var out := []
	for e in m.entries[side]:
		var slot: int = e["slot"]
		if slot == 0 or e["ai"] == null or slot >= targets.size():
			continue
		var left: float = e.get("early_run", 0.0)
		if left > 0.0:
			e["early_run"] = left - delta
			out.append(slot)
			continue
		var depth := absf(goal.z - targets[slot].z)
		if depth < line + 0.6 and depth < PitchSpace.HALF_LENGTH and m._rng.randf() < EARLY_RUN_RATE * delta:
			e["early_run"] = EARLY_RUN_TIME
			out.append(slot)
	return out


## Phase M4: the SUPPORT_PLAYERS outfielders of the side in possession closest to the ball (not the carrier, not the
## keeper) each get an open spot to offer a pass ({slot: Vector3}); the rest keep the shape.
const SUPPORT_PLAYERS := 4


static func _support_spots(m: MatchManager, side: String, owner: Dictionary, targets: Array[Vector3], theirs: Array[Vector3], frame: String) -> Dictionary:
	var out := {}
	if owner.is_empty():
		return out
	var carrier := (owner["node"] as Node3D).global_position
	var goal := PitchSpace.opponent_goal(frame)
	var cands: Array = []
	for e in m.entries[side]:
		if e == owner or int(e["slot"]) == 0 or e["ai"] == null:
			continue
		var p := (e["node"] as Node3D).global_position
		cands.append([Vector2(p.x - carrier.x, p.z - carrier.z).length(), int(e["slot"])])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var taken: Array = []
	for c in cands.slice(0, SUPPORT_PLAYERS):
		var slot: int = c[1]
		var spot := TeamAI.support_spot(carrier, goal, targets[slot], theirs, taken)
		if spot != Vector3.INF:
			out[slot] = spot
			taken.append(spot)
	return out


## Readable name of what an AI player is doing (debug view F9, bug reports F8).
static func intent_name(keeper: bool, owner: bool, chaser: bool, team_has_ball: bool, cmd: Dictionary) -> String:
	if keeper:
		return "KEEPER"
	if owner:
		match cmd.get("action", &""):
			&"shoot": return "SHOOT"
			&"pass": return "PASS"
			&"lob_pass": return "CROSS"
		return "CARRY"
	if chaser:
		return "CLOSE_DOWN"
	if team_has_ball:
		return "SUPPORT"
	return "HOLD_SHAPE" if (cmd.get("move", Vector3.ZERO) as Vector3).length() < 0.05 else "MARK_SHAPE"


static func _apply_cmd(m: MatchManager, e: Dictionary, ai: AIIntent) -> void:
	var cmd: Dictionary = e["cmd"]
	if cmd.is_empty():
		return
	var charging: bool = e["charging"] != &""
	if charging:
		# Phase M1: while the kick charges the player keeps the ball at his foot (he follows it at its own pace instead of
		# planting while a dribbled ball rolls out of reach and cancels the kick) and the aim tracks the receiver.
		ai.set_move_world(_follow_ball(m, e))
		ai.release(&"sprint")
		ai.set_aim_world(_kick_aim(e, e["charging"], _aim_direction(m, e)))
	else:
		ai.set_aim_world(Vector3.ZERO)
		ai.kick_power = 0.0
		ai.set_move_world(cmd["move"])
		# Phase 2: shielding (held while the command says so) and a skill move (asked for once)
		if cmd.get("shield", false):
			ai.press(&"shield")
		else:
			ai.release(&"shield")
		if cmd.has("skill"):
			var sk: Dictionary = cmd["skill"]
			ai.skill_request = sk["id"]
			ai.skill_side = float(sk["side"])
			cmd.erase("skill")
		if cmd["sprint"]:
			ai.press(&"sprint")
		else:
			ai.release(&"sprint")
	var action: StringName = cmd["action"]
	if charging:
		if m._clock >= e["release_at"]:
			var rec: Dictionary = e.get("kick_receiver", {})
			if e["charging"] != &"shoot" and not rec.is_empty():
				m.incoming_pass = {"receiver_id": rec["player_id"], "passer_id": e["player_id"], "t": m._clock}
			ai.release(e["charging"])
			e["charging"] = &""
			e["cmd"] = {}
	elif action != &"" and _can_start_kick(e, action):
		ai.release(&"dribble")
		e["kick_target"] = cmd.get("target_pos", Vector3.INF)
		e["kick_point"] = cmd.get("target_pos", (e["node"] as Node3D).global_position + (cmd["move"] as Vector3) * maxf(float(cmd.get("kick_dist", 10.0)), 1.0))
		e["kick_receiver"] = _receiver_at(m, e, e["kick_point"]) if action != &"shoot" else {}
		e["charging"] = action
		ai.release(&"shield")
		ai.shot_technique = cmd.get("technique", ShotTechnique.NORMAL) if action == &"shoot" else &""
		ai.set_aim_world(_kick_aim(e, action, _aim_direction(m, e)))       # the aim is read from this aim on the release frame
		ai.press(action)
		ai.kick_power = _power_for(e, action, float(cmd.get("kick_dist", -1.0)))
		e["release_at"] = m._clock + (0.03 if ai.kick_power > 0.0 else _charge_for(e, action, float(cmd.get("kick_dist", -1.0))))
	else:
		var carrying: bool = cmd["move"] != Vector3.ZERO and m._owner_entry().get("player_id", "") == e["player_id"]
		if carrying:
			ai.press(&"dribble")
		else:
			ai.release(&"dribble")


## The pass in flight is over once somebody other than the passer has the ball, play stopped, or after 3.5 s.
static func _expire_incoming(m: MatchManager, owner: Dictionary) -> void:
	var inc: Dictionary = m.incoming_pass
	if inc.is_empty():
		return
	if m.state.phase != MatchState.Phase.PLAYING or m._clock - float(inc["t"]) > 3.5 \
			or (not owner.is_empty() and owner["player_id"] != inc["passer_id"] and m._clock - float(inc["t"]) > 0.1):
		m.incoming_pass = {}


## Phase M1 reception: the intended receiver attacks the ball's path — he runs to the point of the ball's line closest
## to him (the interception point), slows down as he gets there and then steps towards the ball to meet it. A slow or
## passed ball is simply collected.
static func receive_move(pos: Vector3, ball: Vector3, ball_vel: Vector3) -> Vector3:
	var v := Vector3(ball_vel.x, 0.0, ball_vel.z)
	var to_ball := Vector3(ball.x - pos.x, 0.0, ball.z - pos.z)
	if v.length() < 2.0:
		return to_ball.normalized() if to_ball.length() > 0.3 else Vector3.ZERO
	var dir := v.normalized()
	var along := (pos - ball).dot(dir)
	if along <= 0.5:
		return to_ball.normalized()                # the ball is level or past: chase it
	var spot := ball + dir * along
	var to_spot := Vector3(spot.x - pos.x, 0.0, spot.z - pos.z)
	if to_spot.length() > 0.4:
		return to_spot.normalized() * clampf(to_spot.length() / 2.5, 0.35, 1.0)
	return to_ball.normalized() * 0.3                # on the line: meet the ball


## Move vector that keeps the charging player on the ball: towards it, at most as fast as needed to stay with it.
static func _follow_ball(m: MatchManager, e: Dictionary) -> Vector3:
	var pos := (e["node"] as Node3D).global_position
	var rel := Vector3(m.ball.global_position.x - pos.x, 0.0, m.ball.global_position.z - pos.z)
	if rel.length() < 0.45:
		return Vector3.ZERO
	var node := e["node"] as PlayerController
	var top := node.config.normal_speed if node != null else 5.0
	var ball_speed := Vector2(m.ball.linear_velocity.x, m.ball.linear_velocity.z).length()
	return rel.normalized() * clampf((ball_speed + rel.length()) / maxf(top, 0.1), 0.25, 1.0)


## The team-mate the kick is meant for (closest to the point it was aimed at, within 6 m: a through ball is played up
## to 4.5 m into the receiver's run), or {}.
static func _receiver_at(m: MatchManager, e: Dictionary, point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 6.0
	for o in m.entries[e["side"]]:
		if o == e:
			continue
		var p := (o["node"] as Node3D).global_position
		var d := Vector2(p.x - point.x, p.z - point.z).length()
		if d < best_d:
			best_d = d
			best = o
	return best


## Ground direction from the ball to where the kick must go now: the receiver's current position plus his run during
## the ball's flight (lead), else the point chosen when the kick started.
static func _aim_direction(m: MatchManager, e: Dictionary) -> Vector3:
	var point: Vector3 = e.get("kick_point", Vector3.INF)
	var rec: Dictionary = e.get("kick_receiver", {})
	if not rec.is_empty() and is_instance_valid(rec["node"]):
		var rn := rec["node"] as CharacterBody3D
		var offset: Vector3 = point - rn.global_position if point != Vector3.INF else Vector3.ZERO
		offset.y = 0.0
		point = rn.global_position + offset.limit_length(4.5)
		var dist := Vector2(point.x - m.ball.global_position.x, point.z - m.ball.global_position.z).length()
		var flight := dist / maxf(pass_power_for(dist) * 0.85, 1.0)
		var run := Vector3(rn.velocity.x, 0.0, rn.velocity.z) * flight
		point += run.limit_length(6.0)
	if point == Vector3.INF:
		return Vector3.ZERO
	var d := Vector3(point.x - m.ball.global_position.x, 0.0, point.z - m.ball.global_position.z)
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## Ground-pass speed (m/s off the foot) for a pass of `dist` metres. A rolling ball loses about 0.22 m/s per metre
## (measured, `tools/exp/roll.tscn`), so this arrives at about 5.5 m/s whatever the length.
static func pass_power_for(dist: float) -> float:
	return clampf(5.5 + dist * 0.22, 6.0, 16.0)


## The AI only starts a kick when the ball is really within reach (`FootballActions` ignores the press otherwise, and the
## charge would be wasted while the player runs on).
static func _can_start_kick(e: Dictionary, action: StringName) -> bool:
	var acts := e["actions"] as FootballActions
	var key: StringName = &"lob" if action == &"lob_pass" else action      # the availability map names the lob "lob"
	return acts == null or bool(acts.get_action_availability().get(key, false))


## Aim that cancels the kick systems' bend towards the ball's side (see `PlayerAI.compensated_aim`), so the ball goes where the AI wants.
static func _kick_aim(e: Dictionary, action: StringName, wanted: Vector3) -> Vector3:
	if wanted == Vector3.ZERO:
		return Vector3.ZERO
	var acts := e["actions"] as FootballActions
	if acts == null or acts.config == null or acts.ball_detector == null:
		return wanted
	var a: float = acts.config.shoot_direction_adjustment
	if action == &"pass":
		a = acts.config.pass_direction_adjustment
	elif action == &"lob_pass":
		a = acts.config.lob_direction_adjustment
	var aim := PlayerAI.compensated_aim(wanted, acts.ball_detector.get_direction_to_ball(), a)
	return aim if aim != Vector3.ZERO else wanted


## The power the AI kicks a pass / lob with (m/s, 0 = charge it): fitted to the distance so the ball arrives at a
## controllable pace. Shots keep their charge (power from the charge curve).
static func _power_for(e: Dictionary, action: StringName, dist: float) -> float:
	var acts := e["actions"] as FootballActions
	if acts == null or acts.config == null or dist < 0.0:
		return 0.0
	var cfg := acts.config
	match action:
		&"pass":
			return clampf(pass_power_for(dist), cfg.min_pass_power, cfg.max_pass_power)
		&"lob_pass":
			return clampf(3.0 + dist * 0.32, cfg.min_lob_power, cfg.max_lob_power)
	return 0.0


## How long the AI holds a kick button: passes (up to 60 % charge) and lobs are charged for the distance to the target (a
## long ball needs more power); shots use the short fixed charge. Without a distance the fixed CHARGE_TIME is used.
static func _charge_for(e: Dictionary, action: StringName, dist: float) -> float:
	var acts := e["actions"] as FootballActions
	if acts == null or acts.config == null or dist < 0.0:
		return float(MatchManager.CHARGE_TIME.get(action, 0.2))
	var cfg := acts.config
	var want := 0.0
	var lo := cfg.default_pass_power
	var hi := cfg.max_pass_power
	match action:
		&"pass":
			want = pass_power_for(dist)
		&"lob_pass":
			want = 3.0 + dist * 0.32
			lo = cfg.default_lob_power
			hi = cfg.max_lob_power
		_:                                # shots keep the short fixed charge: a long wind-up gets blocked (measured)
			return float(MatchManager.CHARGE_TIME.get(action, 0.2))
	# `KickPowerController` gives the default power for a tap and ramps from the default to the maximum while held.
	if want <= lo:
		return 0.03
	var ratio := clampf(inverse_lerp(lo, hi, want), 0.0, 1.0)
	return cfg.quick_tap_threshold + 0.02 + ratio * cfg.charge_time


# --- Phase 2 advanced mechanics ----------------------------------------------------------------------------------

## The carrier's advanced options on top of `PlayerAI.decide`: the technique of a shot, shielding when closely pressed
## with nothing on, or a skill move at a defender in front (see `AdvancedAI`). Rolls from the advanced RNG.
static func _advanced_carrier(m: MatchManager, e: Dictionary, pos: Vector3, theirs: Array[Vector3], frame: String) -> void:
	var cmd: Dictionary = e["cmd"]
	var acts := e["actions"] as FootballActions
	if acts == null or cmd.is_empty():
		return
	var r := m.advanced.rng
	var goal := PitchSpace.opponent_goal(frame)
	var near := INF
	for i in theirs.size():
		near = minf(near, Vector2(theirs[i].x - pos.x, theirs[i].z - pos.z).length())
	var to_goal := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	var final_third := to_goal <= PlayerAI.FINAL_THIRD
	var mods: AttributeModifiers = e["mods"]
	var funnel: Dictionary = m.advanced.stats["carrier"]
	funnel[cmd["action"]] = int(funnel.get(cmd["action"], 0)) + 1
	# A pressed carrier the base AI would make pass may take his man on instead (a skilled one more often, never
	# in his own half) - before this the carrier passed in nearly every situation where a skill move applies.
	if cmd["action"] == &"pass" and float(e.get("skill_cd", 0.0)) <= 0.0 \
			and AdvancedAI.take_on(near, mods, m.setup.difficulty, PitchSpace.progress_of(pos, frame), r.randf()):
		cmd["action"] = &""
		cmd["move"] = Vector3(goal.x - pos.x, 0.0, goal.z - pos.z).normalized()
		cmd["sprint"] = false
		cmd.erase("target_pos")
		e["take_on"] = true
		m.advanced.stats["take_on"] += 1
	match cmd["action"]:
		&"shoot":
			cmd["technique"] = AdvancedAI.technique_for(pos, goal, theirs[0] if not theirs.is_empty() else Vector3.INF, mods,
					near < 2.0, m.setup.difficulty, r.randf())
		&"":
			if float(e.get("shield_left", 0.0)) > 0.0 and near <= 1.8:
				cmd["shield"] = true
				e["intent"] = "SHIELD"
				return
			var near_line := absf(pos.x) > PitchSpace.HALF_WIDTH - 4.0
			var strength := mods.detail("strength") if mods != null else 0.5
			if AdvancedAI.should_shield(near, false, strength, near_line, final_third, r.randf()):
				cmd["shield"] = true
				e["shield_left"] = 1.2
				e["intent"] = "SHIELD"
				return
			if float(e.get("skill_cd", 0.0)) > 0.0:
				return
			var node := e["node"] as PlayerController
			var facing := Vector3(node.velocity.x, 0.0, node.velocity.z)
			if facing.length() <= 0.5:
				facing = -node.global_transform.basis.z
			facing.y = 0.0
			var choice := AdvancedAI.skill_choice({"pos": pos, "facing": facing.normalized(), "goal": goal,
					"opponents": theirs, "mods": mods, "difficulty": m.setup.difficulty, "speed": node.get_current_speed(),
					"rolls": [r.randf(), r.randf(), r.randf()], "dt": MatchManager.THINK_INTERVAL[clampi(m.setup.difficulty, 0, 2)],
					"in_box": to_goal < 18.0 and absf(pos.x - goal.x) < 20.0, "force": e.get("take_on", false)})
			e.erase("take_on")
			if not choice.is_empty():
				m.advanced.stats["skill_choice"] += 1
				cmd["skill"] = choice
				e["skill_cd"] = AdvancedAI.SKILL_COOLDOWN
				e["intent"] = "SKILL_MOVE"


## The (at most 2) AI outfield players of `side` nearest to where an airborne ball comes down to head height, within
## 12 m: {player_id: spot}. Empty when the ball is not in the air.
static func _aerial_players(m: MatchManager, side: String) -> Dictionary:
	var out := {}
	if m.advanced == null:
		return out
	var spot := AdvancedAI.aerial_spot(m.ball.global_position, m.ball.linear_velocity)
	if spot == Vector3.INF:
		return out
	var cands: Array = []
	for e in m.entries[side]:
		if int(e["slot"]) == 0 or e["ai"] == null:
			continue
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - spot.x, p.z - spot.z).length()
		if d <= 12.0:
			cands.append([d, e["player_id"]])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c in cands.slice(0, 2):
		out[c[1]] = spot
	return out


## An AI player going for an aerial ball: runs to the spot, and heads it (shot / pass / clearance) when the header
## window opens, pressing the same buttons a human would.
static func _aerial_step(m: MatchManager, e: Dictionary, ai: AIIntent, frame: String, mine: Array[Vector3]) -> void:
	var acts := e["actions"] as FootballActions
	if acts == null:
		return
	var node := e["node"] as Node3D
	var pos := node.global_position
	m.advanced.stats["aerial_ticks"] += 1
	var spot := AdvancedAI.aerial_spot(m.ball.global_position, m.ball.linear_velocity)
	if spot != Vector3.INF and not acts.header.has_request():
		var to := Vector3(spot.x - pos.x, 0.0, spot.z - pos.z)
		ai.set_move_world(to.normalized() * clampf(to.length() / 2.0, 0.0, 1.0) if to.length() > 0.25 else Vector3.ZERO)
		if to.length() > 4.0:
			ai.press(&"sprint")
		e["intent"] = "AERIAL"
	if not acts.header.window_open() or acts.header.has_request():
		return
	m.advanced.stats["aerial_windows"] += 1
	var goal := PitchSpace.opponent_goal(frame)
	var own := PitchSpace.own_goal(frame)
	var kind := AdvancedAI.header_kind(pos, goal, own)
	var target := Vector3.INF
	match kind:
		HeaderSystem.SHOT:
			var keeper := Vector3.INF
			var other := "away" if e["side"] == "home" else "home"
			if not m.entries[other].is_empty():
				keeper = (m.entries[other][0]["node"] as Node3D).global_position
			target = PlayerAI.shot_target(goal, keeper)
		HeaderSystem.PASS:
			var best_d := INF
			for t: Vector3 in mine:
				var d := Vector2(t.x - pos.x, t.z - pos.z).length()
				var gain := Vector2(goal.x - pos.x, goal.z - pos.z).length() - Vector2(goal.x - t.x, goal.z - t.z).length()
				if d > 4.0 and d < 22.0 and gain > -4.0 and d < best_d:
					best_d = d
					target = t
	acts.header.target = target
	var button: StringName = {HeaderSystem.SHOT: &"shoot", HeaderSystem.PASS: &"pass"}.get(kind, &"lob_pass")
	if target != Vector3.INF:
		ai.set_aim_world(Vector3(target.x - pos.x, 0.0, target.z - pos.z).normalized())
	ai.press(button)
	e["hdr_release"] = button
	m.advanced.stats["aerial_presses"] += 1
