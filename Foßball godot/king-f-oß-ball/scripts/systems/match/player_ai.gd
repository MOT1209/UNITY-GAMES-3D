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


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _dir(from: Vector3, to: Vector3) -> Vector3:
	var d := _flat(to - from)
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


static func decide(ctx: Dictionary) -> Dictionary:
	var pos: Vector3 = ctx["pos"]
	var ball: Vector3 = ctx["ball"]
	var out := {"move": Vector3.ZERO, "sprint": false, "action": &""}
	if ctx.get("is_keeper", false):
		return _keeper(ctx, out)
	if ctx.get("has_ball", false):
		return _with_ball(ctx, out)
	if ctx.get("is_chaser", false):
		var d := _flat(ball - pos).length()
		out["move"] = _dir(pos, ball)
		out["sprint"] = d > 6.0 and int(ctx.get("difficulty", 1)) >= 1
		return out
	var target: Vector3 = ctx["target"]
	var to_target := _flat(target - pos)
	if to_target.length() > ARRIVE_RADIUS:
		out["move"] = to_target.normalized() * clampf(to_target.length() / 4.0, 0.35, 1.0)
		out["sprint"] = to_target.length() > 14.0
	return out


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
	if to_goal <= range_limit or (to_goal <= range_limit * LONG_SHOT_FACTOR and _lane_open(pos, goal, ctx.get("opponents", []))):
		out["move"] = _dir(pos, goal)
		out["action"] = &"shoot"
		return out
	# Pass when pressured, or earlier when an opponent blocks the way ahead and a free team-mate is further forward.
	var blocked := _blocked_ahead(pos, goal, ctx.get("opponents", []))
	if pressured or blocked:
		var t := _best_pass_target(ctx)
		if t == Vector3.INF and pressured:
			t = _best_pass_target(_with_relaxed_profile(ctx))       # nothing ahead: a sideways or back pass beats losing the ball
		if t != Vector3.INF:
			out["move"] = _dir(pos, t)
			out["action"] = &"pass"
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


## An opponent stands within BLOCK_DISTANCE ahead of the carrier, roughly on his way to goal.
static func _blocked_ahead(pos: Vector3, goal: Vector3, opponents: Array) -> bool:
	var dir := _dir(pos, goal)
	for o: Vector3 in opponents:
		var rel := _flat(o - pos)
		var along := rel.dot(dir)
		if along > 0.5 and along < BLOCK_DISTANCE and absf(rel.x * dir.z - rel.z * dir.x) < 3.0:
			return true
	return false


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
	for t: Vector3 in ctx.get("teammates", []):
		var d := _flat(t - pos).length()
		if d < min_dist or d > max_dist:
			continue
		var progress := here - _flat(goal - t).length()    # > 0 = closer to goal
		if progress <= min_progress:
			continue
		var covered := false
		for o in ctx.get("opponents", []):
			if _flat(o - t).length() < cover_radius:
				covered = true
				break
		if covered:
			continue
		var score := progress * progress_weight - d * dist_weight
		if score > best_score:
			best_score = score
			best = t
	return best
