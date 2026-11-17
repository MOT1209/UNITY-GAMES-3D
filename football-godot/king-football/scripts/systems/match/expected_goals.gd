class_name ExpectedGoals
extends RefCounted

## Expected goals (xG) of a shot, and the attack-normalised heat-map grid (Phase 8 analytics).
##
## xG IS AN ESTIMATE, NOT A MEASUREMENT. The match log records where a shot was taken, not its body part, pressure or
## the keeper's position, so the model uses location only: distance to the goal centre and the angle the goal mouth
## subtends at the shot position, in a logistic form
##     xG = sigmoid(INTERCEPT + DIST_COEF * distance + ANGLE_COEF * angle)
## The three coefficients are hand-set so that a central shot gives roughly 0.28 at 6 m, 0.15 at 11 m, 0.07 at 18 m and
## 0.02 at 30 m (the order of magnitude usually quoted for open play). They were NOT fitted to this game's matches nor to
## real data, so compare xG between teams of the same game only. Penalties are not tagged in the event log, so a penalty
## is valued by its location (about 0.15) and is under-estimated.
## Own goals and shoot-out kicks are not shots and have no xG.

const GOAL_WIDTH := 7.32
const INTERCEPT := -1.0
const DIST_COEF := -0.10
const ANGLE_COEF := 0.6

## Heat map: COLS lateral cells (left .. right of the attacking direction) x ROWS cells along the pitch (own goal .. opponent goal).
const HEAT_COLS := 8
const HEAT_ROWS := 12


## xG of a shot at (x, z) world metres at a goal centred on (0, goal_z). 0 when the position is on / behind the goal line.
static func shot_xg(x: float, z: float, goal_z: float) -> float:
	var along := absf(goal_z - z)                      # distance from the goal line, along the pitch
	if along < 0.5:
		along = 0.5
	var dist := Vector2(x, along).length()
	var a := atan2(GOAL_WIDTH * 0.5 - x, along) - atan2(-GOAL_WIDTH * 0.5 - x, along)
	return snappedf(1.0 / (1.0 + exp(-(INTERCEPT + DIST_COEF * dist + ANGLE_COEF * absf(a)))), 0.001)


## World z of the goal `side` attacks in `half` (1 or 2): home attacks -Z in the first half, the ends swap at half-time.
static func attack_goal_z(side: String, half: int) -> float:
	var s := PitchSpace.side_sign(side) * (1.0 if half <= 1 else -1.0)
	return -s * PitchSpace.HALF_LENGTH


## Heat-map cell index (row * HEAT_COLS + col) of a player of `side` standing at world (x, z) in `half`, in the team's own
## frame (so both halves and both sides add up in one grid): row 0 = own goal line, last row = opponent goal line;
## column 0 = left hand side when facing the opponent's goal.
static func heat_cell(x: float, z: float, side: String, half: int) -> int:
	var f := team_frame(x, z, side, half)
	return int(minf(f.y, 0.9999) * HEAT_ROWS) * HEAT_COLS + int(minf(f.x, 0.9999) * HEAT_COLS)


## Position in the team's own frame: Vector2(v, u), v 0 = left .. 1 = right when facing the opponent's goal,
## u 0 = own goal line .. 1 = opponent's goal line (both clamped to the pitch).
static func team_frame(x: float, z: float, side: String, half: int) -> Vector2:
	var s := PitchSpace.side_sign(side) * (1.0 if half <= 1 else -1.0)      # +1: attacks -Z
	var u := clampf(0.5 - s * z / (2.0 * PitchSpace.HALF_LENGTH), 0.0, 1.0)
	var v := clampf(0.5 + s * x / (2.0 * PitchSpace.HALF_WIDTH), 0.0, 1.0)
	return Vector2(v, u)
