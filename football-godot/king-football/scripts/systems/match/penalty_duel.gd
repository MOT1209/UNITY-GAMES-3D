class_name PenaltyDuel
extends Node

## Penalty shoot-out played on the pitch (UX phase 6). Used when a knockout match ends level and a
## human plays: five kicks each, alternating (home first), early end when one side can no longer catch
## up, then sudden death. Every kick is a real kick through `FootballActions`: the human takes his team's
## kicks with his normal shoot button (aim with the stick), AI kickers aim at a corner with an error that
## shrinks with their shooting attribute; the real `TeamGoalkeeper` logic tries to save. A goal is detected
## by the arena's goal trigger (the manager forwards it), a miss when the ball stops, leaves the box or
## after a time-out. The tally becomes the match result's penalty score.

signal finished(home_pens: int, away_pens: int)

const PREP_TIME := 1.0            # ball on the spot, players set
const AI_RUN_UP := 0.6            # AI kicker waits this long before striking
const HUMAN_TIME_LIMIT := 10.0    # the human must shoot within this time, else the AI strikes for him
const FLIGHT_TIMEOUT := 3.5
const RESULT_PAUSE := 1.2
const REGULAR_KICKS := 5
## A penalty is struck, not tapped: the AI holds shoot this long (more power, a little more lift).
const PENALTY_CHARGE := 0.32
## Where AI kickers aim along the goal line (m from the centre): corners, half-corners, the middle.
const TARGETS: Array[float] = [-3.0, -2.2, 0.0, 2.2, 3.0]

enum Step { PREP, KICK, FLIGHT, RESULT, DONE }

var m: MatchManager
var goal_z := 0.0                 # the goal every kick goes at
var score := {"home": 0, "away": 0}
var taken := {"home": 0, "away": 0}
var kicks: Array = []             # [{side, player_id, scored}]
var step: Step = Step.PREP
var kicker_side := "home"
var _order := {"home": [], "away": []}
var _kicker: Dictionary = {}
var _t := 0.0
var _released := false
var _press_t := 0.0
var _rng := RandomNumberGenerator.new()
var _scored_this_kick := false


func _init(manager: MatchManager) -> void:
	name = "PenaltyDuel"
	m = manager
	_rng.seed = manager.setup.rng_seed + 77


## Places everyone and starts the first kick.
func begin() -> void:
	goal_z = PitchSpace.HALF_LENGTH * (1.0 if m.ball.global_position.z >= 0.0 else -1.0)
	for side in ["home", "away"]:
		var list: Array = []
		for e in m.entries[side]:
			if int(e["slot"]) != 0 and not e.get("sent_off", false):
				list.append(e)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["pdata"] as PlayerData).shooting > (b["pdata"] as PlayerData).shooting)
		_order[side] = list
		var i := 0
		for e in m.entries[side]:
			if e["ai"] != null:
				(e["ai"] as AIIntent).release_all()
			if int(e["slot"]) == 0:
				continue
			var node := e["node"] as CharacterBody3D
			var lane := -1.0 if side == "home" else 1.0
			node.global_position = Vector3(lane * (1.0 + float(i % 5) * 1.3), 0.05, float(i / 5) * 1.5 - 0.75)
			node.velocity = Vector3.ZERO
			i += 1
	_next_kick()


func spot() -> Vector3:
	return Vector3(0.0, 0.3, goal_z - signf(goal_z) * FootballPitch.PENALTY_SPOT_DISTANCE)


func defending_side() -> String:
	return "away" if kicker_side == "home" else "home"


func human_kicks() -> bool:
	return m.setup.human_side == kicker_side


func active() -> bool:
	return step != Step.DONE


## Called by the manager when the ball enters a goal during the shoot-out.
func on_goal() -> void:
	if step == Step.FLIGHT or step == Step.KICK:
		_scored_this_kick = true
		_finish_kick()


func _next_kick() -> void:
	var list: Array = _order[kicker_side]
	_kicker = list[taken[kicker_side] % maxi(list.size(), 1)] if not list.is_empty() else {}
	_scored_this_kick = false
	_released = false
	_t = 0.0
	step = Step.PREP
	m.ball.reset_ball(spot())
	var keeper: Dictionary = m.entries[defending_side()][0]
	var gk := keeper["node"] as TeamGoalkeeper
	gk.reset_to(Vector3(0.0, 0.05, goal_z - signf(goal_z) * gk.guard_depth), -signf(goal_z))
	gk.penalty_mode = true
	gk.penalty_guess = keeper_guess((keeper["pdata"] as PlayerData).goalkeeping)
	# The kicking team's keeper waits in the other goal (two keepers in one goal looked absurd).
	var other := m.entries[kicker_side][0]["node"] as TeamGoalkeeper
	other.penalty_mode = false
	other.reset_to(Vector3(0.0, 0.05, -goal_z + signf(goal_z) * other.guard_depth), signf(goal_z))
	if not _kicker.is_empty():
		var node := _kicker["node"] as CharacterBody3D
		node.global_position = spot() - Vector3(0.0, 0.25, 0.0) - Vector3(0.0, 0.0, signf(goal_z) * 0.45)
		node.velocity = Vector3.ZERO
		node.look_at(Vector3(0.0, node.global_position.y, goal_z), Vector3.UP)
		if human_kicks():
			m._select(_kicker)


func _physics_process(delta: float) -> void:
	if step == Step.DONE:
		return
	_t += delta
	match step:
		Step.PREP:
			if _t >= PREP_TIME:
				step = Step.KICK
				_t = 0.0
		Step.KICK:
			_step_kick()
		Step.FLIGHT:
			var b := m.ball.global_position
			if crossed_line_in_goal(b, goal_z):
				_scored_this_kick = true          # over the line between the posts and under the bar
				_finish_kick()
				return
			var stopped := _t > 1.0 and m.ball.linear_velocity.length() < 0.4
			var gone := absf(b.z) > PitchSpace.HALF_LENGTH + 0.5 or absf(b.x) > 8.0
			var held := (m.entries[defending_side()][0]["node"] as TeamGoalkeeper).state == TeamGoalkeeper.State.HOLD
			if stopped or gone or held or _t > FLIGHT_TIMEOUT:
				_finish_kick()
		Step.RESULT:
			if _t >= RESULT_PAUSE:
				_advance()


func _step_kick() -> void:
	if _kicker.is_empty():
		_finish_kick()
		return
	var shot_away := m.ball.global_position.distance_to(spot()) > 1.0 or m.ball.linear_velocity.length() > 2.0
	if shot_away:
		step = Step.FLIGHT
		_t = 0.0
		return
	if human_kicks() and _t < HUMAN_TIME_LIMIT:
		return                                  # waiting for the human's shot
	var ai := _kicker_intent()
	ai.begin_tick()
	var acts := _kicker["actions"] as FootballActions
	var can_shoot := acts == null or bool(acts.get_action_availability().get(&"shoot", false))
	if not _released and not can_shoot:
		# Step up to the ball (slow walk) until the shot is within reach.
		var to_ball := m.ball.global_position - (_kicker["node"] as Node3D).global_position
		to_ball.y = 0.0
		ai.set_move_world(to_ball.normalized() * 0.3)
	elif not _released and _t >= AI_RUN_UP and can_shoot:
		var aim := aim_direction()
		# With the stick neutral at release the kick follows the body's facing: face the target.
		var body := _kicker["node"] as Node3D
		body.look_at(body.global_position + Vector3(aim.x, 0.0, aim.z), Vector3.UP)
		ai.set_move_world(aim)
		ai.press(&"shoot")
		_released = true
		_press_t = _t
	elif _released and ai.is_pressed(&"shoot"):
		ai.set_move_world(Vector3.ZERO)          # planted while charging; the aim from the press frame stays
		if _t >= _press_t + PENALTY_CHARGE:
			ai.release(&"shoot")
	elif _released and _t >= _press_t + 1.5:
		_released = false                         # the strike did not happen (ball not in reach yet): again
	if _t > HUMAN_TIME_LIMIT + 6.0:
		_finish_kick()                            # safety net: never stall the shoot-out


## The intent that kicks for an AI taker (or for a human who let the time run out).
func _kicker_intent() -> AIIntent:
	if _kicker["ai"] == null:                    # human-controlled: hand the kick to an AI intent
		var ai := AIIntent.new()
		_kicker["ai"] = ai
		(_kicker["node"] as PlayerController).intent = ai
		(_kicker["actions"] as FootballActions).intent = ai
	return _kicker["ai"]


## The keeper's guess for this kick: the AI kicker's target side is decided in `aim_direction`, so the
## guess is drawn independently — left, right or staying central — with better keepers staying up a
## little more often (they are harder to send the wrong way).
func keeper_guess(goalkeeping: int) -> int:
	var stay := 0.10 + 0.10 * clampf(float(goalkeeping) / 99.0, 0.0, 1.0)
	var r := _rng.randf()
	if r < stay:
		return 0
	return -1 if r < stay + (1.0 - stay) * 0.5 else 1


## Corner aim with an error that shrinks with the shooting attribute.
func aim_direction() -> Vector3:
	var skill := clampf(float((_kicker["pdata"] as PlayerData).shooting) / 99.0, 0.2, 1.0)
	var target_x := TARGETS[_rng.randi_range(0, TARGETS.size() - 1)]
	target_x += _rng.randf_range(-1.0, 1.0) * (1.0 - skill) * 2.0
	var wanted := (Vector3(target_x, 0.0, goal_z) - spot()).normalized()
	var acts := _kicker["actions"] as FootballActions
	if acts != null and acts.config != null and acts.ball_detector != null:
		var aim := PlayerAI.compensated_aim(wanted, acts.ball_detector.get_direction_to_ball(), acts.config.shoot_direction_adjustment)
		if aim != Vector3.ZERO:
			return aim
	return wanted


func _finish_kick() -> void:
	if step == Step.RESULT or step == Step.DONE:
		return
	taken[kicker_side] += 1
	if _scored_this_kick:
		score[kicker_side] += 1
	kicks.append({"side": kicker_side, "player_id": str(_kicker.get("player_id", "")), "scored": _scored_this_kick})
	m.state.log_event({"minute": 120, "type": "penalty_kick", "side": kicker_side,
			"player_id": str(_kicker.get("player_id", "")), "scored": _scored_this_kick})
	step = Step.RESULT
	_t = 0.0
	_stand_down(_kicker)


## The kicker stops and walks back to his team-mates (no stray intent may touch the next ball).
func _stand_down(e: Dictionary) -> void:
	if e.is_empty():
		return
	var ai: AIIntent = e["ai"]
	if ai != null:
		ai.begin_tick()
		ai.release_all()
		ai.set_move_world(Vector3.ZERO)
	var node := e["node"] as CharacterBody3D
	var lane := -1.0 if e["side"] == "home" else 1.0
	node.global_position = Vector3(lane * 3.0, 0.05, 0.0)
	node.velocity = Vector3.ZERO


## The whole ball is over the goal line between the posts and under the crossbar.
static func crossed_line_in_goal(b: Vector3, p_goal_z: float) -> bool:
	return absf(b.z) > PitchSpace.HALF_LENGTH + 0.11 and signf(b.z) == signf(p_goal_z) \
			and absf(b.x) < 3.66 and b.y < 2.44


## True when the shoot-out is decided after the kicks taken so far.
static func decided(s: Dictionary, t: Dictionary, regular: int = REGULAR_KICKS) -> bool:
	if t["home"] < regular or t["away"] < regular:
		var home_max: int = s["home"] + regular - mini(t["home"], regular)
		var away_max: int = s["away"] + regular - mini(t["away"], regular)
		return s["home"] > away_max or s["away"] > home_max
	return t["home"] == t["away"] and s["home"] != s["away"]


func _advance() -> void:
	if decided(score, taken):
		step = Step.DONE
		for side in ["home", "away"]:
			(m.entries[side][0]["node"] as TeamGoalkeeper).penalty_mode = false
		finished.emit(score["home"], score["away"])
		return
	kicker_side = "away" if kicker_side == "home" else "home"
	_next_kick()


## Tally for the HUD, e.g. "Penalty shoot-out: 3 - 2", plus a prompt when the player must shoot.
func tally_text() -> String:
	# Same order as the scoreboard: in Arabic the home team is on the right, so its count goes last.
	var t := Loc.f("RESULT_PENALTIES", [score["away"], score["home"]] if Loc.is_rtl() else [score["home"], score["away"]])
	if human_kicks() and (step == Step.PREP or step == Step.KICK):
		t += "  ·  " + Loc.t("SHOOTOUT_YOUR_KICK")
	return t
