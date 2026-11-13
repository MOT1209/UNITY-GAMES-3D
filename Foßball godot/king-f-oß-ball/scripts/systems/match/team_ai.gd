class_name TeamAI
extends RefCounted

## Team-level AI (Phase T11): shape, pressing, support. Pure functions: feed
## positions in, get target positions / roles out.


## World target for each of the 11 slots, from formation + tactics + ball.
static func formation_targets(side: String, formation_id: String, tactics: TacticsPreset,
		ball_world: Vector3, team_has_ball: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var progress := PitchSpace.progress_of(ball_world, side)
	for slot in 11:
		var rel := tactics.target_position(formation_id, slot, progress)
		# Compact shape without the ball: pull outfielders slightly toward own half.
		if not team_has_ball and slot != 0:
			rel.y = clampf(rel.y - 0.04, 0.02, 0.98)
		elif team_has_ball and slot != 0:
			# the team pushes up and the forwards make runs ahead of the ball (`support_offset`, in metres, scaled by mentality)
			var slot_pos := FormationData.slot_position(formation_id, slot)
			rel.y = clampf(rel.y + 0.03 + support_offset(slot_pos, tactics) / (2.0 * PitchSpace.HALF_LENGTH), 0.02, 0.98)
		out.append(PitchSpace.to_world(rel, side))
	return out


## Index of the player who should chase the ball: the closest outfielder
## (the goalkeeper only when the ball is very close to goal). -1 if none.
static func chaser_index(positions: Array[Vector3], ball_world: Vector3, side: String) -> int:
	var best := -1
	var best_d := INF
	for i in positions.size():
		var d := Vector2(positions[i].x - ball_world.x, positions[i].z - ball_world.z).length()
		if i == 0:
			var from_goal := Vector2(ball_world.x - PitchSpace.own_goal(side).x,
					ball_world.z - PitchSpace.own_goal(side).z).length()
			if from_goal > 12.0:
				continue
		if d < best_d:
			best_d = d
			best = i
	return best


## Players that should apply pressing: chaser plus the next closest when
## pressing is high (≥ 70) and the ball is within `press_distance`.
static func pressers(positions: Array[Vector3], ball_world: Vector3, side: String,
		tactics: TacticsPreset) -> Array[int]:
	var out: Array[int] = []
	var first := chaser_index(positions, ball_world, side)
	if first < 0:
		return out
	out.append(first)
	if tactics.pressing >= 70:
		var second := -1
		var best := INF
		for i in positions.size():
			if i == first or i == 0:
				continue
			var d := Vector2(positions[i].x - ball_world.x, positions[i].z - ball_world.z).length()
			if d < best and d <= tactics.press_distance():
				best = d
				second = i
		if second >= 0:
			out.append(second)
	return out


## Support run: attackers push toward the ball-carrier's attacking lane.
static func support_offset(slot_position: int, tactics: TacticsPreset) -> float:
	var forward := slot_position in [PlayerData.Position.ST, PlayerData.Position.LW,
			PlayerData.Position.RW, PlayerData.Position.CAM]
	var base := 6.0 if forward else 2.0
	return base * (0.5 + float(tactics.mentality) * 0.25)


## Opponent analysis from the MEASURED match statistics (no guessing): what `side` has seen of the other team so far.
## Returns {possession, shots, on_target, direct, dominant, dangerous}.
##   dominant  - the opponent had >= 60 % of the ball after the first 10 minutes;
##   dangerous - the opponent has at least 2 more shots on target than `side`;
##   direct    - the opponent plays few passes per shot (<= 6) after at least 3 shots.
static func analyse_opponent(state: MatchState, side: String) -> Dictionary:
	var other := "away" if side == "home" else "home"
	var t: Dictionary = state.stats.teams[other]
	var mine: Dictionary = state.stats.teams[side]
	var poss := state.stats.possession_pct(other)
	var shots: int = int(t["shots"])
	return {"possession": poss, "shots": shots, "on_target": int(t["on_target"]),
			"dominant": state.display_minute() >= 10.0 and poss >= 60.0,
			"dangerous": int(t["on_target"]) - int(mine["on_target"]) >= 2,
			"direct": shots >= 3 and float(t["passes"]) / float(shots) <= 6.0}
