class_name SkillMoveCatalog
extends RefCounted

## Data for every skill move (Phase 2 advanced mechanics). `SkillMoveSystem` executes these; nothing here touches the
## ball or a player.
##
## Frame: every vector is in the player's own frame at the start of the move, as Vector2(x, y) with x = towards the
## EXIT side (the side the player wants to go: +1 = that side, -1 = the other one) and y = forward (+) / back (-).
## So one definition serves both directions; `SkillMoveSystem` mirrors it for a left or right exit.
##
## Fields of a move:
##   tier        1 basic, 2 intermediate (advanced = chaining moves, see SkillMoveSystem.COMBO_*)
##   duration    s; kicks are allowed again from `kick_window` x duration (the exit phase), never a lock
##   min_skill   0..1 skill rating (`AttributeModifiers.skill_rating`) for a clean execution; below it quality drops fast
##   speed       [lo, hi] m/s of the player at the start in which the move works best
##   foot        which foot plays the decisive touch: "exit" (foot on the exit side), "feint" (the other one), "strong"
##   feints      [{t, dir, strength, kind}] — what the defender is shown (dir = the fake direction)
##   touches     [{t, dir, speed, carry}] — ball velocity set at t: dir * speed (+ carry x the player's velocity)
##   body        [{t, dur, dir, speed, accel, face}] — body motion: dir * speed x the player's normal speed for dur s
##               (face = turn the body along dir)
##   exposure    0..1 how far from the body the ball travels during the move (tackle risk)
##   protect     0..1 how much the body is between ball and a front defender during the move (tackle protection)
##   clip        animation clip (v2 model) at the exit; "" = none. "Shoot"/"Pass" = the kick wind-up, cut short.
##
## Moves that the available animations cannot show are NOT in here (no rabona, no rainbow flick, no bicycle kick):
## see docs/ADVANCED_MECHANICS.md "Not implemented".

const MOVES := {
	&"body_feint": {
		"tier": 1, "duration": 0.45, "min_skill": 0.22, "speed": [0.0, 3.0], "foot": "strong", "kick_window": 0.55,
		"feints": [{"t": 0.04, "dir": Vector2(-1.0, 0.3), "strength": 0.55, "kind": &"body"}],
		"touches": [{"t": 0.24, "dir": Vector2(0.7, 0.7), "speed": 3.2, "carry": 0.3}],
		"body": [{"t": 0.0, "dur": 0.2, "dir": Vector2(-0.6, 0.6), "speed": 0.45, "accel": 1.6},
				{"t": 0.22, "dur": 0.25, "dir": Vector2(0.8, 0.6), "speed": 1.0, "accel": 2.2}],
		"exposure": 0.15, "protect": 0.0, "clip": "TurnSide"},
	&"step_over": {
		"tier": 1, "duration": 0.6, "min_skill": 0.38, "speed": [1.5, 6.5], "foot": "exit", "kick_window": 0.6,
		"feints": [{"t": 0.14, "dir": Vector2(-1.0, 0.2), "strength": 0.75, "kind": &"step_over"}],
		"touches": [{"t": 0.34, "dir": Vector2(0.8, 0.6), "speed": 3.8, "carry": 0.35}],
		"body": [{"t": 0.0, "dur": 0.3, "dir": Vector2(-0.2, 1.0), "speed": 0.4, "accel": 1.4},
				{"t": 0.32, "dur": 0.28, "dir": Vector2(0.85, 0.5), "speed": 1.05, "accel": 2.4}],
		"exposure": 0.15, "protect": 0.0, "clip": "TurnSide"},
	&"double_step_over": {
		"tier": 1, "duration": 0.85, "min_skill": 0.5, "speed": [1.5, 6.0], "foot": "strong", "kick_window": 0.68,
		"feints": [{"t": 0.12, "dir": Vector2(-1.0, 0.2), "strength": 0.55, "kind": &"step_over"},
				{"t": 0.38, "dir": Vector2(1.0, 0.2), "strength": 0.7, "kind": &"step_over"}],
		"touches": [{"t": 0.62, "dir": Vector2(-0.15, 1.0), "speed": 4.8, "carry": 0.2}],
		"body": [{"t": 0.0, "dur": 0.58, "dir": Vector2(0.0, 1.0), "speed": 0.35, "accel": 1.4},
				{"t": 0.6, "dur": 0.25, "dir": Vector2(-0.15, 1.0), "speed": 1.15, "accel": 2.6}],
		"exposure": 0.15, "protect": 0.0, "clip": "Accelerate"},
	&"ball_roll": {
		"tier": 1, "duration": 0.5, "min_skill": 0.3, "speed": [0.0, 3.5], "foot": "feint", "kick_window": 0.5,
		"feints": [{"t": 0.05, "dir": Vector2(1.0, 0.0), "strength": 0.25, "kind": &"roll"}],
		"touches": [{"t": 0.05, "dir": Vector2(1.0, 0.1), "speed": 2.5, "carry": 0.0}],
		"body": [{"t": 0.02, "dur": 0.45, "dir": Vector2(1.0, 0.15), "speed": 0.55, "accel": 1.8}],
		"exposure": 0.25, "protect": 0.3, "clip": "BallControl"},
	&"drag_back": {
		"tier": 1, "duration": 0.5, "min_skill": 0.22, "speed": [0.0, 5.5], "foot": "strong", "kick_window": 0.45,
		"feints": [{"t": 0.03, "dir": Vector2(0.0, -1.0), "strength": 0.4, "kind": &"stop"}],
		"touches": [{"t": 0.04, "dir": Vector2(0.0, -1.0), "speed": 1.6, "carry": 0.0}],
		"body": [{"t": 0.0, "dur": 0.45, "dir": Vector2(0.0, -0.4), "speed": 0.25, "accel": 3.0}],
		"exposure": 0.15, "protect": 0.45, "clip": "Decelerate"},
	&"stop_and_turn": {
		"tier": 1, "duration": 0.7, "min_skill": 0.2, "speed": [0.0, 5.0], "foot": "strong", "kick_window": 0.6,
		"feints": [{"t": 0.04, "dir": Vector2(0.0, -1.0), "strength": 0.3, "kind": &"stop"}],
		"touches": [{"t": 0.05, "dir": Vector2.ZERO, "speed": 0.0, "carry": 0.0},
				{"t": 0.4, "dir": Vector2(0.15, -1.0), "speed": 3.0, "carry": 0.0}],
		"body": [{"t": 0.0, "dur": 0.36, "dir": Vector2.ZERO, "speed": 0.0, "accel": 3.0},
				{"t": 0.38, "dur": 0.32, "dir": Vector2(0.15, -1.0), "speed": 0.8, "accel": 2.0, "face": true}],
		"exposure": 0.1, "protect": 0.55, "clip": "Decelerate"},
	&"roulette": {
		"tier": 2, "duration": 0.8, "min_skill": 0.6, "speed": [0.0, 4.5], "foot": "strong", "kick_window": 0.62,
		"feints": [{"t": 0.1, "dir": Vector2(-1.0, 0.0), "strength": 0.5, "kind": &"spin"}],
		"touches": [{"t": 0.1, "dir": Vector2(0.0, -0.3), "speed": 1.0, "carry": 0.0},
				{"t": 0.46, "dir": Vector2(1.0, 0.7), "speed": 3.6, "carry": 0.0}],
		"body": [{"t": 0.0, "dur": 0.42, "dir": Vector2(0.4, 0.0), "speed": 0.3, "accel": 2.0},
				{"t": 0.44, "dir": Vector2(0.7, 0.7), "dur": 0.34, "speed": 0.95, "accel": 2.0}],
		"exposure": 0.2, "protect": 0.7, "clip": "TurnSide"},
	&"elastico": {
		"tier": 2, "duration": 0.45, "min_skill": 0.72, "speed": [1.0, 5.5], "foot": "feint", "kick_window": 0.5,
		"feints": [{"t": 0.06, "dir": Vector2(-1.0, 0.1), "strength": 0.85, "kind": &"elastico"}],
		"touches": [{"t": 0.06, "dir": Vector2(-0.6, 0.3), "speed": 1.2, "carry": 0.6},
				{"t": 0.17, "dir": Vector2(1.0, 0.45), "speed": 4.2, "carry": 0.3}],
		"body": [{"t": 0.15, "dur": 0.3, "dir": Vector2(0.8, 0.6), "speed": 1.0, "accel": 2.8}],
		"exposure": 0.35, "protect": 0.0, "clip": "TurnSide"},
	&"reverse_elastico": {
		"tier": 2, "duration": 0.42, "min_skill": 0.72, "speed": [1.0, 5.5], "foot": "exit", "kick_window": 0.5,
		"feints": [{"t": 0.05, "dir": Vector2(-1.0, 0.1), "strength": 0.8, "kind": &"elastico"}],
		"touches": [{"t": 0.05, "dir": Vector2(-0.5, 0.3), "speed": 1.0, "carry": 0.6},
				{"t": 0.15, "dir": Vector2(1.0, 0.45), "speed": 4.2, "carry": 0.3}],
		"body": [{"t": 0.13, "dur": 0.29, "dir": Vector2(0.8, 0.6), "speed": 1.0, "accel": 2.8}],
		"exposure": 0.35, "protect": 0.0, "clip": "TurnSide"},
	&"heel_to_heel": {
		"tier": 2, "duration": 0.5, "min_skill": 0.65, "speed": [3.0, 7.5], "foot": "strong", "kick_window": 0.45,
		"feints": [{"t": 0.05, "dir": Vector2(0.0, -0.6), "strength": 0.5, "kind": &"flick"}],
		"touches": [{"t": 0.08, "dir": Vector2(0.1, 1.0), "speed": 3.0, "carry": 1.0}],
		"body": [{"t": 0.05, "dur": 0.42, "dir": Vector2(-0.3, 1.0), "speed": 1.1, "accel": 2.0}],
		"exposure": 0.45, "protect": 0.0, "clip": "Accelerate"},
	&"la_croqueta": {
		"tier": 2, "duration": 0.32, "min_skill": 0.55, "speed": [0.0, 5.0], "foot": "strong", "kick_window": 0.45,
		"feints": [{"t": 0.0, "dir": Vector2(-0.3, 1.0), "strength": 0.3, "kind": &"croqueta"}],
		"touches": [{"t": 0.04, "dir": Vector2(1.0, 0.25), "speed": 2.6, "carry": 0.5}],
		"body": [{"t": 0.02, "dur": 0.3, "dir": Vector2(0.9, 0.5), "speed": 1.0, "accel": 3.0}],
		"exposure": 0.1, "protect": 0.2, "clip": "TurnSide"},
	&"fake_shot": {
		"tier": 2, "duration": 0.5, "min_skill": 0.3, "speed": [0.0, 6.0], "foot": "strong", "kick_window": 0.5,
		"feints": [{"t": 0.08, "dir": Vector2(0.0, 1.0), "strength": 0.8, "kind": &"shot"}],
		"touches": [{"t": 0.22, "dir": Vector2(1.0, 0.25), "speed": 3.0, "carry": 0.2}],
		"body": [{"t": 0.0, "dur": 0.2, "dir": Vector2(0.0, 1.0), "speed": 0.2, "accel": 2.0},
				{"t": 0.22, "dur": 0.28, "dir": Vector2(0.9, 0.4), "speed": 0.9, "accel": 2.5}],
		"exposure": 0.15, "protect": 0.0, "clip": "Shoot"},
	&"fake_pass": {
		"tier": 2, "duration": 0.48, "min_skill": 0.25, "speed": [0.0, 6.0], "foot": "strong", "kick_window": 0.5,
		"feints": [{"t": 0.07, "dir": Vector2(-1.0, 0.6), "strength": 0.6, "kind": &"pass"}],
		"touches": [{"t": 0.2, "dir": Vector2(1.0, 0.4), "speed": 3.0, "carry": 0.25}],
		"body": [{"t": 0.0, "dur": 0.18, "dir": Vector2(0.0, 1.0), "speed": 0.25, "accel": 2.0},
				{"t": 0.2, "dur": 0.28, "dir": Vector2(0.9, 0.45), "speed": 0.9, "accel": 2.5}],
		"exposure": 0.15, "protect": 0.0, "clip": "Pass"},
}

## Human input -> move. Rows: stick direction relative to the player's facing; columns: a single tap of `skill_move`,
## a second tap within DOUBLE_TAP s, a tap while `sprint` is held. "slow" = the side tap at <= SLOW_SPEED m/s.
const INPUT_TABLE := {
	&"none": [&"drag_back", &"stop_and_turn", &"ball_roll"],
	&"forward": [&"double_step_over", &"heel_to_heel", &"heel_to_heel"],
	&"side": [&"step_over", &"elastico", &"la_croqueta"],
	&"back_side": [&"roulette", &"reverse_elastico", &"ball_roll"],
	&"back": [&"drag_back", &"stop_and_turn", &"stop_and_turn"],
}
const SLOW_SIDE_MOVE := &"body_feint"
const SLOW_SPEED := 2.0
const DOUBLE_TAP := 0.22


static func has(id: StringName) -> bool:
	return MOVES.has(id)


static func get_move(id: StringName) -> Dictionary:
	return MOVES.get(id, {})


static func ids() -> Array:
	return MOVES.keys()


static func ids_of_tier(tier: int) -> Array:
	var out := []
	for id in MOVES:
		if int(MOVES[id]["tier"]) == tier:
			out.append(id)
	return out


## Stick direction (player frame, x = right, y = forward; ZERO = none) -> [row, exit side (+1 right / -1 left / 0)].
static func classify_stick(local_stick: Vector2) -> Array:
	if local_stick.length() < 0.3:
		return [&"none", 0.0]
	var a := rad_to_deg(absf(atan2(local_stick.x, local_stick.y)))      # 0 = forward, 180 = back
	var side := signf(local_stick.x)
	if a < 35.0:
		return [&"forward", 0.0]
	if a <= 115.0:
		return [&"side", side]
	if a <= 155.0:
		return [&"back_side", side]
	return [&"back", 0.0]


## The move a human input asks for. `tap` 0 = single, 1 = double, 2 = with sprint.
static func move_for_input(local_stick: Vector2, tap: int, player_speed: float) -> Array:
	var c := classify_stick(local_stick)
	var row: StringName = c[0]
	var id: StringName = INPUT_TABLE[row][clampi(tap, 0, 2)]
	if row == &"side" and tap == 0 and player_speed <= SLOW_SPEED:
		id = SLOW_SIDE_MOVE
	return [id, float(c[1])]
