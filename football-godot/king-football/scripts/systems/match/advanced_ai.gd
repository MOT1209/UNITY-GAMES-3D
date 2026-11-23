class_name AdvancedAI
extends RefCounted

## AI decisions for the Phase 2 advanced mechanics (pure, static; randomness comes in as `rolls` from the match's
## advanced RNG). `MatchAIDriver` calls these on top of `PlayerAI.decide` and feeds the result through the same
## `AIIntent` a human uses (skill_request, shot_technique, the shield / shoot / pass / lob buttons).
##
## Imperfection is built in on purpose: a move above the player's ability is still tried now and then (and goes wrong
## more often), the difficulty scales how often anything advanced is tried, and EASY never picks the risky moves.

## Decisions per second (before attributes) a free carrier facing a defender tries a skill move, by difficulty.
const SKILL_RATE: Array[float] = [0.35, 0.6, 0.85]
const SKILL_COOLDOWN := 2.2
const SKILL_MIN_DIST := 1.0
const SKILL_MAX_DIST := 3.6


## The skill move a carrier tries now, {id, side} or {} for none.
## ctx: pos, facing (planar), goal, opponents (Array[Vector3]), mods, difficulty, speed, rolls [r0, r1, r2],
##      dt (seconds since the last decision), pressured (bool), final_third (bool).
static func skill_choice(ctx: Dictionary) -> Dictionary:
	var pos: Vector3 = ctx["pos"]
	var facing: Vector3 = ctx.get("facing", Vector3.FORWARD)
	var mods: AttributeModifiers = ctx.get("mods")
	var rolls: Array = ctx.get("rolls", [1.0, 1.0, 1.0])
	var diff := clampi(int(ctx.get("difficulty", 1)), 0, 2)
	# the defender in front (within the cone of the carrier's way)
	var front := Vector3.INF
	var front_d := INF
	var behind := false
	for o: Vector3 in ctx.get("opponents", []):
		var rel := Vector3(o.x - pos.x, 0.0, o.z - pos.z)
		var d := rel.length()
		if d < 0.01 or d > SKILL_MAX_DIST:
			continue
		var along := rel.normalized().dot(facing)
		if along > 0.35 and d < front_d:
			front_d = d
			front = o
		elif along < -0.3 and d < 1.6:
			behind = true
	var skill := mods.skill_rating() if mods != null else 0.5
	var p := SKILL_RATE[diff] * float(ctx.get("dt", 0.18)) * lerpf(0.35, 1.6, skill)
	if rolls[0] >= p:
		return {}
	var side := 0.0
	if front != Vector3.INF:
		var right := facing.cross(Vector3.UP)
		side = -signf(Vector3(front.x - pos.x, 0.0, front.z - pos.z).dot(right))
		if side == 0.0:
			side = 1.0
	var speed := float(ctx.get("speed", 0.0))
	var pool: Array = []
	if behind and front == Vector3.INF:
		pool = [&"roulette", &"stop_and_turn", &"drag_back"]
	elif front != Vector3.INF and front_d >= SKILL_MIN_DIST:
		if bool(ctx.get("in_box", false)):
			pool = [&"fake_shot", &"fake_shot", &"la_croqueta", &"step_over"]
		elif front_d < 1.7:
			pool = [&"la_croqueta", &"roulette", &"drag_back", &"body_feint"]
		elif speed > 3.0:
			pool = [&"step_over", &"double_step_over", &"elastico", &"heel_to_heel", &"body_feint"]
		else:
			pool = [&"step_over", &"body_feint", &"ball_roll", &"fake_pass", &"drag_back"]
	if pool.is_empty():
		return {}
	# Prefer moves within his ability; a move above it is kept with a small chance only (and EASY never risks tier 2).
	var fit: Array = []
	for id in pool:
		var mv := SkillMoveCatalog.get_move(id)
		if diff == 0 and int(mv["tier"]) >= 2:
			continue
		if float(mv["min_skill"]) <= skill + 0.08 or rolls[2] < 0.12:
			fit.append(id)
	if fit.is_empty():
		return {}
	var pick: StringName = fit[clampi(int(rolls[1] * fit.size()), 0, fit.size() - 1)]
	return {"id": pick, "side": side}


## Shooting technique for an AI shot from `pos` at `goal` (keeper position known or INF).
static func technique_for(pos: Vector3, goal: Vector3, keeper: Vector3, mods: AttributeModifiers, pressured: bool,
		difficulty: int, roll: float) -> StringName:
	var d := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	var lateral := absf(pos.x - goal.x)
	var diff := clampi(difficulty, 0, 2)
	if roll < 0.25:
		return ShotTechnique.NORMAL                      # the plain shot stays the most common one
	if keeper != Vector3.INF and diff >= 1:
		var keeper_out := absf(keeper.z - goal.z)
		var kd := Vector2(keeper.x - pos.x, keeper.z - pos.z).length()
		if keeper_out > 5.0 and d > 9.0 and d < 24.0 and kd > 3.0 and (mods == null or mods.detail("finishing") > 0.55):
			return ShotTechnique.CHIP
	if pressured and d < 15.0:
		return ShotTechnique.LOW_DRIVEN
	if d < 20.0 and lateral > 5.0 and (mods == null or mods.detail("curve") >= 0.58) and diff >= 1:
		return ShotTechnique.FINESSE
	if d > 21.0 and not pressured and (mods == null or mods.detail("shot_power") >= 0.65):
		return ShotTechnique.POWER
	return ShotTechnique.NORMAL


## True when a carrier should shield instead of carrying on: closely pressed (<= 1.8 m), with no pass on, and either
## strong enough or near a touchline. `strength` 0..1.
static func should_shield(pressure_dist: float, has_pass: bool, strength: float, near_line: bool, final_third: bool,
		roll: float) -> bool:
	if pressure_dist > 1.8 or has_pass:
		return false
	if near_line:
		return roll < 0.75
	if final_third:
		return false                                     # near goal a carrier takes his man on or shoots
	return roll < clampf((strength - 0.45) * 1.6, 0.05, 0.6)


## Header kind for an AI player in the window: shot in the opponent box, clearance near the own goal, else a pass.
static func header_kind(pos: Vector3, goal: Vector3, own_goal: Vector3) -> StringName:
	var to_goal := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	var to_own := Vector2(own_goal.x - pos.x, own_goal.z - pos.z).length()
	if to_goal < 16.0 and absf(pos.x - goal.x) < 12.0:
		return HeaderSystem.SHOT
	if to_own < 30.0:
		return HeaderSystem.CLEAR
	return HeaderSystem.PASS


## Where an airborne ball will be at head height on its way down (planar point), or INF when it is not coming down there.
static func aerial_spot(ball_pos: Vector3, ball_vel: Vector3, head_height: float = 1.75) -> Vector3:
	if ball_pos.y < 1.0:
		return Vector3.INF
	var a := -0.5 * 9.8
	var b := ball_vel.y
	var c := ball_pos.y - head_height
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return Vector3.INF
	var t := (-b - sqrt(disc)) / (2.0 * a)             # the later root: on the way down
	if t < 0.05 or t > 3.0:
		return Vector3.INF
	return Vector3(ball_pos.x + ball_vel.x * t, 0.0, ball_pos.z + ball_vel.z * t)
