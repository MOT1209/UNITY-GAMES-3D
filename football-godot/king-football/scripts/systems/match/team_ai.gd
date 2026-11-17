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
		if slot != 0 and tactics.player_instructions.has(slot):
			var base: Array = FormationData.slots(formation_id)[slot]
			rel = tactics.apply_instruction(slot, rel, float(base[1]), float(base[2]), team_has_ball)
		var w := PitchSpace.to_world(rel, side)
		# Phase M4: every target lies on the pitch (1 m inside the lines): instructions and push-ups could send a
		# full-back or a forward beyond the touchline / goal line.
		w.x = clampf(w.x, -PitchSpace.HALF_WIDTH + 1.0, PitchSpace.HALF_WIDTH - 1.0)
		w.z = clampf(w.z, -PitchSpace.HALF_LENGTH + 1.0, PitchSpace.HALF_LENGTH - 1.0)
		out.append(w)
	return out


const DANGER_ZONE := 28.0


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
		tactics: TacticsPreset, press_distance_bonus: float = 0.0) -> Array[int]:
	var out: Array[int] = []
	var first := chaser_index(positions, ball_world, side)
	if first < 0:
		return out
	out.append(first)
	# Phase M5: near the own goal (DANGER_ZONE m) a second man always goes too — attackers walked into the box and shot
	# from 5-12 m with nobody but the first presser on them.
	var near_goal := Vector2(ball_world.x - PitchSpace.own_goal(side).x, ball_world.z - PitchSpace.own_goal(side).z).length() <= DANGER_ZONE
	if tactics.pressing >= 70 or near_goal:
		var second := -1
		var best := INF
		for i in positions.size():
			if i == first or i == 0:
				continue
			var d := Vector2(positions[i].x - ball_world.x, positions[i].z - ball_world.z).length()
			if d < best and (d <= tactics.press_distance() + press_distance_bonus or near_goal):
				best = d
				second = i
		if second >= 0:
			out.append(second)
	return out


## Phase M4 support: the best open spot for a team-mate of the carrier to offer a pass. Candidates lie 10-22 m from
## the carrier between straight ahead (towards `goal`) and a wide diagonal (+-75 degrees); each is scored by its distance to
## the nearest opponent (capped at 8 m), an open lane from the carrier, the gain towards goal, and how far the mate
## would have to leave `home` (his place in the shape). Spots within 7 m of `taken` (other supporters) are skipped.
## Every spot is on the pitch. Returns Vector3.INF when nothing is open.
const SUPPORT_RINGS: Array[float] = [11.0, 16.0, 22.0]
const SUPPORT_ANGLES: Array[float] = [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 75.0, -75.0]


static func support_spot(carrier: Vector3, goal: Vector3, home: Vector3, opponents: Array, taken: Array) -> Vector3:
	var line := PlayerAI.offside_line(goal, carrier, opponents) if opponents.size() >= 2 else 0.0
	var fwd := Vector3(goal.x - carrier.x, 0.0, goal.z - carrier.z)
	if fwd.length() < 0.1:
		return Vector3.INF
	fwd = fwd.normalized()
	var best := Vector3.INF
	var best_score := -INF
	for r in SUPPORT_RINGS:
		for a in SUPPORT_ANGLES:
			var spot := carrier + fwd.rotated(Vector3.UP, deg_to_rad(a)) * r
			spot.x = clampf(spot.x, -PitchSpace.HALF_WIDTH + 2.0, PitchSpace.HALF_WIDTH - 2.0)
			spot.z = clampf(spot.z, -PitchSpace.HALF_LENGTH + 3.0, PitchSpace.HALF_LENGTH - 3.0)
			spot.y = 0.0
			if PlayerAI.is_offside(spot, goal, line + 0.5):
				continue                                   # never run into an offside position
			var clash := false
			for t: Vector3 in taken:
				if Vector2(t.x - spot.x, t.z - spot.z).length() < 7.0:
					clash = true
					break
			if clash:
				continue
			var space := 8.0
			for o: Vector3 in opponents:
				space = minf(space, Vector2(o.x - spot.x, o.z - spot.z).length())
			var gain := Vector2(goal.x - carrier.x, goal.z - carrier.z).length() - Vector2(goal.x - spot.x, goal.z - spot.z).length()
			var leave := Vector2(home.x - spot.x, home.z - spot.z).length()
			var score := space * 1.0 + gain * 0.45 - leave * 0.2 + (3.0 if PlayerAI.pass_lane_open(carrier, spot, opponents) else -6.0)
			if score > best_score:
				best_score = score
				best = spot
	return best


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
