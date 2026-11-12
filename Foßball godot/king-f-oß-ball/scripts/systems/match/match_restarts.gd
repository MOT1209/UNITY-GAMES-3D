class_name MatchRestarts
extends RefCounted

## Ball out of play (throw-in, corner, goal kick) and offside. Owned by `MatchRules`; uses its dead-ball restart.
## * Out of play: while the ball is in play and its centre is beyond a touchline or a goal line (outside the goal
##   mouth, which the goal trigger handles), the ball is dead. Side line -> throw-in for the side that did NOT touch
##   it last. Goal line -> corner if the defending side touched it last, otherwise a goal kick for the defenders.
##   Restarts put the ball on the spot and a team-mate next to it (the throw is taken as a restart from rest).
## * Offside: when a pass/lob starts, every team-mate in the opponent half who is ahead of the ball AND ahead of the
##   second-last opponent is offside-positioned. If the first team-mate to get the ball afterwards (within
##   WINDOW seconds, no opponent touch in between) was offside-positioned, the pass is offside: indirect free kick for
##   the opponents where he received it. Being level is onside; a player in his own half is never offside.
##   Not modelled: "interfering with play" without touching the ball, goal-kick / throw-in / corner exceptions
##   (they cannot produce an offside here because a restart clears the pending pass).

const OUT_MARGIN := 0.2
const WINDOW := 4.0
const GOAL_MOUTH := 4.5                    # |x| inside this beyond the goal line is the goal trigger's business

var rules: MatchRules
var _pending: Dictionary = {}              # {side, passer, offside: Array[String], t}
var _clock: float = 0.0


func _init(p_rules: MatchRules) -> void:
	rules = p_rules


func update(delta: float) -> void:
	var m := rules.m
	if m.state.phase != MatchState.Phase.PLAYING:
		_pending = {}
		return
	_clock += delta
	check_out_of_play()


## Returns the kind of restart started ("" = ball in play).
func check_out_of_play() -> String:
	var m := rules.m
	var b := m.ball.global_position
	var last_side := _side_of(m.last_toucher_id)
	if absf(b.x) > PitchSpace.HALF_WIDTH + OUT_MARGIN:
		var taker_side := _other(last_side) if last_side != "" else "home"
		var spot := Vector3(clampf(b.x, -PitchSpace.HALF_WIDTH + 0.5, PitchSpace.HALF_WIDTH - 0.5), 0.3, clampf(b.z, -PitchSpace.HALF_LENGTH + 2.0, PitchSpace.HALF_LENGTH - 2.0))
		spot.x = signf(b.x) * (PitchSpace.HALF_WIDTH - 0.5)
		return _start("throw_ins", taker_side, spot, "throw_in", "HUD_THROW_IN")
	if absf(b.z) > PitchSpace.HALF_LENGTH + OUT_MARGIN and absf(b.x) > GOAL_MOUTH:
		var defender := _side_defending(signf(b.z))
		if last_side == defender:
			var corner := Vector3(signf(b.x) * (PitchSpace.HALF_WIDTH - 0.5), 0.3, signf(b.z) * (PitchSpace.HALF_LENGTH - 0.5))
			return _start("corners", _other(defender), corner, "corner", "HUD_CORNER")
		var spot2 := Vector3(0.0, 0.3, signf(b.z) * (PitchSpace.HALF_LENGTH - FootballPitch.GOAL_AREA_DEPTH))
		return _start("goal_kicks", defender, spot2, "goal_kick", "HUD_GOAL_KICK")
	return ""


func _start(stat: String, side: String, spot: Vector3, kind: String, notice_key: String) -> String:
	var m := rules.m
	if not m.state.record_restart(stat, side):
		return ""
	_pending = {}
	rules.say(notice_key)
	rules.restart_from(spot, side, kind)
	return kind


func _side_of(player_id: String) -> String:
	return str(rules.m.state.stats.players.get(player_id, {}).get("side", ""))


static func _other(side: String) -> String:
	return "away" if side == "home" else "home"


## The side whose own goal is at the end of the pitch with the sign `z_sign` (current half).
func _side_defending(z_sign: float) -> String:
	for side in ["home", "away"]:
		if signf(PitchSpace.own_goal(rules.m.frame_side(side)).z) == z_sign:
			return side
	return "home"


## Depth of `z` towards the goal that `side` attacks (bigger = closer to the opponent's goal line).
func _depth(z: float, side: String) -> float:
	return z * -PitchSpace.side_sign(rules.m.frame_side(side))


## Ids of the outfield players of `side` that are in an offside position for a pass played from `ball_z`.
func offside_positioned(side: String, ball_z: float) -> Array:
	var m := rules.m
	var opponents: Array[float] = []
	for e in m.entries[_other(side)]:
		opponents.append(_depth((e["node"] as Node3D).global_position.z, side))
	opponents.sort()
	opponents.reverse()                                 # deepest first: [keeper-ish, last defender, ...]
	if opponents.size() < 2:
		return []
	var line: float = maxf(opponents[1], _depth(ball_z, side))     # second-last opponent or the ball
	var out: Array = []
	for e in m.entries[side]:
		if int(e["slot"]) == 0 or rules.sent_off.has(e["player_id"]):
			continue
		var d := _depth((e["node"] as Node3D).global_position.z, side)
		if d > 0.0 and d > line + 0.05:
			out.append(e["player_id"])
	return out


## A pass/lob was just played by `player_id` of `side`.
func on_pass(side: String, player_id: String) -> void:
	var m := rules.m
	if m.state.phase != MatchState.Phase.PLAYING:
		return
	_pending = {"side": side, "passer": player_id, "offside": offside_positioned(side, m.ball.global_position.z), "t": _clock}


## The ball now belongs to `entry` (called on every change of owner).
func on_owner(entry: Dictionary) -> String:
	if _pending.is_empty():
		return ""
	var pending := _pending
	_pending = {}
	if entry["side"] != pending["side"] or entry["player_id"] == pending["passer"] or _clock - float(pending["t"]) > WINDOW:
		return ""
	if not (entry["player_id"] in pending["offside"]):
		return ""
	var m := rules.m
	if not m.state.record_restart("offside", pending["side"], entry["player_id"]):
		return ""
	var spot := (entry["node"] as Node3D).global_position
	spot.y = 0.3
	rules.say("HUD_OFFSIDE")
	rules.restart_from(spot, _other(pending["side"]), "offside")
	return "offside"
