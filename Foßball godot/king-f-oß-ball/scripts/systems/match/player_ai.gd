class_name PlayerAI
extends RefCounted

## Individual decision making (Phase T11). Pure: takes a context dictionary,
## returns {move: Vector3 (world dir, length ≤ 1), sprint: bool, action: StringName}.
## `action` is "" / "shoot" / "pass" and is pressed through an `AIIntent`.
##
## ctx keys: pos, ball, has_ball, is_chaser, target (formation position),
## goal (opponent goal), teammates (Array[Vector3]), opponents (Array[Vector3]),
## is_keeper, own_goal, difficulty (0..2), shoot_range, attributes (AttributeModifiers or null)

const ARRIVE_RADIUS := 1.0
const SHOOT_RANGE := 24.0
const PASS_MIN_DISTANCE := 6.0
const LONG_SHOT_FACTOR := 1.3        # with an open lane the carrier shoots from up to 1.3 x the tactics' shoot range
const LANE_WIDTH := 2.5
const BLOCK_DISTANCE := 9.0
const CROSS_ZONE := 36.0             # within this distance of the goal a wide carrier looks for a cross
const WIDE := 14.0                   # |x| from the goal centre beyond which the carrier counts as wide
const BOX_DEPTH := 18.0
const BOX_HALF_WIDTH := 12.0
const THROUGH_LEAD := 4.0
const ADVANCE_PASS_GAIN := 9.0      # Phase M5: a free carrier passes to an open team-mate at least this much nearer the goal
const SHOT_POST_OFFSET := 3.2       # the goal is 7.32 m wide: aim 0.46 m inside the post away from the keeper (Phase M5; was 2.0)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _dir(from: Vector3, to: Vector3) -> Vector3:
	var d := _flat(to - from)
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


static func decide(ctx: Dictionary) -> Dictionary:
	var pos: Vector3 = ctx["pos"]
	var ball: Vector3 = ctx["ball"]
	var out := {"move": Vector3.ZERO, "sprint": false, "action": &"", "kick_dist": -1.0}
	if ctx.get("is_keeper", false):
		return _keeper(ctx, out)
	if ctx.get("has_ball", false):
		return _with_ball(ctx, out)
	if ctx.get("is_chaser", false):
		# Phase M5: close down goal-side — run to a point between the ball and the own goal (1.2 m off the ball) so the
		# carrier is shown away from goal instead of being chased from behind.
		var own: Vector3 = ctx.get("own_goal", ball)
		var spot := ball + _dir(ball, own) * 1.2 if _flat(own - ball).length() < 40.0 else ball
		var d := _flat(spot - pos).length()
		out["move"] = _dir(pos, spot) if d > 0.3 else _dir(pos, ball) * 0.3
		out["sprint"] = d > 6.0 and int(ctx.get("difficulty", 1)) >= 1
		return out
	var target: Vector3 = ctx["target"]
	var to_target := _flat(target - pos)
	if to_target.length() > ARRIVE_RADIUS:
		out["move"] = to_target.normalized() * clampf(to_target.length() / 4.0, 0.35, 1.0)
		out["sprint"] = to_target.length() > 14.0
	else:
		out["move"] = shape_shuffle(pos, ball, target, float(ctx.get("time", 0.0)), int(ctx.get("slot", 0)))
	return out


## Phase M4: a player who has reached his place in the shape does not freeze — he shuffles across, side-on to the
## ball, about +-1 m around his spot (0.7 m/s, half a cycle every SHUFFLE_PERIOD s, phase spread by slot). Before,
## 17 % of all outfield player-samples stood dead still for more than 3 s while the ball was in play.
const SHUFFLE_SPEED := 0.13
const SHUFFLE_PERIOD := 3.2


static func shape_shuffle(pos: Vector3, ball: Vector3, target: Vector3, time: float, slot: int) -> Vector3:
	var to_ball := _dir(pos, ball)
	if to_ball == Vector3.ZERO:
		return Vector3.ZERO
	var across := Vector3(to_ball.z, 0.0, -to_ball.x)
	var side := 1.0 if sin(time * PI / SHUFFLE_PERIOD + float(slot) * 1.7) >= 0.0 else -1.0
	var back := _flat(target - pos) * 0.5                 # stay centred on the spot
	return (across * side * SHUFFLE_SPEED + back * 0.1).limit_length(0.2)


static func _keeper(ctx: Dictionary, out: Dictionary) -> Dictionary:
	var pos: Vector3 = ctx["pos"]
	var ball: Vector3 = ctx["ball"]
	var own_goal: Vector3 = ctx["own_goal"]
	var back_z := signf(own_goal.z)
	# Stay 2.5 m off the goal line, shadow the ball laterally (±3.5 m).
	var target := Vector3(clampf(ball.x * 0.3, -3.5, 3.5), 0.0, own_goal.z - back_z * 2.5)
	var factor := 1.0
	var attrs: AttributeModifiers = ctx.get("attributes")
	if attrs != null:
		factor = attrs.goalkeeping_factor()
	var ball_dist := _flat(ball - own_goal).length()
	if ball_dist < 9.0 and not ctx.get("has_ball", false):
		target = Vector3(ball.x, 0.0, own_goal.z - back_z * clampf(ball_dist * 0.5, 1.0, 4.0))   # come out
	var to_t := _flat(target - pos)
	if to_t.length() > 0.4:
		out["move"] = to_t.normalized() * clampf(to_t.length() * factor, 0.3, 1.0)
		out["sprint"] = ball_dist < 14.0
	if ctx.get("has_ball", false):
		# Distribute: pass to the nearest teammate ahead.
		var best := _best_pass_target(ctx)
		if best != Vector3.INF:
			out["move"] = _dir(pos, best)
			out["action"] = &"pass"
	return out


static func _with_ball(ctx: Dictionary, out: Dictionary) -> Dictionary:
	var pos: Vector3 = ctx["pos"]
	var goal: Vector3 = ctx["goal"]
	var to_goal := _flat(goal - pos).length()
	var range_limit: float = ctx.get("shoot_range", SHOOT_RANGE)
	var prof: Dictionary = ctx.get("profile", {})
	var pressure_radius: float = float(prof.get("pressure_radius", 4.0))
	var pressured := false
	for o in ctx.get("opponents", []):
		if _flat(o - pos).length() < pressure_radius:
			pressured = true
			break
	# Wide in the final third: cross to a free team-mate in the box rather than shoot from a tight angle.
	if to_goal <= CROSS_ZONE and absf(pos.x - goal.x) > WIDE:
		var c := cross_target(ctx)
		if c != Vector3.INF:
			out["move"] = _dir(pos, c)
			out["action"] = &"lob_pass"
			out["kick_dist"] = _flat(c - pos).length()
			out["target_pos"] = c
			return out
	# Phase M5: shoot from a good position only — when the chance (`expected_goal`) is at least the threshold of this
	# tactic (a longer shooting range lowers it). Before, everything within 24 m (31 m with an open lane) was shot at:
	# 15-29 shots and 3-6 goals in every 5-minute match.
	if to_goal <= range_limit * LONG_SHOT_FACTOR and expected_goal(pos, goal, ctx.get("opponents", [])) >= shot_threshold(range_limit):
		out["move"] = _dir(pos, shot_target(goal, ctx.get("opp_keeper", Vector3.INF)))
		out["action"] = &"shoot"
		out["kick_dist"] = to_goal
		return out
	# Pass when pressured, or earlier when an opponent blocks the way ahead and a free team-mate is further forward.
	var blocked := _blocked_ahead(pos, goal, ctx.get("opponents", []))
	# Phase M5: a clearly better option ahead (an open team-mate ADVANCE_PASS_GAIN m nearer the goal, open lane) gets
	# the ball even when the carrier is free — before, he ran until somebody closed him down.
	if not pressured and not blocked:
		var ahead := _best_pass_target(ctx)
		if ahead != Vector3.INF and _flat(goal - pos).length() - _flat(goal - ahead).length() >= ADVANCE_PASS_GAIN:
			ahead = lead_point(pos, ahead, goal, ctx.get("opponents", []))
			out["move"] = _dir(pos, ahead)
			out["action"] = &"pass"
			out["kick_dist"] = _flat(ahead - pos).length()
			out["target_pos"] = ahead
			return out
	if pressured or blocked:
		var t := _best_pass_target(ctx)
		if t == Vector3.INF and pressured:
			t = _best_pass_target(_with_relaxed_profile(ctx))       # nothing ahead: a sideways or back pass beats losing the ball
		if t != Vector3.INF:
			t = lead_point(pos, t, goal, ctx.get("opponents", []))
			out["move"] = _dir(pos, t)
			out["action"] = &"pass"
			out["kick_dist"] = _flat(t - pos).length()
			out["target_pos"] = t
			return out
	var run := _dir(pos, goal)
	if blocked:
		run = _dodge(pos, goal, ctx.get("opponents", []))
	out["move"] = run
	out["sprint"] = not pressured
	return out


## Same context with a pass profile that also accepts sideways and backward passes (up to 10 m back) of 6-25 m.
static func _with_relaxed_profile(ctx: Dictionary) -> Dictionary:
	var c := ctx.duplicate()
	var prof: Dictionary = (ctx.get("profile", {}) as Dictionary).duplicate()
	prof["min_progress"] = -10.0
	prof["min_dist"] = PASS_MIN_DISTANCE
	prof["max_dist"] = 25.0
	c["profile"] = prof
	return c


## Run direction that goes around the nearest blocker ahead: towards the goal, bent to the side away from him.
static func _dodge(pos: Vector3, goal: Vector3, opponents: Array) -> Vector3:
	var dir := _dir(pos, goal)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var nearest := Vector3.INF
	var best := INF
	for o: Vector3 in opponents:
		var rel := _flat(o - pos)
		var along := rel.dot(dir)
		if along > 0.5 and along < BLOCK_DISTANCE and absf(rel.x * dir.z - rel.z * dir.x) < 3.0 and along < best:
			best = along
			nearest = rel
	if nearest == Vector3.INF:
		return dir
	var lateral := nearest.dot(side)
	var sign := -1.0 if lateral > 0.0 else 1.0
	return (dir * 0.6 + side * sign * 0.8).normalized()


## The kick systems bend the kick towards the ball's side of the player: result = normalize(aim * (1 - a) + to_ball * a).
## This returns the aim that makes that blend point exactly along `wanted` (unit vectors on the ground; a in 0..0.95).
static func compensated_aim(wanted: Vector3, to_ball: Vector3, a: float) -> Vector3:
	var d := _flat(wanted)
	var b := _flat(to_ball)
	if d.length_squared() < 0.0001 or b.length_squared() < 0.0001 or a <= 0.0:
		return d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO
	d = d.normalized()
	b = b.normalized()
	a = clampf(a, 0.0, 0.95)
	var db := d.dot(b)
	var disc := a * a * db * db - a * a + (1.0 - a) * (1.0 - a)
	if disc < 0.0:
		return d
	var k := a * db + sqrt(disc)
	var aim := (d * k - b * a) / (1.0 - a)
	return aim.normalized()


## Phase M5 simple expected-goal value (0..0.9) of a shot from `pos`: 0.9 x e^(-d/8) for a central shot (d = distance
## to the goal centre: 11 m ~ 0.23, 16 m ~ 0.12, 25 m ~ 0.04), times the share of the goal mouth he sees compared
## with a central shot from the same distance (tight angles score less), x 0.55 when an opponent stands in the
## shooting lane, x 0.8 when one is within 2 m of him.
const XG_SCALE := 0.9
const XG_DECAY := 8.0
const XG_THRESHOLD := 0.035            # the chance an average (24 m range) tactic shoots at (central, open lane: ~26 m)


static func expected_goal(pos: Vector3, goal: Vector3, opponents: Array) -> float:
	var rel := _flat(goal - pos)
	var d := maxf(rel.length(), 0.5)
	var post_a := Vector3(goal.x - 3.66, 0.0, goal.z) - _flat(pos)
	var post_b := Vector3(goal.x + 3.66, 0.0, goal.z) - _flat(pos)
	var seen := post_a.angle_to(post_b)
	var central := 2.0 * atan(3.66 / d)
	var xg := XG_SCALE * exp(-d / XG_DECAY) * clampf(seen / maxf(central, 0.001), 0.0, 1.0)
	if not _lane_open(pos, goal, opponents):
		xg *= 0.55
	for o: Vector3 in opponents:
		if _flat(o - pos).length() < 2.0:
			xg *= 0.8
			break
	return clampf(xg, 0.0, 0.9)


## The xG a shot needs for a tactic whose shooting range is `shoot_range` m (24 m = XG_THRESHOLD; every 3 m more of range
## lowers it by a fifth: long-range tactics shoot more often).
static func shot_threshold(shoot_range: float) -> float:
	return XG_THRESHOLD * pow(0.8, (shoot_range - 24.0) / 3.0)


## Where to shoot: 2 m inside the post on the side away from the goalkeeper (the goal centre when he is not known).
static func shot_target(goal: Vector3, keeper: Vector3) -> Vector3:
	if keeper == Vector3.INF:
		return goal
	var side := 1.0 if keeper.x <= goal.x else -1.0
	return Vector3(goal.x + side * SHOT_POST_OFFSET, goal.y, goal.z)


## A free team-mate inside the penalty box of the opponent (the one closest to the goal), slightly ahead of him; INF when none.
static func cross_target(ctx: Dictionary) -> Vector3:
	var goal: Vector3 = ctx["goal"]
	var best := Vector3.INF
	var best_d := INF
	for t: Vector3 in ctx.get("teammates", []):
		var to_goal := _flat(goal - t).length()
		if to_goal > BOX_DEPTH or absf(t.x - goal.x) > BOX_HALF_WIDTH:
			continue
		var covered := false
		for o: Vector3 in ctx.get("opponents", []):
			if _flat(o - t).length() < 2.0:
				covered = true
				break
		if covered:
			continue
		if to_goal < best_d:
			best_d = to_goal
			best = t
	if best == Vector3.INF:
		return best
	return best + _dir(best, goal) * 1.5


## Through ball: a forward pass is aimed into the receiver's run (towards the goal) when that space is free; otherwise at his feet.
static func lead_point(pos: Vector3, receiver: Vector3, goal: Vector3, opponents: Array) -> Vector3:
	var gain := _flat(goal - pos).length() - _flat(goal - receiver).length()
	if gain <= 6.0:
		return receiver
	var lead := minf(THROUGH_LEAD, gain * 0.25)
	var spot := receiver + _dir(receiver, goal) * lead
	for o: Vector3 in opponents:
		if _flat(o - spot).length() < 2.5:
			return receiver
	return spot


## No opponent within LANE_WIDTH of the straight line from `pos` to the goal (ahead of the shooter).
static func _lane_open(pos: Vector3, goal: Vector3, opponents: Array) -> bool:
	var dir := _dir(pos, goal)
	var len := _flat(goal - pos).length()
	for o: Vector3 in opponents:
		var rel := _flat(o - pos)
		var along := rel.dot(dir)
		if along <= 0.5 or along >= len:
			continue
		if absf(rel.x * dir.z - rel.z * dir.x) < LANE_WIDTH:
			return false
	return true


## Phase M1: no opponent can get to the ground pass from `from` (the ball) to `to` on its way — none within
## PASS_LANE_BASE + PASS_LANE_GROWTH x (distance along the pass) of the line (the further out, the more time he has
## to step across). Before this only opponents next to the receiver were checked and 4 of 5 passes were intercepted.
const PASS_LANE_BASE := 1.1
const PASS_LANE_GROWTH := 0.09


static func pass_lane_open(from: Vector3, to: Vector3, opponents: Array) -> bool:
	var dir := _dir(from, to)
	var len := _flat(to - from).length()
	if dir == Vector3.ZERO:
		return true
	for o: Vector3 in opponents:
		var rel := _flat(o - from)
		var along := rel.dot(dir)
		if along <= -0.3 or along >= len - 0.5:
			continue
		if absf(rel.x * dir.z - rel.z * dir.x) < PASS_LANE_BASE + PASS_LANE_GROWTH * maxf(along, 0.0):
			return false
	return true


## An opponent stands within BLOCK_DISTANCE ahead of the carrier, roughly on his way to goal.
static func _blocked_ahead(pos: Vector3, goal: Vector3, opponents: Array) -> bool:
	var dir := _dir(pos, goal)
	for o: Vector3 in opponents:
		var rel := _flat(o - pos)
		var along := rel.dot(dir)
		if along > 0.5 and along < BLOCK_DISTANCE and absf(rel.x * dir.z - rel.z * dir.x) < 3.0:
			return true
	return false


## Phase M4 offside line: distance to the opponent goal line of the second-last opponent, or of the ball when that is
## nearer the line (as in the law). A team-mate nearer the goal line than this, in the opponent half, is offside.
static func offside_line(goal: Vector3, ball: Vector3, opponents: Array) -> float:
	var depths: Array[float] = []
	for o: Vector3 in opponents:
		depths.append(absf(goal.z - o.z))
	depths.sort()
	var second := depths[1] if depths.size() >= 2 else 0.0
	return minf(second, absf(goal.z - ball.z))


static func is_offside(mate: Vector3, goal: Vector3, line: float) -> bool:
	var d := absf(goal.z - mate.z)
	return d < line - 0.1 and d < PitchSpace.HALF_LENGTH


## Closest teammate that is further forward than the passer, ≥ PASS_MIN_DISTANCE
## away and not covered by an opponent (≥ 3 m). Vector3.INF when none.
static func _best_pass_target(ctx: Dictionary) -> Vector3:
	var prof: Dictionary = ctx.get("profile", {})
	var min_dist: float = float(prof.get("min_dist", PASS_MIN_DISTANCE))
	var max_dist: float = float(prof.get("max_dist", 35.0))
	var progress_weight: float = float(prof.get("progress_weight", 1.0))
	var dist_weight: float = float(prof.get("dist_weight", 0.2))
	var min_progress: float = float(prof.get("min_progress", 0.0))
	var cover_radius: float = float(prof.get("cover_radius", 3.0))
	var pos: Vector3 = ctx["pos"]
	var goal: Vector3 = ctx["goal"]
	var here := _flat(goal - pos).length()
	var best := Vector3.INF
	var best_score := -INF
	var line := offside_line(goal, ctx.get("ball", pos), ctx.get("opponents", [])) if not ctx.get("opponents", []).is_empty() else 0.0
	var allow_offside: bool = ctx.get("offside_mistake", false)
	for t: Vector3 in ctx.get("teammates", []):
		var d := _flat(t - pos).length()
		if d < min_dist or d > max_dist:
			continue
		if not allow_offside and is_offside(t, goal, line):
			continue                                    # Phase M4: no pass to an offside man (except the odd mistake)
		var progress := here - _flat(goal - t).length()    # > 0 = closer to goal
		if progress <= min_progress:
			continue
		var covered := false
		for o in ctx.get("opponents", []):
			if _flat(o - t).length() < cover_radius:
				covered = true
				break
		if covered or not pass_lane_open(ctx.get("ball", pos), t, ctx.get("opponents", [])):
			continue
		var score := progress * progress_weight - d * dist_weight
		if score > best_score:
			best_score = score
			best = t
	return best
