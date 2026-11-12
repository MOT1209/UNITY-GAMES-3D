class_name MatchRules
extends RefCounted

## Tackles, fouls, free kicks, penalties and cards (Phase 2 gameplay). Owned by `MatchManager`.
## Everything here changes real match state: a tackle either wins the ball, misses, or is a foul.
## A foul is recorded through `MatchState.record_foul` (events + statistics), the ball is dead, and play
## restarts from the spot (free kick) or the penalty spot when the foul is inside the fouled side's
## attacking penalty area. Cards: yellow for a foul from behind or a third foul by the same player,
## a second yellow is a red card; a sent-off player leaves the pitch for good.
## The outcome of a tackle is ONE roll `0..1` compared with probabilities that depend on the tackler's
## `defending` and the ball carrier's `dribbling` attributes, so tests can force every outcome.

const TACKLE_RANGE := 2.0
const COOLDOWN := 1.2
const WALL_DISTANCE := 9.15
const NOTICE_TIME := 2.5
## Attempts per second of an AI defender that is within range of the ball carrier, by difficulty.
const AI_RATE: Array[float] = [0.4, 0.8, 1.3]

var m: MatchManager
var cooldown: Dictionary = {}              # player_id -> seconds
var sent_off: Dictionary = {}              # player_id -> true
var notice: String = ""
var notice_left: float = 0.0
var last_outcome: String = ""              # "won" / "missed" / "foul" (for tests and the HUD)


func _init(manager: MatchManager) -> void:
	m = manager


## Called every physics tick while the ball is in play.
func update(delta: float) -> void:
	notice_left = maxf(notice_left - delta, 0.0)
	for k in cooldown.keys():
		cooldown[k] = maxf(float(cooldown[k]) - delta, 0.0)
	var carrier := m._owner_entry()
	if carrier.is_empty() or int(carrier["slot"]) == 0 or m.state.phase != MatchState.Phase.PLAYING:
		return
	var enemy := "away" if carrier["side"] == "home" else "home"
	for e in m.entries[enemy]:
		if int(e["slot"]) == 0 or sent_off.has(e["player_id"]) or float(cooldown.get(e["player_id"], 0.0)) > 0.0:
			continue
		if _flat_distance(e, carrier) > TACKLE_RANGE:
			continue
		var wants := false
		if e["ai"] == null:
			wants = Input.is_action_just_pressed("tackle")
		else:
			wants = m._rng.randf() < AI_RATE[clampi(m.setup.difficulty, 0, 2)] * delta
		if wants:
			resolve(e, carrier, m._rng.randf())
			return


static func _flat_distance(a: Dictionary, b: Dictionary) -> float:
	var pa := (a["node"] as Node3D).global_position
	var pb := (b["node"] as Node3D).global_position
	return Vector2(pa.x - pb.x, pa.z - pb.z).length()


## True when the tackler comes from behind the ball carrier (the carrier faces away from him).
func from_behind(tackler: Dictionary, victim: Dictionary) -> bool:
	var vn := victim["node"] as Node3D
	var tn := tackler["node"] as Node3D
	var forward := -vn.global_transform.basis.z
	forward.y = 0.0
	var to_tackler := tn.global_position - vn.global_position
	to_tackler.y = 0.0
	if forward.length_squared() < 0.0001 or to_tackler.length_squared() < 0.0001:
		return false
	return forward.normalized().dot(to_tackler.normalized()) < -0.35


func win_probability(tackler: Dictionary, victim: Dictionary) -> float:
	var d: float = float((tackler["pdata"] as PlayerData).defending)
	var dr: float = float((victim["pdata"] as PlayerData).dribbling)
	return clampf(0.45 + (d - dr) / 200.0, 0.15, 0.8)


## Resolves one tackle with `roll` in 0..1. Returns "won", "missed" or "foul".
func resolve(tackler: Dictionary, victim: Dictionary, roll: float) -> String:
	cooldown[tackler["player_id"]] = COOLDOWN
	var behind := from_behind(tackler, victim)
	var p_win := win_probability(tackler, victim) * (0.5 if behind else 1.0)
	var foul_share := 0.6 if behind else 0.3
	var outcome := "missed"
	if roll < p_win:
		outcome = "won"
	elif roll < p_win + (1.0 - p_win) * foul_share:
		outcome = "foul"
	last_outcome = outcome
	match outcome:
		"won":
			var dir := (tackler["node"] as Node3D).global_position - (victim["node"] as Node3D).global_position
			dir.y = 0.0
			m.ball.apply_kick(dir, 4.0)
		"foul":
			_foul(tackler, victim, behind)
	return outcome


func _foul(tackler: Dictionary, victim: Dictionary, behind: bool) -> void:
	var side: String = tackler["side"]
	var pid: String = tackler["player_id"]
	var prior: int = int(m.state.stats.players.get(pid, {}).get("fouls", 0))
	var card := "yellow" if (behind or prior >= 2) else ""
	var spot := (victim["node"] as Node3D).global_position
	spot.y = 0.3
	var shown := m.state.record_foul(side, pid, victim["player_id"], card)
	if shown == "" and m.state.stats.players[pid]["fouls"] != prior + 1:
		return                                   # the ball was not in play: nothing recorded, nothing to restart
	var kicker_side: String = victim["side"]
	var penalty := _is_penalty(spot, kicker_side)
	if penalty:
		var goal_z := PitchSpace.opponent_goal(m.frame_side(kicker_side)).z
		spot = Vector3(0.0, 0.3, goal_z - signf(goal_z) * FootballPitch.PENALTY_SPOT_DISTANCE)
	_say("HUD_PENALTY" if penalty else "HUD_FOUL")
	if shown == "yellow":
		_say("HUD_YELLOW_CARD")
	if shown == "red":
		_say("HUD_RED_CARD")
		send_off(tackler)
	_restart_from(spot, kicker_side, penalty, victim)


## Foul inside the attacking penalty area of the fouled side.
func _is_penalty(spot: Vector3, kicker_side: String) -> bool:
	var goal_z := PitchSpace.opponent_goal(m.frame_side(kicker_side)).z
	return absf(spot.z - goal_z) <= FootballPitch.PENALTY_AREA_DEPTH and absf(spot.x) <= FootballPitch.PENALTY_AREA_WIDTH * 0.5


## Dead ball: puts the ball on the spot, clears the defenders away from it and lets play resume shortly.
func _restart_from(spot: Vector3, kicker_side: String, penalty: bool, victim: Dictionary) -> void:
	m.state.phase = MatchState.Phase.KICKOFF
	m._needs_reset = false
	m._pause_left = 1.5
	m.ball.reset_ball(spot)
	var defender_side := "away" if kicker_side == "home" else "home"
	var goal_z := PitchSpace.opponent_goal(m.frame_side(kicker_side)).z
	for e in m.entries[defender_side]:
		if int(e["slot"]) == 0 or sent_off.has(e["player_id"]):
			continue
		var node := e["node"] as CharacterBody3D
		var p := node.global_position
		var away := Vector3(p.x - spot.x, 0.0, p.z - spot.z)
		var inside_box := penalty and absf(p.z - goal_z) <= FootballPitch.PENALTY_AREA_DEPTH + 1.0
		if away.length() < WALL_DISTANCE or inside_box:
			var dir := away.normalized() if away.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
			if penalty:
				dir = Vector3(signf(p.x - spot.x) if p.x != spot.x else 1.0, 0.0, -signf(goal_z)).normalized()
			var target := Vector3(spot.x, 0.05, spot.z) + dir * (WALL_DISTANCE if not penalty else 20.0)
			target.x = clampf(target.x, -PitchSpace.HALF_WIDTH + 1.0, PitchSpace.HALF_WIDTH - 1.0)
			target.z = clampf(target.z, -PitchSpace.HALF_LENGTH + 1.0, PitchSpace.HALF_LENGTH - 1.0)
			node.global_position = target
			node.velocity = Vector3.ZERO
	# the fouled player takes it
	var vn := victim["node"] as CharacterBody3D
	vn.global_position = Vector3(spot.x, 0.05, spot.z) + Vector3(0.0, 0.0, 1.0)
	vn.velocity = Vector3.ZERO
	for s in m.entries:
		for e in m.entries[s]:
			if e["ai"] != null:
				(e["ai"] as AIIntent).release_all()


## A sent-off player leaves the pitch for good (no collisions, no processing, never selected again).
func send_off(entry: Dictionary) -> void:
	sent_off[entry["player_id"]] = true
	entry["sent_off"] = true
	var node := entry["node"] as CharacterBody3D
	node.collision_layer = 0
	node.collision_mask = 0
	node.global_position = Vector3(0.0, 0.05, 90.0)
	node.velocity = Vector3.ZERO
	node.visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if not m.selected.is_empty() and m.selected["player_id"] == entry["player_id"]:
		m.switch_player()


## Re-applies red cards after a match was restored from a save.
func reapply_sent_off() -> void:
	for side in m.entries:
		for e in m.entries[side]:
			if int(m.state.stats.players.get(e["player_id"], {}).get("red", 0)) > 0 and not sent_off.has(e["player_id"]):
				send_off(e)


func _say(key: String) -> void:
	notice = Loc.t(key) if notice == "" or notice_left <= 0.0 else notice + " · " + Loc.t(key)
	notice_left = NOTICE_TIME
