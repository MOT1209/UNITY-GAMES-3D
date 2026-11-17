class_name PitchSpace
extends RefCounted

## Mapping between team-relative pitch space (x −1 left … 1 right as seen
## attacking; y 0 own goal … 1 opponent goal) and world coordinates of the
## stadium arena (centre at origin, length along Z, goal N at −Z, goal S at +Z).
## HOME attacks goal N (−Z) and defends S; AWAY the opposite.

const HALF_LENGTH := 52.5
const HALF_WIDTH := 34.0


static func side_sign(side: String) -> float:
	return 1.0 if side == "home" else -1.0


static func to_world(rel: Vector2, side: String) -> Vector3:
	var s := side_sign(side)
	return Vector3(s * rel.x * HALF_WIDTH * 0.9, 0.0, s * (1.0 - 2.0 * rel.y) * HALF_LENGTH)


static func own_goal(side: String) -> Vector3:
	return Vector3(0.0, 0.0, side_sign(side) * HALF_LENGTH)


static func opponent_goal(side: String) -> Vector3:
	return Vector3(0.0, 0.0, -side_sign(side) * HALF_LENGTH)


## 0 = ball at own goal line … 1 = at the opponent's goal line.
static func progress_of(world: Vector3, side: String) -> float:
	return clampf(0.5 - side_sign(side) * world.z / (2.0 * HALF_LENGTH), 0.0, 1.0)


## Which side scores when the ball enters goal `goal_id` ("N" or "S").
static func scoring_side(goal_id: StringName) -> String:
	return "home" if goal_id == &"N" else "away"
