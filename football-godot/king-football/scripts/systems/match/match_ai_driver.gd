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
	for side in ["home", "away"]:
		var other := "away" if side == "home" else "home"
		var data: Dictionary = m.sides[side]
		var tactics: TacticsPreset = data["tactics"]
		var mine := m._positions(side)
		var theirs := m._positions(other)
		var has_ball_team: bool = owner_side == side
		var frame := m.frame_side(side)
		var targets := TeamAI.formation_targets(frame, data["formation"], tactics, m.ball.global_position, has_ball_team)
		var chasers: Array[int] = TeamAI.pressers(mine, m.ball.global_position, frame, tactics,
				AIDifficulty.press_distance_bonus(m.setup.difficulty))
		for e in m.entries[side]:
			var ai: AIIntent = e["ai"]
			if ai == null:
				continue                         # human controlled
			ai.begin_tick()
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
					"opp_keeper": theirs[0] if not theirs.is_empty() else Vector3.INF})
			_apply_cmd(m, e, ai)


static func _apply_cmd(m: MatchManager, e: Dictionary, ai: AIIntent) -> void:
	var cmd: Dictionary = e["cmd"]
	if cmd.is_empty():
		return
	var planting: bool = e["charging"] != &""        # while a kick charges the player stands still; the aim set on the press frame stays
	ai.set_move_world(Vector3.ZERO if planting else cmd["move"])
	if cmd["sprint"] and not planting:
		ai.press(&"sprint")
	else:
		ai.release(&"sprint")
	var action: StringName = cmd["action"]
	if e["charging"] != &"":
		if m._clock >= e["release_at"]:
			ai.release(e["charging"])
			e["charging"] = &""
			e["cmd"] = {}
	elif action != &"" and _can_start_kick(e, action):
		ai.release(&"dribble")
		ai.set_move_world(_kick_aim(e, action, cmd["move"]))       # the aim is read from this move on the press frame
		ai.press(action)
		e["charging"] = action
		e["release_at"] = m._clock + _charge_for(e, action, float(cmd.get("kick_dist", -1.0)))
	else:
		var carrying: bool = cmd["move"] != Vector3.ZERO and m._owner_entry().get("player_id", "") == e["player_id"]
		if carrying:
			ai.press(&"dribble")
		else:
			ai.release(&"dribble")


## The AI only starts a kick when the ball is really within reach (`FootballActions` ignores the press otherwise, and the
## charge would be wasted while the player runs on).
static func _can_start_kick(e: Dictionary, action: StringName) -> bool:
	var acts := e["actions"] as FootballActions
	var key: StringName = &"lob" if action == &"lob_pass" else action      # the availability map names the lob "lob"
	return acts == null or bool(acts.get_action_availability().get(key, false))


## Aim that cancels the kick systems' bend towards the ball's side (see `PlayerAI.compensated_aim`), so the ball goes where the AI wants.
static func _kick_aim(e: Dictionary, action: StringName, wanted: Vector3) -> Vector3:
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


## How long the AI holds a kick button: passes (up to 60 % charge) and lobs are charged for the distance to the target (a
## long ball needs more power); shots use the short fixed charge. Without a distance the fixed CHARGE_TIME is used.
static func _charge_for(e: Dictionary, action: StringName, dist: float) -> float:
	var acts := e["actions"] as FootballActions
	if acts == null or acts.config == null or dist < 0.0:
		return float(MatchManager.CHARGE_TIME.get(action, 0.2))
	var cfg := acts.config
	var ratio := 0.0
	match action:
		&"pass":
			ratio = minf(inverse_lerp(cfg.min_pass_power, cfg.max_pass_power, clampf(4.0 + dist * 0.35, cfg.min_pass_power, cfg.max_pass_power)), 0.6)
		&"lob_pass":
			ratio = inverse_lerp(cfg.min_lob_power, cfg.max_lob_power, clampf(3.0 + dist * 0.32, cfg.min_lob_power, cfg.max_lob_power))
		_:                                # shots keep the short fixed charge: a long wind-up gets blocked (measured)
			return float(MatchManager.CHARGE_TIME.get(action, 0.2))
	return cfg.quick_tap_threshold + 0.02 + ratio * cfg.charge_time
