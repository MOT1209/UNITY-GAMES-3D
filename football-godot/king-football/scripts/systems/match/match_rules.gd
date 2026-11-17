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
## Free kicks closer than this to the goal get a defensive wall (UX phase 6).
const WALL_MAX_GOAL_DISTANCE := 32.0
const WALL_SPACING := 0.75
const NOTICE_TIME := 2.5
## Attempts per second of an AI defender that is within range of the ball carrier, by difficulty.
const AI_RATE: Array[float] = [0.12, 0.2, 0.3]
## Team-wide pause (seconds) after any tackle attempt of that side, so a defence does not tackle constantly.
const TEAM_COOLDOWN := 3.0
const FOUL_SHARE_FRONT := 0.12              # of the failed tackles: a foul from the front / from behind
const FOUL_SHARE_BEHIND := 0.30
const YELLOW_SEVERITY := 0.5                # from behind AND a severity above this = yellow card
const YELLOW_AFTER_FOULS := 3               # a player who has already fouled this often gets a card
## Advantage rule: after a foul the referee lets play go on when the fouled player still has the ball in the attacking
## part of the pitch. If the fouling side wins the ball within ADVANTAGE_SECONDS the foul is given after all (free kick at
## the original spot); otherwise play simply continues. No advantage for cards or fouls inside the penalty area.
const ADVANTAGE_SECONDS := 4.0
const ADVANTAGE_MIN_PROGRESS := 0.62        # fouled side's pitch progress (0 own goal .. 1 opponent goal) of the ball

var m: MatchManager
var cooldown: Dictionary = {}              # player_id -> seconds
var team_cooldown: Dictionary = {"home": 0.0, "away": 0.0}
var sent_off: Dictionary = {}              # player_id -> true
var notice: String = ""
var notice_left: float = 0.0
var restarts: MatchRestarts
var last_outcome: String = ""              # "won" / "missed" / "foul" (for tests and the HUD)
var last_wall: Array = []                  # player ids placed in the wall at the last free kick
var last_throw_animated := false            # the last throw-in taker played the throw-in clip
var advantage_enabled := true
## Running advantage ({} = none): kicker_side, victim (entry), fouler_id, spot, left (seconds).
var advantage: Dictionary = {}
var last_advantage_outcome: String = ""     # "played_on" / "foul_called" (tests, HUD)


## Breaks the rules <-> restarts reference cycle (two RefCounted objects pointing at each other are
## never freed: "ObjectDB instances were leaked at exit"). Called when the match is deleted.
func release() -> void:
	if restarts != null:
		restarts.rules = null
	restarts = null
	m = null


func _init(manager: MatchManager) -> void:
	m = manager
	restarts = MatchRestarts.new(self)


## Called every physics tick while the ball is in play.
func update(delta: float) -> void:
	notice_left = maxf(notice_left - delta, 0.0)
	restarts.update(delta)
	if not advantage.is_empty():
		_update_advantage(delta)
	for k in cooldown.keys():
		cooldown[k] = maxf(float(cooldown[k]) - delta, 0.0)
	for k in team_cooldown.keys():
		team_cooldown[k] = maxf(float(team_cooldown[k]) - delta, 0.0)
	var carrier := m._owner_entry()
	if carrier.is_empty() or int(carrier["slot"]) == 0 or m.state.phase != MatchState.Phase.PLAYING:
		return
	var enemy := "away" if carrier["side"] == "home" else "home"
	for e in m.entries[enemy]:
		if int(e["slot"]) == 0 or sent_off.has(e["player_id"]) or float(cooldown.get(e["player_id"], 0.0)) > 0.0 or float(team_cooldown[e["side"]]) > 0.0:
			continue
		if _flat_distance(e, carrier) > TACKLE_RANGE:
			continue
		var wants := false
		if e["ai"] == null:
			# Human tackler: read the shared intent channel (raw mode reads the
			# global Input exactly as before; driven mode serves touch/remote).
			wants = (e["node"].intent as IntentProvider).just_pressed(&"tackle")
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


## A roll that falls inside the foul zone of this tackle at `severity` 0..1 (tests and tools; 0.9 from behind is a card).
func foul_roll(tackler: Dictionary, victim: Dictionary, severity: float) -> float:
	var behind := from_behind(tackler, victim)
	var p_win := win_probability(tackler, victim) * (0.5 if behind else 1.0)
	var share := FOUL_SHARE_BEHIND if behind else FOUL_SHARE_FRONT
	return p_win + (1.0 - p_win) * share * clampf(severity, 0.0, 0.999)


func win_probability(tackler: Dictionary, victim: Dictionary) -> float:
	var d: float = float((tackler["pdata"] as PlayerData).defending)
	var dr: float = float((victim["pdata"] as PlayerData).dribbling)
	return clampf(0.45 + (d - dr) / 120.0, 0.15, 0.8)      # Phase M5: /200 -> /120, the better defender wins more duels


## Resolves one tackle with `roll` in 0..1. Returns "won", "missed" or "foul".
func resolve(tackler: Dictionary, victim: Dictionary, roll: float) -> String:
	cooldown[tackler["player_id"]] = COOLDOWN
	var behind := from_behind(tackler, victim)
	var p_win := win_probability(tackler, victim) * (0.5 if behind else 1.0)
	var foul_share := FOUL_SHARE_BEHIND if behind else FOUL_SHARE_FRONT
	var outcome := "missed"
	var severity := 0.0
	if roll < p_win:
		outcome = "won"
	elif roll < p_win + (1.0 - p_win) * foul_share:
		outcome = "foul"
		severity = (roll - p_win) / maxf((1.0 - p_win) * foul_share, 0.0001)      # 0..1 inside the foul zone
	last_outcome = outcome
	team_cooldown[tackler["side"]] = TEAM_COOLDOWN
	match outcome:
		"won":
			var dir := (tackler["node"] as Node3D).global_position - (victim["node"] as Node3D).global_position
			dir.y = 0.0
			m.ball.apply_kick(dir, 4.0)
		"foul":
			_foul(tackler, victim, behind, severity)
	return outcome


func _foul(tackler: Dictionary, victim: Dictionary, behind: bool, severity: float) -> void:
	var side: String = tackler["side"]
	var pid: String = tackler["player_id"]
	var prior: int = int(m.state.stats.players.get(pid, {}).get("fouls", 0))
	var card := "yellow" if ((behind and severity >= YELLOW_SEVERITY) or prior >= YELLOW_AFTER_FOULS) else ""
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
	if not penalty and shown == "" and advantage_enabled and _advantage_applies(victim, kicker_side):
		_start_advantage(victim, kicker_side, pid, spot)
		return
	say("HUD_PENALTY" if penalty else "HUD_FOUL")
	if shown == "yellow":
		say("HUD_YELLOW_CARD")
	if shown == "red":
		say("HUD_RED_CARD")
		send_off(tackler)
	restart_from(spot, kicker_side, "penalty" if penalty else "free_kick", victim)


## True when the fouled player still has the ball and it is in the attacking part of the pitch (a clear benefit).
func _advantage_applies(victim: Dictionary, kicker_side: String) -> bool:
	var owner := m._owner_entry()
	if owner.is_empty() or owner["player_id"] != victim["player_id"]:
		return false
	var progress := PitchSpace.progress_of(m.ball.global_position, m.frame_side(kicker_side))
	return progress >= ADVANTAGE_MIN_PROGRESS


func _start_advantage(victim: Dictionary, kicker_side: String, fouler_id: String, spot: Vector3) -> void:
	advantage = {"kicker_side": kicker_side, "victim": victim, "fouler_id": fouler_id, "spot": spot, "left": ADVANTAGE_SECONDS}
	m.state.log_event({"minute": m.state.display_minute(), "type": "advantage", "side": kicker_side, "player_id": victim["player_id"],
			"fouler_id": fouler_id})
	say("HUD_ADVANTAGE")


func _update_advantage(delta: float) -> void:
	advantage["left"] = float(advantage["left"]) - delta
	var owner := m._owner_entry()
	if not owner.is_empty() and owner["side"] != advantage["kicker_side"]:
		# the fouling side won the ball: no benefit came out of it, the foul is given
		var a := advantage
		advantage = {}
		last_advantage_outcome = "foul_called"
		m.state.log_event({"minute": m.state.display_minute(), "type": "advantage_end", "side": a["kicker_side"],
				"player_id": a["victim"]["player_id"], "outcome": "foul_called"})
		say("HUD_FOUL")
		restart_from(a["spot"], a["kicker_side"], "free_kick", a["victim"])
	elif float(advantage["left"]) <= 0.0:
		end_advantage("played_on")


## Ends a running advantage without calling the foul (time ran out, or the ball went dead: goal, throw-in, corner ...).
func end_advantage(outcome: String = "played_on") -> void:
	if advantage.is_empty():
		return
	var a := advantage
	advantage = {}
	last_advantage_outcome = outcome
	m.state.log_event({"minute": m.state.display_minute(), "type": "advantage_end", "side": a["kicker_side"],
			"player_id": a["victim"]["player_id"], "outcome": outcome})


## Foul inside the attacking penalty area of the fouled side.
func _is_penalty(spot: Vector3, kicker_side: String) -> bool:
	var goal_z := PitchSpace.opponent_goal(m.frame_side(kicker_side)).z
	return absf(spot.z - goal_z) <= FootballPitch.PENALTY_AREA_DEPTH and absf(spot.x) <= FootballPitch.PENALTY_AREA_WIDTH * 0.5


## Dead ball: puts the ball on the spot, clears the opponents away from it and lets play resume shortly.
## `kind`: "free_kick", "penalty", "throw_in", "corner", "goal_kick", "offside" (indirect free kick).
## `taker` is the player who takes it (he is placed next to the ball); null = the nearest outfield team-mate.
func restart_from(spot: Vector3, kicker_side: String, kind: String, taker: Dictionary = {}) -> void:
	m.state.phase = MatchState.Phase.KICKOFF
	m._needs_reset = false
	m._pause_left = 1.5
	m.ball.reset_ball(spot)
	var defender_side := "away" if kicker_side == "home" else "home"
	var goal_z := PitchSpace.opponent_goal(m.frame_side(kicker_side)).z
	var penalty := kind == "penalty"
	var clearance := {"free_kick": WALL_DISTANCE, "offside": WALL_DISTANCE, "corner": WALL_DISTANCE, "throw_ins": 2.0,
			"throw_in": 2.0, "goal_kick": 20.0, "penalty": 20.0}.get(kind, WALL_DISTANCE) as float
	for e in m.entries[defender_side]:
		if int(e["slot"]) == 0 or sent_off.has(e["player_id"]):
			continue
		var node := e["node"] as CharacterBody3D
		var p := node.global_position
		var away := Vector3(p.x - spot.x, 0.0, p.z - spot.z)
		var inside_box := penalty and absf(p.z - goal_z) <= FootballPitch.PENALTY_AREA_DEPTH + 1.0
		if away.length() < clearance or inside_box:
			var dir := away.normalized() if away.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
			if penalty:
				dir = Vector3(signf(p.x - spot.x) if p.x != spot.x else 1.0, 0.0, -signf(goal_z)).normalized()
			var target := Vector3(spot.x, 0.05, spot.z) + dir * clearance
			target.x = clampf(target.x, -PitchSpace.HALF_WIDTH + 1.0, PitchSpace.HALF_WIDTH - 1.0)
			target.z = clampf(target.z, -PitchSpace.HALF_LENGTH + 1.0, PitchSpace.HALF_LENGTH - 1.0)
			node.global_position = target
			node.velocity = Vector3.ZERO
	last_wall = []
	last_throw_animated = false
	if kind == "free_kick":
		_build_wall(spot, defender_side, Vector3(0.0, 0.0, goal_z))
	if taker.is_empty():
		taker = _nearest_outfield(kicker_side, spot)
	if not taker.is_empty():
		var vn := taker["node"] as CharacterBody3D
		var off := Vector3(0.0, 0.0, 1.0) if absf(spot.x) < 33.0 else Vector3(-signf(spot.x), 0.0, 0.0)
		vn.global_position = Vector3(spot.x, 0.05, spot.z) + off
		vn.velocity = Vector3.ZERO
		if kind == "throw_in":
			# The taker stands on the line facing the pitch and throws with both hands over the head.
			vn.look_at(Vector3(0.0, vn.global_position.y, spot.z), Vector3.UP)
			var vis := vn.get_node_or_null("VisualRoot")
			if vis != null and vis.has_method("play_reaction"):
				last_throw_animated = bool(vis.play_reaction("ThrowIn"))
	for s in m.entries:
		for e in m.entries[s]:
			if e["ai"] != null:
				(e["ai"] as AIIntent).release_all()


## Direct free kick within shooting range: 3 (4 when closer than 25 m) defenders line up 9.15 m from the
## ball on the line to the goal centre, shoulder to shoulder, facing the ball.
func _build_wall(spot: Vector3, defender_side: String, goal_center: Vector3) -> void:
	var to_goal := Vector3(goal_center.x - spot.x, 0.0, goal_center.z - spot.z)
	var dist := to_goal.length()
	if dist > WALL_MAX_GOAL_DISTANCE or dist < WALL_DISTANCE + 1.0:
		return
	var dir := to_goal / dist
	var side_dir := Vector3(-dir.z, 0.0, dir.x)
	var count := 4 if dist < 25.0 else 3
	var candidates: Array = []
	for e in m.entries[defender_side]:
		if int(e["slot"]) != 0 and not sent_off.has(e["player_id"]):
			candidates.append(e)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["node"] as Node3D).global_position.distance_to(spot) < (b["node"] as Node3D).global_position.distance_to(spot))
	var center := Vector3(spot.x, 0.05, spot.z) + dir * WALL_DISTANCE
	for i in mini(count, candidates.size()):
		var e: Dictionary = candidates[i]
		var node := e["node"] as CharacterBody3D
		var offset := (float(i) - float(count - 1) * 0.5) * WALL_SPACING
		node.global_position = center + side_dir * offset
		node.velocity = Vector3.ZERO
		node.look_at(Vector3(spot.x, node.global_position.y, spot.z), Vector3.UP)
		last_wall.append(e["player_id"])


func _nearest_outfield(side: String, spot: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for e in m.entries[side]:
		if int(e["slot"]) == 0 or sent_off.has(e["player_id"]):
			continue
		var d := (e["node"] as Node3D).global_position.distance_to(spot)
		if d < best_d:
			best_d = d
			best = e
	return best


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
	if not m.selected2.is_empty() and m.selected2["player_id"] == entry["player_id"]:
		m.switch_player2()


## Re-applies red cards after a match was restored from a save.
func reapply_sent_off() -> void:
	for side in m.entries:
		for e in m.entries[side]:
			if int(m.state.stats.players.get(e["player_id"], {}).get("red", 0)) > 0 and not sent_off.has(e["player_id"]):
				send_off(e)


func say(key: String) -> void:
	notice = Loc.t(key) if notice == "" or notice_left <= 0.0 else notice + " · " + Loc.t(key)
	notice_left = NOTICE_TIME
